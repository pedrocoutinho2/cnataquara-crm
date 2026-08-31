-- opt-out por lead, exigido para qualquer disparo de marketing
alter table crm_leads add column if not exists wa_optout boolean not null default false;
alter table crm_leads add column if not exists wa_optin_em timestamptz;

-- ============ regras de disparo ============
create table if not exists crm_wa_regras (
  id uuid primary key default gen_random_uuid(),
  chave text unique not null,
  nome text not null,
  gatilho text not null,                       -- experimental_vespera | agendamento_lembrete | lead_parado
  categoria text not null default 'utility',   -- utility | marketing
  template_nome text,
  ativa boolean not null default false,        -- nasce desligada de proposito
  modo text not null default 'sugestao',       -- sugestao | automatico
  hora_inicio time not null default '09:00',
  hora_fim time not null default '20:00',
  dias_semana int[] not null default '{1,2,3,4,5,6}',  -- 0=domingo
  cooldown_dias int not null default 7,
  params jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint crm_wa_regras_modo_ck check (modo in ('sugestao','automatico')),
  constraint crm_wa_regras_cat_ck check (categoria in ('utility','marketing'))
);

-- ============ fila ============
create table if not exists crm_wa_fila (
  id uuid primary key default gen_random_uuid(),
  regra_id uuid references crm_wa_regras(id) on delete cascade,
  lead_id uuid references crm_leads(id) on delete cascade,
  conversa_id uuid references crm_wa_conversas(id) on delete set null,
  wa_chave text,
  referencia text not null,                    -- ancora de deduplicacao
  template_nome text,
  variaveis jsonb not null default '[]'::jsonb,
  texto_previa text,                           -- o que sera enviado, para o consultor conferir
  agendado_para timestamptz not null,
  status text not null default 'sugerido',     -- sugerido | aprovado | enviado | descartado | falhou
  motivo text,
  decidido_por text,
  decidido_em timestamptz,
  mensagem_id uuid references crm_wa_mensagens(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint crm_wa_fila_status_ck check (status in ('sugerido','aprovado','enviado','descartado','falhou'))
);

create unique index if not exists crm_wa_fila_dedup
  on crm_wa_fila(regra_id, lead_id, referencia);
create index if not exists crm_wa_fila_status_idx
  on crm_wa_fila(status, agendado_para);

alter table crm_wa_regras enable row level security;
alter table crm_wa_fila enable row level security;

drop policy if exists anon_all on crm_wa_regras;
create policy anon_all on crm_wa_regras for all to anon using (true) with check (true);
drop policy if exists anon_all on crm_wa_fila;
create policy anon_all on crm_wa_fila for all to anon using (true) with check (true);

notify pgrst, 'reload schema';