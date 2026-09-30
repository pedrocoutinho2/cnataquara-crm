-- Correção da 2b-5b-4 (achada no teste, antes de qualquer uso): crm_equipe_salvar mandava null
-- explícito em colunas NOT NULL com default (hora_inicio 09:00, hora_fim 18:00, papel 'comercial',
-- permissoes '{}'). Agora respeita os defaults no insert e nunca grava null por cima no update.
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
            coalesce(nullif(p->>'hora_inicio','')::time, time '09:00'),
            coalesce(nullif(p->>'hora_fim','')::time, time '18:00'), true,
            coalesce(nullif(p->>'papel',''), 'comercial'),
            coalesce((p->>'admin')::boolean, false), coalesce((p->>'consultor')::boolean, false),
            coalesce(p->'permissoes', '{}'::jsonb))
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
        hora_inicio = coalesce(nullif(p->>'hora_inicio','')::time, hora_inicio),
        hora_fim = coalesce(nullif(p->>'hora_fim','')::time, hora_fim)
      where id = v_id;
    end if;
  end if;

  insert into crm_usuario_unidades (usuario_id, unidade, papel, admin, consultor, permissoes, ativo)
  values (v_id, un, coalesce(nullif(p->>'papel',''), 'comercial'), coalesce((p->>'admin')::boolean, false),
          coalesce((p->>'consultor')::boolean, false), p->'permissoes', coalesce((p->>'ativo')::boolean, true))
  on conflict (usuario_id, unidade) do update set
    papel = case when p ? 'papel' then excluded.papel else crm_usuario_unidades.papel end,
    admin = case when p ? 'admin' then excluded.admin else crm_usuario_unidades.admin end,
    consultor = case when p ? 'consultor' then excluded.consultor else crm_usuario_unidades.consultor end,
    permissoes = case when p ? 'permissoes' then excluded.permissoes else crm_usuario_unidades.permissoes end,
    ativo = case when p ? 'ativo' then excluded.ativo else crm_usuario_unidades.ativo end;

  return v_id;
end $function$;