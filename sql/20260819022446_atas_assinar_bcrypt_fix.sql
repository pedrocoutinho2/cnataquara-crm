create or replace function crm_ata_assinar(p_reuniao uuid, p_email text, p_senha text, p_ua text default null)
returns jsonb language plpgsql security definer set search_path to 'public','extensions' as $$
declare v_u record; v_r record; v_hash text; v_falta int;
begin
  select * into v_u from crm_usuarios
   where email is not null and lower(btrim(email)) = lower(btrim(p_email)) and ativo = true;
  if not found or v_u.senha_hash is null then
    return jsonb_build_object('ok', false, 'erro', 'credenciais');
  end if;
  if v_u.senha_hash <> extensions.crypt(p_senha, v_u.senha_hash) then
    return jsonb_build_object('ok', false, 'erro', 'credenciais');
  end if;

  select * into v_r from crm_reunioes where id = p_reuniao;
  if not found then return jsonb_build_object('ok', false, 'erro', 'reuniao'); end if;
  if v_r.status not in ('em_assinatura','assinada') or v_r.hash_documento is null then
    return jsonb_build_object('ok', false, 'erro', 'nao_congelada');
  end if;
  if not exists (select 1 from crm_reuniao_participantes
                  where reuniao_id = p_reuniao and nome = v_u.nome and deve_assinar) then
    return jsonb_build_object('ok', false, 'erro', 'nao_participante');
  end if;

  v_hash := encode(extensions.digest(v_r.hash_documento||'|'||v_u.nome||'|'||clock_timestamp()::text,'sha256'),'hex');
  insert into crm_reuniao_assinaturas (reuniao_id, nome, email, hash_documento, hash_assinatura, user_agent)
  values (p_reuniao, v_u.nome, v_u.email, v_r.hash_documento, v_hash, p_ua)
  on conflict (reuniao_id, nome) do nothing;

  select count(*) into v_falta
    from crm_reuniao_participantes p
   where p.reuniao_id = p_reuniao and p.deve_assinar
     and not exists (select 1 from crm_reuniao_assinaturas a
                      where a.reuniao_id = p_reuniao and a.nome = p.nome);
  if v_falta = 0 then
    update crm_reunioes set status = 'assinada', atualizado_em = now() where id = p_reuniao;
  end if;

  return jsonb_build_object('ok', true, 'nome', v_u.nome, 'faltam', v_falta,
                            'hash', v_hash, 'completa', v_falta = 0);
end $$;

create or replace function crm_ata_congelar(p_reuniao uuid)
returns text language plpgsql security definer set search_path to 'public','extensions' as $$
declare v_hash text; v_base text; v_st text;
begin
  select status,
         coalesce(ata_bruta,'')||'|'||coalesce(resumo,'')||'|'||coalesce(decisoes::text,'[]')
         ||'|'||coalesce(pendencias::text,'[]')||'|'||to_char(data,'YYYY-MM-DD')||'|'||coalesce(titulo,'')
    into v_st, v_base from crm_reunioes where id = p_reuniao;
  if v_st is null then raise exception 'reuniao nao encontrada'; end if;
  if v_st not in ('rascunho','analisada') then
    return (select hash_documento from crm_reunioes where id = p_reuniao);
  end if;
  v_hash := encode(extensions.digest(v_base,'sha256'),'hex');
  update crm_reunioes set hash_documento = v_hash, congelada_em = now(),
         status = 'em_assinatura', atualizado_em = now() where id = p_reuniao;
  return v_hash;
end $$;

notify pgrst, 'reload schema';