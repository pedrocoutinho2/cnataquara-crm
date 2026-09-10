/* Filtro de ultimo contato no quadro de Clientes B2C (10/09/2026).
   Uso: CRM_HTML=/caminho/index.html node --test qa/filtro-ultimo-contato.test.mjs */
import test from 'node:test';
import assert from 'node:assert/strict';
import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';

const HTML = process.env.CRM_HTML;
if (!HTML) throw new Error('defina CRM_HTML');
const FILE = pathToFileURL(HTML).href;
const d = n => { const x = new Date(); x.setDate(x.getDate() - n); return x.toISOString().slice(0, 10); };
const USERS = [{ id: 'u1', nome: 'Admin QA', email: 'qa@cnataquara.com.br', cor: '#19408B', admin: true, ativo: true,
  consultor: true, papel: 'admin', permissoes: {}, hora_inicio: null, hora_fim: null }];
const base = { etapa: 'respondeu', curso: 'Inglês', origem: 'Google', responsavel: 'Admin QA', data_entrada: d(90),
  proximo_atendimento: null, tentativas_sem_retorno: 0 };
const LEADS = [
  ['ZZ HOJE', d(0)], ['ZZ TRES DIAS', d(3)], ['ZZ QUINZE DIAS', d(15)], ['ZZ SESSENTA DIAS', d(60)], ['ZZ NUNCA', null]
].map((p, i) => Object.assign({}, base, { id: 'L' + i, nome: p[0], ultimo_contato: p[1] }));

async function abrir() {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  await ctx.addInitScript(() => { localStorage.setItem('crmAuth', 'Admin QA'); localStorage.setItem('crmAuthEmail', 'qa@cnataquara.com.br'); localStorage.setItem('crmUnidade', 'taquara'); });
  const json = (r, b) => r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(b) });
  await ctx.route('**/rest/v1/**', r => json(r, []));
  await ctx.route('**/crm_usuarios*', r => json(r, USERS));
  await ctx.route('**/crm_leads*', r => json(r, LEADS));
  await ctx.route('**/crm_leads_interacoes*', r => json(r, []));
  await ctx.route('**/crm_leads_etapas*', r => json(r, []));
  const page = await ctx.newPage();
  await page.goto(FILE);
  await page.waitForFunction(() => document.getElementById('login').classList.contains('off'), null, { timeout: 15000 });
  await page.evaluate(() => setTab('leads'));
  await page.waitForSelector('#board .card', { timeout: 15000 });
  await page.click('#fbtn');
  return { browser, page };
}
const nomes = page => page.$$eval('#board .card', cs => cs.map(c => c.innerText).join('|'));
async function preset(page, v) {
  await page.selectOption('#fpanel select[data-fs=uc]', v);
  await page.waitForTimeout(250);
  return nomes(page);
}

test('uc - cada preset mostra so os leads da faixa', async () => {
  const { browser, page } = await abrir();
  try {
    let t = await preset(page, 'hoje');
    assert.match(t, /ZZ HOJE/); assert.doesNotMatch(t, /TRES|QUINZE|SESSENTA|NUNCA/);
    t = await preset(page, '7');
    assert.match(t, /ZZ HOJE/); assert.match(t, /ZZ TRES/); assert.doesNotMatch(t, /QUINZE|SESSENTA|NUNCA/);
    t = await preset(page, '8a30');
    assert.match(t, /ZZ QUINZE/); assert.doesNotMatch(t, /HOJE|TRES|SESSENTA|NUNCA/);
    t = await preset(page, 'mais30');
    assert.match(t, /ZZ SESSENTA/); assert.doesNotMatch(t, /HOJE|TRES|QUINZE|NUNCA/);
    t = await preset(page, 'nunca');
    assert.match(t, /ZZ NUNCA/); assert.doesNotMatch(t, /HOJE|TRES|QUINZE|SESSENTA/);
    assert.equal(await page.textContent('#fcount'), '1');
  } finally { await browser.close(); }
});

test('uc - faixa de datas filtra e nao traz quem nunca teve contato', async () => {
  const { browser, page } = await abrir();
  try {
    await page.fill('#fpanel input[data-fk=ucDe]', d(20));
    await page.dispatchEvent('#fpanel input[data-fk=ucDe]', 'change');
    await page.waitForTimeout(300);
    const t = await nomes(page);
    assert.match(t, /ZZ HOJE/); assert.match(t, /ZZ QUINZE/);
    assert.doesNotMatch(t, /SESSENTA|NUNCA/);
  } finally { await browser.close(); }
});

test('[GUARDA] uc - limpar filtros traz todo mundo de volta', async () => {
  const { browser, page } = await abrir();
  try {
    await preset(page, 'nunca');
    await page.click('#fclear');
    await page.waitForTimeout(300);
    const t = await nomes(page);
    for (const n of ['HOJE', 'TRES', 'QUINZE', 'SESSENTA', 'NUNCA']) assert.match(t, new RegExp('ZZ ' + n));
  } finally { await browser.close(); }
});
