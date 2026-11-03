-- WhatsApp multi-número · W1: validação de sessão do CRM para as Edge Functions (wa-send, wa-media).
-- Recebe o token de sessão que o front já guarda e devolve quem é, de qual unidade e o nível no
-- módulo 'conversas'. Só service_role executa: a chave anon do HTML não chama isto direto.
create or replace function public.crm_wa_sessao(p_token uuid, p_min integer default 1)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare uid uuid; un text; u crm_usuarios; nv int;
begin
  select usuario_id, unidade into uid, un from crm_sessoes where token = p_token and expira_em > now();
  if uid is null then raise exception 'sessao_invalida' using errcode = 'P0001'; end if;
  if un is null then raise exception 'unidade_nao_escolhida' using errcode = 'P0001'; end if;
  select * into u from crm_usuarios where id = uid and ativo;
  if not found then raise exception 'sessao_invalida' using errcode = 'P0001'; end if;
  nv := crm_nivel_num(uid, 'conversas', un);
  if nv < p_min then raise exception 'sem_permissao' using errcode = 'P0001'; end if;
  return jsonb_build_object('usuario_id', u.id, 'nome', u.nome, 'unidade', un, 'nivel', nv);
end $function$;

revoke all on function public.crm_wa_sessao(uuid, integer) from public, anon, authenticated;
grant execute on function public.crm_wa_sessao(uuid, integer) to service_role;