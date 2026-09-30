-- Consolidação · Fase 2b-5b-4: equipe por unidade (para a tela de Equipe do front novo).
-- crm_equipe_listar / crm_equipe_salvar / crm_equipe_definir_senha: exigem sessão + módulo 'equipe'
-- e trabalham só na unidade da sessão. Casamento entre unidades POR E-MAIL: salvar com um e-mail
-- que já existe vincula a pessoa existente à unidade em vez de criar outra.
-- Dados da pessoa (nome, e-mail, cor, horário) só são alterados se quem edita tem acesso a todas
-- as unidades da pessoa; senão, só o vínculo desta unidade muda.
-- crm_definir_senha (anon, sem checagem) segue existindo para o front atual; revogar na Fase 3.

create or replace function public.crm_usuario_espelho_legado()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  -- As RPCs novas de equipe gerenciam o vínculo elas mesmas.
  if coalesce(current_setting('crm.sem_espelho', true), '') = '1' then return new; end if;
  insert into crm_usuario_unidades (usuario_id, unidade, papel, admin, consultor, permissoes, ativo)
  values (new.id, 'taquara', new.papel, coalesce(new.admin,false), coalesce(new.consultor,false), new.permissoes, coalesce(new.ativo,true))
  on conflict (usuario_id, unidade) do update
    set papel = excluded.papel, admin = excluded.admin, consultor = excluded.consultor,
        permissoes = excluded.permissoes, ativo = excluded.ativo;
  return new;
end $function$;

create or replace function public.crm_equipe_listar(p_token uuid)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare u crm_usuarios; un text;
begin
  u := crm_exige(p_token, 'equipe', 1);
  un := crm_sessao_unidade(p_token);
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', us.id, 'nome', us.nome, 'email', us.email, 'email_agenda', us.email_agenda, 'cor', us.cor,
      'hora_inicio', us.hora_inicio, 'hora_fim', us.hora_fim,
      'senha_definida', us.senha_hash is not null, 'senha_temporaria', us.senha_temporaria,
      'senha_definida_em', us.senha_definida_em,
      'ativo', (v.ativo and us.ativo), 'papel', v.papel, 'admin', v.admin, 'consultor', v.consultor,
      'permissoes', v.permissoes,
      'unidades', (select jsonb_agg(o.unidade order by o.unidade) from crm_usuario_unidades o where o.usuario_id = us.id and o.ativo))
    order by us.nome)
    from crm_usuario_unidades v join crm_usuarios us on us.id = v.usuario_id
   where v.unidade = un), '[]'::jsonb);
end $function$;

create or replace function public.crm_equipe_salvar(p_token uuid, p jsonb)
 returns uuid
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare u crm_usuarios; un text; v_id uuid; v_email text; v_pode_pessoa boolean;
begin
  u := crm_exige(p_token, 'equipe', 2);
  un := crm_sessao_unidade(p_token);
  v_email := nullif(lower(btrim(p->>'email')), '');
  v_id := nullif(p->>'id', '')::uuid;
  if v_id is null and v_email is not null then
    select id into v_id from crm_usuarios where email is not null and lower(btrim(email)) = v_email;
  end if;

  perform set_config('crm.sem_espelho', '1', true);

  if v_id is null then
    if coalesce(btrim(p->>'nome'), '') = '' then raise exception 'nome_obrigatorio' using errcode = 'P0001'; end if;
    insert into crm_usuarios (nome, email, email_agenda, cor, hora_inicio, hora_fim, ativo, papel, admin, consultor, permissoes)
    values (btrim(p->>'nome'), v_email, nullif(p->>'email_agenda',''), nullif(p->>'cor',''),
            nullif(p->>'hora_inicio','')::time, nullif(p->>'hora_fim','')::time, true,
            nullif(p->>'papel',''), coalesce((p->>'admin')::boolean, false), coalesce((p->>'consultor')::boolean, false),
            p->'permissoes')
    returning id into v_id;
  else
    -- só mexe nos dados da pessoa se quem edita enxerga todas as unidades dela
    select not exists (
      select 1 from crm_usuario_unidades t
       where t.usuario_id = v_id and t.ativo
         and t.unidade not in (select m.unidade from crm_usuario_unidades m where m.usuario_id = u.id and m.ativo)
    ) into v_pode_pessoa;
    if v_pode_pessoa then
      update crm_usuarios set
        nome = coalesce(nullif(btrim(p->>'nome'),''), nome),
        email = case when p ? 'email' then v_email else email end,
        email_agenda = case when p ? 'email_agenda' then nullif(p->>'email_agenda','') else email_agenda end,
        cor = case when p ? 'cor' then nullif(p->>'cor','') else cor end,
        hora_inicio = case when p ? 'hora_inicio' then nullif(p->>'hora_inicio','')::time else hora_inicio end,
        hora_fim = case when p ? 'hora_fim' then nullif(p->>'hora_fim','')::time else hora_fim end
      where id = v_id;
    end if;
  end if;

  insert into crm_usuario_unidades (usuario_id, unidade, papel, admin, consultor, permissoes, ativo)
  values (v_id, un, nullif(p->>'papel',''), coalesce((p->>'admin')::boolean, false),
          coalesce((p->>'consultor')::boolean, false), p->'permissoes', coalesce((p->>'ativo')::boolean, true))
  on conflict (usuario_id, unidade) do update set
    papel = case when p ? 'papel' then excluded.papel else crm_usuario_unidades.papel end,
    admin = case when p ? 'admin' then excluded.admin else crm_usuario_unidades.admin end,
    consultor = case when p ? 'consultor' then excluded.consultor else crm_usuario_unidades.consultor end,
    permissoes = case when p ? 'permissoes' then excluded.permissoes else crm_usuario_unidades.permissoes end,
    ativo = case when p ? 'ativo' then excluded.ativo else crm_usuario_unidades.ativo end;

  return v_id;
end $function$;

create or replace function public.crm_equipe_definir_senha(p_token uuid, p_usuario uuid, p_senha text, p_temporaria boolean default true)
 returns boolean
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare u crm_usuarios; un text;
begin
  u := crm_exige(p_token, 'equipe', 2);
  un := crm_sessao_unidade(p_token);
  if not exists (select 1 from crm_usuario_unidades where usuario_id = p_usuario and unidade = un) then
    raise exception 'usuario_de_outra_unidade' using errcode = 'P0001';
  end if;
  if not crm_senha_valida(p_senha) then
    raise exception 'A senha precisa ter no minimo 8 caracteres, com pelo menos uma letra e um numero.';
  end if;
  update crm_usuarios
     set senha_hash = extensions.crypt(p_senha, extensions.gen_salt('bf', 10)),
         senha_definida_em = now(),
         senha_temporaria = p_temporaria,
         pin_hash = null
   where id = p_usuario;
  return found;
end $function$;

revoke all on function public.crm_equipe_listar(uuid) from public;
revoke all on function public.crm_equipe_salvar(uuid, jsonb) from public;
revoke all on function public.crm_equipe_definir_senha(uuid, uuid, text, boolean) from public;
grant execute on function public.crm_equipe_listar(uuid) to anon, authenticated;
grant execute on function public.crm_equipe_salvar(uuid, jsonb) to anon, authenticated;
grant execute on function public.crm_equipe_definir_senha(uuid, uuid, text, boolean) to anon, authenticated;

notify pgrst, 'reload schema';