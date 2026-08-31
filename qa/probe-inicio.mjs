import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';

const FILE = pathToFileURL(process.env.CRM_HTML).href;
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
  data: '2026-08-' + String(21 + i).padStart(2, '0'), agendados: 20, efetivos: 15,
  pendentes: 5, matriculas: 1, leads_novos: 3, cumprimento: 75,
  fechado_em: null, fechado_por: null
}));

const LEADS = Array.from({ length: 40 }, (_, i) => ({
  id: 'L' + i, nome: 'Lead ' + i, etapa: 'novo', curso: 'Inglês', origem: 'Google',
  responsavel: 'Admin QA', data_entrada: HOJE, ultimo_contato: null, ultima_tentativa: null,
  tentativas_sem_retorno: 0, nome_aluno: null, nivel: null, turma: null, motivo_perda: null,
  whatsapp: '2199999' + String(1000 + i), idade: null, responsavel_legal: null,
  data_inicio_aulas: null, proximo_atendimento: HOJE, proximo_atendimento_hora: '09:00:00',
  proximo_canal: 'whatsapp', data_fechamento: null, acao_id: null, observacoes: null
}));

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
page.on('console', m => { if (m.type() === 'error') console.log('  [console]', m.text().slice(0, 120)); });
await page.goto(FILE);
await page.waitForFunction(() => document.getElementById('login').classList.contains('off'), null, { timeout: 15000 });
await page.evaluate(() => setTab('inicio'));
await page.waitForTimeout(1500);

const r = await page.evaluate(() => {
  const out = {};
  const cs = el => el ? getComputedStyle(el) : null;
  const info = el => el ? {
    tag: el.tagName.toLowerCase() + (el.id ? '#' + el.id : '') + (el.className ? '.' + String(el.className).split(' ').join('.') : ''),
    clientH: el.clientHeight, scrollH: el.scrollHeight,
    rola: el.scrollHeight > el.clientHeight + 1,
    overflowY: cs(el).overflowY, height: cs(el).height, flex: cs(el).flex,
    minHeight: cs(el).minHeight, alignSelf: cs(el).alignSelf
  } : null;
  const board = document.getElementById('board');
  const rs = board.querySelector('.rscreen');
  out.board = info(board);
  out.rscreen = info(rs);
  out.mainwrap = info(document.querySelector('.mainwrap'));
  out.shell = info(document.querySelector('.shell'));
  out.body = { clientH: document.body.clientHeight, scrollH: document.body.scrollHeight, overflowY: cs(document.body).overflowY, position: cs(document.body).position, classes: document.body.className };
  out.docEl = { clientH: document.documentElement.clientHeight, scrollH: document.documentElement.scrollHeight, overflowY: cs(document.documentElement).overflowY };
  out.alignItemsBoard = cs(board).alignItems;
  /* consegue rolar de fato? */
  board.scrollTop = 9999;
  out.boardScrollTopDepois = board.scrollTop;
  if (rs) { rs.scrollTop = 9999; out.rscreenScrollTopDepois = rs.scrollTop; }
  window.scrollTo(0, 9999);
  out.windowScrollY = window.scrollY;
  return out;
});
console.log(JSON.stringify(r, null, 2));
await browser.close();
