CREATE OR REPLACE FUNCTION public.metas_carregar(p_token uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u crm_usuarios; un text; g int; lm int; lr int; rm int; r jsonb;
begin
  u := crm_sessao_user(p_token);
  un := crm_sessao_unidade(p_token);
  g := crm_nivel_num(u.id,'metas',un); rm := crm_nivel_num(u.id,'rema',un);
  lm := greatest(g, crm_nivel_num(u.id,'metas_mat',un)); lr := greatest(g, rm);
  if lm = 0 and lr = 0 then raise exception 'sem_permissao' using errcode = 'P0001'; end if;
  select jsonb_build_object(
    'eu', jsonb_build_object('nome',u.nome,'metas',g,'mat',lm,'remav',lr,'rema',rm),
    'motivos', case when lr>0 then coalesce((select valor from crm_metas_config where chave='rema_motivos' and unidade=un),'[]'::jsonb) else '[]'::jsonb end,
    'semestres', coalesce((select jsonb_agg(
        case when g>0 then to_jsonb(s) || jsonb_build_object('pico',(coalesce(s.rema_auto,0)+coalesce(s.rema_contratual,0)+coalesce(s.matriculas,0)))
             else jsonb_build_object('inicio',s.inicio,'fim',s.fim,'obs',s.obs)
               || case when lm>0 then jsonb_build_object('matriculas',s.matriculas) else '{}'::jsonb end
               || case when lr>0 then jsonb_build_object('rema_auto',s.rema_auto,'rema_contratual',s.rema_contratual,'base_auto',s.base_auto,
                    'base_contratual',s.base_contratual,'mensal',s.mensal,'pico',(coalesce(s.rema_auto,0)+coalesce(s.rema_contratual,0)+coalesce(s.matriculas,0))) else '{}'::jsonb end
        end order by s.inicio) from crm_metas_semestre s where s.unidade=un),'[]'::jsonb),
    'periodos', coalesce((select jsonb_agg(
      jsonb_build_object('id',p.id,'inicio',p.inicio,'fim',p.fim,'status',p.status,
        'indicadores', coalesce((select jsonb_agg(jsonb_build_object(
            'id',i.id,'indicador',i.indicador,'base_media',i.base_media,'base_ref',i.base_ref,'obs',i.obs,'curva',i.curva,
            'faixas', coalesce((select jsonb_agg(jsonb_build_object('nivel',f.nivel,'alvo',f.alvo,'pct',f.pct,'regra',f.regra,'valor_rs',f.valor_rs) order by f.nivel)
                                 from crm_metas_faixa f where f.indicador_id=i.id),'[]'::jsonb))
          order by i.indicador) from crm_metas_indicador i where i.periodo_id=p.id
            and ((i.indicador='matricula' and lm>0) or (i.indicador<>'matricula' and lr>0))),'[]'::jsonb),
        'base_proj', case when lr>0 then (select jsonb_build_object(
            'contr', count(*) filter (where tipo='automatica' and status='realizada'),
            'auto', count(*) filter (where tipo='contratual' and status='realizada') + metas_mat_real(p.id))
          from crm_rema_aluno a where a.periodo_id=p.id and a.na_lista) end,
        'rema', case when lr>0 then (select jsonb_build_object(
            'total',count(*),'auto',count(*) filter (where tipo='automatica'),'contr',count(*) filter (where tipo='contratual'),
            'auto_real',count(*) filter (where tipo='automatica' and status='realizada'),
            'contr_real',count(*) filter (where tipo='contratual' and status='realizada'),
            'pend_auto',count(*) filter (where tipo='automatica' and status in ('pendente','negociacao')),
            'pend_contr',count(*) filter (where tipo='contratual' and status in ('pendente','negociacao')),
            'nao_renova',count(*) filter (where status='nao_renova'),'trancou',count(*) filter (where status='trancou'),
            'negociacao',count(*) filter (where status='negociacao'))
          from crm_rema_aluno a where a.periodo_id=p.id and a.na_lista) end,
        'rema_mes', case when lr>0 then (select jsonb_agg(jsonb_build_object('mes', m::date,
            'contr', (select count(*) from crm_rema_aluno a where a.periodo_id=p.id and a.na_lista and a.tipo='contratual' and a.status='realizada'
                       and date_trunc('month', coalesce(a.data_status, (a.alterado_em at time zone 'America/Sao_Paulo')::date)) = m),
            'auto',  (select count(*) from crm_rema_aluno a where a.periodo_id=p.id and a.na_lista and a.tipo='automatica' and a.status='realizada'
                       and date_trunc('month', coalesce(a.data_status, (a.alterado_em at time zone 'America/Sao_Paulo')::date)) = m))
          order by m) from generate_series(date_trunc('month',p.inicio), date_trunc('month',p.fim), interval '1 month') m) end,
        'ultimo_import', case when lr>0 then (select to_jsonb(ri) from crm_rema_import ri where ri.periodo_id=p.id order by ri.em desc limit 1) end
      )
      || case when lm>0 then jsonb_build_object(
        'meses', (select jsonb_agg(jsonb_build_object('mes', m::date,'ritmo_1', mm.ritmo_1, 'ritmo_ult', mm.ritmo_ult, 'ajuste', mm.ajuste,
            'crm', (select count(*) from crm_leads l where l.unidade=un and l.etapa='fechado' and l.data_fechamento >= m::date and l.data_fechamento < (m + interval '1 month')::date))
          order by m) from generate_series(date_trunc('month',p.inicio), date_trunc('month',p.fim), interval '1 month') m
          left join crm_metas_mes mm on mm.periodo_id=p.id and mm.mes=m::date),
        'por_consultor', coalesce((select jsonb_agg(jsonb_build_object('responsavel',x.responsavel,'n',x.n) order by x.n desc)
          from (select coalesce(l.responsavel,'Sem responsável') responsavel, count(*) n from crm_leads l
                 where l.unidade=un and l.etapa='fechado' and l.data_fechamento between p.inicio and p.fim group by 1) x),'[]'::jsonb)) else '{}'::jsonb end
      order by p.inicio) from crm_metas_periodo p where p.unidade=un),'[]'::jsonb)
  ) into r;
  return r;
end $function$;

CREATE OR REPLACE FUNCTION public.metas_salvar_periodo(p_token uuid, p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u crm_usuarios; un text; pid uuid; ind jsonb; iid uuid; fx jsonb; ms jsonb;
begin
  u := crm_exige(p_token, 'metas', 2);
  un := crm_sessao_unidade(p_token);
  insert into crm_metas_periodo(unidade, inicio, fim, status, atualizado_por, atualizado_em)
  values (un, (p->>'inicio')::date, (p->>'fim')::date, coalesce(p->>'status','rascunho'), u.nome, now())
  on conflict (unidade, inicio) do update set fim=excluded.fim, status=excluded.status, atualizado_por=u.nome, atualizado_em=now()
  returning id into pid;
  for ind in select * from jsonb_array_elements(coalesce(p->'indicadores','[]'::jsonb)) loop
    insert into crm_metas_indicador(periodo_id, indicador, base_media, base_ref, obs, curva)
    values (pid, ind->>'indicador', nullif(ind->>'base_media','')::numeric, nullif(ind->>'base_ref','')::numeric, ind->>'obs',
            case when jsonb_typeof(ind->'curva')='array' then ind->'curva' end)
    on conflict (periodo_id, indicador) do update set base_media=excluded.base_media, base_ref=excluded.base_ref, obs=excluded.obs,
      curva = case when ind ? 'curva' then excluded.curva else crm_metas_indicador.curva end
    returning id into iid;
    if ind ? 'faixas' then
      delete from crm_metas_faixa where indicador_id=iid;
      for fx in select * from jsonb_array_elements(ind->'faixas') loop
        if nullif(fx->>'alvo','') is not null then
          insert into crm_metas_faixa(indicador_id, nivel, alvo, pct, regra, valor_rs)
          values (iid, (fx->>'nivel')::int, (fx->>'alvo')::int, nullif(fx->>'pct','')::numeric, fx->>'regra', nullif(fx->>'valor_rs','')::numeric);
        end if;
      end loop;
    end if;
  end loop;
  for ms in select * from jsonb_array_elements(coalesce(p->'meses','[]'::jsonb)) loop
    insert into crm_metas_mes(periodo_id, mes, ritmo_1, ritmo_ult, ajuste)
    values (pid, (ms->>'mes')::date, nullif(ms->>'ritmo_1','')::int, nullif(ms->>'ritmo_ult','')::int, nullif(ms->>'ajuste','')::int)
    on conflict (periodo_id, mes) do update set ritmo_1=excluded.ritmo_1, ritmo_ult=excluded.ritmo_ult, ajuste=excluded.ajuste;
  end loop;
  return pid;
end $function$;

notify pgrst, 'reload schema';