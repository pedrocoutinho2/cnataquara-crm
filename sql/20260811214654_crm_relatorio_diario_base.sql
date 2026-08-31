-- Data "de hoje" sempre em horário de Brasília (o banco roda em UTC,
-- então CURRENT_DATE viraria o dia às 21h BRT e quebraria o turno do Marlon)
create or replace function crm_hoje_br() returns date
language sql stable as $fn$
  select (now() at time zone 'America/Sao_Paulo')::date;
$fn$;

-- Jornada de cada pessoa da equipe
alter table crm_usuarios
  add column if not exists hora_inicio time not null default '09:00',
  add column if not exists hora_fim    time not null default '18:00',
  add column if not exists consultor   boolean not null default false;

-- Corrige os defaults que usavam CURRENT_DATE em UTC
alter table crm_leads_interacoes alter column data set default crm_hoje_br();
alter table crm_leads            alter column data_entrada set default crm_hoje_br();

-- Snapshot congelado do fechamento de expediente
create table if not exists crm_relatorio_diario (
  id            uuid primary key default gen_random_uuid(),
  data          date not null,
  consultor     text not null,
  agendados     int  not null default 0,
  realizados    int  not null default 0,
  efetivos      int  not null default 0,
  nao_efetivos  int  not null default 0,
  pendentes     int  not null default 0,
  leads_novos   int  not null default 0,
  movimentacoes int  not null default 0,
  matriculas    int  not null default 0,
  perdidos      int  not null default 0,
  amanha        int  not null default 0,
  cumprimento   numeric(5,2) not null default 0,
  detalhe       jsonb not null default '{}'::jsonb,
  fechado_em    timestamptz not null default now(),
  fechado_por   text,
  unique (data, consultor)
);

create index if not exists ix_crm_rel_diario_consultor_data
  on crm_relatorio_diario (consultor, data desc);

alter table crm_relatorio_diario enable row level security;

drop policy if exists anon_all on crm_relatorio_diario;
create policy anon_all on crm_relatorio_diario
  for all to anon using (true) with check (true);