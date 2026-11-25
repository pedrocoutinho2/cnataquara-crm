CREATE OR REPLACE FUNCTION public.crm_wa_painel(p_token uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s jsonb; un text; uid uuid; vt boolean;
begin
  s := crm_wa_sessao(p_token, 1); un := s->>'unidade'; uid := (s->>'usuario_id')::uuid;
  vt := crm_wa_ve_tudo(uid, un);
  return jsonb_build_object(
    'eu', s || jsonb_build_object('ve_tudo', vt),
    'contas', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'rotulo', c.rotulo, 'numero_e164', c.numero_e164, 'ambiente', c.ambiente, 'provider', c.provider, 'principal', c.principal) order by c.principal desc, c.rotulo)
                          from crm_wa_contas c where c.unidade = un and c.ativa), '[]'::jsonb),
    'templates', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'nome', t.nome, 'idioma', t.idioma, 'corpo', t.corpo, 'variaveis', t.variaveis, 'conta_id', t.conta_id) order by t.nome)
                          from crm_wa_templates t where t.unidade = un and t.status = 'aprovado'), '[]'::jsonb),
    -- todos os agentes aparecem para todos (transferir e acompanhar); contagens só para a gestão
    'agentes', coalesce((select jsonb_agg(jsonb_build_object(
                  'usuario_id', a.usuario_id, 'nome', a.nome, 'no_rodizio', a.no_rodizio,
                  'abertas', case when vt then (select count(*) from crm_wa_conversas c where c.unidade = un and c.atendente_id = a.usuario_id and c.status <> 'resolvida') end,
                  'nao_lidas', case when vt then (select coalesce(sum(c.nao_lidas), 0) from crm_wa_conversas c where c.unidade = un and c.atendente_id = a.usuario_id) end)
                  order by a.nome)
                from crm_wa_agentes(un) a), '[]'::jsonb),
    'sem_dono', case when vt then (select count(*) from crm_wa_conversas c where c.unidade = un and c.atendente_id is null) else 0 end,
    'transf_para_mim', (select count(*) from crm_wa_conversas c where c.unidade = un and c.transf_para = uid));
end $function$;
notify pgrst, 'reload schema';