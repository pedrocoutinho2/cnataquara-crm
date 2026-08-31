/* Onda 4 · A15 (efetividade media canal, nao capacidade) e A18 (dono fora da equipe).
   Tem que FALHAR no arquivo anterior e PASSAR no novo.

   Uso:  CRM_HTML=/caminho/index.html node --test qa/onda4.test.mjs
*/
import test from 'node:test';
import assert from 'node:assert/strict';
import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';

const HTML = process.env.CRM_HTML;
if (!HTML) throw new Error('defina CRM_HTML com o caminho do index.html');
const FILE = pathToFileURL(HTML).href;
const HOJE = new Date().toISOString().slice(0, 10);

const USERS = [
  { id: 'u1', nome: 'Admin QA', email: 'qa@cnataquara.com.br', cor: '#19408B', admin: true, ativo: true, consultor: true, papel: 'admin', permissoes: {}, hora_inicio: '09:00:00', hora_fim: '18:00:00' },
  { id: 'u2', nome: 'ZAP', email: 'zap@x.com', cor: '#1E7A46', admin: false, ativo: true, consultor: true, papel: 'comercial', permissoes: {}, hora_inicio: null, hora_fim: null },
  { id: 'u3', nome: 'FONE', email: 'fone@x.com', cor: '#B87500', admin: false, ativo: true, consultor: true, papel: 'comercial', permissoes: {}, hora_inicio: null, hora_fim: null }
];

function lead(o) {
  return Object.assign({
    id: 'x', nome: 'Lead', nome_aluno: null, whatsapp: null, idade: null, responsavel_legal: null,
    origem: 'Google', curso: 'Inglês', responsavel: 'ZAP', etapa: 'novo', data_entrada: HOJE,
    data_inicio_aulas: null, nivel: null, turma: null, motivo_perda: null, turno_desejado: null,
    ultimo_contato: null, ultima_tentativa: null, tentativas_sem_retorno: 0,
    proximo_atendimento: null, proximo_atendimento_hora: null, proximo_canal: null,
    data_fechamento: null, observacoes: null, acao_id: null, instagram: null, telefone: null,
    sem_turma: false, espera_desde: null, created_at: HOJE + 'T09:00:00Z', updated_at: HOJE + 'T09:00:00Z'
  }, o);
}

/* ZAP e FONE têm o MESMO desempenho real; muda só o canal.
   ZAP:  10 tentativas por WhatsApp, 8 responderam  -> 80% no WhatsApp
   FONE: 10 tentativas por ligação,  1 respondeu    -> 10% na ligação
   Os dois têm 5 notas, que NÃO são contato e antes contavam como 100% efetivas. */
const INTER = [];
for (let i = 0; i < 10; i++) INTER.push({ lead_id: 'L1', data: HOJE, autor: 'ZAP', tipo: 'whatsapp', efetivo: i < 8, motivo_nao_efetivo: i < 8 ? null : 'nao_leu' });
for (let i = 0; i < 10; i++) INTER.push({ lead_id: 'L2', data: HOJE, autor: 'FONE', tipo: 'ligacao', efetivo: i < 1, motivo_nao_efetivo: i < 1 ? null : 'nao_atendeu' });
for (let i = 0; i < 5; i++) INTER.push({ lead_id: 'L1', data: HOJE, autor: 'ZAP', tipo: 'nota', efetivo: true, motivo_nao_efetivo: null });
for (let i = 0; i < 5; i++) INTER.push({ lead_id: 'L2', data: HOJE, autor: 'FONE', tipo: 'nota', efetivo: true, motivo_nao_efetivo: null });

const LEADS = [
  lead({ id: 'L1', nome: 'ZZ DO ZAP', responsavel: 'ZAP' }),
  lead({ id: 'L2', nome: 'ZZ DO FONE', responsavel: 'FONE' }),
  /* A18: dono que não está no cadastro de usuários ativos */
  lead({ id: 'L3', nome: 'ZZ ORFAO', responsavel: 'SABRINA QUE SAIU' }),
  lead({ id: 'L4', nome: 'ZZ ORFAO 2', responsavel: 'SABRINA QUE SAIU' })
];

async function abrir() {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  await ctx.addInitScript(() => {
    try {
      localStorage.setItem('crmAuth', 'Admin QA');
      localStorage.setItem('crmAuthEmail', 'qa@cnataquara.com.br');
    } catch (e) { }
  });
  const json = (r, b) => r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(b) });
  await ctx.route('**/rest/v1/**', r => json(r, []));
  await ctx.route('**/crm_usuarios*', r => json(r, USERS));
  await ctx.route('**/crm_leads?*', r => json(r, LEADS));
  await ctx.route('**/crm_leads_interacoes*', r => json(r, INTER));
  const page = await ctx.newPage();
  await page.goto(FILE);
  await page.waitForFunction(() => document.getElementById('login').classList.contains('off'), null, { timeout: 15000 });
  await page.evaluate(() => setTab('leads'));
  await page.waitForSelector('#board .card', { timeout: 15000 });
  return { browser, page };
}

/* ------------------------------------------------------------------------- A15 */
test('A15 - nota não conta como tentativa nem como contato efetivo', async () => {
  const { browser, page } = await abrir();
  try {
    const r = await page.evaluate(() => {
      const st = statsContato([
        { tipo: 'nota', efetivo: true },
        { tipo: 'whatsapp', efetivo: true },
        { tipo: 'ligacao', efetivo: false }
      ]);
      return { n: st.n, ef: st.ef, notas: st.notas };
    });
    assert.deepEqual(r, { n: 2, ef: 1, notas: 1 });
  } finally { await browser.close(); }
});

test('A15 - efetivo só conta quando é true de verdade', async () => {
  const { browser, page } = await abrir();
  try {
    const st = await page.evaluate(() => {
      const s = statsContato([
        { tipo: 'ligacao', efetivo: null },
        { tipo: 'ligacao' },
        { tipo: 'ligacao', efetivo: true }
      ]);
      return { n: s.n, ef: s.ef };
    });
    assert.deepEqual(st, { n: 3, ef: 1 }, 'nulo e ausente não podem virar contato efetivo');
  } finally { await browser.close(); }
});

test('A15 - a resposta sai por canal, nunca como número único da pessoa', async () => {
  const { browser, page } = await abrir();
  try {
    const r = await page.evaluate(() => {
      const st = statsContato([
        { tipo: 'whatsapp', efetivo: true }, { tipo: 'whatsapp', efetivo: true },
        { tipo: 'ligacao', efetivo: false }, { tipo: 'ligacao', efetivo: false }
      ]);
      return respostaCanais(st);
    });
    /* pct() formata com uma casa e vírgula: "100,0%" */
    assert.match(r, /WhatsApp 100,0%/);
    assert.match(r, /Liga(ç|c)ão 0,0%/);
  } finally { await browser.close(); }
});

test('A15 - o ranking mostra tentativas, falaram e canal; não mostra "Efetividade"', async () => {
  const { browser, page } = await abrir();
  try {
    await page.evaluate(() => { RGO = 'funil'; setTab('relatorios'); });
    await page.waitForSelector('.rtab', { timeout: 15000 });
    const html = await page.locator('#board').innerHTML();
    assert.ok(/Resposta por canal/.test(html), 'a coluna nova tem que existir');
    assert.equal(/>Efetividade</.test(html), false, 'a coluna "Efetividade" não pode mais existir');

    const linha = page.locator('.rtab tr', { hasText: 'FONE' }).first();
    const tds = await linha.locator('td').allInnerTexts();
    /* Leads, Tentativas, Falaram: as 5 notas do FONE não podem entrar */
    assert.equal(tds[1].trim(), '1', 'FONE tem 1 lead');
    assert.equal(tds[2].trim(), '10', '10 tentativas — as 5 notas ficam de fora');
    assert.equal(tds[3].trim(), '1', '1 conversa de fato');
    assert.match(tds[4], /Liga(ç|c)ão 10,0%/, 'a taxa aparece amarrada ao canal');
  } finally { await browser.close(); }
});

test('A15 - a nota do relatório nomeia o efeito do canal', async () => {
  const { browser, page } = await abrir();
  try {
    await page.evaluate(() => { RGO = 'funil'; setTab('relatorios'); });
    await page.waitForSelector('.rtab', { timeout: 15000 });
    /* a nota do card do ranking, não a primeira nota da tela */
    const nota = await page.locator('.rcard', { hasText: 'Ranking de consultores' }).locator('.rnote').first().innerText();
    assert.match(nota, /canal/i);
    assert.match(nota, /WhatsApp/);
  } finally { await browser.close(); }
});

/* ------------------------------------------------------------------------- A18 */
test('A18 - dono fora da equipe aparece no filtro de Responsável', async () => {
  const { browser, page } = await abrir();
  try {
    await page.click('#fbtn');
    await page.waitForSelector('#fpanel select[data-fs=resp]', { state: 'attached' });
    const opts = await page.evaluate(() =>
      Array.from(document.querySelectorAll('#fpanel select[data-fs=resp] option')).map(o => o.textContent));
    const orfao = opts.find(o => o.includes('SABRINA QUE SAIU'));
    assert.ok(orfao, 'quem saiu tem que estar na lista, senão o lead dele some da tela');
    assert.match(orfao, /fora da equipe \(2\)/);
  } finally { await browser.close(); }
});

/* [GUARDA] passa nos dois: filtrar por responsável sempre funcionou. O defeito
   era só a LISTA do filtro, que não oferecia quem saiu. Existe para garantir que
   a mudança na lista não quebrou a filtragem. */
test('[GUARDA] A18 - filtrar por quem saiu devolve os leads dele', async () => {
  const { browser, page } = await abrir();
  try {
    const n = await page.evaluate(() => {
      filters.resp = 'SABRINA QUE SAIU';
      render();
      return document.querySelectorAll('#board .card').length;
    });
    assert.equal(n, 2);
  } finally { await browser.close(); }
});

test('A18 - a lista começa pela equipe ativa e joga quem saiu para o fim', async () => {
  const { browser, page } = await abrir();
  try {
    const opts = await page.evaluate(() => responsaveisDaBase().map(o => o[0]));
    assert.equal(opts.indexOf('SABRINA QUE SAIU'), opts.length - 1, 'quem saiu vai para o fim');
    assert.ok(opts.indexOf('ZAP') < opts.indexOf('SABRINA QUE SAIU'));
  } finally { await browser.close(); }
});
