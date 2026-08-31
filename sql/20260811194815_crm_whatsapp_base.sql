-- 1. Chave canonica de numero brasileiro: DDD + 8 ultimos digitos.
-- Colapsa 5521982288009 / 21982288009 / 552182288009 / 2182288009 na mesma chave.
create or replace function crm_wa_chave(p_num text)
returns text
language plpgsql
immutable
as $fn$
declare d text;
begin
  d := regexp_replace(coalesce(p_num, ''), '\D', '', 'g');
  if length(d) >= 12 and left(d, 2) = '55' then
    d := substr(d, 3);
  end if;
  if length(d) < 10 then
    return null;
  end if;
  return left(d, 2) || right(d, 8);
end;
$fn$;

alter table crm_leads
  add column if not exists wa_chave text
  generated always as (crm_wa_chave(whatsapp)) stored;

create index if not exists idx_crm_leads_wa_chave on crm_leads (wa_chave) where wa_chave is not null;

-- 2. Contas (numeros) conectados
create table if not exists crm_wa_contas (
  id uuid primary key default gen_random_uuid(),
  rotulo text not null,
  numero_e164 text not null,
  phone_number_id text unique,
  waba_id text,
  ambiente text not null default 'teste' check (ambiente in ('teste','producao')),
  ativa boolean not null default true,
  created_at timestamptz not null default now()
);

-- 3. Conversas
create table if not exists crm_wa_conversas (
  id uuid primary key default gen_random_uuid(),
  conta_id uuid not null references crm_wa_contas(id) on delete cascade,
  wa_id text not null,
  numero_e164 text,
  wa_chave text,
  nome_perfil text,
  lead_id uuid references crm_leads(id) on delete set null,
  lead_ambiguo boolean not null default false,
  status text not null default 'aberta' check (status in ('aberta','pendente','resolvida')),
  atendente_id uuid references crm_usuarios(id) on delete set null,
  janela_expira_em timestamptz,
  ultima_mensagem_em timestamptz,
  ultima_previa text,
  nao_lidas integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (conta_id, wa_id)
);

create index if not exists idx_crm_wa_conversas_recentes on crm_wa_conversas (ultima_mensagem_em desc nulls last);
create index if not exists idx_crm_wa_conversas_lead on crm_wa_conversas (lead_id);
create index if not exists idx_crm_wa_conversas_chave on crm_wa_conversas (wa_chave);

-- 4. Mensagens
create table if not exists crm_wa_mensagens (
  id uuid primary key default gen_random_uuid(),
  conversa_id uuid not null references crm_wa_conversas(id) on delete cascade,
  direcao text not null check (direcao in ('entrada','saida')),
  tipo text not null default 'texto'
    check (tipo in ('texto','imagem','audio','video','documento','sticker','localizacao','contato','template','interativo','sistema')),
  texto text,
  midia_path text,
  midia_mime text,
  midia_nome text,
  wa_message_id text,
  responde_a text,
  template_nome text,
  status text not null default 'pendente'
    check (status in ('pendente','enviado','entregue','lido','falhou')),
  erro_codigo text,
  erro_msg text,
  autor_id uuid references crm_usuarios(id) on delete set null,
  wa_timestamp timestamptz not null default now(),
  created_at timestamptz not null default now()
);

-- Idempotencia: a Meta reenvia webhook em caso de timeout
create unique index if not exists idx_crm_wa_msg_waid on crm_wa_mensagens (wa_message_id) where wa_message_id is not null;
create index if not exists idx_crm_wa_msg_conversa on crm_wa_mensagens (conversa_id, wa_timestamp desc);

-- 5. Templates aprovados na Meta
create table if not exists crm_wa_templates (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  idioma text not null default 'pt_BR',
  categoria text not null check (categoria in ('MARKETING','UTILITY','AUTHENTICATION')),
  status text not null default 'PENDENTE',
  corpo text,
  variaveis jsonb not null default '[]'::jsonb,
  descricao text,
  created_at timestamptz not null default now(),
  unique (nome, idioma)
);

-- 6. Log cru de webhook, para auditoria e replay
create table if not exists crm_wa_eventos (
  id bigint generated always as identity primary key,
  recebido_em timestamptz not null default now(),
  tipo text,
  payload jsonb not null,
  processado boolean not null default false,
  erro text
);

create index if not exists idx_crm_wa_eventos_pendentes on crm_wa_eventos (recebido_em desc) where processado = false;