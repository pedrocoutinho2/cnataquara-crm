-- W3a: caixa de entrada precisa saber o transporte da conta (Evolution não tem janela de 24h nem template).
-- Só acrescenta campos ao retorno; assinatura e regras iguais.
create or replace function public.crm_wa_painel(p_token uuid)
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
declare s jsonb; un text;
begin
  s := crm_wa_sessao(p_token, 1); un := s->>'unidade';
  return jsonb_build_object(
    'eu', s,
    'contas', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'rotulo', c.rotulo, 'numero_e164', c.numero_e164, 'ambiente', c.ambiente, 'provider', c.provider) order by c.rotulo)
                          from crm_wa_contas c where c.unidade = un and c.ativa), '[]'::jsonb),
    'templates', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'nome', t.nome, 'idioma', t.idioma, 'corpo', t.corpo, 'variaveis', t.variaveis, 'conta_id', t.conta_id) order by t.nome)
                          from crm_wa_templates t where t.unidade = un and t.status = 'aprovado'), '[]'::jsonb));
end $function$;

create or replace function public.crm_wa_conversas_listar(p_token uuid, p_conta_id uuid default null::uuid, p_limite integer default 300)
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
declare s jsonb; un text;
begin
  s := crm_wa_sessao(p_token, 1); un := s->>'unidade';
  return coalesce((select jsonb_agg(x.j order by x.ord desc nulls last) from (
    select c.ultima_mensagem_em ord,
           to_jsonb(c) || jsonb_build_object(
             'conta_rotulo', ct.rotulo, 'conta_numero', ct.numero_e164, 'conta_provider', ct.provider,
             'lead', case when l.id is null then null else jsonb_build_object('id', l.id, 'nome', l.nome, 'etapa', l.etapa, 'responsavel', l.responsavel) end) j
      from crm_wa_conversas c
      join crm_wa_contas ct on ct.id = c.conta_id
      left join crm_leads l on l.id = c.lead_id and l.unidade = un
     where c.unidade = un and (p_conta_id is null or c.conta_id = p_conta_id)
     order by c.ultima_mensagem_em desc nulls last
     limit least(greatest(coalesce(p_limite, 300), 1), 500)) x), '[]'::jsonb);
end $function$;

notify pgrst, 'reload schema';