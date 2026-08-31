create extension if not exists pgcrypto;

/* ========== 1. AGENDA: responsavel unico + participantes + lembrete ========== */
alter table crm_agenda_eventos add column if not exists participantes text[] not null default '{}';
alter table crm_agenda_eventos add column if not exists lembrete_min int not null default 30;
alter table crm_agenda_eventos add column if not exists reuniao_id uuid;

/* migra a lista antiga de responsaveis: primeiro vira responsavel, todos viram participantes */
update crm_agenda_eventos
   set participantes = (select array_agg(trim(x)) from unnest(string_to_array(responsavel, ',')) x where trim(x) <> ''),
       responsavel   = trim(split_part(responsavel, ',', 1))
 where responsavel is not null and trim(responsavel) <> '' and participantes = '{}';

/* ========== 2. Categoria Reuniao interna ========== */
insert into crm_agenda_categorias (nome, cor, ordem, ativa)
select 'Reunião interna', '#19408B', coalesce((select max(ordem) from crm_agenda_categorias),0)+1, true
where not exists (select 1 from crm_agenda_categorias where lower(nome) = 'reunião interna');

/* ========== 3. ATAS DE REUNIAO ========== */
create table if not exists crm_reunioes (
  id              uuid primary key default gen_random_uuid(),
  titulo          text not null,
  tipo            text not null default 'equipe',
  data            date not null default crm_hoje_br(),
  hora_inicio     time,
  hora_fim        time,
  local           text,
  redator         text,
  ata_bruta       text not null default '',
  resumo          text,
  decisoes        jsonb not null default '[]'::jsonb,
  pendencias      jsonb not null default '[]'::jsonb,
  analise_payload jsonb,
  analise_em      timestamptz,
  analise_modelo  text,
  status          text not null default 'rascunho',
  hash_documento  text,
  congelada_em    timestamptz,
  pdf_url         text,
  drive_file_id   text,
  evento_id       uuid references crm_agenda_eventos(id) on delete set null,
  retifica_id     uuid references crm_reunioes(id) on delete set null,
  criado_por      text,
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now()
);

create table if not exists crm_reuniao_participantes (
  id           uuid primary key default gen_random_uuid(),
  reuniao_id   uuid not null references crm_reunioes(id) on delete cascade,
  nome         text not null,
  email        text,
  presente     boolean not null default true,
  papel        text default 'participante',
  deve_assinar boolean not null default true,
  unique (reuniao_id, nome)
);

create table if not exists crm_reuniao_assinaturas (
  id               uuid primary key default gen_random_uuid(),
  reuniao_id       uuid not null references crm_reunioes(id) on delete cascade,
  nome             text not null,
  email            text,
  assinado_em      timestamptz not null default now(),
  hash_documento   text not null,
  hash_assinatura  text not null,
  user_agent       text,
  metodo           text not null default 'senha_crm',
  provedor         text,
  provedor_doc_id  text,
  provedor_payload jsonb,
  unique (reuniao_id, nome)
);

/* ========== 4. DEMANDAS INTERNAS ========== */
create table if not exists crm_demandas (
  id             uuid primary key default gen_random_uuid(),
  titulo         text not null,
  descricao      text,
  responsavel    text,
  prazo          date,
  prioridade     text not null default 'media',
  status         text not null default 'pendente',
  origem         text not null default 'manual',
  reuniao_id     uuid references crm_reunioes(id) on delete set null,
  trecho_origem  text,
  prazo_inferido boolean not null default false,
  criado_por     text,
  criado_em      timestamptz not null default now(),
  concluida_em   timestamptz,
  concluida_por  text
);

create index if not exists ix_reunioes_data      on crm_reunioes(data desc);
create index if not exists ix_reuniao_part_r     on crm_reuniao_participantes(reuniao_id);
create index if not exists ix_demandas_resp      on crm_demandas(responsavel, status);
create index if not exists ix_demandas_reuniao   on crm_demandas(reuniao_id);
create index if not exists ix_agenda_ev_data     on crm_agenda_eventos(data);

/* ========== 5. RLS no padrao do CRM ========== */
alter table crm_reunioes               enable row level security;
alter table crm_reuniao_participantes  enable row level security;
alter table crm_reuniao_assinaturas    enable row level security;
alter table crm_demandas               enable row level security;

drop policy if exists anon_all on crm_reunioes;
drop policy if exists anon_all on crm_reuniao_participantes;
drop policy if exists anon_all on crm_demandas;
drop policy if exists anon_ins on crm_reuniao_assinaturas;
drop policy if exists anon_sel on crm_reuniao_assinaturas;

create policy anon_all on crm_reunioes              for all to anon using (true) with check (true);
create policy anon_all on crm_reuniao_participantes for all to anon using (true) with check (true);
create policy anon_all on crm_demandas              for all to anon using (true) with check (true);
create policy anon_ins on crm_reuniao_assinaturas   for insert to anon with check (true);
create policy anon_sel on crm_reuniao_assinaturas   for select to anon using (true);

notify pgrst, 'reload schema';