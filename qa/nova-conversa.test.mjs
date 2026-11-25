/* Nova conversa pela tela de Conversas + ficha do lead no funil (25/11/2026).
   Uso:  CRM_HTML=/caminho/index.html [CHROME=/usr/bin/google-chrome] node --test qa/nova-conversa.test.mjs
   Mocka waRpc, waFn e api: nada sai para o banco. */
import test from 'node:test';
import assert from 'node:assert/strict';
import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';

const HTML = process.env.CRM_HTML;
if (!HTML) throw new Error('defina CRM_HTML com o caminho do index.html');
const FILE = pathToFileURL(HTML).href;

async function abrir(cfg = {}) {
  const browser = await chromium.launch(process.env.CHROME ? { executablePath: process.env.CHROME } : {});
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  await ctx.route('**/rest/v1/**', r => r.fulfill({ status: 200, contentType: 'application/json', body: '[]' }));
  await ctx.route('**/functions/v1/**', r => r.fulfill({ status: 200, contentType: 'application/json', body: '{}' }));
  const page = await ctx.newPage();
  page.on('pageerror', e => { page._erros = (page._erros || []).concat(String(e)); });
  await page.goto(FILE);
  await page.evaluate((cfg) => {
    const agora = new Date().toISOString();
    window.QA = { rpc: [], send: [], api: [], conv: [{ id: 'c1', conta_id: 'k1', conta_provider: 'evolution', numero_e164: '+5521999990000',
      wa_id: '5521999990000', wa_chave: '2199990000', nome_perfil: 'Maria', atendente_id: 'u1', atendente_nome: 'Pedro', status: 'aberta',
      nao_lidas: 0, ultima_mensagem_em: agora, ultima_previa: 'oi', lead: null, lead_id: null, seguidores: [] }] };
    const contas = [{ id: 'k1', provider: 'evolution', rotulo: 'Principal', numero_e164: '5521900000000' }];
    if (cfg.duasContas) contas.push({ id: 'k2', provider: 'evolution', rotulo: 'Patrick', numero_e164: '5521900000001' });
    window.waRpc = async function (nome, args) {
      QA.rpc.push([nome, args]);
      switch (nome) {
        case 'crm_wa_painel': return { eu: { usuario_id: 'u1', nivel: 2, ve_tudo: false }, contas, templates: [], agentes: [] };
        case 'crm_wa_conversas_listar': return QA.conv.map(c => Object.assign({}, c));
        case 'crm_wa_conversa_vincular_lead': { const c = QA.conv.find(x => x.id === args.p_conversa_id); c.lead_id = args.p_lead_id; c.lead = { nome: 'x', etapa: 'contato_feito' }; return null; }
        default: return [];
      }
    };
    window.waFn = async function (nome, body) {
      QA.send.push(body);
      const id = 'c' + (QA.conv.length + 1);
      QA.conv.push({ id, conta_id: body.conta_id, conta_provider: 'evolution', numero_e164: '+' + body.numero, wa_id: body.numero,
        wa_chave: body.numero.slice(2, 4) + body.numero.slice(-8), atendente_id: 'u1', atendente_nome: 'Pedro', status: 'aberta',
        nao_lidas: 0, ultima_mensagem_em: new Date().toISOString(), ultima_previa: body.texto,
        lead: null, lead_id: cfg.leadExistente ? null : null, seguidores: [] });
      return { ok: true, conversa_id: id };
    };
    window.api = async function (path, opt) {
      QA.api.push([path, opt && opt.method, opt && opt.body ? JSON.parse(opt.body) : null]);
      if (path === '/rpc/crm_wa_chave') { const d = JSON.parse(opt.body).p_num.replace(/\D/g, '').replace(/^55/, ''); return d.slice(0, 2) + d.slice(-8); }
      if (path.startsWith('/crm_leads?wa_chave')) return cfg.leadExistente ? [{ id: 'L9', nome: 'Ana Antiga', responsavel: 'Roberta' }] : [];
      if (path === '/crm_leads' && opt.method === 'POST') return [{ id: 'Lnovo' }];
      return [];
    };
    window.podeEditar = () => true;
    window.waRespCarregar = async function () { };
  }, cfg);
  await page.evaluate(() => {
    document.getElementById('login').classList.add('off');
    currentUser = 'Pedro'; tab = 'conversas'; window.sessTok = () => 'tok-qa';
    return openConversas();
  });
  await page.waitForSelector('#wanova');
  return { browser, page };
}

async function preencher(page, num, nome, txt) {
  await page.click('#wanova');
  await page.fill('#wanovonum', num);
  await page.locator('#wanovonum').blur();
  await page.waitForTimeout(150);
  if (nome) await page.fill('#wanovonome', nome);
  await page.fill('#wanovotxt', txt);
}

test('número novo: envia e cria a ficha no funil com o nome digitado', async () => {
  const { browser, page } = await abrir();
  try {
    await preencher(page, '21 98888-7777', 'Ana  Souza', 'Olá Ana!');
    assert.match(await page.textContent('#wanovoaviso'), /lead é criado/);
    await page.click('#wanovook');
    await page.waitForFunction(() => QA.rpc.some(r => r[0] === 'crm_wa_conversa_vincular_lead'));
    const q = await page.evaluate(() => QA);
    assert.deepEqual(q.send[0], { numero: '5521988887777', texto: 'Olá Ana!', conta_id: 'k1' });
    const post = q.api.find(a => a[0] === '/crm_leads' && a[1] === 'POST');
    assert.ok(post, 'POST do lead');
    assert.equal(post[2].nome, 'Ana Souza');
    assert.equal(post[2].nome_auto, false);
    assert.equal(post[2].etapa, 'contato_feito');
    assert.equal(post[2].responsavel, 'Pedro');
    assert.equal(post[2].whatsapp, '(21) 98888-7777');
    assert.equal(post[2].proximo_canal, 'whatsapp');
    assert.deepEqual(q.rpc.find(r => r[0] === 'crm_wa_conversa_vincular_lead')[1], { p_conversa_id: 'c2', p_lead_id: 'Lnovo' });
    assert.equal(await page.evaluate(() => WA.sel), 'c2');
    assert.deepEqual(page._erros || [], []);
  } finally { await browser.close(); }
});

test('sem nome: lead nasce com nome automático', async () => {
  const { browser, page } = await abrir();
  try {
    await preencher(page, '2133334444', '', 'Oi');
    await page.click('#wanovook');
    await page.waitForFunction(() => QA.api.some(a => a[0] === '/crm_leads' && a[1] === 'POST'));
    const post = await page.evaluate(() => QA.api.find(a => a[0] === '/crm_leads' && a[1] === 'POST')[2]);
    assert.equal(post.nome, 'WhatsApp (21) 3333-4444');
    assert.equal(post.nome_auto, true);
  } finally { await browser.close(); }
});

test('número que já é lead: não cria outro, liga à ficha existente', async () => {
  const { browser, page } = await abrir({ leadExistente: true });
  try {
    await preencher(page, '21977776666', '', 'Oi de novo');
    assert.match(await page.textContent('#wanovoaviso'), /Já é lead: Ana Antiga/);
    await page.click('#wanovook');
    await page.waitForFunction(() => QA.rpc.some(r => r[0] === 'crm_wa_conversa_vincular_lead'));
    const q = await page.evaluate(() => QA);
    assert.ok(!q.api.some(a => a[0] === '/crm_leads' && a[1] === 'POST'), 'não pode criar lead duplicado');
    assert.equal(q.rpc.find(r => r[0] === 'crm_wa_conversa_vincular_lead')[1].p_lead_id, 'L9');
  } finally { await browser.close(); }
});

test('número que já tem conversa: oferece abrir, sem enviar', async () => {
  const { browser, page } = await abrir();
  try {
    await preencher(page, '(21) 99999-0000', '', 'x');
    assert.match(await page.textContent('#wanovoaviso'), /Já existe conversa/);
    await page.click('#wanovoabre');
    assert.equal(await page.evaluate(() => WA.sel), 'c1');
    assert.equal(await page.evaluate(() => QA.send.length), 0);
  } finally { await browser.close(); }
});

test('unidade com dois números: exige escolher por qual enviar', async () => {
  const { browser, page } = await abrir({ duasContas: true });
  try {
    await preencher(page, '21966665555', '', 'Oi');
    await page.click('#wanovook');
    await page.waitForTimeout(150);
    assert.equal(await page.evaluate(() => QA.send.length), 0);
    await page.selectOption('#wanovoconta', 'k2');
    await page.click('#wanovook');
    await page.waitForFunction(() => QA.send.length === 1);
    assert.equal(await page.evaluate(() => QA.send[0].conta_id), 'k2');
  } finally { await browser.close(); }
});

test('número inválido não envia', async () => {
  const { browser, page } = await abrir();
  try {
    await preencher(page, '12345', '', 'Oi');
    assert.match(await page.textContent('#wanovoaviso'), /inválido/);
    await page.click('#wanovook');
    await page.waitForTimeout(150);
    assert.equal(await page.evaluate(() => QA.send.length), 0);
  } finally { await browser.close(); }
});
