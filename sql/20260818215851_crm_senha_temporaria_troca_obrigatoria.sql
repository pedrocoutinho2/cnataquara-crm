alter table crm_usuarios
  add column if not exists senha_temporaria boolean not null default false;

-- login agora avisa se a senha e temporaria
create or replace function crm_login(p_nome text, p_senha text)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u record;
begin
  select * into u from crm_usuarios
   where lower(nome) = lower(btrim(p_nome)) and ativo = true;
  if not found then return null; end if;
  if u.senha_hash is null then return null; end if;
  if u.senha_hash <> extensions.crypt(p_senha, u.senha_hash) then return null; end if;
  return jsonb_build_object(
    'id',u.id,'nome',u.nome,'cor',u.cor,'admin',u.admin,'ativo',u.ativo,
    'consultor',u.consultor,'papel',u.papel,'permissoes',u.permissoes,
    'hora_inicio',u.hora_inicio,'hora_fim',u.hora_fim,
    'senha_temporaria',u.senha_temporaria
  );
end $$;

-- reset por admin: por padrao marca como temporaria e obriga a troca
create or replace function crm_definir_senha(p_id uuid, p_senha text, p_temporaria boolean default true)
returns boolean
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not crm_senha_valida(p_senha) then
    raise exception 'A senha precisa ter no minimo 8 caracteres, com pelo menos uma letra e um numero.';
  end if;
  update crm_usuarios
     set senha_hash = extensions.crypt(p_senha, extensions.gen_salt('bf', 10)),
         senha_definida_em = now(),
         senha_temporaria = p_temporaria,
         pin_hash = null
   where id = p_id;
  return found;
end $$;

-- troca pela propria pessoa: limpa a marca de temporaria e recusa repetir a atual
create or replace function crm_trocar_senha(p_nome text, p_atual text, p_nova text)
returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare u record;
begin
  select * into u from crm_usuarios where lower(nome)=lower(btrim(p_nome)) and ativo=true;
  if not found or u.senha_hash is null then return false; end if;
  if u.senha_hash <> extensions.crypt(p_atual, u.senha_hash) then return false; end if;
  if not crm_senha_valida(p_nova) then
    raise exception 'A senha precisa ter no minimo 8 caracteres, com pelo menos uma letra e um numero.';
  end if;
  if u.senha_hash = extensions.crypt(p_nova, u.senha_hash) then
    raise exception 'A nova senha precisa ser diferente da atual.';
  end if;
  update crm_usuarios
     set senha_hash = extensions.crypt(p_nova, extensions.gen_salt('bf',10)),
         senha_definida_em = now(), senha_temporaria = false, pin_hash = null
   where id = u.id;
  return true;
end $$;

grant execute on function crm_login(text,text) to anon;
grant execute on function crm_definir_senha(uuid,text,boolean) to anon;
grant execute on function crm_trocar_senha(text,text,text) to anon;

notify pgrst, 'reload schema';