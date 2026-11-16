-- Rede. Decisão de 16/11/2026 (Pedro): a gestão (nível total em leads) também pode gravar o login
-- do CNA Box de cada consultor da unidade, para não depender de cada um fazer. A senha continua
-- só no Vault: ninguém lê de volta pelo front, nem a gestão. Fica registrado quem gravou.
alter table public.crm_box_credenciais add column if not exists definido_por text;

-- o próprio consultor gravando: registra o nome dele
create or replace function public.crm_box_credencial_salvar(p_token uuid, p_email text, p_senha text)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare s jsonb; v_id uuid; v_secret uuid; v_un text; v_uid uuid;
begin
  s := crm_box_sessao(p_token, 2);
  v_un := s->>'unidade'; v_uid := (s->>'usuario_id')::uuid;
  if coalesce(trim(p_email),'') = '' or coalesce(p_senha,'') = '' then
    raise exception 'email_e_senha_obrigatorios' using errcode = 'P0001';
  end if;
  select id, secret_id into v_id, v_secret from crm_box_credenciais where unidade = v_un and usuario_id = v_uid;
  if v_id is null then
    v_secret := vault.create_secret(p_senha, 'crm_box_' || v_un || '_' || v_uid::text, 'Senha do CNA Box de usuário do CRM');
    insert into crm_box_credenciais (unidade, usuario_id, email_box, secret_id, definido_por)
    values (v_un, v_uid, lower(trim(p_email)), v_secret, s->>'nome');
  else
    perform vault.update_secret(v_secret, p_senha);
    update crm_box_credenciais
       set email_box = lower(trim(p_email)), atualizado_em = now(), ultimo_erro = null, ultimo_ok_em = null,
           definido_por = s->>'nome'
     where id = v_id;
  end if;
  return jsonb_build_object('ok', true, 'email_box', lower(trim(p_email)));
end $f$;

-- gestão: consultores da unidade da sessão e o estado do login do Box de cada um (sem senha)
create or replace function public.crm_box_equipe_listar(p_token uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $f$
declare s jsonb;
begin
  s := crm_box_sessao(p_token, 3);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'usuario_id', u.id, 'nome', u.nome, 'conectado', c.id is not null, 'email_box', c.email_box,
             'atualizado_em', c.atualizado_em, 'ultimo_ok_em', c.ultimo_ok_em, 'ultimo_erro', c.ultimo_erro,
             'definido_por', c.definido_por) order by u.nome)
    from crm_usuario_unidades uu
    join crm_usuarios u on u.id = uu.usuario_id and u.ativo
    left join crm_box_credenciais c on c.unidade = uu.unidade and c.usuario_id = u.id
    where uu.unidade = s->>'unidade' and uu.ativo and (uu.consultor or c.id is not null)
  ), '[]'::jsonb);
end $f$;

-- gestão grava o login do Box de alguém com vínculo ativo na mesma unidade
create or replace function public.crm_box_credencial_salvar_de(p_token uuid, p_usuario_id uuid, p_email text, p_senha text)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare s jsonb; v_id uuid; v_secret uuid; v_un text;
begin
  s := crm_box_sessao(p_token, 3);
  v_un := s->>'unidade';
  if not exists (select 1 from crm_usuario_unidades uu join crm_usuarios u on u.id = uu.usuario_id and u.ativo
                  where uu.usuario_id = p_usuario_id and uu.unidade = v_un and uu.ativo) then
    raise exception 'usuario_fora_da_unidade' using errcode = 'P0001';
  end if;
  if coalesce(trim(p_email),'') = '' or coalesce(p_senha,'') = '' then
    raise exception 'email_e_senha_obrigatorios' using errcode = 'P0001';
  end if;
  select id, secret_id into v_id, v_secret from crm_box_credenciais where unidade = v_un and usuario_id = p_usuario_id;
  if v_id is null then
    v_secret := vault.create_secret(p_senha, 'crm_box_' || v_un || '_' || p_usuario_id::text, 'Senha do CNA Box de usuário do CRM');
    insert into crm_box_credenciais (unidade, usuario_id, email_box, secret_id, definido_por)
    values (v_un, p_usuario_id, lower(trim(p_email)), v_secret, s->>'nome');
  else
    perform vault.update_secret(v_secret, p_senha);
    update crm_box_credenciais
       set email_box = lower(trim(p_email)), atualizado_em = now(), ultimo_erro = null, ultimo_ok_em = null,
           definido_por = s->>'nome'
     where id = v_id;
  end if;
  return jsonb_build_object('ok', true, 'email_box', lower(trim(p_email)));
end $f$;

revoke all on function public.crm_box_equipe_listar(uuid) from public;
revoke all on function public.crm_box_credencial_salvar_de(uuid, uuid, text, text) from public;
grant execute on function public.crm_box_equipe_listar(uuid) to anon, authenticated, service_role;
grant execute on function public.crm_box_credencial_salvar_de(uuid, uuid, text, text) to anon, authenticated, service_role;

notify pgrst, 'reload schema';