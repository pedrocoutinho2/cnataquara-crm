create or replace function crm_relatorio_dia(p_data date, p_consultor text)
returns jsonb
language sql
stable
as $fn$
with ag as (
  select 'lead'::text as tipo, l.id::text as ref, l.nome, l.proximo_atendimento_hora as hora,
         l.whatsapp,
         exists(select 1 from crm_leads_interacoes i
                 where i.lead_id = l.id and i.data = p_data and i.autor = p_consultor) as feito
    from crm_leads l
   where l.responsavel = p_consultor and l.proximo_atendimento = p_data
  union all
  select 'escola', e.id::text, e.nome, e.proximo_contato_hora, e.whatsapp,
         exists(select 1 from crm_interacoes i
                 where i.escola_id = e.id
                   and (i.data at time zone 'America/Sao_Paulo')::date = p_data
                   and i.autor = p_consultor)
    from crm_escolas e
   where e.responsavel = p_consultor and e.proximo_contato = p_data
  union all
  select 'empresa', c.id::text, c.nome, c.proximo_contato_hora, c.whatsapp,
         exists(select 1 from crm_interacoes i
                 where i.empresa_id = c.id
                   and (i.data at time zone 'America/Sao_Paulo')::date = p_data
                   and i.autor = p_consultor)
    from crm_empresas c
   where c.responsavel = p_consultor and c.proximo_contato = p_data
  union all
  select 'tarefa', t.id::text, coalesce(l.nome, 'Tarefa') || ' · ' || t.tipo, t.hora_prevista,
         l.whatsapp,
         (t.status = 'concluida' or t.concluida_em is not null)
    from crm_tarefas t left join crm_leads l on l.id = t.lead_id
   where t.responsavel = p_consultor and t.data_prevista = p_data
),
am as (
  select 'lead'::text as tipo, l.nome, l.proximo_atendimento_hora as hora
    from crm_leads l
   where l.responsavel = p_consultor and l.proximo_atendimento = p_data + 1
  union all
  select 'escola', e.nome, e.proximo_contato_hora
    from crm_escolas e
   where e.responsavel = p_consultor and e.proximo_contato = p_data + 1
  union all
  select 'empresa', c.nome, c.proximo_contato_hora
    from crm_empresas c
   where c.responsavel = p_consultor and c.proximo_contato = p_data + 1
  union all
  select 'tarefa', coalesce(l.nome, 'Tarefa') || ' · ' || t.tipo, t.hora_prevista
    from crm_tarefas t left join crm_leads l on l.id = t.lead_id
   where t.responsavel = p_consultor and t.data_prevista = p_data + 1
),
re as (
  select 'lead'::text as tipo, l.nome,
         (i.created_at at time zone 'America/Sao_Paulo')::time as hora,
         i.efetivo, i.motivo_nao_efetivo as motivo, i.nota as resumo, i.tipo as canal
    from crm_leads_interacoes i join crm_leads l on l.id = i.lead_id
   where i.autor = p_consultor and i.data = p_data
  union all
  select case when i.escola_id is not null then 'escola' else 'empresa' end,
         coalesce(e.nome, c.nome),
         (i.data at time zone 'America/Sao_Paulo')::time,
         i.efetivo, i.motivo_nao_efetivo, i.resumo, i.tipo
    from crm_interacoes i
    left join crm_escolas  e on e.id = i.escola_id
    left join crm_empresas c on c.id = i.empresa_id
   where i.autor = p_consultor
     and (i.data at time zone 'America/Sao_Paulo')::date = p_data
  union all
  select 'tarefa', coalesce(l.nome, 'Tarefa'),
         (t.concluida_em at time zone 'America/Sao_Paulo')::time,
         true, null, t.observacao, t.canal
    from crm_tarefas t left join crm_leads l on l.id = t.lead_id
   where t.concluida_por = p_consultor
     and (t.concluida_em at time zone 'America/Sao_Paulo')::date = p_data
),
ev as (
  select etapa from crm_leads_etapas
   where autor = p_consultor
     and (data at time zone 'America/Sao_Paulo')::date = p_data
),
n as (
  select
    (select count(*) from ag)                             as agendados,
    (select count(*) from ag where feito)                 as cumpridos,
    (select count(*) from ag where not feito)             as pendentes,
    (select count(*) from re)                             as realizados,
    (select count(*) from re where efetivo)               as efetivos,
    (select count(*) from re where not efetivo)           as nao_efetivos,
    (select count(*) from am)                             as amanha,
    (select count(*) from ev)                             as movimentacoes,
    (select count(*) from ev where etapa = 'fechado')     as matriculas,
    (select count(*) from ev where etapa = 'perdido')     as perdidos,
    (select count(*) from crm_leads l
      where l.responsavel = p_consultor and l.data_entrada = p_data) as leads_novos
)
select jsonb_build_object(
  'data', p_data,
  'consultor', p_consultor,
  'kpis', jsonb_build_object(
     'agendados', n.agendados,
     'cumpridos', n.cumpridos,
     'pendentes', n.pendentes,
     'realizados', n.realizados,
     'efetivos', n.efetivos,
     'nao_efetivos', n.nao_efetivos,
     'amanha', n.amanha,
     'movimentacoes', n.movimentacoes,
     'matriculas', n.matriculas,
     'perdidos', n.perdidos,
     'leads_novos', n.leads_novos,
     'cumprimento', case when n.agendados > 0
                         then round(100.0 * n.cumpridos / n.agendados, 1)
                         else 0 end
  ),
  'agendados', coalesce((select jsonb_agg(x order by x->>'hora' nulls last)
                           from (select to_jsonb(a) as x from ag a) s), '[]'::jsonb),
  'realizados', coalesce((select jsonb_agg(x order by x->>'hora' nulls last)
                           from (select to_jsonb(r) as x from re r) s), '[]'::jsonb),
  'amanha', coalesce((select jsonb_agg(x order by x->>'hora' nulls last)
                           from (select to_jsonb(m) as x from am m) s), '[]'::jsonb)
) from n;
$fn$;

grant execute on function crm_relatorio_dia(date, text) to anon;