-- Integração CRM → CNA Box, fase 1: campos e fila (rede, base gpnwmsnayrqjcmhqrtpx)
-- Decisões: 2026-11-05-integracao-crm-box-login-por-consultor, 2026-11-05-integracao-crm-box-campos-e-mapeamentos
-- Aditiva: só colunas anuláveis, tabela nova e função. Nenhum dado existente muda.

-- 1. Lead: dados que o Box exige
alter table public.crm_leads
  add column if not exists data_nascimento date,
  add column if not exists sexo text,
  add column if not exists sexo_sugerido boolean not null default false,
  add column if not exists disponibilidade smallint[],
  add column if not exists box_id bigint,
  add column if not exists box_vinculado_em timestamptz;

alter table public.crm_leads
  add constraint crm_leads_sexo_chk check (sexo is null or sexo in ('F','M')),
  add constraint crm_leads_disponibilidade_chk check (disponibilidade is null or disponibilidade <@ array[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18]::smallint[]);

create unique index if not exists crm_leads_box_id_uk
  on public.crm_leads (unidade, box_id) where box_id is not null;

comment on column public.crm_leads.data_nascimento is 'Data de nascimento do aluno. Obrigatória no CNA Box.';
comment on column public.crm_leads.sexo is 'F ou M. Pode vir sugerido pelo primeiro nome (sexo_sugerido=true) até o consultor confirmar.';
comment on column public.crm_leads.disponibilidade is 'Ids de período do CNA Box: 1-6 manhã seg-sáb, 7-12 tarde seg-sáb, 13-18 noite seg-sáb.';
comment on column public.crm_leads.box_id is 'AlunoId/PessoaEscolaId do prospect no CNA Box. Preenchido ao cadastrar ou ao achar o cadastro existente.';

-- 2. Interação: motivo do repique (opções do Box) e marcador secundário de receptivo
alter table public.crm_leads_interacoes
  add column if not exists motivo_repique text,
  add column if not exists lead_procurou boolean not null default false,
  add column if not exists box_enviado_em timestamptz;

alter table public.crm_leads_interacoes
  add constraint crm_leads_interacoes_motivo_repique_chk check (
    motivo_repique is null or motivo_repique in ('vai_pesquisar','sem_tempo','desempregado','nao_quer_agora'));

comment on column public.crm_leads_interacoes.motivo_repique is 'Motivo de não agendar visita, mesmas opções do Box: vai_pesquisar(1), sem_tempo(3), desempregado(4), nao_quer_agora(7).';
comment on column public.crm_leads_interacoes.lead_procurou is 'Marcador secundário: o lead retomou o contato por conta própria. Força receptivo no Box.';

-- 3. Regra de ativo/receptivo
create or replace function public.crm_box_receptivo(p_interacao_id uuid)
returns boolean
language sql
stable
set search_path = public
as $$
  with i as (
    select i.id, i.lead_id, i.lead_procurou, l.origem,
           row_number() over (partition by i.lead_id order by i.data, i.created_at, i.id) rn
    from crm_leads_interacoes i
    join crm_leads l on l.id = i.lead_id
    where i.lead_id = (select lead_id from crm_leads_interacoes where id = p_interacao_id)
      and i.tipo <> 'nota'
  )
  select coalesce(
    (select lead_procurou
            or (rn = 1 and origem in ('Google','Instagram','Facebook','Matriz','Presencial','Flyer'))
     from i where id = p_interacao_id),
    false);
$$;

comment on function public.crm_box_receptivo(uuid) is 'Receptivo no Box: primeiro contato (fora notas) de lead de origem de campanha/inbound, ou lead_procurou=true. Demais: ativo. Origem Outro [CONFIRMAR].';

-- 4. Fila de envio para o Box (modo sugestão: candidato -> aprovado -> enviado)
create table if not exists public.crm_box_fila (
  id uuid primary key default gen_random_uuid(),
  unidade text not null,
  lead_id uuid not null references public.crm_leads(id) on delete cascade,
  interacao_id uuid references public.crm_leads_interacoes(id) on delete set null,
  operacao text not null check (operacao in ('vincular','cadastro','atendimento')),
  status text not null default 'pendente'
    check (status in ('pendente','aguardando_dados','aprovado','enviado','erro','ignorado')),
  pendencias text[],
  consultor text,
  payload jsonb,
  resposta jsonb,
  erro text,
  tentativas integer not null default 0,
  criado_em timestamptz not null default now(),
  aprovado_por text,
  aprovado_em timestamptz,
  enviado_em timestamptz
);

create unique index if not exists crm_box_fila_interacao_uk
  on public.crm_box_fila (interacao_id) where interacao_id is not null;
create index if not exists crm_box_fila_status_idx
  on public.crm_box_fila (unidade, status, criado_em);

create trigger a00_herda_unidade before insert or update on public.crm_box_fila
  for each row execute function public.crm_herda_unidade('crm_leads', 'lead_id');

-- Sem policy para anon: acesso só por RPC com token de sessão (dívida nº 1).
alter table public.crm_box_fila enable row level security;

comment on table public.crm_box_fila is 'Fila CRM -> CNA Box. Cada item é candidato até aprovação; a Edge Function envia com o login do consultor dono do lead.';

notify pgrst, 'reload schema';