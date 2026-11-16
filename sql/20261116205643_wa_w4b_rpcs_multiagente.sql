-- wa_w4b_rpcs_multiagente · CRM CNA (gpnwmsnayrqjcmhqrtpx) · escopo: rede
-- Visibilidade por agente nas RPCs da caixa de entrada + ações de gestão.
-- Consultor: só conversas com atendente_id = ele. Gestão (crm_wa_ve_tudo): todas da unidade.

-- acesso a uma conversa pela sessão (erro se não pode)
create or replace function public.crm_wa_conversa_do(s jsonb, p_conversa_id uuid)
returns crm_wa_conversas language plpgsql stable security definer set search_path = public as $$
declare c crm_wa_conversas;
begin
  select * into c from crm_wa_conversas where id = p_conversa_id and unidade = s->>'unidade';
  if not found then raise exception 'conversa_de_outra_unidade' using errcode = 'P0001'; end if;
  if c.atendente_id is distinct from (s->>'usuario_id')::uuid
     and not crm_wa_ve_tudo((s->>'usuario_id')::uuid, s->>'unidade') then
    raise exception 'conversa_de_outro_agente' using errcode = 'P0001';
  end if;
  return c;
end $$;
revoke execute on function public.crm_wa_conversa_do(jsonb, uuid) from public, anon, authenticated;

create or replace function public.crm_wa_painel(p_token uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare s jsonb; un text; uid uuid; vt boolean;
begin
  s := crm_wa_sessao(p_token, 1); un := s->>'unidade'; uid := (s->>'usuario_id')::uuid;
  vt := crm_wa_ve_tudo(uid, un);
  return jsonb_build_object(
    'eu', s || jsonb_build_object('ve_tudo', vt),
    'contas', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'rotulo', c.rotulo, 'numero_e164', c.numero_e164, 'ambiente', c.ambiente, 'provider', c.provider) order by c.rotulo)
                          from crm_wa_contas c where c.unidade = un and c.ativa), '[]'::jsonb),
    'templates', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'nome', t.nome, 'idioma', t.idioma, 'corpo', t.corpo, 'variaveis', t.variaveis, 'conta_id', t.conta_id) order by t.nome)
                          from crm_wa_templates t where t.unidade = un and t.status = 'aprovado'), '[]'::jsonb),
    'agentes', coalesce((select jsonb_agg(jsonb_build_object(
                  'usuario_id', a.usuario_id, 'nome', a.nome, 'no_rodizio', a.no_rodizio,
                  'abertas', (select count(*) from crm_wa_conversas c where c.unidade = un and c.atendente_id = a.usuario_id and c.status <> 'resolvida'),
                  'nao_lidas', (select coalesce(sum(c.nao_lidas), 0) from crm_wa_conversas c where c.unidade = un and c.atendente_id = a.usuario_id))
                  order by a.nome)
                from crm_wa_agentes(un) a where vt or a.usuario_id = uid), '[]'::jsonb),
    'sem_dono', case when vt then (select count(*) from crm_wa_conversas c where c.unidade = un and c.atendente_id is null) else 0 end);
end $$;

drop function if exists public.crm_wa_conversas_listar(uuid, uuid, integer);
create or replace function public.crm_wa_conversas_listar(p_token uuid, p_conta_id uuid default null, p_limite integer default 300,
                                                          p_atendente uuid default null, p_sem_dono boolean default false)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare s jsonb; un text; uid uuid; vt boolean;
begin
  s := crm_wa_sessao(p_token, 1); un := s->>'unidade'; uid := (s->>'usuario_id')::uuid;
  vt := crm_wa_ve_tudo(uid, un);
  return coalesce((select jsonb_agg(x.j order by x.ord desc nulls last) from (
    select c.ultima_mensagem_em ord,
           to_jsonb(c) || jsonb_build_object(
             'conta_rotulo', ct.rotulo, 'conta_numero', ct.numero_e164, 'conta_provider', ct.provider,
             'atendente_nome', au.nome,
             'lead', case when l.id is null then null else jsonb_build_object('id', l.id, 'nome', l.nome, 'etapa', l.etapa, 'responsavel', l.responsavel) end) j
      from crm_wa_conversas c
      join crm_wa_contas ct on ct.id = c.conta_id
      left join crm_usuarios au on au.id = c.atendente_id
      left join crm_leads l on l.id = c.lead_id and l.unidade = un
     where c.unidade = un and (p_conta_id is null or c.conta_id = p_conta_id)
       and case when not vt then c.atendente_id = uid
                when p_sem_dono then c.atendente_id is null
                when p_atendente is not null then c.atendente_id = p_atendente
                else true end
     order by c.ultima_mensagem_em desc nulls last
     limit least(greatest(coalesce(p_limite, 300), 1), 500)) x), '[]'::jsonb);
end $$;

create or replace function public.crm_wa_mensagens_listar(p_token uuid, p_conversa_id uuid, p_limite integer default 400)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare s jsonb;
begin
  s := crm_wa_sessao(p_token, 1);
  perform crm_wa_conversa_do(s, p_conversa_id);
  return coalesce((select jsonb_agg(to_jsonb(m) order by m.wa_timestamp asc, m.created_at asc) from (
    select * from crm_wa_mensagens where conversa_id = p_conversa_id
     order by wa_timestamp desc nulls last, created_at desc
     limit least(greatest(coalesce(p_limite, 400), 1), 1000)) m), '[]'::jsonb);
end $$;

-- abrir marca como lida só para o dono (ou sem dono, pela gestão); não troca mais o atendente
create or replace function public.crm_wa_conversa_abrir(p_token uuid, p_conversa_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare s jsonb; c crm_wa_conversas;
begin
  s := crm_wa_sessao(p_token, 1);
  c := crm_wa_conversa_do(s, p_conversa_id);
  if c.nao_lidas > 0 and (c.atendente_id = (s->>'usuario_id')::uuid or c.atendente_id is null) then
    update crm_wa_conversas set nao_lidas = 0 where id = c.id;
  end if;
end $$;

create or replace function public.crm_wa_conversa_vincular_lead(p_token uuid, p_conversa_id uuid, p_lead_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare s jsonb; un text;
begin
  s := crm_wa_sessao(p_token, 2); un := s->>'unidade';
  perform crm_wa_conversa_do(s, p_conversa_id);
  if not exists (select 1 from crm_leads where id = p_lead_id and unidade = un) then
    raise exception 'lead_de_outra_unidade' using errcode = 'P0001';
  end if;
  update crm_wa_conversas set lead_id = p_lead_id, lead_ambiguo = false where id = p_conversa_id and unidade = un;
end $$;

create or replace function public.crm_wa_nao_lidas(p_token uuid)
returns integer language plpgsql stable security definer set search_path = public as $$
declare s jsonb; un text; uid uuid;
begin
  s := crm_wa_sessao(p_token, 0);
  if (s->>'nivel')::int < 1 then return 0; end if;
  un := s->>'unidade'; uid := (s->>'usuario_id')::uuid;
  if crm_wa_ve_tudo(uid, un) then
    return coalesce((select sum(nao_lidas) from crm_wa_conversas where unidade = un and nao_lidas > 0
                       and (atendente_id = uid or atendente_id is null)), 0)::int;
  end if;
  return coalesce((select sum(nao_lidas) from crm_wa_conversas where unidade = un and atendente_id = uid and nao_lidas > 0), 0)::int;
end $$;

-- transferir: gestão transfere qualquer conversa; consultor só a própria
create or replace function public.crm_wa_conversa_transferir(p_token uuid, p_conversa_id uuid, p_usuario_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s jsonb; un text; nome text;
begin
  s := crm_wa_sessao(p_token, 2); un := s->>'unidade';
  perform crm_wa_conversa_do(s, p_conversa_id);
  select a.nome into nome from crm_wa_agentes(un) a where a.usuario_id = p_usuario_id;
  if nome is null then raise exception 'agente_invalido' using errcode = 'P0001'; end if;
  update crm_wa_conversas set atendente_id = p_usuario_id, atribuicao = 'manual', atribuida_em = now()
   where id = p_conversa_id and unidade = un;
  return jsonb_build_object('atendente_id', p_usuario_id, 'atendente_nome', nome);
end $$;

-- gestão: distribui as sem dono pelo rodízio (mais antigas primeiro)
create or replace function public.crm_wa_distribuir_sem_dono(p_token uuid)
returns integer language plpgsql security definer set search_path = public as $$
declare s jsonb; un text; c record; ag uuid; n int := 0;
begin
  s := crm_wa_sessao(p_token, 2); un := s->>'unidade';
  if not crm_wa_ve_tudo((s->>'usuario_id')::uuid, un) then raise exception 'sem_permissao' using errcode = 'P0001'; end if;
  for c in select id, lead_id from crm_wa_conversas where unidade = un and atendente_id is null
           order by ultima_mensagem_em asc nulls first for update loop
    ag := case when c.lead_id is not null then crm_wa_dono_do_lead(c.lead_id, un) end;
    if ag is null then ag := crm_wa_proximo_agente(un); end if;
    exit when ag is null;
    update crm_wa_conversas set atendente_id = ag, atribuicao = 'distribuida', atribuida_em = now() where id = c.id;
    n := n + 1;
  end loop;
  return n;
end $$;

create or replace function public.crm_wa_conversa_status(p_token uuid, p_conversa_id uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
declare s jsonb;
begin
  s := crm_wa_sessao(p_token, 2);
  if p_status not in ('aberta', 'pendente', 'resolvida') then raise exception 'status_invalido' using errcode = 'P0001'; end if;
  perform crm_wa_conversa_do(s, p_conversa_id);
  update crm_wa_conversas set status = p_status, updated_at = now() where id = p_conversa_id;
end $$;

-- gestão liga/desliga uma pessoa no rodízio (null volta ao padrão do papel)
create or replace function public.crm_wa_agente_rodizio(p_token uuid, p_usuario_id uuid, p_rodizio boolean)
returns void language plpgsql security definer set search_path = public as $$
declare s jsonb; un text;
begin
  s := crm_wa_sessao(p_token, 2); un := s->>'unidade';
  if not crm_wa_ve_tudo((s->>'usuario_id')::uuid, un) then raise exception 'sem_permissao' using errcode = 'P0001'; end if;
  update crm_usuario_unidades set wa_rodizio = p_rodizio where usuario_id = p_usuario_id and unidade = un and ativo;
  if not found then raise exception 'agente_invalido' using errcode = 'P0001'; end if;
end $$;

grant execute on function public.crm_wa_painel(uuid) to anon;
grant execute on function public.crm_wa_conversas_listar(uuid, uuid, integer, uuid, boolean) to anon;
grant execute on function public.crm_wa_mensagens_listar(uuid, uuid, integer) to anon;
grant execute on function public.crm_wa_conversa_abrir(uuid, uuid) to anon;
grant execute on function public.crm_wa_conversa_vincular_lead(uuid, uuid, uuid) to anon;
grant execute on function public.crm_wa_nao_lidas(uuid) to anon;
grant execute on function public.crm_wa_conversa_transferir(uuid, uuid, uuid) to anon;
grant execute on function public.crm_wa_distribuir_sem_dono(uuid) to anon;
grant execute on function public.crm_wa_conversa_status(uuid, uuid, text) to anon;
grant execute on function public.crm_wa_agente_rodizio(uuid, uuid, boolean) to anon;

notify pgrst, 'reload schema';
