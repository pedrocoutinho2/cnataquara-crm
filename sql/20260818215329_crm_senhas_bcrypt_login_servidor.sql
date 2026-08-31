alter table crm_usuarios
  add column if not exists senha_hash text,
  add column if not exists senha_definida_em timestamptz,
  alter column pin_hash drop not null;

-- politica de senha: 8+ caracteres, com letra e numero
create or replace function crm_senha_valida(p_senha text) returns boolean
language sql immutable as $$
  select p_senha is not null
     and length(p_senha) >= 8
     and p_senha ~ '[A-Za-zÀ-ÿ]'
     and p_senha ~ '[0-9]';
$$;

-- login verificado no servidor; nunca devolve hash
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
    'hora_inicio',u.hora_inicio,'hora_fim',u.hora_fim
  );
end $$;

-- reset por admin
create or replace function crm_definir_senha(p_id uuid, p_senha text)
returns boolean
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not crm_senha_valida(p_senha) then
    raise exception 'A senha precisa ter no minimo 8 caracteres, com pelo menos uma letra e um numero.';
  end if;
  update crm_usuarios
     set senha_hash = extensions.crypt(p_senha, extensions.gen_salt('bf', 10)),
         senha_definida_em = now(),
         pin_hash = null
   where id = p_id;
  return found;
end $$;

-- troca pela propria pessoa, exigindo a senha atual
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
  update crm_usuarios
     set senha_hash = extensions.crypt(p_nova, extensions.gen_salt('bf',10)),
         senha_definida_em = now(), pin_hash = null
   where id = u.id;
  return true;
end $$;

-- o navegador nunca mais le hash de senha
revoke select (pin_hash, senha_hash) on crm_usuarios from anon;
revoke select (pin_hash, senha_hash) on crm_usuarios from authenticated;

grant execute on function crm_login(text,text) to anon;
grant execute on function crm_definir_senha(uuid,text) to anon;
grant execute on function crm_trocar_senha(text,text,text) to anon;

notify pgrst, 'reload schema';