-- Consolidação · Fase 2b-5a: painel, relatórios e fechamento do dia por unidade.
-- crm_painel.recup ganha desempate (nome, id): a lista cortava 15 de um empate e variava a cada chamada.
-- Todas ganham p_unidade (default 'taquara', provisório até a fase de contract), então
-- as chamadas do front atual seguem iguais. Assinaturas antigas removidas no mesmo passo
-- para não haver função ambígua. Consultores da unidade vêm de crm_usuario_unidades.

drop function if exists public.crm_painel_equipe(date);
drop function if exists public.crm_fechar_pendentes();
drop function if exists public.crm_fechar_dia(date, text, text);
drop function if exists public.crm_relatorio_dia(date, text);
drop function if exists public.crm_painel();

create function public.crm_relatorio_dia(p_data date, p_consultor text, p_unidade text default 'taquara')
 returns jsonb
 language sql
 stable
as $function$
with ag as (
  select 'lead'::text as tipo, l.id::text as ref, l.nome, l.proximo_atendimento_hora as hora,
         l.whatsapp,
         exists(select 1 from crm_leads_interacoes i
                 where i.lead_id = l.id and i.data = p_data and i.autor = p_consultor) as feito
    from crm_leads l
   where l.unidade = p_unidade and l.responsavel = p_consultor and l.proximo_atendimento = p_data
  union all
  select 'escola', e.id::text, e.nome, e.proximo_contato_hora, e.whatsapp,
         exists(select 1 from crm_interacoes i
                 where i.escola_id = e.id
                   and (i.data at time zone 'America/Sao_Paulo')::date = p_data
                   and i.autor = p_consultor)
    from crm_escolas e
   where e.unidade = p_unidade and e.responsavel = p_consultor and e.proximo_contato = p_data
  union all
  select 'empresa', c.id::text, c.nome, c.proximo_contato_hora, c.whatsapp,
         exists(select 1 from crm_interacoes i
                 where i.empresa_id = c.id
                   and (i.data at time zone 'America/Sao_Paulo')::date = p_data
                   and i.autor = p_consultor)
    from crm_empresas c
   where c.unidade = p_unidade and c.responsavel = p_consultor and c.proximo_contato = p_data
  union all
  select 'tarefa', t.id::text, coalesce(l.nome, 'Tarefa') || ' · ' || t.tipo, t.hora_prevista,
         l.whatsapp,
         (t.status = 'concluida' or t.concluida_em is not null)
    from crm_tarefas t left join crm_leads l on l.id = t.lead_id
   where t.unidade = p_unidade and t.responsavel = p_consultor and t.data_prevista = p_data
),
am as (
  select 'lead'::text as tipo, l.nome, l.proximo_atendimento_hora as hora
    from crm_leads l
   where l.unidade = p_unidade and l.responsavel = p_consultor and l.proximo_atendimento = p_data + 1
  union all
  select 'escola', e.nome, e.proximo_contato_hora
    from crm_escolas e
   where e.unidade = p_unidade and e.responsavel = p_consultor and e.proximo_contato = p_data + 1
  union all
  select 'empresa', c.nome, c.proximo_contato_hora
    from crm_empresas c
   where c.unidade = p_unidade and c.responsavel = p_consultor and c.proximo_contato = p_data + 1
  union all
  select 'tarefa', coalesce(l.nome, 'Tarefa') || ' · ' || t.tipo, t.hora_prevista
    from crm_tarefas t left join crm_leads l on l.id = t.lead_id
   where t.unidade = p_unidade and t.responsavel = p_consultor and t.data_prevista = p_data + 1
),
re as (
  select 'lead'::text as tipo, l.nome,
         (i.created_at at time zone 'America/Sao_Paulo')::time as hora,
         i.efetivo, i.motivo_nao_efetivo as motivo, i.nota as resumo, i.tipo as canal
    from crm_leads_interacoes i join crm_leads l on l.id = i.lead_id
   where i.unidade = p_unidade and i.autor = p_consultor and i.data = p_data
  union all
  select case when i.escola_id is not null then 'escola' else 'empresa' end,
         coalesce(e.nome, c.nome),
         (i.data at time zone 'America/Sao_Paulo')::time,
         i.efetivo, i.motivo_nao_efetivo, i.resumo, i.tipo
    from crm_interacoes i
    left join crm_escolas  e on e.id = i.escola_id
    left join crm_empresas c on c.id = i.empresa_id
   where i.unidade = p_unidade and i.autor = p_consultor
     and (i.data at time zone 'America/Sao_Paulo')::date = p_data
  union all
  select 'tarefa', coalesce(l.nome, 'Tarefa'),
         (t.concluida_em at time zone 'America/Sao_Paulo')::time,
         true, null, t.observacao, t.canal
    from crm_tarefas t left join crm_leads l on l.id = t.lead_id
   where t.unidade = p_unidade and t.concluida_por = p_consultor
     and (t.concluida_em at time zone 'America/Sao_Paulo')::date = p_data
),
ev as (
  select etapa from crm_leads_etapas
   where unidade = p_unidade and autor = p_consultor
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
      where l.unidade = p_unidade and l.responsavel = p_consultor and l.data_entrada = p_data) as leads_novos
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
$function$;

create function public.crm_fechar_dia(p_data date, p_consultor text, p_por text default null, p_unidade text default 'taquara')
 returns jsonb
 language plpgsql
as $function$
declare j jsonb; k jsonb;
begin
  j := crm_relatorio_dia(p_data, p_consultor, p_unidade);
  k := j->'kpis';

  insert into crm_relatorio_diario
    (unidade, data, consultor, agendados, realizados, efetivos, nao_efetivos, pendentes,
     leads_novos, movimentacoes, matriculas, perdidos, amanha, cumprimento,
     detalhe, fechado_em, fechado_por)
  values
    (p_unidade, p_data, p_consultor,
     (k->>'agendados')::int, (k->>'realizados')::int, (k->>'efetivos')::int,
     (k->>'nao_efetivos')::int, (k->>'pendentes')::int, (k->>'leads_novos')::int,
     (k->>'movimentacoes')::int, (k->>'matriculas')::int, (k->>'perdidos')::int,
     (k->>'amanha')::int, (k->>'cumprimento')::numeric,
     j, now(), coalesce(p_por, p_consultor))
  on conflict (unidade, data, consultor) do update set
     agendados = excluded.agendados,
     realizados = excluded.realizados,
     efetivos = excluded.efetivos,
     nao_efetivos = excluded.nao_efetivos,
     pendentes = excluded.pendentes,
     leads_novos = excluded.leads_novos,
     movimentacoes = excluded.movimentacoes,
     matriculas = excluded.matriculas,
     perdidos = excluded.perdidos,
     amanha = excluded.amanha,
     cumprimento = excluded.cumprimento,
     detalhe = excluded.detalhe,
     fechado_em = now(),
     fechado_por = excluded.fechado_por;

  return j;
end;
$function$;

create function public.crm_fechar_pendentes()
 returns integer
 language plpgsql
as $function$
declare d date; alvo date; n int := 0; u record;
begin
  d := (now() at time zone 'America/Sao_Paulo')::date;
  foreach alvo in array array[d, d - 1] loop
    for u in select us.nome, v.unidade
               from crm_usuario_unidades v
               join crm_usuarios us on us.id = v.usuario_id and us.ativo
               join crm_unidades un on un.slug = v.unidade and un.status <> 'inativa'
              where v.ativo and v.consultor loop
      if not exists (select 1 from crm_relatorio_diario r
                      where r.unidade = u.unidade and r.data = alvo and r.consultor = u.nome) then
        perform crm_fechar_dia(alvo, u.nome, 'automático', u.unidade);
        n := n + 1;
      end if;
    end loop;
  end loop;
  return n;
end;
$function$;

create function public.crm_painel_equipe(p_data date, p_unidade text default 'taquara')
 returns jsonb
 language sql
 stable
as $function$
with u as (
  select us.nome from crm_usuarios us
    join crm_usuario_unidades v on v.usuario_id = us.id and v.unidade = p_unidade and v.ativo and v.consultor
   where us.ativo is true
),
d as (
  select u.nome, crm_relatorio_dia(p_data, u.nome, p_unidade) as j from u
),
s as (
  select d.nome,
         (d.j->'kpis') as kpis,
         r.fechado_por,
         r.fechado_em
    from d
    left join crm_relatorio_diario r on r.unidade = p_unidade and r.consultor = d.nome and r.data = p_data
),
mes as (
  select date_trunc('month', p_data)::date as ini,
         (date_trunc('month', p_data) + interval '1 month - 1 day')::date as fim
),
lm as (
  select l.* from crm_leads l, mes m
   where l.unidade = p_unidade and l.data_entrada between m.ini and m.fim
),
fm as (
  select l.* from crm_leads l, mes m
   where l.unidade = p_unidade and l.etapa = 'fechado' and l.data_fechamento between m.ini and m.fim
),
pm as (
  select l.* from crm_leads l, mes m
   where l.unidade = p_unidade and l.etapa = 'perdido' and l.data_fechamento between m.ini and m.fim
)
select jsonb_build_object(
  'data', p_data,
  'consultores', coalesce((select jsonb_agg(jsonb_build_object(
        'nome', s.nome, 'kpis', s.kpis,
        'fechado_por', s.fechado_por, 'fechado_em', s.fechado_em) order by s.nome) from s), '[]'::jsonb),
  'unidade', jsonb_build_object(
    'leads_hoje',       (select count(*) from crm_leads where unidade = p_unidade and data_entrada = p_data),
    'matriculas_hoje',  (select count(*) from crm_leads_etapas
                          where unidade = p_unidade and etapa='fechado' and (data at time zone 'America/Sao_Paulo')::date = p_data),
    'leads_mes',        (select count(*) from lm),
    'matriculas_mes',   (select count(*) from fm),
    'perdidos_mes',     (select count(*) from pm),
    'ativos',           (select count(*) from crm_leads where unidade = p_unidade and etapa not in ('fechado','perdido')),
    'sem_responsavel',  (select count(*) from crm_leads
                          where unidade = p_unidade and etapa not in ('fechado','perdido') and coalesce(responsavel,'') = ''),
    'nunca_contatados', (select count(*) from crm_leads
                          where unidade = p_unidade and etapa not in ('fechado','perdido') and ultimo_contato is null),
    'esquecidos',       (select count(*) from crm_leads
                          where unidade = p_unidade and etapa not in ('fechado','perdido')
                            and (ultimo_contato is null or ultimo_contato < p_data - 7)),
    'negociacao_parados',(select count(*) from crm_leads
                          where unidade = p_unidade and etapa = 'negociacao'
                            and (ultimo_contato is null or ultimo_contato < p_data - 5)),
    'espera_turma',     (select count(*) from crm_leads where unidade = p_unidade and sem_turma is true and etapa <> 'fechado'),
    'dias_nao_fechados',(select count(*) from u
                          where not exists (select 1 from crm_relatorio_diario r
                                             where r.unidade = p_unidade and r.consultor = u.nome and r.data = p_data))
  )
) $function$;

create function public.crm_painel(p_unidade text default 'taquara')
 returns json
 language sql
 stable
 set search_path to 'public'
as $function$
  select json_build_object(
    'gerado_em', now(),
    'metas', (select json_build_object('mat', max(meta_matriculas), 'leads', max(meta_leads))
              from crm_metas where unidade = p_unidade and competencia = to_char(current_date,'YYYY-MM') and escopo = 'unidade'),
    'etapas', (select json_agg(t) from (
        select etapa, count(*)::int n from crm_leads where unidade = p_unidade group by etapa order by 2 desc) t),
    'leads_7d', (select count(*)::int from crm_leads where unidade = p_unidade and data_entrada >= current_date - 6),
    'leads_mes', (select count(*)::int from crm_leads where unidade = p_unidade and data_entrada >= date_trunc('month', current_date)),
    'fechados_mes', (select count(*)::int from crm_leads
        where unidade = p_unidade and etapa = 'fechado' and coalesce(data_fechamento, data_entrada) >= date_trunc('month', current_date)),
    'atend_hoje', (select count(*)::int from crm_leads where unidade = p_unidade and proximo_atendimento = current_date),
    'atend_atraso', (select count(*)::int from crm_leads
        where unidade = p_unidade and proximo_atendimento < current_date and etapa not in ('perdido','fechado')),
    'consultores', (select json_agg(t) from (
        select coalesce(nullif(responsavel,''),'sem dono') r, count(*)::int n,
               count(*) filter (where etapa = 'fechado')::int f
        from crm_leads where unidade = p_unidade and data_entrada >= date_trunc('month', current_date)
        group by 1 order by 2 desc limit 6) t),
    'serie', (select json_agg(t) from (
        select to_char(date_trunc('month', data_entrada),'YYYY-MM') m, count(*)::int n,
               count(*) filter (where etapa = 'fechado')::int f
        from crm_leads where unidade = p_unidade and data_entrada >= date_trunc('month', current_date) - interval '5 month'
        group by 1 order by 1) t),
    'buckets', (select json_agg(t) from (
        select case when d <= 30 then '8 a 30 dias'
                    when d <= 90 then '31 a 90 dias'
                    else 'mais de 90 dias' end faixa,
               count(*)::int n, min(d)::int ord
        from (select (current_date - coalesce(ultimo_contato, data_entrada)) d
              from crm_leads
              where unidade = p_unidade and etapa not in ('perdido','fechado')
                and coalesce(ultimo_contato, data_entrada) < current_date - 7) x
        group by 1 order by 3) t),
    'recup', (select json_agg(t) from (
        select nome, etapa, coalesce(nullif(responsavel,''),'sem dono') resp,
               (current_date - coalesce(ultimo_contato, data_entrada))::int dias,
               coalesce(curso,'-') curso
        from crm_leads
        where unidade = p_unidade and etapa not in ('perdido','fechado')
          and coalesce(ultimo_contato, data_entrada) between current_date - 30 and current_date - 8
        order by 4 desc, nome, id limit 15) t),
    'agenda', (select json_agg(t) from (
        select titulo, data, hora_inicio, coalesce(responsavel,'-') resp
        from crm_agenda_eventos
        where unidade = p_unidade and data between current_date and current_date + 7
        order by data, hora_inicio nulls last limit 10) t),
    'tarefas', (select json_agg(t) from (
        select tipo, data_prevista, coalesce(responsavel,'-') resp
        from crm_tarefas
        where unidade = p_unidade and status = 'pendente' and data_prevista <= current_date + 7
        order by data_prevista limit 10) t),
    'atend_dia', (select json_agg(t) from (
        select coalesce(nullif(responsavel,''),'sem dono') resp,
               count(*) filter (where proximo_atendimento = current_date)::int hoje,
               count(*) filter (where proximo_atendimento < current_date)::int atrasado
        from crm_leads
        where unidade = p_unidade and etapa not in ('perdido','fechado')
          and proximo_atendimento is not null and proximo_atendimento <= current_date
        group by 1 order by 3 desc) t),
    'ult_mov', (select max(data) from crm_leads_etapas where unidade = p_unidade)
  );
$function$;

grant execute on function public.crm_relatorio_dia(date, text, text) to anon, authenticated;
grant execute on function public.crm_fechar_dia(date, text, text, text) to anon, authenticated;
grant execute on function public.crm_fechar_pendentes() to anon, authenticated;
grant execute on function public.crm_painel_equipe(date, text) to anon, authenticated;
grant execute on function public.crm_painel(text) to anon, authenticated;

notify pgrst, 'reload schema';