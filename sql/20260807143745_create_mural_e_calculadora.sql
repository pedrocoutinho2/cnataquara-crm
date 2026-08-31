-- ============ MURAL ============
create table if not exists crm_avisos (
  id               uuid primary key default gen_random_uuid(),
  tipo             text not null default 'promocao' check (tipo in ('promocao','aviso')),
  titulo           text not null,
  corpo            text not null default '',
  destaque         boolean not null default false,
  vigencia_inicio  date not null default current_date,
  vigencia_fim     date,
  ordem            int not null default 0,
  ativo            boolean not null default true,
  criado_por       text,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now()
);
create index if not exists idx_crm_avisos_vigencia on crm_avisos (ativo, vigencia_inicio, vigencia_fim);

create table if not exists crm_faq (
  id             uuid primary key default gen_random_uuid(),
  categoria      text not null default 'Geral',
  pergunta       text not null,
  resposta       text not null default '',
  tags           text[] not null default '{}',
  ordem          int not null default 0,
  ativo          boolean not null default true,
  criado_por     text,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now()
);
create index if not exists idx_crm_faq_cat on crm_faq (categoria, ordem);

-- ============ CALCULADORA ============
create table if not exists crm_precos_materiais (
  id           uuid primary key default gen_random_uuid(),
  ano          int not null,
  codigo       text not null,
  nome         text not null,
  valor_cents  int not null check (valor_cents >= 0),
  ordem        int not null default 0,
  ativo        boolean not null default true,
  unique (ano, codigo)
);

create table if not exists crm_precos_niveis (
  id                   uuid primary key default gen_random_uuid(),
  ano                  int not null,
  idioma               text not null check (idioma in ('ingles','espanhol')),
  codigo               text not null,
  nome                 text not null,
  valor_periodo_cents  int not null check (valor_periodo_cents >= 0),
  material_codigo      text,
  ordem                int not null default 0,
  ativo                boolean not null default true,
  unique (ano, codigo)
);

create table if not exists crm_precos_certificacoes (
  id           uuid primary key default gen_random_uuid(),
  ano          int not null,
  exame        text not null,
  modalidade   text not null,
  valor_cents  int not null check (valor_cents >= 0),
  descricao    text,
  ordem        int not null default 0,
  ativo        boolean not null default true
);

-- ============ RLS (mesmo padrao das tabelas existentes) ============
alter table crm_avisos enable row level security;
alter table crm_faq enable row level security;
alter table crm_precos_materiais enable row level security;
alter table crm_precos_niveis enable row level security;
alter table crm_precos_certificacoes enable row level security;

drop policy if exists "anon all crm_avisos" on crm_avisos;
create policy "anon all crm_avisos" on crm_avisos for all to anon using (true) with check (true);

drop policy if exists "anon all crm_faq" on crm_faq;
create policy "anon all crm_faq" on crm_faq for all to anon using (true) with check (true);

drop policy if exists "anon all crm_precos_materiais" on crm_precos_materiais;
create policy "anon all crm_precos_materiais" on crm_precos_materiais for all to anon using (true) with check (true);

drop policy if exists "anon all crm_precos_niveis" on crm_precos_niveis;
create policy "anon all crm_precos_niveis" on crm_precos_niveis for all to anon using (true) with check (true);

drop policy if exists "anon all crm_precos_certificacoes" on crm_precos_certificacoes;
create policy "anon all crm_precos_certificacoes" on crm_precos_certificacoes for all to anon using (true) with check (true);