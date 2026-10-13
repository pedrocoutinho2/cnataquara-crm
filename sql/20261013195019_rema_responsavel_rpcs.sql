-- Rema: responsável pelo contato com cada aluno da lista (divisão da secretaria).
-- Regra (Pedro, 13/10/2026): lista em ordem alfabética dividida em blocos iguais
-- entre as pessoas de crm_metas_config 'rema_divisao' da unidade, na ordem do array.
-- Aluno que entra depois (reimportação) cai no bloco pelo corte alfabético já existente.
-- Todas veem a lista inteira: o responsável é marcação de organização, não permissão.

create or replace function public.rema_dividir(p_periodo uuid)
 returns integer
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare un text; resp uuid[]; k int; n int := 0;
begin
  select unidade into un from crm_metas_periodo where id = p_periodo;
  if un is null then return 0; end if;
  select array(select (jsonb_array_elements_text(valor->'responsaveis'))::uuid) into resp
    from crm_metas_config where chave = 'rema_divisao' and unidade = un;
  k := coalesce(cardinality(resp), 0);
  if k = 0 then return 0; end if;
  if not exists (select 1 from crm_rema_aluno where periodo_id = p_periodo and responsavel_id is not null) then
    -- divisão inicial: ordem alfabética, blocos iguais (o primeiro fica com a sobra)
    with o as (
      select id, (row_number() over (order by lower(aluno), chave) - 1) rn, count(*) over () tot
      from crm_rema_aluno where periodo_id = p_periodo and na_lista)
    update crm_rema_aluno a set responsavel_id = resp[1 + ((o.rn * k) / o.tot)::int]
      from o where a.id = o.id;
  else
    -- aluno novo: herda o bloco alfabético em que cai
    update crm_rema_aluno a set responsavel_id = coalesce(
      (select u.r from unnest(resp) with ordinality u(r, i)
        where (select min(lower(b.aluno)) from crm_rema_aluno b
                where b.periodo_id = p_periodo and b.responsavel_id = u.r) <= lower(a.aluno)
        order by u.i desc limit 1),
      resp[1])
    where a.periodo_id = p_periodo and a.na_lista and a.responsavel_id is null;
  end if;
  get diagnostics n = row_count;
  return n;
end $function$;
revoke all on function public.rema_dividir(uuid) from public, anon, authenticated;

create or replace function public.rema_lista(p_token uuid, p_periodo uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare u crm_usuarios; un text;
begin
  u := crm_sessao_user(p_token);
  un := crm_sessao_unidade(p_token);
  if greatest(crm_nivel_num(u.id,'metas',un), crm_nivel_num(u.id,'rema',un)) = 0 then raise exception 'sem_permissao' using errcode='P0001'; end if;
  if not exists (select 1 from crm_metas_periodo where id = p_periodo and unidade = un) then
    raise exception 'periodo_de_outra_unidade' using errcode = 'P0001';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id',a.id,'aluno',a.aluno,'turma',a.turma,'curso',a.curso,'estagio',a.estagio,'professor',a.professor,
      'formato',a.formato,'tipo',a.tipo,'status',a.status,'status_box',a.status_box,'motivo',a.motivo,'obs',a.obs,
      'data_status',a.data_status,'alterado_por',a.alterado_por,'alterado_em',a.alterado_em,
      'responsavel_id',a.responsavel_id,'responsavel',r.nome)
    order by (a.status in ('pendente','negociacao')) desc, a.aluno)
    from crm_rema_aluno a left join crm_usuarios r on r.id = a.responsavel_id
    where a.periodo_id=p_periodo and a.na_lista),'[]'::jsonb);
end $function$;

create or replace function public.rema_importar(p_token uuid, p_periodo uuid, p_empresa text, p_gerado text, p_arquivo text, p_rows jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare u crm_usuarios; un text; esperado text; rw jsonb; ch text; st text; tp text; ex crm_rema_aluno;
        n_lin int := 0; n_novo int := 0; n_atu int := 0; n_sai int := 0; chaves text[] := '{}';
begin
  u := crm_exige(p_token, 'metas', 2);
  un := crm_sessao_unidade(p_token);
  if not exists (select 1 from crm_metas_periodo where id = p_periodo and unidade = un) then
    raise exception 'periodo_de_outra_unidade' using errcode = 'P0001';
  end if;
  select valor #>> '{}' into esperado from crm_metas_config where chave='razao_social' and unidade = un;
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
  perform rema_dividir(p_periodo);
  insert into crm_rema_import(periodo_id, arquivo, gerado, linhas, novos, atualizados, sairam, por)
  values (p_periodo, p_arquivo, p_gerado, n_lin, n_novo, n_atu, n_sai, u.nome);
  return jsonb_build_object('linhas',n_lin,'novos',n_novo,'atualizados',n_atu,'sairam',n_sai);
end $function$;

notify pgrst, 'reload schema';