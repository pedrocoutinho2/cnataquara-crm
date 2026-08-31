create table if not exists crm_turmas (
  id uuid primary key default gen_random_uuid(),
  semestre text not null default '2026.2',
  dias text not null,
  horario text not null,
  sala text not null,
  curso text not null,
  codigo text,
  professor text,
  alunos integer not null default 0,
  capacidade integer not null default 16,
  sem_vaga boolean not null default false,
  ativa boolean not null default true,
  obs text,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create index if not exists crm_turmas_semestre_idx on crm_turmas(semestre);
create index if not exists crm_turmas_dias_idx on crm_turmas(dias);

alter table crm_turmas enable row level security;

drop policy if exists "anon all" on crm_turmas;
create policy "anon all" on crm_turmas for all to anon using (true) with check (true);