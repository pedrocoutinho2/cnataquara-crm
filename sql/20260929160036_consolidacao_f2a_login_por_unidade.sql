-- Consolidação · Fase 2a: login identifica a unidade pelo e-mail (vínculo em crm_usuario_unidades)
-- 1 vínculo ativo  -> sessão já nasce com a unidade, front entra direto, sem seletor.
-- 2+ vínculos      -> sessão nasce sem unidade, front mostra a tela de escolha.
-- 0 vínculos       -> não entra (mesma resposta de senha errada).
-- Aditivo: todos os campos antigos de crm_login continuam iguais.

create or replace function public.crm_login(p_email text, p_senha text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare u record; t uuid; v_unids jsonb; v_n int; v_unid text;
begin
  select * into u from crm_usuarios
   where email is not null
     and lower(btrim(email)) = lower(btrim(p_email))
     and ativo = true;
  if not found then return null; end if;
  if u.senha_hash is null then return null; end if;
  if u.senha_hash <> extensions.crypt(p_senha, u.senha_hash) then return null; end if;

  select coalesce(jsonb_agg(jsonb_build_object('slug', un.slug, 'nome', un.nome, 'status', un.status) order by un.ordem), '[]'::jsonb),
         count(*)
    into v_unids, v_n
    from crm_usuario_unidades uu
    join crm_unidades un on un.slug = uu.unidade
   where uu.usuario_id = u.id and uu.ativo and un.status <> 'inativa';
  if v_n = 0 then return null; end if;
  if v_n = 1 then v_unid := v_unids->0->>'slug'; end if;

  delete from crm_sessoes where expira_em < now();
  insert into crm_sessoes(usuario_id, unidade) values (u.id, v_unid) returning token into t;
  return jsonb_build_object(
    'id',u.id,'nome',u.nome,'email',u.email,'cor',u.cor,'admin',u.admin,'ativo',u.ativo,
    'consultor',u.consultor,'papel',u.papel,'permissoes',u.permissoes,
    'hora_inicio',u.hora_inicio,'hora_fim',u.hora_fim,
    'senha_temporaria',u.senha_temporaria,
    'token',t,
    'unidades',v_unids,
    'unidade',v_unid,
    'escolher_unidade',(v_n > 1)
  );
end $function$;

create or replace function public.crm_sessao_escolher_unidade(p_token uuid, p_unidade text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare uid uuid; v record;
begin
  select usuario_id into uid from crm_sessoes where token = p_token and expira_em > now();
  if uid is null then raise exception 'sessao_invalida' using errcode = 'P0001'; end if;

  select uu.*, un.nome as unidade_nome, un.status as unidade_status into v
    from crm_usuario_unidades uu
    join crm_unidades un on un.slug = uu.unidade
    join crm_usuarios us on us.id = uu.usuario_id and us.ativo
   where uu.usuario_id = uid and uu.unidade = p_unidade and uu.ativo and un.status <> 'inativa';
  if not found then raise exception 'unidade_nao_permitida' using errcode = 'P0001'; end if;

  update crm_sessoes set unidade = p_unidade where token = p_token;
  return jsonb_build_object(
    'unidade', v.unidade, 'nome', v.unidade_nome, 'status', v.unidade_status,
    'papel', v.papel, 'admin', v.admin, 'consultor', v.consultor, 'permissoes', v.permissoes
  );
end $function$;

revoke all on function public.crm_sessao_escolher_unidade(uuid, text) from public;
grant execute on function public.crm_sessao_escolher_unidade(uuid, text) to anon, authenticated;
comment on function public.crm_sessao_escolher_unidade(uuid, text) is 'Define a unidade ativa da sessão. Só aceita unidade com vínculo ativo do usuário.';

notify pgrst, 'reload schema';