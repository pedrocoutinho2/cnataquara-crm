-- Login passa a emitir token de sessão (campo novo, aditivo).
create or replace function public.crm_login(p_email text, p_senha text)
 returns jsonb language plpgsql security definer
 set search_path to 'public', 'extensions'
as $function$
declare u record; t uuid;
begin
  select * into u from crm_usuarios
   where email is not null
     and lower(btrim(email)) = lower(btrim(p_email))
     and ativo = true;
  if not found then return null; end if;
  if u.senha_hash is null then return null; end if;
  if u.senha_hash <> extensions.crypt(p_senha, u.senha_hash) then return null; end if;
  delete from crm_sessoes where expira_em < now();
  insert into crm_sessoes(usuario_id) values (u.id) returning token into t;
  return jsonb_build_object(
    'id',u.id,'nome',u.nome,'email',u.email,'cor',u.cor,'admin',u.admin,'ativo',u.ativo,
    'consultor',u.consultor,'papel',u.papel,'permissoes',u.permissoes,
    'hora_inicio',u.hora_inicio,'hora_fim',u.hora_fim,
    'senha_temporaria',u.senha_temporaria,
    'token',t
  );
end $function$;

-- Nível de um usuário num módulo, espelhando nivelDe() do front.
create or replace function public.crm_nivel_num(p_usuario uuid, p_mod text)
 returns int language plpgsql stable security definer set search_path to 'public'
as $function$
declare u record; n text;
begin
  select * into u from crm_usuarios where id = p_usuario and ativo = true;
  if not found then return 0; end if;
  n := u.permissoes ->> p_mod;
  if n is null then
    select nivel into n from crm_papel_permissoes
     where papel = coalesce(u.papel, case when u.admin then 'admin' else 'comercial' end) and modulo = p_mod;
  end if;
  if n is null then n := case when u.admin then 'total' else 'nenhum' end; end if;
  return case n when 'total' then 3 when 'editar' then 2 when 'ver' then 1 else 0 end;
end $function$;

-- Valida token e nível mínimo. Devolve o usuário.
create or replace function public.crm_exige(p_token uuid, p_mod text, p_min int)
 returns public.crm_usuarios language plpgsql security definer set search_path to 'public'
as $function$
declare u crm_usuarios; uid uuid;
begin
  select usuario_id into uid from crm_sessoes where token = p_token and expira_em > now();
  if uid is null then raise exception 'sessao_invalida' using errcode = 'P0001'; end if;
  select * into u from crm_usuarios where id = uid and ativo = true;
  if not found then raise exception 'sessao_invalida' using errcode = 'P0001'; end if;
  if crm_nivel_num(uid, p_mod) < p_min then raise exception 'sem_permissao' using errcode = 'P0001'; end if;
  return u;
end $function$;

create or replace function public.crm_norm(p text)
 returns text language sql immutable
as $$ select btrim(regexp_replace(translate(upper(coalesce(p,'')),'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ','AAAAAEEEEIIIIOOOOOUUUUC'),'\s+',' ','g')) $$;

-- Painel completo (dados pequenos: semestres, períodos, faixas, meses, agregados de rema).
create or replace function public.metas_carregar(p_token uuid)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare u crm_usuarios; r jsonb;
begin
  u := crm_exige(p_token, 'metas', 1);
  select jsonb_build_object(
    'eu', jsonb_build_object('nome',u.nome,'metas',crm_nivel_num(u.id,'metas'),'rema',crm_nivel_num(u.id,'rema')),
    'motivos', coalesce((select valor from crm_metas_config where chave='rema_motivos'),'[]'::jsonb),
    'semestres', coalesce((select jsonb_agg(to_jsonb(s) order by s.inicio) from crm_metas_semestre s),'[]'::jsonb),
    'periodos', coalesce((select jsonb_agg(
      jsonb_build_object(
        'id',p.id,'inicio',p.inicio,'fim',p.fim,'status',p.status,
        'indicadores', coalesce((select jsonb_agg(jsonb_build_object(
            'id',i.id,'indicador',i.indicador,'base_media',i.base_media,'base_ref',i.base_ref,'obs',i.obs,
            'faixas', coalesce((select jsonb_agg(jsonb_build_object('nivel',f.nivel,'alvo',f.alvo,'regra',f.regra,'valor_rs',f.valor_rs) order by f.nivel)
                                 from crm_metas_faixa f where f.indicador_id=i.id),'[]'::jsonb))
          order by i.indicador) from crm_metas_indicador i where i.periodo_id=p.id),'[]'::jsonb),
        'meses', (select jsonb_agg(jsonb_build_object(
            'mes', m::date,
            'ritmo_1', mm.ritmo_1, 'ritmo_ult', mm.ritmo_ult, 'ajuste', mm.ajuste,
            'crm', (select count(*) from crm_leads l where l.etapa='fechado'
                     and l.data_fechamento >= m::date and l.data_fechamento < (m + interval '1 month')::date))
          order by m)
          from generate_series(date_trunc('month',p.inicio), date_trunc('month',p.fim), interval '1 month') m
          left join crm_metas_mes mm on mm.periodo_id=p.id and mm.mes=m::date),
        'por_consultor', coalesce((select jsonb_agg(jsonb_build_object('responsavel',x.responsavel,'n',x.n) order by x.n desc)
          from (select coalesce(l.responsavel,'Sem responsável') responsavel, count(*) n from crm_leads l
                 where l.etapa='fechado' and l.data_fechamento between p.inicio and p.fim group by 1) x),'[]'::jsonb),
        'rema', (select jsonb_build_object(
            'total',count(*),
            'auto',count(*) filter (where tipo='automatica'),
            'contr',count(*) filter (where tipo='contratual'),
            'auto_real',count(*) filter (where tipo='automatica' and status='realizada'),
            'contr_real',count(*) filter (where tipo='contratual' and status='realizada'),
            'pend_auto',count(*) filter (where tipo='automatica' and status in ('pendente','negociacao')),
            'pend_contr',count(*) filter (where tipo='contratual' and status in ('pendente','negociacao')),
            'nao_renova',count(*) filter (where status='nao_renova'),
            'trancou',count(*) filter (where status='trancou'),
            'negociacao',count(*) filter (where status='negociacao'))
          from crm_rema_aluno a where a.periodo_id=p.id and a.na_lista),
        'ultimo_import', (select to_jsonb(ri) from crm_rema_import ri where ri.periodo_id=p.id order by ri.em desc limit 1)
      ) order by p.inicio) from crm_metas_periodo p),'[]'::jsonb)
  ) into r;
  return r;
end $function$;

-- Salva período, indicadores, faixas e meses. Só quem edita metas.
create or replace function public.metas_salvar_periodo(p_token uuid, p jsonb)
 returns uuid language plpgsql security definer set search_path to 'public'
as $function$
declare u crm_usuarios; pid uuid; ind jsonb; iid uuid; fx jsonb; ms jsonb;
begin
  u := crm_exige(p_token, 'metas', 2);
  insert into crm_metas_periodo(inicio, fim, status, atualizado_por, atualizado_em)
  values ((p->>'inicio')::date, (p->>'fim')::date, coalesce(p->>'status','rascunho'), u.nome, now())
  on conflict (inicio) do update set fim=excluded.fim, status=excluded.status, atualizado_por=u.nome, atualizado_em=now()
  returning id into pid;
  for ind in select * from jsonb_array_elements(coalesce(p->'indicadores','[]'::jsonb)) loop
    insert into crm_metas_indicador(periodo_id, indicador, base_media, base_ref, obs)
    values (pid, ind->>'indicador', nullif(ind->>'base_media','')::numeric, nullif(ind->>'base_ref','')::numeric, ind->>'obs')
    on conflict (periodo_id, indicador) do update set base_media=excluded.base_media, base_ref=excluded.base_ref, obs=excluded.obs
    returning id into iid;
    if ind ? 'faixas' then
      delete from crm_metas_faixa where indicador_id=iid;
      for fx in select * from jsonb_array_elements(ind->'faixas') loop
        if nullif(fx->>'alvo','') is not null then
          insert into crm_metas_faixa(indicador_id, nivel, alvo, regra, valor_rs)
          values (iid, (fx->>'nivel')::int, (fx->>'alvo')::int, fx->>'regra', nullif(fx->>'valor_rs','')::numeric);
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

create or replace function public.metas_salvar_semestre(p_token uuid, p jsonb)
 returns void language plpgsql security definer set search_path to 'public'
as $function$
declare u crm_usuarios;
begin
  u := crm_exige(p_token, 'metas', 2);
  insert into crm_metas_semestre(inicio, fim, matriculas, rema_auto, rema_contratual, base_auto, base_contratual, obs, atualizado_por, atualizado_em)
  values ((p->>'inicio')::date, (p->>'fim')::date,
          nullif(p->>'matriculas','')::int, nullif(p->>'rema_auto','')::int, nullif(p->>'rema_contratual','')::int,
          nullif(p->>'base_auto','')::int, nullif(p->>'base_contratual','')::int, p->>'obs', u.nome, now())
  on conflict (inicio) do update set fim=excluded.fim, matriculas=excluded.matriculas, rema_auto=excluded.rema_auto,
    rema_contratual=excluded.rema_contratual, base_auto=excluded.base_auto, base_contratual=excluded.base_contratual,
    obs=excluded.obs, atualizado_por=u.nome, atualizado_em=now();
end $function$;

create or replace function public.rema_lista(p_token uuid, p_periodo uuid)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare u crm_usuarios;
begin
  u := crm_exige(p_token, 'metas', 1);
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id',a.id,'aluno',a.aluno,'turma',a.turma,'curso',a.curso,'estagio',a.estagio,'professor',a.professor,
      'formato',a.formato,'tipo',a.tipo,'status',a.status,'status_box',a.status_box,'motivo',a.motivo,'obs',a.obs,
      'data_status',a.data_status,'alterado_por',a.alterado_por,'alterado_em',a.alterado_em)
    order by (a.status in ('pendente','negociacao')) desc, a.aluno)
    from crm_rema_aluno a where a.periodo_id=p_periodo and a.na_lista),'[]'::jsonb);
end $function$;

create or replace function public.rema_marcar(p_token uuid, p_id uuid, p_status text, p_motivo text, p_data date, p_obs text)
 returns void language plpgsql security definer set search_path to 'public'
as $function$
declare u crm_usuarios;
begin
  u := crm_exige(p_token, 'rema', 2);
  if p_status not in ('pendente','realizada','nao_renova','trancou','negociacao') then raise exception 'status_invalido'; end if;
  update crm_rema_aluno set status=p_status,
    motivo = case when p_status='nao_renova' then p_motivo else null end,
    obs = coalesce(p_obs, obs), data_status = coalesce(p_data, current_date),
    alterado_por=u.nome, alterado_em=now()
  where id=p_id;
end $function$;

-- Importa o Relatório de Índice de Rematrícula do Box.
-- Box "Realizada"/"Não Realizada" prevalece; Box "Pendente" não desfaz marcação feita no CRM.
create or replace function public.rema_importar(p_token uuid, p_periodo uuid, p_empresa text, p_gerado text, p_arquivo text, p_rows jsonb)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare u crm_usuarios; esperado text; rw jsonb; ch text; st text; tp text; ex crm_rema_aluno;
        n_lin int := 0; n_novo int := 0; n_atu int := 0; n_sai int := 0; chaves text[] := '{}';
begin
  u := crm_exige(p_token, 'metas', 2);
  select valor #>> '{}' into esperado from crm_metas_config where chave='razao_social';
  if esperado is null or position(crm_norm(esperado) in crm_norm(p_empresa)) = 0 then
    raise exception 'empresa_diferente';
  end if;
  for rw in select * from jsonb_array_elements(p_rows) loop
    if coalesce(btrim(rw->>'aluno'),'') = '' then continue; end if;
    n_lin := n_lin + 1;
    ch := lower(regexp_replace(btrim(rw->>'aluno'),'\s+',' ','g')) || '|' || upper(btrim(coalesce(rw->>'turma','')));
    chaves := chaves || ch;
    tp := case when crm_norm(rw->>'tipo') like '%CONTRATUAL%' then 'contratual' else 'automatica' end;
    st := case crm_norm(rw->>'status') when 'REALIZADA' then 'realizada' when 'NAO REALIZADA' then 'nao_renova' else 'pendente' end;
    select * into ex from crm_rema_aluno where periodo_id=p_periodo and chave=ch;
    if not found then
      insert into crm_rema_aluno(periodo_id, chave, aluno, turma, idioma, curso, estagio, professor, formato, horario, tipo, status, status_box, alterado_por, alterado_em)
      values (p_periodo, ch, btrim(rw->>'aluno'), btrim(rw->>'turma'), rw->>'idioma', rw->>'curso', rw->>'estagio', rw->>'professor',
              rw->>'formato', btrim(rw->>'horario'), tp, st, rw->>'status', 'relatório do Box', now());
      n_novo := n_novo + 1;
    else
      update crm_rema_aluno set
        aluno=btrim(rw->>'aluno'), idioma=rw->>'idioma', curso=rw->>'curso', estagio=rw->>'estagio', professor=rw->>'professor',
        formato=rw->>'formato', horario=btrim(rw->>'horario'), tipo=tp, status_box=rw->>'status', na_lista=true, importado_em=now(),
        status = case when st='pendente' then ex.status else st end,
        alterado_por = case when st='pendente' or ex.status=st then ex.alterado_por else 'relatório do Box' end,
        alterado_em = case when st='pendente' or ex.status=st then ex.alterado_em else now() end
      where id=ex.id;
      n_atu := n_atu + 1;
    end if;
  end loop;
  update crm_rema_aluno set na_lista=false where periodo_id=p_periodo and na_lista and not (chave = any(chaves));
  get diagnostics n_sai = row_count;
  insert into crm_rema_import(periodo_id, arquivo, gerado, linhas, novos, atualizados, sairam, por)
  values (p_periodo, p_arquivo, p_gerado, n_lin, n_novo, n_atu, n_sai, u.nome);
  return jsonb_build_object('linhas',n_lin,'novos',n_novo,'atualizados',n_atu,'sairam',n_sai);
end $function$;

revoke all on function public.crm_nivel_num(uuid,text) from public, anon, authenticated;
revoke all on function public.crm_exige(uuid,text,int) from public, anon, authenticated;
grant execute on function public.metas_carregar(uuid) to anon;
grant execute on function public.metas_salvar_periodo(uuid,jsonb) to anon;
grant execute on function public.metas_salvar_semestre(uuid,jsonb) to anon;
grant execute on function public.rema_lista(uuid,uuid) to anon;
grant execute on function public.rema_marcar(uuid,uuid,text,text,date,text) to anon;
grant execute on function public.rema_importar(uuid,uuid,text,text,text,jsonb) to anon;

notify pgrst, 'reload schema';
