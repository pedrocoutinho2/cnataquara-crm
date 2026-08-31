-- Campo de agendamento do proximo contato em escolas e empresas
-- (crm_leads ja possui proximo_atendimento)
alter table public.crm_escolas  add column if not exists proximo_contato date;
alter table public.crm_empresas add column if not exists proximo_contato date;

-- Contato nao efetivo registrado na propria linha do tempo de interacoes
alter table public.crm_leads_interacoes
  add column if not exists efetivo boolean not null default true,
  add column if not exists motivo_nao_efetivo text,
  add column if not exists proximo_contato date;

alter table public.crm_interacoes
  add column if not exists efetivo boolean not null default true,
  add column if not exists motivo_nao_efetivo text,
  add column if not exists proximo_contato date;

-- Indices para as consultas de alerta (por responsavel + data agendada)
create index if not exists idx_leads_prox    on public.crm_leads(proximo_atendimento) where proximo_atendimento is not null;
create index if not exists idx_escolas_prox  on public.crm_escolas(proximo_contato)    where proximo_contato is not null;
create index if not exists idx_empresas_prox on public.crm_empresas(proximo_contato)   where proximo_contato is not null;
create index if not exists idx_lint_efetivo  on public.crm_leads_interacoes(lead_id, efetivo);