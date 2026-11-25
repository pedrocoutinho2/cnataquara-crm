/* Notas internas com menção nas Conversas (25/11/2026).
   Uso:  CRM_HTML=/caminho/index.html node --test qa/notas-internas.test.mjs
   Mocka só as RPCs da caixa de entrada (waRpc) e o wa-send (waFn): nada sai para o banco. */
import test from 'node:test';
import assert from 'node:assert/strict';
import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';

const HTML = process.env.CRM_HTML;
if (!HTML) throw new Error('defina CRM_HTML com o caminho do index.html');
const FILE = pathToFileURL(HTML).href;

async function abrir(viewport = { width: 1440, height: 900 }, eu = 'u1') {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport });
  await ctx.route('**/rest/v1/**', r => r.fulfill({ status: 200, contentType: 'application/json', body: '[]' }));
  await ctx.route('**/functions/v1/**', r => r.fulfill({ status: 200, contentType: 'application/json', body: '{}' }));
  const page = await ctx.newPage();
  page.on('pageerror', e => { page._erros = (page._erros || []).concat(String(e)); });
  await page.goto(FILE);
  await page.evaluate((eu) => {
    const agora = Date.now();
    window.QA = { chamadas: [], waSend: 0, notas: [], mencoes: [] };
    const iso = (m) => new Date(agora - m * 60000).toISOString();
    QA.notas = [{ id: 'n0', conversa_id: 'c1', autor_id: 'u2', autor_nome: 'Roberta Marques', texto: '@Pedro já liguei, sem resposta', apagada: false,
      created_at: iso(30), editada_em: null, mencoes: [{ usuario_id: 'u1', nome: 'Pedro', lida_em: null }] }];
    QA.mencoes = [{ nota_id: 'n0', conversa_id: 'c1', autor_nome: 'Roberta Marques', texto: '@Pedro já liguei', contato: 'Maria' }];
    const PESSOAS = [{ usuario_id: 'u1', nome: 'Pedro' }, { usuario_id: 'u2', nome: 'Roberta Marques' }, { usuario_id: 'u3', nome: 'Patrick Miguez' }];
    const conv = { id: 'c1', conta_id: 'k1', conta_provider: 'evolution', numero_e164: '5521999990000', nome_perfil: 'Maria',
      atendente_id: 'u2', atendente_nome: 'Roberta Marques', status: 'aberta', nao_lidas: 0, ultima_mensagem_em: iso(5),
      ultima_previa: 'oi', lead: null, lead_id: null, seguidores: [] };
    const msgs = [
      { id: 'm1', conversa_id: 'c1', direcao: 'entrada', tipo: 'texto', texto: 'Oi, quero saber do curso', wa_timestamp: iso(60), status: 'recebido' },
      { id: 'm2', conversa_id: 'c1', direcao: 'saida', tipo: 'texto', texto: 'Olá! Claro', wa_timestamp: iso(10), status: 'lido', autor_id: 'u2' }
    ];
    window.waRpc = async function (nome, args) {
      QA.chamadas.push([nome, args]);
      switch (nome) {
        case 'crm_wa_painel': return { eu: { usuario_id: eu, nivel: eu === 'u1' ? 3 : 2, ve_tudo: eu === 'u1' },
          contas: [{ id: 'k1', provider: 'evolution', rotulo: 'Taquara', numero_e164: '5521900000000' }], templates: [],
          agentes: [{ usuario_id: 'u2', nome: 'Roberta Marques', abertas: 1 }, { usuario_id: 'u3', nome: 'Patrick Miguez', abertas: 0 }] };
        case 'crm_wa_conversas_listar': return [Object.assign({}, conv)];
        case 'crm_wa_mensagens_listar': return msgs;
        case 'crm_wa_notas_listar': return QA.notas.slice();
        case 'crm_wa_notas_pessoas': return PESSOAS;
        case 'crm_wa_mencoes_pendentes': return QA.mencoes.slice();
        case 'crm_wa_mencoes_marcar_lidas': QA.mencoes = []; return 1;
        case 'crm_wa_nota_criar': {
          const ment = PESSOAS.filter(p => args.p_mencoes.includes(p.usuario_id)).map(p => ({ usuario_id: p.usuario_id, nome: p.nome, lida_em: null }));
          QA.notas.push({ id: 'n' + QA.notas.length, conversa_id: args.p_conversa_id, autor_id: eu, autor_nome: 'Pedro', texto: args.p_texto,
            apagada: false, created_at: new Date().toISOString(), editada_em: null, mencoes: ment });
          return { id: 'nx', mencoes: args.p_mencoes };
        }
        case 'crm_wa_nota_editar': {
          const n = QA.notas.find(x => x.id === args.p_nota_id); n.texto = args.p_texto; n.editada_em = new Date().toISOString();
          n.mencoes = PESSOAS.filter(p => args.p_mencoes.includes(p.usuario_id)).map(p => ({ usuario_id: p.usuario_id, nome: p.nome }));
          return { id: n.id, mencoes: args.p_mencoes };
        }
        case 'crm_wa_nota_apagar': { const n = QA.notas.find(x => x.id === args.p_nota_id); n.apagada = true; n.texto = null; return null; }
        case 'crm_wa_fila_listar': return [];
        case 'crm_respostas_rapidas': return [];
        default: return [];
      }
    };
    window.waFn = async function (nome) { if (nome === 'wa-send') QA.waSend++; return {}; };
    window.waRespCarregar = async function () { };
  }, eu);
  await page.evaluate(() => {
    document.getElementById('login').classList.add('off');
    currentUser = 'Pedro'; tab = 'conversas'; window.sessTok = () => 'tok-qa';
    return openConversas();
  });
  await page.waitForSelector('.wai[data-c="c1"]');
  return { browser, page };
}

test('menção pendente aparece na lista e some ao abrir a conversa', async () => {
  const { browser, page } = await abrir();
  try {
    assert.ok(await page.locator('#wamentbar').isVisible(), 'barra de menção');
    assert.ok(await page.locator('.wai[data-c="c1"] .watag.ment').isVisible(), 'tag @ você na conversa');
    assert.equal(await page.locator('#nbConversas').textContent(), '1');
    await page.click('.wai[data-c="c1"]');
    await page.waitForSelector('.wani[data-n="n0"]');
    await page.waitForFunction(() => QA.chamadas.some(c => c[0] === 'crm_wa_mencoes_marcar_lidas'));
    assert.equal(await page.locator('#wamentbar').count(), 0, 'barra some depois de ler');
    assert.equal(await page.locator('#nbConversas').textContent(), '0');
    /* a nota fica no meio do tempo, entre a entrada (60 min) e a saída (10 min) */
    const ordem = await page.$$eval('#wamsgs > .wam, #wamsgs > .wani', els => els.map(e => e.dataset.m || ('n:' + e.dataset.n)));
    assert.deepEqual(ordem, ['m1', 'n:n0', 'm2']);
    assert.match(await page.locator('.wani[data-n="n0"] .ment').first().textContent(), /@Pedro/);
    assert.equal(await page.locator('.wani[data-n="n0"] [data-nedit]').count(), 0, 'nota alheia não tem Editar');
    assert.deepEqual(page._erros || [], []);
  } finally { await browser.close(); }
});

test('nota interna com @ salva por RPC, nunca pelo wa-send', async () => {
  const { browser, page } = await abrir();
  try {
    await page.click('.wai[data-c="c1"]');
    await page.waitForSelector('.wamodo');
    await page.click('.wamodo [data-modo="nota"]');
    const ta = page.locator('#wantxt');
    await ta.click();
    await ta.pressSequentially('Pode me explicar o preço que passou? @Pat');
    await page.waitForSelector('#wamentpop.open');
    assert.match(await page.locator('#wamentpop').textContent(), /@Patrick Miguez/);
    await page.keyboard.press('Enter');
    assert.equal(await ta.inputValue(), 'Pode me explicar o preço que passou? @Patrick Miguez ');
    await page.keyboard.press('Enter');
    await page.waitForFunction(() => QA.chamadas.some(c => c[0] === 'crm_wa_nota_criar'));
    const args = await page.evaluate(() => QA.chamadas.find(c => c[0] === 'crm_wa_nota_criar')[1]);
    assert.deepEqual(args.p_mencoes, ['u3']);
    assert.equal(args.p_conversa_id, 'c1');
    assert.equal(await page.evaluate(() => QA.waSend), 0, 'wa-send não pode ser chamado');
    await page.waitForSelector('.wani [data-nedit]');
    assert.equal(await page.locator('#wantxt').inputValue(), '');
    assert.deepEqual(page._erros || [], []);
  } finally { await browser.close(); }
});

test('/nota no campo de mensagem troca para nota interna', async () => {
  const { browser, page } = await abrir();
  try {
    await page.click('.wai[data-c="c1"]');
    await page.waitForSelector('#watxt');
    await page.locator('#watxt').pressSequentially('/nota ');
    await page.waitForSelector('#wantxt');
    assert.ok(await page.locator('.wacomp.nota').isVisible());
    await page.locator('#wantxt').pressSequentially('lembrar de ligar sexta');
    await page.click('#wanotasend');
    await page.waitForFunction(() => QA.chamadas.some(c => c[0] === 'crm_wa_nota_criar'));
    assert.equal(await page.evaluate(() => QA.waSend), 0);
  } finally { await browser.close(); }
});

test('autor edita (em modal) e apaga a própria nota', async () => {
  const { browser, page } = await abrir();
  try {
    await page.click('.wai[data-c="c1"]');
    await page.click('.wamodo [data-modo="nota"]');
    await page.locator('#wantxt').fill('rascunho');
    await page.click('#wanotasend');
    await page.waitForSelector('.wani [data-nedit]');
    await page.click('.wani [data-nedit]');
    await page.waitForSelector('#wanted');
    await page.locator('#wanted').fill('');
    await page.locator('#wanted').pressSequentially('texto novo @Rob');
    await page.waitForSelector('#wanedpop.open');
    await page.keyboard.press('Enter');
    await page.click('#wanedok');
    await page.waitForFunction(() => QA.chamadas.some(c => c[0] === 'crm_wa_nota_editar'));
    const a = await page.evaluate(() => QA.chamadas.find(c => c[0] === 'crm_wa_nota_editar')[1]);
    assert.equal(a.p_texto, 'texto novo @Roberta Marques');
    assert.deepEqual(a.p_mencoes, ['u2']);
    await page.waitForSelector('.wani .meta span[title^="Editada"]');
    await page.click('.wani [data-ndel]');
    await page.click('#wandok');
    await page.waitForFunction(() => QA.chamadas.some(c => c[0] === 'crm_wa_nota_apagar'));
    await page.waitForSelector('.wani.apag');
    assert.match(await page.locator('.wani.apag .tx').textContent(), /Nota apagada/);
    assert.deepEqual(page._erros || [], []);
  } finally { await browser.close(); }
});

test('celular 390 px: abas e compositor cabem na tela', async () => {
  const { browser, page } = await abrir({ width: 390, height: 844 });
  try {
    await page.click('.wai[data-c="c1"]');
    await page.click('.wamodo [data-modo="nota"]');
    await page.waitForSelector('#wantxt');
    const w = await page.evaluate(() => {
      const r = document.querySelector('.wacomp.nota').getBoundingClientRect();
      const m = document.querySelector('.wamodo').getBoundingClientRect();
      return { comp: r.right, modo: m.right, vw: innerWidth };
    });
    assert.ok(w.comp <= w.vw + 1 && w.modo <= w.vw + 1, JSON.stringify(w));
    await page.screenshot({ path: '/tmp/notas-390.png' });
  } finally { await browser.close(); }
});
