create or replace function public.crm_painel()
returns json
language sql
stable
security invoker
set search_path = public
as $$
  select json_build_object(
    'gerado_em', now(),
    'metas', (select json_build_object('mat', max(meta_matriculas), 'leads', max(meta_leads))
              from crm_metas where competencia = to_char(current_date,'YYYY-MM') and escopo = 'unidade'),
    'etapas', (select json_agg(t) from (
        select etapa, count(*)::int n from crm_leads group by etapa order by 2 desc) t),
    'leads_7d', (select count(*)::int from crm_leads where data_entrada >= current_date - 6),
    'leads_mes', (select count(*)::int from crm_leads where data_entrada >= date_trunc('month', current_date)),
    'fechados_mes', (select count(*)::int from crm_leads
        where etapa = 'fechado' and coalesce(data_fechamento, data_entrada) >= date_trunc('month', current_date)),
    'atend_hoje', (select count(*)::int from crm_leads where proximo_atendimento = current_date),
    'atend_atraso', (select count(*)::int from crm_leads
        where proximo_atendimento < current_date and etapa not in ('perdido','fechado')),
    'consultores', (select json_agg(t) from (
        select coalesce(nullif(responsavel,''),'sem dono') r, count(*)::int n,
               count(*) filter (where etapa = 'fechado')::int f
        from crm_leads where data_entrada >= date_trunc('month', current_date)
        group by 1 order by 2 desc limit 6) t),
    'serie', (select json_agg(t) from (
        select to_char(date_trunc('month', data_entrada),'YYYY-MM') m, count(*)::int n,
               count(*) filter (where etapa = 'fechado')::int f
        from crm_leads where data_entrada >= date_trunc('month', current_date) - interval '5 month'
        group by 1 order by 1) t),
    'buckets', (select json_agg(t) from (
        select case when d <= 30 then '8 a 30 dias'
                    when d <= 90 then '31 a 90 dias'
                    else 'mais de 90 dias' end faixa,
               count(*)::int n, min(d)::int ord
        from (select (current_date - coalesce(ultimo_contato, data_entrada)) d
              from crm_leads
              where etapa not in ('perdido','fechado')
                and coalesce(ultimo_contato, data_entrada) < current_date - 7) x
        group by 1 order by 3) t),
    'recup', (select json_agg(t) from (
        select nome, etapa, coalesce(nullif(responsavel,''),'sem dono') resp,
               (current_date - coalesce(ultimo_contato, data_entrada))::int dias,
               coalesce(curso,'-') curso
        from crm_leads
        where etapa not in ('perdido','fechado')
          and coalesce(ultimo_contato, data_entrada) between current_date - 30 and current_date - 8
        order by 4 desc limit 15) t),
    'agenda', (select json_agg(t) from (
        select titulo, data, hora_inicio, coalesce(responsavel,'-') resp
        from crm_agenda_eventos
        where data between current_date and current_date + 7
        order by data, hora_inicio nulls last limit 10) t),
    'tarefas', (select json_agg(t) from (
        select tipo, data_prevista, coalesce(responsavel,'-') resp
        from crm_tarefas
        where status = 'pendente' and data_prevista <= current_date + 7
        order by data_prevista limit 10) t),
    'atend_dia', (select json_agg(t) from (
        select coalesce(nullif(responsavel,''),'sem dono') resp,
               count(*) filter (where proximo_atendimento = current_date)::int hoje,
               count(*) filter (where proximo_atendimento < current_date)::int atrasado
        from crm_leads
        where etapa not in ('perdido','fechado')
          and proximo_atendimento is not null and proximo_atendimento <= current_date
        group by 1 order by 3 desc) t),
    'ult_mov', (select max(data) from crm_leads_etapas)
  );
$$;

revoke all on function public.crm_painel() from public;
grant execute on function public.crm_painel() to anon, authenticated;
comment on function public.crm_painel() is 'Payload unico do painel Cockpit Taquara (funil, agenda, fila de parados). Security invoker: respeita RLS.';