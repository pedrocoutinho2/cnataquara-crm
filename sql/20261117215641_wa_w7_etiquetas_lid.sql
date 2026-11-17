-- W7 (17/11/2026): etiqueta do WhatsApp decide o dono. O CRM nunca escreve etiqueta no WhatsApp.
-- Mapa LID (identificador interno do WhatsApp usado nos eventos de etiqueta) -> conversa do CRM,
-- definição das etiquetas por conta (com o consultor dono, quando for etiqueta de consultor)
-- e estado atual de etiqueta por LID.
create table if not exists crm_wa_lids (
  conta_id uuid not null references crm_wa_contas(id) on delete cascade,
  lid text not null,
  conversa_id uuid references crm_wa_conversas(id) on delete set null,
  numero text,
  origem text,
  atualizado_em timestamptz not null default now(),
  unidade text not null,
  primary key (conta_id, lid)
);
create table if not exists crm_wa_etiquetas (
  conta_id uuid not null references crm_wa_contas(id) on delete cascade,
  label_id text not null,
  nome text,
  cor int,
  apagada boolean not null default false,
  usuario_id uuid references crm_usuarios(id),
  atualizado_em timestamptz not null default now(),
  unidade text not null,
  primary key (conta_id, label_id)
);
create table if not exists crm_wa_lid_etiquetas (
  conta_id uuid not null references crm_wa_contas(id) on delete cascade,
  lid text not null,
  label_id text not null,
  em timestamptz not null default now(),
  unidade text not null,
  primary key (conta_id, lid, label_id)
);
alter table crm_wa_lids enable row level security;
alter table crm_wa_etiquetas enable row level security;
alter table crm_wa_lid_etiquetas enable row level security;
-- sem policy para anon: acesso só por service role (Edge Functions) e RPC.
create index if not exists crm_wa_lids_conversa on crm_wa_lids(conversa_id);
notify pgrst, 'reload schema';