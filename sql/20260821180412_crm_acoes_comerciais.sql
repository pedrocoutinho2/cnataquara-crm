-- =========================================================
-- Ações comerciais de campo (panfletagem, blitz, evento)
-- =========================================================

create table if not exists public.crm_acoes (
  id                uuid primary key default gen_random_uuid(),
  titulo            text not null,
  tipo              text not null default 'panfletagem',
  data              date not null,
  hora_inicio       time,
  hora_fim          time,
  local_nome        text,
  escola_id         uuid references public.crm_escolas(id) on delete set null,
  empresa_id        uuid references public.crm_empresas(id) on delete set null,
  endereco          text,
  equipe            text[] not null default '{}',
  pedagogico        boolean not null default false,
  pedagogico_quem   text,
  cobertura         text not null default 'sem',
  materiais         text[] not null default '{}',
  meta_leads        integer,
  leads_captados    integer,
  custo_previsto_cents integer not null default 0,
  custo_real_cents  integer,
  observacoes       text,
  status            text not null default 'rascunho',
  parecer           text,
  submetido_por     text,
  submetido_em      timestamptz,
  aprovado_por      text,
  aprovado_em       timestamptz,
  agenda_evento_id  uuid references public.crm_agenda_eventos(id) on delete set null,
  criado_por        text,
  criado_em         timestamptz not null default now(),
  atualizado_em     timestamptz not null default now(),
  constraint crm_acoes_tipo_ck check (tipo in
    ('panfletagem','captacao_leads','evento_institucional','visita_corporativa','blitz','acao_escola','outro')),
  constraint crm_acoes_cobertura_ck check (cobertura in
    ('sem','registros','mascote','live')),
  constraint crm_acoes_status_ck check (status in
    ('rascunho','aguardando','aprovada','ajustar','realizada','cancelada')),
  constraint crm_acoes_hora_ck check (hora_inicio is null or hora_fim is null or hora_fim >= hora_inicio)
);

create index if not exists crm_acoes_data_idx    on public.crm_acoes(data desc);
create index if not exists crm_acoes_status_idx  on public.crm_acoes(status);
create index if not exists crm_acoes_escola_idx  on public.crm_acoes(escola_id);
create index if not exists crm_acoes_empresa_idx on public.crm_acoes(empresa_id);

-- catálogo editável de materiais (sem deploy para incluir item novo)
create table if not exists public.crm_acoes_materiais (
  id     uuid primary key default gen_random_uuid(),
  nome   text not null unique,
  ordem  integer not null default 0,
  ativo  boolean not null default true
);

insert into public.crm_acoes_materiais(nome,ordem) values
  ('Pedestal',10),('Banner roll-up',20),('Tenda 3x3',30),('Caixa de som',40),
  ('Panfletos',50),('Brindes',60),('Mesa e toalha',70),('Fantasia do mascote',80),
  ('Tablet para cadastro',90),('Ficha de cadastro impressa',100)
on conflict (nome) do nothing;

-- vínculo lead -> ação: é o que fecha o ciclo de custo por lead
alter table public.crm_leads
  add column if not exists acao_id uuid references public.crm_acoes(id) on delete set null;
create index if not exists crm_leads_acao_idx on public.crm_leads(acao_id);

-- RLS no padrão da casa
alter table public.crm_acoes            enable row level security;
alter table public.crm_acoes_materiais  enable row level security;
drop policy if exists anon_all on public.crm_acoes;
drop policy if exists anon_all on public.crm_acoes_materiais;
create policy anon_all on public.crm_acoes           for all to anon using (true) with check (true);
create policy anon_all on public.crm_acoes_materiais for all to anon using (true) with check (true);

-- módulo + permissões por papel
insert into public.crm_modulos(modulo,nome,grupo,ordem)
values ('acoes','Ações comerciais','Comercial',45)
on conflict (modulo) do update set nome=excluded.nome, grupo=excluded.grupo, ordem=excluded.ordem;

insert into public.crm_papel_permissoes(papel,modulo,nivel) values
  ('admin','acoes','total'),
  ('coordenacao','acoes','editar'),
  ('comercial','acoes','editar'),
  ('secretaria','acoes','ver'),
  ('pedagogico','acoes','ver')
on conflict (papel,modulo) do update set nivel=excluded.nivel, atualizado_em=now();

notify pgrst, 'reload schema';