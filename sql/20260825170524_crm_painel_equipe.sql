create or replace function public.crm_painel_equipe(p_data date)
returns jsonb language sql stable as $fn$
with u as (
  select nome from crm_usuarios where ativo is true and consultor is true
),
d as (
  select u.nome, crm_relatorio_dia(p_data, u.nome) as j from u
),
s as (
  select d.nome,
         (d.j->'kpis') as kpis,
         r.fechado_por,
         r.fechado_em
    from d
    left join crm_relatorio_diario r on r.consultor = d.nome and r.data = p_data
),
mes as (
  select date_trunc('month', p_data)::date as ini,
         (date_trunc('month', p_data) + interval '1 month - 1 day')::date as fim
),
lm as (
  select l.* from crm_leads l, mes m
   where l.data_entrada between m.ini and m.fim
),
fm as (
  select l.* from crm_leads l, mes m
   where l.etapa = 'fechado' and l.data_fechamento between m.ini and m.fim
),
pm as (
  select l.* from crm_leads l, mes m
   where l.etapa = 'perdido' and l.data_fechamento between m.ini and m.fim
)
select jsonb_build_object(
  'data', p_data,
  'consultores', coalesce((select jsonb_agg(jsonb_build_object(
        'nome', s.nome, 'kpis', s.kpis,
        'fechado_por', s.fechado_por, 'fechado_em', s.fechado_em) order by s.nome) from s), '[]'::jsonb),
  'unidade', jsonb_build_object(
    'leads_hoje',       (select count(*) from crm_leads where data_entrada = p_data),
    'matriculas_hoje',  (select count(*) from crm_leads_etapas
                          where etapa='fechado' and (data at time zone 'America/Sao_Paulo')::date = p_data),
    'leads_mes',        (select count(*) from lm),
    'matriculas_mes',   (select count(*) from fm),
    'perdidos_mes',     (select count(*) from pm),
    'ativos',           (select count(*) from crm_leads where etapa not in ('fechado','perdido')),
    'sem_responsavel',  (select count(*) from crm_leads
                          where etapa not in ('fechado','perdido') and coalesce(responsavel,'') = ''),
    'nunca_contatados', (select count(*) from crm_leads
                          where etapa not in ('fechado','perdido') and ultimo_contato is null),
    'esquecidos',       (select count(*) from crm_leads
                          where etapa not in ('fechado','perdido')
                            and (ultimo_contato is null or ultimo_contato < p_data - 7)),
    'negociacao_parados',(select count(*) from crm_leads
                          where etapa = 'negociacao'
                            and (ultimo_contato is null or ultimo_contato < p_data - 5)),
    'espera_turma',     (select count(*) from crm_leads where sem_turma is true and etapa <> 'fechado'),
    'dias_nao_fechados',(select count(*) from u
                          where not exists (select 1 from crm_relatorio_diario r
                                             where r.consultor = u.nome and r.data = p_data))
  )
) $fn$;

notify pgrst, 'reload schema';