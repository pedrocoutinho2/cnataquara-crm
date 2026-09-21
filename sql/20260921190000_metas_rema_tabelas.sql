-- Metas de matrícula e rematrícula + sessão por token (21/09/2026)

-- Sessão: token emitido no login. Tabelas novas só respondem via RPC com token válido.
create table if not exists public.crm_sessoes(
  token uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references public.crm_usuarios(id) on delete cascade,
  criado_em timestamptz not null default now(),
  expira_em timestamptz not null default now() + interval '30 days'
);
create index if not exists crm_sessoes_usuario_idx on public.crm_sessoes(usuario_id);
alter table public.crm_sessoes enable row level security;

create table if not exists public.crm_metas_config(
  chave text primary key,
  valor jsonb not null
);
alter table public.crm_metas_config enable row level security;

-- Histórico por semestre (base de média, pico e manutenção). Editável.
create table if not exists public.crm_metas_semestre(
  id uuid primary key default gen_random_uuid(),
  inicio date not null unique,
  fim date not null,
  matriculas int,
  rema_auto int,
  rema_contratual int,
  base_auto int,
  base_contratual int,
  obs text,
  atualizado_em timestamptz not null default now(),
  atualizado_por text
);
alter table public.crm_metas_semestre enable row level security;

-- Período de metas (Abr a Set ou Out a Mar).
create table if not exists public.crm_metas_periodo(
  id uuid primary key default gen_random_uuid(),
  inicio date not null unique,
  fim date not null,
  status text not null default 'rascunho' check (status in ('rascunho','ativa','fechada')),
  atualizado_em timestamptz not null default now(),
  atualizado_por text
);
alter table public.crm_metas_periodo enable row level security;

-- Um indicador por período: matricula (comercial), rema_contratual (secretaria), rema_total (pedagogico).
create table if not exists public.crm_metas_indicador(
  id uuid primary key default gen_random_uuid(),
  periodo_id uuid not null references public.crm_metas_periodo(id) on delete cascade,
  indicador text not null check (indicador in ('matricula','rema_contratual','rema_total')),
  base_media numeric,
  base_ref numeric,
  obs text,
  unique(periodo_id, indicador)
);
alter table public.crm_metas_indicador enable row level security;

-- Metas 1..N (comissão por faixa).
create table if not exists public.crm_metas_faixa(
  id uuid primary key default gen_random_uuid(),
  indicador_id uuid not null references public.crm_metas_indicador(id) on delete cascade,
  nivel int not null,
  alvo int not null,
  regra text,
  valor_rs numeric,
  unique(indicador_id, nivel)
);
alter table public.crm_metas_faixa enable row level security;

-- Ritmo mensal (só acompanhamento) e ajuste manual do realizado de matrícula.
create table if not exists public.crm_metas_mes(
  id uuid primary key default gen_random_uuid(),
  periodo_id uuid not null references public.crm_metas_periodo(id) on delete cascade,
  mes date not null,
  ritmo_1 int,
  ritmo_ult int,
  ajuste int,
  unique(periodo_id, mes)
);
alter table public.crm_metas_mes enable row level security;

-- Lista de rema do período (dado de aluno: só via RPC).
create table if not exists public.crm_rema_aluno(
  id uuid primary key default gen_random_uuid(),
  periodo_id uuid not null references public.crm_metas_periodo(id) on delete cascade,
  chave text not null,
  aluno text not null,
  turma text,
  idioma text, curso text, estagio text, professor text, formato text, horario text,
  tipo text not null check (tipo in ('automatica','contratual')),
  status text not null default 'pendente' check (status in ('pendente','realizada','nao_renova','trancou','negociacao')),
  status_box text,
  motivo text,
  obs text,
  data_status date,
  alterado_por text,
  alterado_em timestamptz,
  na_lista boolean not null default true,
  importado_em timestamptz not null default now(),
  unique(periodo_id, chave)
);
alter table public.crm_rema_aluno enable row level security;

create table if not exists public.crm_rema_import(
  id uuid primary key default gen_random_uuid(),
  periodo_id uuid not null references public.crm_metas_periodo(id) on delete cascade,
  arquivo text, gerado text,
  linhas int, novos int, atualizados int, sairam int,
  por text, em timestamptz not null default now()
);
alter table public.crm_rema_import enable row level security;

-- Módulos e permissões padrão: metas = painel e configuração; rema = marcar status.
insert into public.crm_modulos(modulo,nome,grupo,ordem) values
  ('metas','Metas · matrícula e rema','Gestão',137),
  ('rema','Metas · marcar rematrícula','Gestão',138)
on conflict do nothing;
insert into public.crm_papel_permissoes(papel,modulo,nivel) values
  ('admin','metas','total'),('admin','rema','total'),
  ('comercial','metas','ver'),('comercial','rema','nenhum'),
  ('secretaria','metas','ver'),('secretaria','rema','editar'),
  ('pedagogico','metas','ver'),('pedagogico','rema','ver'),
  ('coordenacao','metas','ver'),('coordenacao','rema','ver')
on conflict do nothing;

insert into public.crm_metas_config(chave,valor) values
  ('razao_social','"INSTITUTO DE EDUCACAO E IDIOMAS TAQUARA"'),
  ('rema_motivos','["Financeiro","Horário incompatível","Mudança de endereço","Insatisfação com o curso","Atingiu o objetivo","Saúde ou questão pessoal","Outro"]')
on conflict (chave) do nothing;

notify pgrst, 'reload schema';
