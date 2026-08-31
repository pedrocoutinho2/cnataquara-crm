/* A52 (tentativas de contato) e arrastar evento no calendário.
   Tem que FALHAR no arquivo anterior e PASSAR no novo.

   Uso:  CRM_HTML=/caminho/index.html node --test qa/onda1c.test.mjs
*/
import test from 'node:test';
import assert from 'node:assert/strict';
import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';

const HTML = process.env.CRM_HTML;
if (!HTML) throw new Error('defina CRM_HTML com o caminho do index.html');
const FILE = pathToFileURL(HTML).href;

const HOJE = new Date().toISOString().slice(0, 10);
const MES = HOJE.slice(0, 8);

const USERS = [{
  id: 'u1', nome: 'Admin QA', email: 'qa@cnataquara.com.br', cor: '#19408B',
  admin: true, ativo: true, consultor: true, papel: 'admin', permissoes: {},
  hora_inicio: null, hora_fim: null
}];

const LEADS = [
  { id: 'L-TENT', nome: 'ZZ TRES TENTATIVAS', etapa: 'contato_feito', curso: 'Inglês', origem: 'Google',
    responsavel: 'Admin QA', data_entrada: HOJE, ultimo_contato: null, ultima_tentativa: '2026-08-20',
    tentativas_sem_retorno: 3, nome_aluno: null, nivel: null, turma: null, motivo_perda: null,
    whatsapp: '21999990001', idade: null, responsavel_legal: null, data_inicio_aulas: null,
    proximo_atendimento: null, proximo_atendimento_hora: null, proximo_canal: null,
    data_fechamento: null, acao_id: null, observacoes: null },
  { id: 'L-ZERO', nome: 'ZZ SEM TENTATIVA', etapa: 'novo', curso: 'Inglês', origem: 'Google',
    responsavel: 'Admin QA', data_entrada: HOJE, ultimo_contato: null, ultima_tentativa: null,
    tentativas_sem_retorno: 0, nome_aluno: null, nivel: null, turma: null, motivo_perda: null,
    whatsapp: '21999990002', idade: null, responsavel_legal: null, data_inicio_aulas: null,
    proximo_atendimento: null, proximo_atendimento_hora: null, proximo_canal: null,
    data_fechamento: null, acao_id: null, observacoes: null }
];

const CATS = [{ id: 'c1', nome: 'Reunião', cor: '#19408B', ordem: 1, ativa: true }];
const EVENTOS = [{
  id: 'E1', titulo: 'ZZ EVENTO ARRASTAVEL', descricao: null, categoria_id: 'c1',
  data: MES + '10', hora_inicio: '09:00:00', hora_fim: '10:00:00',
  responsavel: 'Admin QA', participantes: ['Admin QA'], lembrete_min: 0,
  criado_por: 'Admin QA', gcal_id: null, gcal_sync: 'off'
}];

async function abrir() {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const patches = [];

  await ctx.addInitScript(() => {
    try {
      localStorage.setItem('crmAuth', 'Admin QA');
      localStorage.setItem('crmAuthEmail', 'qa@cnataquara.com.br');
      localStorage.setItem('crmAgdVista', 'mes');
    } catch (e) { }
  });

  const json = (route, body) => route.fulfill({
    status: 200, contentType: 'application/json', body: JSON.stringify(body)
  });

  /* pega-tudo primeiro; a ultima rota registrada vence no Playwright */
  await ctx.route('**/rest/v1/**', r => json(r, []));
  await ctx.route('**/crm_usuarios*', r => json(r, USERS));
  await ctx.route('**/crm_agenda_categorias*', r => json(r, CATS));
  await ctx.route('**/crm_agenda_config*', r => json(r, []));
  await ctx.route('**/crm_agenda_eventos*', r => {
    const req = r.request();
    if (req.method() !== 'GET') {
      const body = JSON.parse(req.postData() || '{}');
      patches.push({ url: req.url(), method: req.method(), body });
      const alvo = EVENTOS.find(e => req.url().includes(e.id)) || EVENTOS[0];
      return json(r, [Object.assign({}, alvo, body)]);
    }
    return json(r, EVENTOS);
  });
  await ctx.route('**/crm_leads*', r => {
    const req = r.request();
    if (req.method() !== 'GET') {
      const body = JSON.parse(req.postData() || '{}');
      patches.push({ url: req.url(), method: req.method(), body });
      const alvo = LEADS.find(l => req.url().includes(l.id)) || LEADS[0];
      return json(r, [Object.assign({}, alvo, body)]);
    }
    return json(r, LEADS);
  });

  const page = await ctx.newPage();
  await page.goto(FILE);
  await page.waitForFunction(() => document.getElementById('login').classList.contains('off'), null, { timeout: 15000 });
  return { browser, page, patches };
}

async function irParaLeads(page) {
  await page.evaluate(() => setTab('leads'));
  await page.waitForSelector('#board .card', { timeout: 15000 });
}
async function irParaCalendario(page) {
  await page.evaluate(() => setTab('calendario'));
  await page.waitForSelector('.agev', { timeout: 15000 });
}

/* ------------------------------------------------------------------------- A52 */
test('A52 - o card mostra quantas tentativas sem retorno o lead acumula', async () => {
  const { browser, page } = await abrir();
  try {
    await irParaLeads(page);
    const card = page.locator('#board .card', { hasText: 'ZZ TRES TENTATIVAS' }).first();
    const tag = card.locator('.agt.tent');
    assert.equal(await tag.count(), 1);
    assert.match(await tag.innerText(), /3x sem retorno/);
    assert.equal(await tag.evaluate(el => el.classList.contains('alta')), true,
      '3 ou mais tentativas tem que acender o alerta');
  } finally { await browser.close(); }
});

/* [GUARDA] passa no arquivo antigo tambem, de proposito: garante que a etiqueta
   nova nao apareceu em card que nao devia. Nao discrimina, e isso e' intencional. */
test('[GUARDA] A52 - lead sem tentativa nao ganha etiqueta', async () => {
  const { browser, page } = await abrir();
  try {
    await irParaLeads(page);
    const card = page.locator('#board .card', { hasText: 'ZZ SEM TENTATIVA' }).first();
    assert.equal(await card.locator('.agt.tent').count(), 0);
  } finally { await browser.close(); }
});

test('A52 - a ficha diz quantas tentativas e a data da ultima', async () => {
  const { browser, page } = await abrir();
  try {
    await irParaLeads(page);
    await page.locator('#board .card', { hasText: 'ZZ TRES TENTATIVAS' }).first().click();
    await page.waitForSelector('#ov.open');
    const sub = await page.locator('#msub').innerText();
    assert.match(sub, /3 tentativas sem retorno/);
    assert.match(sub, /20\/08\/2026/);
  } finally { await browser.close(); }
});

test('A52 - registrar contato nao manda mais ultimo_contato no PATCH', async () => {
  const { browser, page, patches } = await abrir();
  try {
    await irParaLeads(page);
    await page.locator('#board .card', { hasText: 'ZZ SEM TENTATIVA' }).first().click();
    await page.waitForSelector('#ov.open');
    await page.fill('#iresumo', 'Atendeu, quer visitar a escola.');
    await page.click('#iadd');
    await page.waitForTimeout(800);
    const pl = patches.filter(p => p.method === 'PATCH' && p.url.includes('crm_leads'));
    assert.ok(pl.length >= 1, 'o registro de contato tem que gerar PATCH no lead');
    assert.ok(pl.every(p => !('ultimo_contato' in p.body)),
      'quem escreve ultimo_contato agora e o trigger do banco, nao o front');
  } finally { await browser.close(); }
});

test('A52 - tentativasLead ignora valor invalido', async () => {
  const { browser, page } = await abrir();
  try {
    const r = await page.evaluate(() => [
      tentativasLead(null),
      tentativasLead({ tentativas_sem_retorno: null }),
      tentativasLead({ tentativas_sem_retorno: -2 }),
      tentativasLead({ tentativas_sem_retorno: '4' })
    ]);
    assert.deepEqual(r, [0, 0, 0, 4]);
  } finally { await browser.close(); }
});

/* ------------------------------------------------------------------ calendário */
test('calendario - o evento e arrastavel para quem pode editar', async () => {
  const { browser, page } = await abrir();
  try {
    await irParaCalendario(page);
    const ev = page.locator('.agev[data-ev=E1]').first();
    assert.equal(await ev.getAttribute('draggable'), 'true');
    assert.equal(await ev.getAttribute('data-de'), MES + '10');
  } finally { await browser.close(); }
});

test('calendario - arrastar para outro dia remarca o evento', async () => {
  const { browser, page, patches } = await abrir();
  try {
    await irParaCalendario(page);
    const destino = MES + '17';
    await page.evaluate(d => agdRemarcar('E1', d), destino);
    await page.waitForTimeout(600);
    const p = patches.find(x => x.method === 'PATCH' && x.url.includes('crm_agenda_eventos'));
    assert.ok(p, 'tem que sair PATCH em crm_agenda_eventos');
    assert.equal(p.body.data, destino);
    assert.equal(p.body.gcal_sync, 'pendente');
    assert.equal(await page.locator('.agcell[data-d="' + destino + '"] .agev[data-ev=E1]').count(), 1,
      'o evento tem que aparecer no dia de destino');
  } finally { await browser.close(); }
});

/* [GUARDA] tambem passa no antigo, onde nao ha arrasto nenhum. Existe para pegar
   regressao futura, nao para provar a correcao. */
test('[GUARDA] calendario - soltar no mesmo dia nao grava nada', async () => {
  const { browser, page, patches } = await abrir();
  try {
    await irParaCalendario(page);
    await page.evaluate(() => {
      AGDRAG = { id: 'E1', de: document.querySelector('.agev[data-ev=E1]').dataset.de };
      const col = document.querySelector('.agev[data-ev=E1]').closest('.agcell');
      const e = new Event('drop', { bubbles: true });
      e.preventDefault = () => { };
      col.dispatchEvent(e);
    });
    await page.waitForTimeout(400);
    assert.equal(patches.filter(x => x.url.includes('crm_agenda_eventos')).length, 0);
  } finally { await browser.close(); }
});
