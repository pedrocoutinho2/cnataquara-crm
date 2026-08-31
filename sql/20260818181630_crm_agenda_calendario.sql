-- Calendário de ações comerciais e pedagógicas
create table if not exists crm_agenda_categorias (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  cor text not null default '#19408B',
  ordem int not null default 0,
  ativa boolean not null default true,
  criado_em timestamptz not null default now()
);

create table if not exists crm_agenda_eventos (
  id uuid primary key default gen_random_uuid(),
  titulo text not null,
  descricao text,
  categoria_id uuid references crm_agenda_categorias(id),
  data date not null,
  hora_inicio time,
  hora_fim time,
  responsavel text,
  criado_por text,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  gcal_id text,
  gcal_sync text not null default 'off'  -- off | pendente | ok | erro
);

create index if not exists idx_agenda_ev_data on crm_agenda_eventos(data);

-- Config da ponte com Google Agenda (Apps Script)
create table if not exists crm_agenda_config (
  id int primary key default 1,
  gas_url text,
  gas_token text,
  constraint uma_linha check (id = 1)
);
insert into crm_agenda_config (id) values (1) on conflict do nothing;

-- Seed de categorias
insert into crm_agenda_categorias (nome, cor, ordem)
select * from (values
  ('Comercial', '#E6143C', 1),
  ('Pedagógico', '#19408B', 2),
  ('Acadêmico', '#1E7A46', 3)
) as v(nome, cor, ordem)
where not exists (select 1 from crm_agenda_categorias);

-- RLS no padrão do CRM (permissivo para anon; segurança em nível de UI)
alter table crm_agenda_categorias enable row level security;
alter table crm_agenda_eventos enable row level security;
alter table crm_agenda_config enable row level security;

drop policy if exists anon_all on crm_agenda_categorias;
create policy anon_all on crm_agenda_categorias for all to anon using (true) with check (true);
drop policy if exists anon_all on crm_agenda_eventos;
create policy anon_all on crm_agenda_eventos for all to anon using (true) with check (true);
drop policy if exists anon_all on crm_agenda_config;
create policy anon_all on crm_agenda_config for all to anon using (true) with check (true);

notify pgrst, 'reload schema';