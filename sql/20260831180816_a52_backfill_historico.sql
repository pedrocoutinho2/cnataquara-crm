-- A52 · backfill — aplicado por execute_sql em 31/08/2026, logo depois da migração
-- 20260831180815. Não está em schema_migrations porque é DML, mas roda uma vez e
-- é idempotente. Estado anterior guardado em crm_leads_bkp_20260831_a52.
--
-- Medido antes de rodar, sobre 553 leads e 342 interações:
--   135 leads com pelo menos um contato efetivo
--    45 leads com ultimo_contato carimbado APENAS por tentativa sem sucesso
--    52 leads com tentativa pendente, 93 tentativas no total, pior caso 6

-- create table crm_leads_bkp_20260831_a52 as
--   select id, ultimo_contato, ultima_tentativa, tentativas_sem_retorno, now() as salvo_em
--   from crm_leads;

begin;

-- 1. ultimo_contato passa a ser a data da última interação EFETIVA
with ult_ef as (
  select lead_id, max(data) d from crm_leads_interacoes where efetivo group by lead_id
)
update crm_leads l set ultimo_contato = e.d
  from ult_ef e where e.lead_id = l.id and l.ultimo_contato is distinct from e.d;

-- 2. quem só tem tentativa e carrega a data dela em ultimo_contato foi carimbado
--    pelo bug: volta a ser "nunca contatado", que é a verdade
with ult_ef as (select lead_id from crm_leads_interacoes where efetivo group by lead_id),
     ult_ne as (select lead_id, max(data) d from crm_leads_interacoes where not efetivo group by lead_id)
update crm_leads l set ultimo_contato = null
  from ult_ne n where n.lead_id = l.id
   and not exists (select 1 from ult_ef e where e.lead_id = l.id)
   and l.ultimo_contato = n.d;

-- 3. ultima_tentativa
with ult_ne as (
  select lead_id, max(data) d from crm_leads_interacoes where not efetivo group by lead_id
)
update crm_leads l set ultima_tentativa = n.d from ult_ne n where n.lead_id = l.id;

-- 4. tentativas acumuladas DEPOIS do último contato efetivo
with ult_ef as (
  select lead_id, max(data) d from crm_leads_interacoes where efetivo group by lead_id
), depois as (
  select i.lead_id, count(*) n
    from crm_leads_interacoes i
    left join ult_ef e on e.lead_id = i.lead_id
   where not i.efetivo and (e.d is null or i.data > e.d)
   group by i.lead_id
)
update crm_leads l set tentativas_sem_retorno = d.n from depois d where d.lead_id = l.id;

commit;
