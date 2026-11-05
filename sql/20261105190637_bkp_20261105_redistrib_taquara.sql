-- Base gpnwmsnayrqjcmhqrtpx, unidade taquara. Backup antes de redistribuir leads ativos de Eliane/Camila/Pedro entre Patrick e Roberta (decisão 05/11/2026).
create table public.crm_leads_bkp_20261105_redistrib as
select id, unidade, etapa, responsavel as responsavel_anterior, proximo_atendimento, proximo_atendimento_hora,
       case when row_number() over (order by proximo_atendimento nulls last, proximo_atendimento_hora nulls last, id) % 2 = 1
            then 'Patrick Miguez' else 'Roberta Marques' end as responsavel_novo,
       now() as salvo_em
from public.crm_leads
where unidade = 'taquara'
  and responsavel in ('Eliane','Camila','Pedro')
  and etapa not in ('fechado','perdido');
alter table public.crm_leads_bkp_20261105_redistrib enable row level security;
notify pgrst, 'reload schema';