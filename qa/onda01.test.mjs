/* Suite da onda 0 e 1 das correcoes do CRM CNA Taquara.
   Roda em Chromium headless. Cada teste tem que FALHAR no index.html antigo e
   PASSAR no novo - se passar nos dois, nao mede nada.

   Uso:  CRM_HTML=/caminho/index.html node --test qa/onda01.test.mjs
*/
import test from 'node:test';
import assert from 'node:assert/strict';
import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';

const HTML = process.env.CRM_HTML;
if (!HTML) throw new Error('defina CRM_HTML com o caminho do index.html');
const FILE = pathToFileURL(HTML).href;

const HOJE = new Date().toISOString().slice(0, 10);
const ANTIGO = '2025-11-04';           // fora de qualquer recorte de "este mes"

const USERS = [{
  id: 'u1', nome: 'Admin QA', email: 'qa@cnataquara.com.br', cor: '#19408B',
  admin: true, ativo: true, consultor: true, papel: 'admin', permissoes: {},
  hora_inicio: null, hora_fim: null
}];

function lead(o) {
  return Object.assign({
    id: 'x', nome: 'Lead X', nome_aluno: null, whatsapp: '21999990000', idade: null,
    responsavel_legal: null, origem: 'Instagram', curso: 'Inglês', responsavel: 'Admin QA',
    etapa: 'novo', data_entrada: HOJE, data_inicio_aulas: null, nivel: null, turma: null,
    motivo_perda: null, turno_desejado: null, ultimo_contato: null,
    proximo_atendimento: null, proximo_atendimento_hora: null, proximo_canal: null,
    data_fechamento: null, observacoes: null, acao_id: null, instagram: null,
    telefone: null, created_at: HOJE + 'T09:00:00Z', updated_at: HOJE + 'T09:00:00Z'
  }, o);
}

/* A base da fixture: um lead antigo em negociacao (A01), um em etapa terminal (A08),
   um com pendencia visivel (A09) e um limpo. */
const LEADS = [
  lead({ id: 'L-ANTIGO', nome: 'ZZ ANTIGO NEGOCIACAO', etapa: 'negociacao', data_entrada: ANTIGO, nome_aluno: 'Aluno A', nivel: 'Fly' }),
  lead({ id: 'L-PERDIDO', nome: 'ZZ PERDIDO', etapa: 'perdido', motivo_perda: 'preco', data_entrada: HOJE }),
  lead({ id: 'L-PEND', nome: 'ZZ COM PENDENCIA', etapa: 'negociacao', nome_aluno: null, nivel: null, data_entrada: HOJE }),
  lead({ id: 'L-LIMPO', nome: 'ZZ LIMPO', etapa: 'novo', data_entrada: HOJE })
];

async function abrir() {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const patches = [];

  await ctx.addInitScript(() => {
    try {
      localStorage.setItem('crmAuth', 'Admin QA');
      localStorage.setItem('crmAuthEmail', 'qa@cnataquara.com.br');
    } catch (e) { }
  });

  const json = (route, body) => route.fulfill({
    status: 200, contentType: 'application/json', body: JSON.stringify(body)
  });

  /* ARMADILHA JA PAGA: no Playwright a ULTIMA rota registrada vence.
     O pega-tudo entra PRIMEIRO; as rotas especificas depois. */
  await ctx.route('**/rest/v1/**', r => json(r, []));
  await ctx.route('**/storage/v1/**', r => json(r, []));
  await ctx.route('**/crm_usuarios*', r => json(r, USERS));
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
  await page.evaluate(() => setTab('leads'));
  await page.waitForSelector('#board .card', { timeout: 15000 });
  return { browser, page, patches };
}

const abreFicha = (page, nome) => page.locator('#board .card', { hasText: nome }).first().click();

/* ------------------------------------------------------------------ A01/A02/A03 */
test('A01 - o funil abre com todo o historico, nao so o mes corrente', async () => {
  const { browser, page } = await abrir();
  try {
    const n = await page.locator('#board .card', { hasText: 'ZZ ANTIGO NEGOCIACAO' }).count();
    assert.equal(n, 1, 'lead de novembro/2025 em negociacao tem que aparecer no quadro');
  } finally { await browser.close(); }
});

test('A02 - o seletor de periodo abre em "tudo", sem recorte automatico', async () => {
  const { browser, page } = await abrir();
  try {
    const per = await page.evaluate(() => ({ per: filters.per, de: filters.entradaDe }));
    assert.equal(per.per, null);
    assert.equal(per.de, null);
  } finally { await browser.close(); }
});

/* ------------------------------------------------------------------------- A08 */
test('A08 - etapa terminal sai da navegacao por setas', async () => {
  const { browser, page } = await abrir();
  try {
    const card = page.locator('#board .card', { hasText: 'ZZ PERDIDO' }).first();
    assert.equal(await card.locator('[data-mv]').count(), 0,
      'card em "perdido" nao pode ter seta de progressao');
  } finally { await browser.close(); }
});

/* ------------------------------------------------------------------------- A09 */
test('A09 - Salvar grava mesmo com campo obrigatorio em branco', async () => {
  const { browser, page, patches } = await abrir();
  try {
    await abreFicha(page, 'ZZ COM PENDENCIA');
    await page.waitForSelector('#ov.open');
    await page.click('#save');
    await page.waitForTimeout(600);
    assert.ok(patches.some(p => p.method === 'PATCH'),
      'clicar em Salvar com nome do aluno e nivel vazios tem que gravar mesmo assim');
  } finally { await browser.close(); }
});

test('A09 - o card mostra etiqueta do que falta', async () => {
  const { browser, page } = await abrir();
  try {
    const card = page.locator('#board .card', { hasText: 'ZZ COM PENDENCIA' }).first();
    const tag = card.locator('.agt.pend');
    assert.equal(await tag.count(), 1);
    const txt = await tag.innerText();
    assert.match(txt, /nome do aluno/);
    assert.match(txt, /n[ií]vel/);
  } finally { await browser.close(); }
});

test('A09 - a ficha cobra no topo, nomeando a etapa', async () => {
  const { browser, page } = await abrir();
  try {
    await abreFicha(page, 'ZZ COM PENDENCIA');
    await page.waitForSelector('#ov.open');
    const box = page.locator('#pendbox');
    assert.ok(await box.isVisible(), 'a cobranca tem que estar visivel no topo da ficha');
    assert.match(await box.innerText(), /Negocia/);
  } finally { await browser.close(); }
});

test('A09 - card e ficha leem a mesma pendenciasLead()', async () => {
  const { browser, page } = await abrir();
  try {
    const p = await page.evaluate(() => pendenciasLead({ etapa: 'fechado', curso: 'Inglês', origem: 'Google' }));
    assert.deepEqual(p, ['nome do aluno', 'nível', 'turma', 'início das aulas']);
  } finally { await browser.close(); }
});

/* --------------------------------------------------------------------- A10/A11 */
test('A11 - o botao de registrar tentativa nunca abre desabilitado', async () => {
  const { browser, page } = await abrir();
  try {
    await abreFicha(page, 'ZZ LIMPO');
    await page.waitForSelector('#ov.open');
    await page.click('#isub button[data-is=ne]');
    assert.equal(await page.locator('#neadd').isDisabled(), false);
  } finally { await browser.close(); }
});

test('A11 - a cobranca sai uma vez so, em .ibox warn, e o vermelho so vem depois de tentar', async () => {
  const { browser, page } = await abrir();
  try {
    await abreFicha(page, 'ZZ LIMPO');
    await page.waitForSelector('#ov.open');
    await page.click('#isub button[data-is=ne]');
    assert.equal(await page.locator('#neaviso').isVisible(), false, 'nada de vermelho antes da tentativa');
    assert.equal(await page.locator('#nedata.need').count(), 0);
    await page.click('#neadd');
    assert.ok(await page.locator('#neaviso.ibox.warn').isVisible(), 'depois de tentar, cobra uma vez so');
    assert.equal(await page.locator('#nedata.need').count(), 1);
    /* e some no proprio input do campo */
    await page.fill('#nedata', HOJE);
    assert.equal(await page.locator('#nedata.need').count(), 0);
  } finally { await browser.close(); }
});

test('A10 - os 7 motivos de tentativa sem sucesso sao chips', async () => {
  const { browser, page } = await abrir();
  try {
    await abreFicha(page, 'ZZ LIMPO');
    await page.waitForSelector('#ov.open');
    await page.click('#isub button[data-is=ne]');
    assert.equal(await page.locator('#nechips button[data-ne]').count(), 7);
    await page.click('#nechips button[data-ne=nao_atendeu]');
    assert.equal(await page.locator('#nemotivo').inputValue(), 'nao_atendeu');
  } finally { await browser.close(); }
});

/* ------------------------------------------------------------------------- A19 */
test('A19 - o X da ficha e visivel no desktop', async () => {
  const { browser, page } = await abrir();
  try {
    await abreFicha(page, 'ZZ LIMPO');
    await page.waitForSelector('#ov.open');
    assert.ok(await page.locator('#closex').isVisible());
  } finally { await browser.close(); }
});

test('A19 - X, Escape e clique no fundo passam pela flag DIRTY', async () => {
  const { browser, page } = await abrir();
  try {
    await abreFicha(page, 'ZZ LIMPO');
    await page.waitForSelector('#ov.open');
    /* ficha limpa: o X fecha */
    await page.click('#closex');
    await page.waitForSelector('#ov.open', { state: 'detached', timeout: 3000 }).catch(() => { });
    assert.equal(await page.locator('#ov.open').count(), 0, 'ficha limpa: o X fecha');

    await abreFicha(page, 'ZZ LIMPO');
    await page.waitForSelector('#ov.open');
    await page.fill('#form [data-k=nome]', 'ZZ LIMPO editado');
    await page.click('#closex');
    await page.waitForTimeout(300);
    assert.equal(await page.locator('#ov.open').count(), 1, 'ficha suja: o X avisa, nao descarta');
    await page.keyboard.press('Escape');
    await page.waitForTimeout(300);
    assert.equal(await page.locator('#ov.open').count(), 1, 'ficha suja: Escape tambem nao descarta');
  } finally { await browser.close(); }
});

/* ------------------------------------------------------------------------- A21 */
test('A21 - o contato efetivo confirma na tela', async () => {
  const { browser, page } = await abrir();
  try {
    await abreFicha(page, 'ZZ LIMPO');
    await page.waitForSelector('#ov.open');
    await page.fill('#iresumo', 'Falei com a mae, vai passar aqui sabado.');
    await page.click('#iadd');
    await page.waitForSelector('#toast', { state: 'visible', timeout: 4000 });
    assert.match(await page.locator('#toast').innerText(), /registrado/i);
  } finally { await browser.close(); }
});

/* ------------------------------------------------------------------------- A12 */
test('A12 - a ficha reflete o que o banco carimbou na resposta do PATCH', async () => {
  const { browser, page } = await abrir();
  try {
    assert.equal(await page.evaluate(() => typeof refletirCarimbo), 'function');
    await abreFicha(page, 'ZZ LIMPO');
    await page.waitForSelector('#ov.open');
    await page.evaluate(() => refletirCarimbo({
      id: 'L-LIMPO', nome: 'ZZ LIMPO', etapa: 'aguardando_271',
      ultimo_contato: '2026-08-20', proximo_atendimento: '2026-10-01',
      proximo_atendimento_hora: '09:00'
    }));
    assert.equal(await page.locator('#form [data-k=ultimo_contato]').inputValue(), '2026-08-20');
  } finally { await browser.close(); }
});
