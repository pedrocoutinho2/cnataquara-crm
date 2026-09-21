-- Visibilidade por área (21/09/2026): comercial vê só matrícula, secretaria e pedagógico só rema,
-- "metas" vira gestão (histórico e configuração). Resumo da tela inicial liberado para todos.
insert into crm_modulos(modulo,nome,grupo,ordem) values ('metas_mat','Metas · matrícula','Gestão',137)
on conflict do nothing;
update crm_modulos set nome='Metas · gestão (histórico e configuração)', ordem=136 where modulo='metas';
update crm_modulos set nome='Metas · rematrícula' where modulo='rema';
insert into crm_papel_permissoes(papel,modulo,nivel) values
  ('admin','metas_mat','total'),('comercial','metas_mat','ver'),('secretaria','metas_mat','nenhum'),
  ('pedagogico','metas_mat','nenhum'),('coordenacao','metas_mat','ver')
on conflict do nothing;
update crm_papel_permissoes set nivel='nenhum' where modulo='metas' and papel in ('comercial','secretaria','pedagogico');

create or replace function public.crm_sessao_user(p_token uuid)
 returns public.crm_usuarios language plpgsql security definer set search_path to 'public'
as $function$
declare u crm_usuarios; uid uuid;
begin
  select usuario_id into uid from crm_sessoes where token = p_token and expira_em > now();
  if uid is null then raise exception 'sessao_invalida' using errcode = 'P0001'; end if;
  select * into u from crm_usuarios where id = uid and ativo = true;
  if not found then raise exception 'sessao_invalida' using errcode = 'P0001'; end if;
  return u;
end $function$;
revoke all on function public.crm_sessao_user(uuid) from public, anon, authenticated;

-- matrícula realizada do período: ajuste manual do mês ou leads em fechado
create or replace function public.metas_mat_real(p_periodo uuid)
 returns int language sql stable security definer set search_path to 'public'
as $$
  select coalesce(sum(coalesce(mm.ajuste,(select count(*) from crm_leads l where l.etapa='fechado'
           and l.data_fechamento >= m::date and l.data_fechamento < (m + interval '1 month')::date)::int)),0)::int
  from crm_metas_periodo p
  cross join generate_series(date_trunc('month',p.inicio), date_trunc('month',p.fim), interval '1 month') m
  left join crm_metas_mes mm on mm.periodo_id=p.id and mm.mes=m::date
  where p.id=p_periodo
$$;
revoke all on function public.metas_mat_real(uuid) from public, anon, authenticated;

create or replace function public.metas_carregar(p_token uuid)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare u crm_usuarios; g int; lm int; lr int; rm int; r jsonb;
begin
  u := crm_sessao_user(p_token);
  g := crm_nivel_num(u.id,'metas'); rm := crm_nivel_num(u.id,'rema');
  lm := greatest(g, crm_nivel_num(u.id,'metas_mat')); lr := greatest(g, rm);
  if lm = 0 and lr = 0 then raise exception 'sem_permissao' using errcode = 'P0001'; end if;
  select jsonb_build_object(
    'eu', jsonb_build_object('nome',u.nome,'metas',g,'mat',lm,'remav',lr,'rema',rm),
    'motivos', case when lr>0 then coalesce((select valor from crm_metas_config where chave='rema_motivos'),'[]'::jsonb) else '[]'::jsonb end,
    'semestres', coalesce((select jsonb_agg(
        case when g>0 then to_jsonb(s) || jsonb_build_object('pico',(coalesce(s.rema_auto,0)+coalesce(s.rema_contratual,0)+coalesce(s.matriculas,0)))
             else jsonb_build_object('inicio',s.inicio,'fim',s.fim,'obs',s.obs)
               || case when lm>0 then jsonb_build_object('matriculas',s.matriculas) else '{}'::jsonb end
               || case when lr>0 then jsonb_build_object('rema_auto',s.rema_auto,'rema_contratual',s.rema_contratual,'base_auto',s.base_auto,
                    'base_contratual',s.base_contratual,'pico',(coalesce(s.rema_auto,0)+coalesce(s.rema_contratual,0)+coalesce(s.matriculas,0))) else '{}'::jsonb end
        end order by s.inicio) from crm_metas_semestre s),'[]'::jsonb),
    'periodos', coalesce((select jsonb_agg(
      jsonb_build_object('id',p.id,'inicio',p.inicio,'fim',p.fim,'status',p.status,
        'indicadores', coalesce((select jsonb_agg(jsonb_build_object(
            'id',i.id,'indicador',i.indicador,'base_media',i.base_media,'base_ref',i.base_ref,'obs',i.obs,
            'faixas', coalesce((select jsonb_agg(jsonb_build_object('nivel',f.nivel,'alvo',f.alvo,'regra',f.regra,'valor_rs',f.valor_rs) order by f.nivel)
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
        'ultimo_import', case when lr>0 then (select to_jsonb(ri) from crm_rema_import ri where ri.periodo_id=p.id order by ri.em desc limit 1) end
      )
      || case when lm>0 then jsonb_build_object(
        'meses', (select jsonb_agg(jsonb_build_object('mes', m::date,'ritmo_1', mm.ritmo_1, 'ritmo_ult', mm.ritmo_ult, 'ajuste', mm.ajuste,
            'crm', (select count(*) from crm_leads l where l.etapa='fechado' and l.data_fechamento >= m::date and l.data_fechamento < (m + interval '1 month')::date))
          order by m) from generate_series(date_trunc('month',p.inicio), date_trunc('month',p.fim), interval '1 month') m
          left join crm_metas_mes mm on mm.periodo_id=p.id and mm.mes=m::date),
        'por_consultor', coalesce((select jsonb_agg(jsonb_build_object('responsavel',x.responsavel,'n',x.n) order by x.n desc)
          from (select coalesce(l.responsavel,'Sem responsável') responsavel, count(*) n from crm_leads l
                 where l.etapa='fechado' and l.data_fechamento between p.inicio and p.fim group by 1) x),'[]'::jsonb)) else '{}'::jsonb end
      order by p.inicio) from crm_metas_periodo p),'[]'::jsonb)
  ) into r;
  return r;
end $function$;

create or replace function public.rema_lista(p_token uuid, p_periodo uuid)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare u crm_usuarios;
begin
  u := crm_sessao_user(p_token);
  if greatest(crm_nivel_num(u.id,'metas'), crm_nivel_num(u.id,'rema')) = 0 then raise exception 'sem_permissao' using errcode='P0001'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id',a.id,'aluno',a.aluno,'turma',a.turma,'curso',a.curso,'estagio',a.estagio,'professor',a.professor,
      'formato',a.formato,'tipo',a.tipo,'status',a.status,'status_box',a.status_box,'motivo',a.motivo,'obs',a.obs,
      'data_status',a.data_status,'alterado_por',a.alterado_por,'alterado_em',a.alterado_em)
    order by (a.status in ('pendente','negociacao')) desc, a.aluno)
    from crm_rema_aluno a where a.periodo_id=p_periodo and a.na_lista),'[]'::jsonb);
end $function$;

-- Big numbers da tela inicial: qualquer sessão válida. Sem valores em R$, sem lista de alunos.
create or replace function public.metas_resumo(p_token uuid)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare u crm_usuarios; p crm_metas_periodo; ant crm_metas_semestre; r jsonb;
begin
  u := crm_sessao_user(p_token);
  select * into p from crm_metas_periodo where inicio <= current_date and fim >= current_date order by inicio desc limit 1;
  if not found then return null; end if;
  select * into ant from crm_metas_semestre where inicio < p.inicio order by inicio desc limit 1;
  select jsonb_build_object(
    'inicio',p.inicio,'fim',p.fim,'status',p.status,
    'mat_real', metas_mat_real(p.id),
    'mat_metas', coalesce((select jsonb_agg(f.alvo order by f.nivel) from crm_metas_faixa f join crm_metas_indicador i on i.id=f.indicador_id where i.periodo_id=p.id and i.indicador='matricula'),'[]'::jsonb),
    'contr_metas', coalesce((select jsonb_agg(f.alvo order by f.nivel) from crm_metas_faixa f join crm_metas_indicador i on i.id=f.indicador_id where i.periodo_id=p.id and i.indicador='rema_contratual'),'[]'::jsonb),
    'total_metas', coalesce((select jsonb_agg(f.alvo order by f.nivel) from crm_metas_faixa f join crm_metas_indicador i on i.id=f.indicador_id where i.periodo_id=p.id and i.indicador='rema_total'),'[]'::jsonb),
    'pico_ant', case when ant.id is null then null else coalesce(ant.rema_auto,0)+coalesce(ant.rema_contratual,0)+coalesce(ant.matriculas,0) end,
    'rema', (select jsonb_build_object('total',count(*),'contr',count(*) filter (where tipo='contratual'),
        'auto_real',count(*) filter (where tipo='automatica' and status='realizada'),
        'contr_real',count(*) filter (where tipo='contratual' and status='realizada'),
        'pend',count(*) filter (where status in ('pendente','negociacao')))
      from crm_rema_aluno a where a.periodo_id=p.id and a.na_lista)
  ) into r;
  return r;
end $function$;

grant execute on function public.metas_carregar(uuid) to anon;
grant execute on function public.rema_lista(uuid,uuid) to anon;
grant execute on function public.metas_resumo(uuid) to anon;
notify pgrst, 'reload schema';
