/* Rolagem vertical fora do quadro (kanban).
   Tem que FALHAR no arquivo anterior e PASSAR no novo.

   Uso:  CRM_HTML=/caminho/index.html node --test qa/scroll.test.mjs
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
  hora_inicio: '09:00:00', hora_fim: '18:00:00'
}];

const DIA = {
  kpis: { efetivos: 12, agendados: 30, cumpridos: 12, pendentes: 18, cumprimento: 40, matriculas: 2, leads_novos: 5 },
  consultor: 'Admin QA', data: HOJE
};
const SERIE = Array.from({ length: 10 }, (_, i) => ({
  data: '2026-08-' + String(11 + i).padStart(2, '0'), agendados: 20, efetivos: 15,
  pendentes: 5, matriculas: 1, leads_novos: 3, cumprimento: 75, fechado_em: null, fechado_por: null
}));
const LEADS = Array.from({ length: 40 }, (_, i) => ({
  id: 'L' + i, nome: 'Lead ' + i, etapa: 'novo', curso: 'Inglês', origem: 'Google',
  responsavel: 'Admin QA', data_entrada: HOJE, ultimo_contato: null, ultima_tentativa: null,
  tentativas_sem_retorno: 0, nome_aluno: null, nivel: null, turma: null, motivo_perda: null,
  whatsapp: '2199999' + String(1000 + i), idade: null, responsavel_legal: null,
  data_inicio_aulas: null, proximo_atendimento: HOJE, proximo_atendimento_hora: '09:00:00',
  proximo_canal: 'whatsapp', data_fechamento: null, acao_id: null, observacoes: null
}));

async function abrir() {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 800 } });
  await ctx.addInitScript(() => {
    try {
      localStorage.setItem('crmAuth', 'Admin QA');
      localStorage.setItem('crmAuthEmail', 'qa@cnataquara.com.br');
      localStorage.setItem('crmIniVista', 'minha');
    } catch (e) { }
  });
  const json = (r, b) => r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(b) });
  await ctx.route('**/rest/v1/**', r => json(r, []));
  await ctx.route('**/crm_usuarios*', r => json(r, USERS));
  await ctx.route('**/crm_leads*', r => json(r, LEADS));
  await ctx.route('**/rpc/crm_relatorio_dia*', r => json(r, DIA));
  await ctx.route('**/crm_relatorio_diario*', r => json(r, SERIE));
  const page = await ctx.newPage();
  await page.goto(FILE);
  await page.waitForFunction(() => document.getElementById('login').classList.contains('off'), null, { timeout: 15000 });
  return { browser, page };
}

/* dispara um wheel real no #board e devolve se o CRM engoliu o evento */
function roda(page) {
  return page.evaluate(() => {
    const board = document.getElementById('board');
    board.scrollTop = 0;
    board.scrollLeft = 0;
    const e = new WheelEvent('wheel', { deltaY: 300, deltaX: 0, bubbles: true, cancelable: true });
    board.dispatchEvent(e);
    return { engoliu: e.defaultPrevented, scrollLeft: board.scrollLeft, podeRolar: board.scrollHeight > board.clientHeight + 1 };
  });
}

test('a tela de Início rola: a roda do mouse não é sequestrada', async () => {
  const { browser, page } = await abrir();
  try {
    await page.evaluate(() => setTab('inicio'));
    await page.waitForSelector('#board .rscreen', { timeout: 15000 });
    const r = await roda(page);
    assert.equal(r.podeRolar, true, 'o conteúdo do Início é maior que a janela');
    assert.equal(r.engoliu, false, 'o handler de wheel não pode chamar preventDefault fora do quadro');
    assert.equal(r.scrollLeft, 0, 'rolagem vertical não pode virar rolagem horizontal aqui');
  } finally { await browser.close(); }
});

test('[GUARDA] no quadro de leads a roda continua rolando na horizontal', async () => {
  const { browser, page } = await abrir();
  try {
    await page.evaluate(() => setTab('leads'));
    await page.waitForSelector('#board .card', { timeout: 15000 });
    const r = await roda(page);
    assert.equal(r.engoliu, true, 'no kanban o comportamento antigo tem que continuar');
  } finally { await browser.close(); }
});

test('telaKanban conhece só as três abas em quadro', async () => {
  const { browser, page } = await abrir();
  try {
    const r = await page.evaluate(() => ({
      quadro: ['leads', 'escolas', 'empresas'].map(t => telaKanban(t)),
      telas: ['inicio', 'conversas', 'calendario', 'atas', 'demandas', 'acoes',
        'relatorios', 'equipe', 'mural', 'faq', 'calc', 'turmas'].map(t => telaKanban(t))
    }));
    assert.deepEqual(r.quadro, [true, true, true]);
    assert.equal(r.telas.some(Boolean), false, 'nenhuma tela comum pode ser tratada como quadro');
  } finally { await browser.close(); }
});
