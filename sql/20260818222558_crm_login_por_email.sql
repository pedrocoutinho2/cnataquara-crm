alter table crm_usuarios add column if not exists email text;

create unique index if not exists crm_usuarios_email_uix
  on crm_usuarios (lower(btrim(email))) where email is not null;

-- login passa a ser por e-mail
drop function if exists crm_login(text,text);
create or replace function crm_login(p_email text, p_senha text)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u record;
begin
  select * into u from crm_usuarios
   where email is not null
     and lower(btrim(email)) = lower(btrim(p_email))
     and ativo = true;
  if not found then return null; end if;
  if u.senha_hash is null then return null; end if;
  if u.senha_hash <> extensions.crypt(p_senha, u.senha_hash) then return null; end if;
  return jsonb_build_object(
    'id',u.id,'nome',u.nome,'email',u.email,'cor',u.cor,'admin',u.admin,'ativo',u.ativo,
    'consultor',u.consultor,'papel',u.papel,'permissoes',u.permissoes,
    'hora_inicio',u.hora_inicio,'hora_fim',u.hora_fim,
    'senha_temporaria',u.senha_temporaria
  );
end $$;

-- troca da propria senha tambem por e-mail
drop function if exists crm_trocar_senha(text,text,text);
create or replace function crm_trocar_senha(p_email text, p_atual text, p_nova text)
returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare u record;
begin
  select * into u from crm_usuarios
   where email is not null and lower(btrim(email)) = lower(btrim(p_email)) and ativo = true;
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
grant execute on function crm_trocar_senha(text,text,text) to anon;

notify pgrst, 'reload schema';