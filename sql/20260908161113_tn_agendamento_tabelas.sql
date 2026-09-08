-- 002-teste-de-nivel-agendamento.sql
-- Projeto: cnataquara-comercial (gpnwmsnayrqjcmhqrtpx)
-- Aplicado em producao em 08/09/2026, nas migracoes:
--   tn_agendamento_tabelas · tn_agendamento_rls · tn_disponibilidade_fn · tn_agendar_fn
--
-- O que este arquivo cria:
--   1. crm_tn_grade        — grade semanal recorrente publicada pelo pedagogico
--   2. crm_tn_avulsos      — vagas extras e bloqueios pontuais (dia inteiro ou faixa)
--   3. crm_tn_agendamentos — o teste marcado, sempre amarrado a um lead do funil B2C
--   4. crm_leads.email     — coluna nova; nao existia e e' o que permite convidar no Google
--   5. crm_tn_disponibilidade() — expande grade + avulsos - bloqueios - ocupados
--   6. crm_tn_agendar()         — reserva o slot com guarda de concorrencia
--
-- Validado em BEGIN..ROLLBACK (08/09/2026): 13 slots em 14 dias, bloqueio de dia
-- inteiro zera o dia, slot ocupado barra o segundo agendamento, horario fora da
-- grade e' recusado, lead sai com proximo_canal = 'teste_nivel'.

-- ============================================================ 1. tabelas

create table if not exists crm_tn_grade(
  id uuid primary key default gen_random_uuid(),
  dia_semana smallint not null check (dia_semana between 0 and 6), -- 0=domingo, igual a extract(dow)
  hora_inicio time not null,
  hora_fim time not null,
  duracao_min smallint not null default 40 check (duracao_min between 10 and 240),
  modalidade text not null default 'presencial' check (modalidade in ('presencial','online')),
  aplicador text not null,
  vigencia_inicio date not null default current_date,
  vigencia_fim date,
  ativo boolean not null default true,
  criado_por text,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint crm_tn_grade_janela check (hora_fim > hora_inicio),
  constraint crm_tn_grade_vigencia check (vigencia_fim is null or vigencia_fim >= vigencia_inicio)
);

create table if not exists crm_tn_avulsos(
  id uuid primary key default gen_random_uuid(),
  tipo text not null check (tipo in ('vaga','bloqueio')),
  data date not null,
  hora_inicio time,                       -- nulo em bloqueio = dia inteiro
  hora_fim time,
  duracao_min smallint not null default 40 check (duracao_min between 10 and 240),
  modalidade text not null default 'presencial' check (modalidade in ('presencial','online')),
  aplicador text,                         -- nulo em bloqueio = vale para todos
  motivo text,
  ativo boolean not null default true,
  criado_por text,
  criado_em timestamptz not null default now(),
  constraint crm_tn_avulsos_vaga_completa check (tipo <> 'vaga' or (hora_inicio is not null and aplicador is not null)),
  constraint crm_tn_avulsos_janela check (hora_fim is null or hora_inicio is null or hora_fim > hora_inicio)
);

create table if not exists crm_tn_agendamentos(
  id uuid primary key default gen_random_uuid(),
  lead_id uuid not null references crm_leads(id) on delete cascade,
  data date not null,
  hora_inicio time not null,
  hora_fim time not null,
  duracao_min smallint not null default 40,
  modalidade text not null check (modalidade in ('presencial','online')),
  aplicador text not null,
  origem_tipo text not null default 'grade' check (origem_tipo in ('grade','avulso','manual')),
  origem_id uuid,
  nome_aluno text,
  email text,
  whatsapp text,
  status text not null default 'agendado' check (status in ('agendado','confirmado','realizado','faltou','cancelado')),
  observacoes text,
  agenda_evento_id uuid references crm_agenda_eventos(id) on delete set null,
  meet_url text,
  criado_por text,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

-- Um teste por horario por aplicador. Cancelado libera a vaga.
create unique index if not exists crm_tn_agend_slot_uk
  on crm_tn_agendamentos(data, hora_inicio, aplicador)
  where status <> 'cancelado';
create index if not exists crm_tn_agend_lead_ix on crm_tn_agendamentos(lead_id);
create index if not exists crm_tn_agend_data_ix on crm_tn_agendamentos(data);
create index if not exists crm_tn_avulsos_data_ix on crm_tn_avulsos(data) where ativo;
create index if not exists crm_tn_grade_dia_ix on crm_tn_grade(dia_semana) where ativo;

alter table crm_leads add column if not exists email text;

alter table crm_tn_grade enable row level security;
alter table crm_tn_avulsos enable row level security;
alter table crm_tn_agendamentos enable row level security;

