/* Cadastro de lead (10/09/2026):
   1. responsavel pelo aluno menor = o proprio prospect, por padrao
   2. primeiro contato ja feito, registrado no proprio cadastro
   Tem que FALHAR no arquivo anterior e PASSAR no novo, exceto os [GUARDA].

   Uso:  CRM_HTML=/caminho/index.html node --test qa/cadastro.test.mjs
*/
import test from 'node:test';
import assert from 'node:assert/strict';
import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';

const HTML = process.env.CRM_HTML;
if (!HTML) throw new Error('defina CRM_HTML com o caminho do index.html');
const FILE = pathToFileURL(HTML).href;
const HOJE = new Date().toISOString().slice(0, 10);

const USERS = [{
  id: 'u1', nome: 'Admin QA', email: 'qa@cnataquara.com.br', cor: '#19408B',
  admin: true, ativo: true, consultor: true, papel: 'admin', permissoes: {},
  hora_inicio: null, hora_fim: null
}];
const BASE = {
  etapa: 'respondeu', curso: 'Inglês', origem: 'Google', responsavel: 'Admin QA',
  data_entrada: HOJE, ultimo_contato: null, ultima_tentativa: null, tentativas_sem_retorno: 0,
  nome_aluno: null, nivel: null, turma: null, motivo_perda: null, whatsapp: null, idade: null,
  responsavel_legal: null, data_inicio_aulas: null, proximo_atendimento: null,
  proximo_atendimento_hora: null, proximo_canal: null, data_fechamento: null, acao_id: null, observacoes: null
};
const LEADS = [
  Object.assign({}, BASE, { id: 'L-AVO', nome: 'ZZ AVO QUE PROCUROU', nome_aluno: 'ZZ NETO', idade: 9,
    responsavel_legal: 'ZZ MAE QUE ASSINA', whatsapp: '21999990011' }),
  Object.assign({}, BASE, { id: 'L-MAE', nome: 'ZZ MAE PROSPECT', nome_aluno: 'ZZ FILHO', idade: 8,
    responsavel_legal: 'ZZ MAE PROSPECT', whatsapp: '21999990012' })
];

async function abrir() {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const reqs = [];
  await ctx.addInitScript(() => {
    try {
      localStorage.setItem('crmAuth', 'Admin QA');
      localStorage.setItem('crmAuthEmail', 'qa@cnataquara.com.br');
    } catch (e) { }
  });
  const json = (route, body) => route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(body) });
  await ctx.route('**/rest/v1/**', r => json(r, []));
  await ctx.route('**/crm_usuarios*', r => json(r, USERS));
  let novo = null;
  await ctx.route('**/crm_leads*', r => {
    const req = r.request();
    if (req.method() === 'POST') {
      const body = JSON.parse(req.postData() || '{}');
      reqs.push({ t: 'lead', method: 'POST', body });
      /* imita o trigger crm_leads_agenda_novo: sem agenda informada, 10 minutos */
      novo = Object.assign({}, BASE, { id: 'L-NEW', etapa: 'novo' }, body);
      if (!novo.proximo_atendimento) { novo.proximo_atendimento = HOJE; novo.proximo_atendimento_hora = '23:59'; novo.proximo_canal = 'whatsapp'; }
      return json(r, [novo]);
    }
    if (req.method() === 'PATCH') {
      const body = JSON.parse(req.postData() || '{}');
      reqs.push({ t: 'lead', method: 'PATCH', url: req.url(), body });
      const alvo = req.url().includes('L-NEW') ? novo : (LEADS.find(l => req.url().includes(l.id)) || LEADS[0]);
      return json(r, [Object.assign(alvo, body)]);
    }
    if (req.url().includes('id=eq.L-NEW')) {
      reqs.push({ t: 'lead', method: 'GET-ONE' });
      return json(r, [Object.assign({}, novo, { ultimo_contato: HOJE })]);
    }
    return json(r, LEADS);
  });
  /* registrada depois: vence o pega-tudo de crm_leads* */
  await ctx.route('**/crm_leads_interacoes*', r => {
    const req = r.request();
    if (req.method() === 'POST') {
      const body = JSON.parse(req.postData() || '{}');
      reqs.push({ t: 'int', method: 'POST', body });
      return json(r, [Object.assign({ id: 'I1', data: HOJE }, body)]);
    }
    return json(r, []);
  });
  const page = await ctx.newPage();
  await page.goto(FILE);
  await page.waitForFunction(() => document.getElementById('login').classList.contains('off'), null, { timeout: 15000 });
  await page.evaluate(() => setTab('leads'));
  await page.waitForSelector('#board .card', { timeout: 15000 });
  return { browser, page, reqs };
}
async function novoLead(page) {
  await page.evaluate(() => openModal(null));
  await page.waitForSelector('#ov.open');
}
const leadPost = reqs => reqs.find(x => x.t === 'lead' && x.method === 'POST');
const intPost = reqs => reqs.find(x => x.t === 'int' && x.method === 'POST');

/* ----------------------------------------------------------- responsavel */
test('resp - menor: o responsavel e o proprio prospect sem digitar de novo', async () => {
  const { browser, page, reqs } = await abrir();
  try {
    await novoLead(page);
    await page.fill('#form [data-k=nome]', 'ZZ MARIA MAE');
    await page.fill('#form [data-k=idade]', '10');
    const inp = page.locator('#form [data-k=responsavel_legal]');
    assert.equal(await inp.isVisible(), false, 'o campo nao pode pedir o mesmo nome de novo');
    assert.match(await page.locator('#fRespLegal .rlmesmo').innerText(), /ZZ MARIA MAE/);
    await page.click('#save');
    await page.waitForTimeout(700);
    assert.equal(leadPost(reqs).body.responsavel_legal, 'ZZ MARIA MAE');
  } finally { await browser.close(); }
});

test('resp - o nome do prospect editado depois continua valendo para o responsavel', async () => {
  const { browser, page, reqs } = await abrir();
  try {
    await novoLead(page);
    await page.fill('#form [data-k=idade]', '7');
    await page.fill('#form [data-k=nome]', 'ZZ JOANA');
    await page.fill('#form [data-k=nome]', 'ZZ JOANA SILVA');
    await page.click('#save');
    await page.waitForTimeout(700);
    assert.equal(leadPost(reqs).body.responsavel_legal, 'ZZ JOANA SILVA');
  } finally { await browser.close(); }
});

test('resp - "Outra pessoa" abre o campo, cobra e grava o nome digitado', async () => {
  const { browser, page, reqs } = await abrir();
  try {
    await novoLead(page);
    await page.fill('#form [data-k=nome]', 'ZZ AVO');
    await page.fill('#form [data-k=idade]', '6');
    await page.click('#fRespLegal .rlmesmo [data-rl=outra]');
    const inp = page.locator('#form [data-k=responsavel_legal]');
    assert.equal(await inp.isVisible(), true);
    assert.equal(await inp.evaluate(el => el.classList.contains('need')), true);
    await inp.fill('ZZ MAE QUE ASSINA');
    await page.click('#save');
    await page.waitForTimeout(700);
    assert.equal(leadPost(reqs).body.responsavel_legal, 'ZZ MAE QUE ASSINA');
  } finally { await browser.close(); }
});

/* [GUARDA] passa no antigo tambem: la o campo ja ficava aberto e vazio. */
test('[GUARDA] resp - adolescente que procurou sozinho: o responsavel tem que ser outra pessoa', async () => {
  const { browser, page } = await abrir();
  try {
    await novoLead(page);
    await page.fill('#form [data-k=nome]', 'ZZ TEEN');
    await page.fill('#form [data-k=idade]', '15');
    await page.fill('#form [data-k=nome_aluno]', 'ZZ TEEN');
    const inp = page.locator('#form [data-k=responsavel_legal]');
    assert.equal(await inp.isVisible(), true);
    assert.equal(await inp.inputValue(), '', 'o aluno nao pode virar responsavel dele mesmo');
    assert.equal(await page.locator('#fRespLegal .rlvolta').isVisible(), false);
  } finally { await browser.close(); }
});

/* [GUARDA] passa no antigo tambem: garante que a ficha antiga nao perde o nome. */
test('[GUARDA] resp - ficha gravada com responsavel diferente abre com o campo aberto', async () => {
  const { browser, page } = await abrir();
  try {
    await page.locator('#board .card', { hasText: 'ZZ AVO QUE PROCUROU' }).first().click();
    await page.waitForSelector('#ov.open');
    const inp = page.locator('#form [data-k=responsavel_legal]');
    assert.equal(await inp.isVisible(), true);
    assert.equal(await inp.inputValue(), 'ZZ MAE QUE ASSINA');
  } finally { await browser.close(); }
});

test('[GUARDA] resp - adulto nao ganha responsavel', async () => {
  const { browser, page, reqs } = await abrir();
  try {
    await novoLead(page);
    await page.fill('#form [data-k=nome]', 'ZZ ADULTO');
    await page.fill('#form [data-k=idade]', '30');
    assert.equal(await page.locator('#fRespLegal').isVisible(), false);
    await page.click('#save');
    await page.waitForTimeout(700);
    assert.equal(leadPost(reqs).body.responsavel_legal, null);
  } finally { await browser.close(); }
});

/* ------------------------------------------------------- primeiro contato */
test('[GUARDA] 1o contato - padrao "ainda nao falei" deixa o banco agendar os 10 minutos', async () => {
  const { browser, page, reqs } = await abrir();
  try {
    await novoLead(page);
    await page.fill('#form [data-k=nome]', 'ZZ NOVO SEM CONTATO');
    await page.click('#save');
    await page.waitForTimeout(800);
    const b = leadPost(reqs).body;
    assert.ok(!b.proximo_atendimento, 'nao pode mandar agenda: quem agenda e o trigger');
    assert.ok(!b.ultimo_contato);
    assert.equal(intPost(reqs), undefined);
  } finally { await browser.close(); }
});

test('1o contato - "ja falei" agenda a data escolhida e registra contato efetivo', async () => {
  const { browser, page, reqs } = await abrir();
  try {
    await novoLead(page);
    await page.fill('#form [data-k=nome]', 'ZZ VEIO NA RECEPCAO');
    await page.click('#pcBox [data-pc=sim]');
    await page.selectOption('#pcCanal', 'visita');
    await page.locator('#pcBox .rted').fill('Veio na recepcao, quer turma de sabado.');
    const prox = await page.inputValue('#pcProx');
    assert.ok(prox > HOJE, 'a sugestao tem que ser o proximo dia util, nao hoje');
    await page.click('#save');
    await page.waitForTimeout(1200);
    const b = leadPost(reqs).body;
    assert.equal(b.proximo_atendimento, prox);
    assert.ok(b.proximo_atendimento_hora);
    assert.ok(!b.ultimo_contato, 'ultimo contato continua sendo do trigger, nao do front');
    const i = intPost(reqs);
    assert.ok(i, 'o contato tem que entrar no historico');
    assert.equal(i.body.efetivo, true);
    assert.equal(i.body.tipo, 'visita');
    assert.equal(i.body.lead_id, 'L-NEW');
    assert.match(i.body.nota, /quer turma de sabado/);
    assert.equal(i.body.proximo_contato, prox);
    const et = reqs.find(x => x.method === 'PATCH' && x.body.etapa === 'respondeu');
    assert.ok(et, 'contato efetivo leva o lead para Respondeu');
  } finally { await browser.close(); }
});

test('1o contato - "ja falei" sem relato nao grava nada e diz o que falta', async () => {
  const { browser, page, reqs } = await abrir();
  try {
    await novoLead(page);
    await page.fill('#form [data-k=nome]', 'ZZ SEM RELATO');
    await page.click('#pcBox [data-pc=sim]');
    await page.click('#save');
    await page.waitForTimeout(600);
    assert.equal(leadPost(reqs), undefined);
    assert.equal(intPost(reqs), undefined);
  } finally { await browser.close(); }
});

test('1o contato - em "Aguardando 27.1" o bloco nao pede data e nao manda agenda', async () => {
  const { browser, page, reqs } = await abrir();
  try {
    await novoLead(page);
    await page.fill('#form [data-k=nome]', 'ZZ SO NO 27.1');
    await page.selectOption('#form [data-k=etapa]', 'aguardando_271');
    await page.click('#pcBox [data-pc=sim]');
    assert.equal(await page.locator('#pcProx').isVisible(), false);
    await page.locator('#pcBox .rted').fill('Ligou, so consegue comecar em fevereiro.');
    await page.click('#save');
    await page.waitForTimeout(1000);
    assert.ok(!leadPost(reqs).body.proximo_atendimento, '01/10 e carimbo do banco no INSERT');
    const i = intPost(reqs);
    assert.ok(i);
    assert.equal(i.body.proximo_contato, null);
  } finally { await browser.close(); }
});

test('[GUARDA] 1o contato - ficha existente nao mostra o bloco e mantem o campo', async () => {
  const { browser, page } = await abrir();
  try {
    await page.locator('#board .card', { hasText: 'ZZ MAE PROSPECT' }).first().click();
    await page.waitForSelector('#ov.open');
    assert.equal(await page.locator('#pcBox').count(), 0);
    assert.equal(await page.locator('#form [data-k=ultimo_contato]').count(), 1);
  } finally { await browser.close(); }
});
