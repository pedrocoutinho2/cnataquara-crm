-- WhatsApp multi-número · W1b: RPCs da caixa de entrada (substituem o acesso direto do front às crm_wa_*).
-- Todas exigem sessão do CRM com unidade escolhida e nível no módulo 'conversas' (1 ler, 2 agir),
-- e só enxergam a unidade da sessão. Mapa do front de 01/10: linhas 4282 a 4663 do index.html.

create or replace function public.crm_wa_painel(p_token uuid)
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
declare s jsonb; un text;
begin
  s := crm_wa_sessao(p_token, 1); un := s->>'unidade';
  return jsonb_build_object(
    'eu', s,
    'contas', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'rotulo', c.rotulo, 'numero_e164', c.numero_e164, 'ambiente', c.ambiente) order by c.rotulo)
                          from crm_wa_contas c where c.unidade = un and c.ativa), '[]'::jsonb),
    'templates', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'nome', t.nome, 'idioma', t.idioma, 'corpo', t.corpo, 'variaveis', t.variaveis, 'conta_id', t.conta_id) order by t.nome)
                          from crm_wa_templates t where t.unidade = un and t.status = 'aprovado'), '[]'::jsonb));
end $function$;

create or replace function public.crm_wa_conversas_listar(p_token uuid, p_conta_id uuid default null, p_limite integer default 300)
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
declare s jsonb; un text;
begin
  s := crm_wa_sessao(p_token, 1); un := s->>'unidade';
  return coalesce((select jsonb_agg(x.j order by x.ord desc nulls last) from (
    select c.ultima_mensagem_em ord,
           to_jsonb(c) || jsonb_build_object(
             'conta_rotulo', ct.rotulo, 'conta_numero', ct.numero_e164,
             'lead', case when l.id is null then null else jsonb_build_object('id', l.id, 'nome', l.nome, 'etapa', l.etapa, 'responsavel', l.responsavel) end) j
      from crm_wa_conversas c
      join crm_wa_contas ct on ct.id = c.conta_id
      left join crm_leads l on l.id = c.lead_id and l.unidade = un
     where c.unidade = un and (p_conta_id is null or c.conta_id = p_conta_id)
     order by c.ultima_mensagem_em desc nulls last
     limit least(greatest(coalesce(p_limite, 300), 1), 500)) x), '[]'::jsonb);
end $function$;

create or replace function public.crm_wa_mensagens_listar(p_token uuid, p_conversa_id uuid, p_limite integer default 400)
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
declare s jsonb; un text;
begin
  s := crm_wa_sessao(p_token, 1); un := s->>'unidade';
  if not exists (select 1 from crm_wa_conversas where id = p_conversa_id and unidade = un) then
    raise exception 'conversa_de_outra_unidade' using errcode = 'P0001';
  end if;
  -- as N mais recentes, devolvidas em ordem cronológica
  return coalesce((select jsonb_agg(to_jsonb(m) order by m.wa_timestamp asc, m.created_at asc) from (
    select * from crm_wa_mensagens where conversa_id = p_conversa_id
     order by wa_timestamp desc nulls last, created_at desc
     limit least(greatest(coalesce(p_limite, 400), 1), 1000)) m), '[]'::jsonb);
end $function$;

create or replace function public.crm_wa_conversa_abrir(p_token uuid, p_conversa_id uuid)
 returns void language plpgsql security definer set search_path to 'public'
as $function$
declare s jsonb;
begin
  s := crm_wa_sessao(p_token, 1);
  update crm_wa_conversas set nao_lidas = 0, atendente_id = (s->>'usuario_id')::uuid
   where id = p_conversa_id and unidade = s->>'unidade' and nao_lidas > 0;
end $function$;

create or replace function public.crm_wa_conversa_vincular_lead(p_token uuid, p_conversa_id uuid, p_lead_id uuid)
 returns void language plpgsql security definer set search_path to 'public'
as $function$
declare s jsonb; un text;
begin
  s := crm_wa_sessao(p_token, 2); un := s->>'unidade';
  if not exists (select 1 from crm_leads where id = p_lead_id and unidade = un) then
    raise exception 'lead_de_outra_unidade' using errcode = 'P0001';
  end if;
  update crm_wa_conversas set lead_id = p_lead_id, lead_ambiguo = false
   where id = p_conversa_id and unidade = un;
  if not found then raise exception 'conversa_de_outra_unidade' using errcode = 'P0001'; end if;
end $function$;

create or replace function public.crm_wa_nao_lidas(p_token uuid)
 returns integer language plpgsql stable security definer set search_path to 'public'
as $function$
declare s jsonb;
begin
  s := crm_wa_sessao(p_token, 0);
  if (s->>'nivel')::int < 1 then return 0; end if;
  return coalesce((select sum(nao_lidas) from crm_wa_conversas where unidade = s->>'unidade' and nao_lidas > 0), 0)::int;
end $function$;

create or replace function public.crm_wa_fila_listar(p_token uuid, p_limite integer default 100)
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
declare s jsonb; un text;
begin
  s := crm_wa_sessao(p_token, 1); un := s->>'unidade';
  return coalesce((select jsonb_agg(x.j order by x.ord) from (
    select f.agendado_para ord,
           to_jsonb(f) || jsonb_build_object(
             'lead', case when l.id is null then null else jsonb_build_object('id', l.id, 'nome', l.nome, 'whatsapp', l.whatsapp) end,
             'regra', case when r.id is null then null else jsonb_build_object('chave', r.chave, 'nome', r.nome, 'categoria', r.categoria) end) j
      from crm_wa_fila f
      left join crm_leads l on l.id = f.lead_id and l.unidade = un
      left join crm_wa_regras r on r.id = f.regra_id
     where f.unidade = un and f.status = 'sugerido'
     order by f.agendado_para asc
     limit least(greatest(coalesce(p_limite, 100), 1), 300)) x), '[]'::jsonb);
end $function$;

create or replace function public.crm_wa_fila_decidir(p_token uuid, p_id uuid, p_status text, p_mensagem_id uuid default null)
 returns void language plpgsql security definer set search_path to 'public'
as $function$
declare s jsonb;
begin
  s := crm_wa_sessao(p_token, 2);
  if p_status not in ('enviado', 'descartado') then raise exception 'status_invalido' using errcode = 'P0001'; end if;
  update crm_wa_fila set status = p_status, decidido_por = s->>'nome', decidido_em = now(),
                         mensagem_id = coalesce(p_mensagem_id, mensagem_id)
   where id = p_id and unidade = s->>'unidade' and status = 'sugerido';
  if not found then raise exception 'sugestao_indisponivel' using errcode = 'P0001'; end if;
end $function$;

do $$
declare f text;
begin
  foreach f in array array['crm_wa_painel(uuid)','crm_wa_conversas_listar(uuid,uuid,integer)','crm_wa_mensagens_listar(uuid,uuid,integer)',
                           'crm_wa_conversa_abrir(uuid,uuid)','crm_wa_conversa_vincular_lead(uuid,uuid,uuid)','crm_wa_nao_lidas(uuid)',
                           'crm_wa_fila_listar(uuid,integer)','crm_wa_fila_decidir(uuid,uuid,text,uuid)'] loop
    execute format('revoke all on function public.%s from public', f);
    execute format('grant execute on function public.%s to anon, authenticated', f);
  end loop;
end $$;

notify pgrst, 'reload schema';