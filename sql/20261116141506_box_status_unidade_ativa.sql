-- Rede. crm_box_credencial_status passa a dizer se a unidade da sessão usa o CNA Box
-- (crm_box_config.ativo), para o card do lead cobrar "falta para o Box" só onde faz sentido.
create or replace function public.crm_box_credencial_status(p_token uuid) returns jsonb
language plpgsql stable security definer set search_path to 'public' as $f$
declare s jsonb; r crm_box_credenciais; v_ativo boolean;
begin
  s := crm_box_sessao(p_token, 1);
  select coalesce(bool_or(ativo), false) into v_ativo from crm_box_config where unidade = s->>'unidade';
  select * into r from crm_box_credenciais
   where unidade = s->>'unidade' and usuario_id = (s->>'usuario_id')::uuid;
  if not found then return jsonb_build_object('conectado', false, 'box_ativo', v_ativo); end if;
  return jsonb_build_object('conectado', true, 'box_ativo', v_ativo, 'email_box', r.email_box, 'atualizado_em', r.atualizado_em,
                            'ultimo_ok_em', r.ultimo_ok_em, 'ultimo_erro', r.ultimo_erro);
end $f$;
notify pgrst, 'reload schema';