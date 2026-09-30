-- Consolidação do CRM em base única · Fase 1 (expand, aditiva)
-- Base: CRM CNA (gpnwmsnayrqjcmhqrtpx). Decisão: 50-decisoes/2026-09-29-crm-base-unica
-- Nada existente muda de comportamento: toda tabela de dado ganha `unidade` com
-- default 'taquara', então o front atual, que não envia a coluna, continua gravando certo.
-- Globais (sem coluna): crm_unidades, crm_modulos, crm_papel_permissoes.
-- crm_usuarios: sem coluna; acesso por unidade vai para crm_usuario_unidades.
-- Tabelas de backup antigas (*bkp*) ficam de fora.

-- 1. Catálogo de unidades
create table public.crm_unidades (
  slug text primary key check (slug ~ '^[a-z0-9-]+$'),
  nome text not null,
  sufixo_email text,
  status text not null default 'ativa' check (status in ('ativa','implantacao','inativa')),
  ordem integer not null default 0,
  criado_em timestamptz not null default now()
);
insert into public.crm_unidades (slug, nome, sufixo_email, status, ordem) values
  ('taquara',        'Taquara',        '.taquara@cna.com.br',   'ativa',       1),
  ('queimados',      'Queimados',      '.queimados@cna.com.br', 'ativa',       2),
  ('jardim-america', 'Jardim América', null,                    'implantacao', 3);
alter table public.crm_unidades enable row level security;
create policy crm_unidades_leitura on public.crm_unidades for select to anon, authenticated using (true);
revoke insert, update, delete, truncate on public.crm_unidades from anon, authenticated;
grant select on public.crm_unidades to anon, authenticated;
comment on table public.crm_unidades is 'Unidades da rede. Leitura pública (nome e slug), escrita só por migração.';

-- 2. Vínculo usuário × unidade (quem entra em qual unidade, com qual papel)
create table public.crm_usuario_unidades (
  usuario_id uuid not null references public.crm_usuarios(id) on delete cascade,
  unidade text not null references public.crm_unidades(slug),
  papel text,
  admin boolean not null default false,
  consultor boolean not null default false,
  permissoes jsonb,
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  primary key (usuario_id, unidade)
);
alter table public.crm_usuario_unidades enable row level security;  -- sem policy: só RPC security definer
revoke all on public.crm_usuario_unidades from anon, authenticated;
comment on table public.crm_usuario_unidades is 'Acesso por unidade. 1 vínculo ativo = entra direto; 2+ = tela de escolha após o login.';
insert into public.crm_usuario_unidades (usuario_id, unidade, papel, admin, consultor, permissoes, ativo)
select id, 'taquara', papel, coalesce(admin,false), coalesce(consultor,false), permissoes, coalesce(ativo,true)
from public.crm_usuarios;

-- 3. Coluna unidade nas 54 tabelas de dado
alter table public.crm_acoes add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_acoes_unidade_idx on public.crm_acoes (unidade);
alter table public.crm_acoes_materiais add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_acoes_materiais_unidade_idx on public.crm_acoes_materiais (unidade);
alter table public.crm_agenda_categorias add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_agenda_categorias_unidade_idx on public.crm_agenda_categorias (unidade);
alter table public.crm_agenda_config add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_agenda_config_unidade_idx on public.crm_agenda_config (unidade);
alter table public.crm_agenda_eventos add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_agenda_eventos_unidade_idx on public.crm_agenda_eventos (unidade);
alter table public.crm_avisos add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_avisos_unidade_idx on public.crm_avisos (unidade);
alter table public.crm_configs add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_configs_unidade_idx on public.crm_configs (unidade);
alter table public.crm_demanda_anexos add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_demanda_anexos_unidade_idx on public.crm_demanda_anexos (unidade);
alter table public.crm_demanda_itens add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_demanda_itens_unidade_idx on public.crm_demanda_itens (unidade);
alter table public.crm_demandas add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_demandas_unidade_idx on public.crm_demandas (unidade);
alter table public.crm_empresas add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_empresas_unidade_idx on public.crm_empresas (unidade);
alter table public.crm_escolas add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_escolas_unidade_idx on public.crm_escolas (unidade);
alter table public.crm_faq add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_faq_unidade_idx on public.crm_faq (unidade);
alter table public.crm_interacoes add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_interacoes_unidade_idx on public.crm_interacoes (unidade);
alter table public.crm_leads add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_leads_unidade_idx on public.crm_leads (unidade);
alter table public.crm_leads_etapas add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_leads_etapas_unidade_idx on public.crm_leads_etapas (unidade);
alter table public.crm_leads_interacoes add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_leads_interacoes_unidade_idx on public.crm_leads_interacoes (unidade);
alter table public.crm_metas add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_metas_unidade_idx on public.crm_metas (unidade);
alter table public.crm_metas_config add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_metas_config_unidade_idx on public.crm_metas_config (unidade);
alter table public.crm_metas_faixa add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_metas_faixa_unidade_idx on public.crm_metas_faixa (unidade);
alter table public.crm_metas_indicador add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_metas_indicador_unidade_idx on public.crm_metas_indicador (unidade);
alter table public.crm_metas_mes add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_metas_mes_unidade_idx on public.crm_metas_mes (unidade);
alter table public.crm_metas_periodo add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_metas_periodo_unidade_idx on public.crm_metas_periodo (unidade);
alter table public.crm_metas_semestre add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_metas_semestre_unidade_idx on public.crm_metas_semestre (unidade);
alter table public.crm_precos_certificacoes add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_precos_certificacoes_unidade_idx on public.crm_precos_certificacoes (unidade);
alter table public.crm_precos_materiais add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_precos_materiais_unidade_idx on public.crm_precos_materiais (unidade);
alter table public.crm_precos_niveis add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_precos_niveis_unidade_idx on public.crm_precos_niveis (unidade);
alter table public.crm_relatorio_diario add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_relatorio_diario_unidade_idx on public.crm_relatorio_diario (unidade);
alter table public.crm_rema_aluno add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_rema_aluno_unidade_idx on public.crm_rema_aluno (unidade);
alter table public.crm_rema_import add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_rema_import_unidade_idx on public.crm_rema_import (unidade);
alter table public.crm_respostas_rapidas add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_respostas_rapidas_unidade_idx on public.crm_respostas_rapidas (unidade);
alter table public.crm_reuniao_assinaturas add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_reuniao_assinaturas_unidade_idx on public.crm_reuniao_assinaturas (unidade);
alter table public.crm_reuniao_participantes add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_reuniao_participantes_unidade_idx on public.crm_reuniao_participantes (unidade);
alter table public.crm_reunioes add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_reunioes_unidade_idx on public.crm_reunioes (unidade);
alter table public.crm_tarefas add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_tarefas_unidade_idx on public.crm_tarefas (unidade);
alter table public.crm_tn_agendamentos add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_tn_agendamentos_unidade_idx on public.crm_tn_agendamentos (unidade);
alter table public.crm_tn_avulsos add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_tn_avulsos_unidade_idx on public.crm_tn_avulsos (unidade);
alter table public.crm_tn_grade add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_tn_grade_unidade_idx on public.crm_tn_grade (unidade);
alter table public.crm_turmas add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_turmas_unidade_idx on public.crm_turmas (unidade);
alter table public.crm_wa_contas add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_wa_contas_unidade_idx on public.crm_wa_contas (unidade);
alter table public.crm_wa_conversas add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_wa_conversas_unidade_idx on public.crm_wa_conversas (unidade);
alter table public.crm_wa_eventos add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_wa_eventos_unidade_idx on public.crm_wa_eventos (unidade);
alter table public.crm_wa_fila add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_wa_fila_unidade_idx on public.crm_wa_fila (unidade);
alter table public.crm_wa_mensagens add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_wa_mensagens_unidade_idx on public.crm_wa_mensagens (unidade);
alter table public.crm_wa_optout add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_wa_optout_unidade_idx on public.crm_wa_optout (unidade);
alter table public.crm_wa_regras add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_wa_regras_unidade_idx on public.crm_wa_regras (unidade);
alter table public.crm_wa_templates add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index crm_wa_templates_unidade_idx on public.crm_wa_templates (unidade);
alter table public.escape_jogadores add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index escape_jogadores_unidade_idx on public.escape_jogadores (unidade);
alter table public.escape_salas add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index escape_salas_unidade_idx on public.escape_salas (unidade);
alter table public.escape_sessao_salas add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index escape_sessao_salas_unidade_idx on public.escape_sessao_salas (unidade);
alter table public.escape_sessoes add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index escape_sessoes_unidade_idx on public.escape_sessoes (unidade);
alter table public.escape_temporadas add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index escape_temporadas_unidade_idx on public.escape_temporadas (unidade);
alter table public.escape_variantes add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index escape_variantes_unidade_idx on public.escape_variantes (unidade);
alter table public.leads_teste_nivel add column unidade text not null default 'taquara' references public.crm_unidades(slug);
create index leads_teste_nivel_unidade_idx on public.leads_teste_nivel (unidade);

-- 4. Sessão guarda a unidade ativa (default provisório 'taquara' para as sessões do front atual)
alter table public.crm_sessoes add column unidade text default 'taquara' references public.crm_unidades(slug);

notify pgrst, 'reload schema';