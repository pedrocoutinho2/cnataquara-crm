alter table crm_leads
  add column if not exists data_inicio_aulas date,
  add column if not exists nivel text,
  add column if not exists turma text;

create table if not exists crm_tarefas (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid not null references crm_leads(id) on delete cascade,
  tipo text not null,
  data_prevista date not null,
  responsavel text,
  status text not null default 'pendente',
  canal text,
  resultado text,
  observacao text,
  concluida_em timestamptz,
  concluida_por text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint crm_tarefas_lead_tipo_uk unique (lead_id, tipo)
);

create index if not exists crm_tarefas_fila_idx on crm_tarefas (status, data_prevista);
create index if not exists crm_tarefas_lead_idx on crm_tarefas (lead_id);

alter table crm_tarefas enable row level security;

drop policy if exists "anon all" on crm_tarefas;
create policy "anon all" on crm_tarefas for all to anon using (true) with check (true);