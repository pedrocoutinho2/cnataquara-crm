-- wa_w5_acompanhar_transferencia_sugestao · CRM CNA (gpnwmsnayrqjcmhqrtpx) · escopo: rede
-- Pedido do Pedro em 16/11/2026:
--  * Acompanhar: outro consultor vê (e pode ajudar a responder) a conversa sem assumir o lead.
--  * Transferência entre consultores com aceite: o dono envia, o destino aceita ou recusa.
--    Gestão transfere direto, de qualquer um para qualquer um.
--  * Dono da conversa e responsável do lead andam juntos (nos dois sentidos).
--  * Sugestão de etapa (IA) em modo sugestão: consultor aceita ou ignora.
--  * Celular: edição, exclusão e reação feitas no WhatsApp chegam ao CRM.
--  * Histórico importado vira lead (data real do primeiro contato; etapa deduzida da conversa).

alter table public.crm_wa_conversas
  add column if not exists transf_para uuid references public.crm_usuarios(id) on delete set null,
  add column if not exists transf_de uuid references public.crm_usuarios(id) on delete set null,
  add column if not exists transf_em timestamptz,
  add column if not exists sugestao_etapa text,
  add column if not exists sugestao_motivo text,
  add column if not exists sugestao_em timestamptz,
  add column if not exists sugestao_status text;

alter table public.crm_wa_mensagens
  add column if not exists editada boolean not null default false,
  add column if not exists apagada boolean not null default false,
  add column if not exists reacoes jsonb not null default '{}'::jsonb;

create table if not exists public.crm_wa_seguidores (
  conversa_id uuid not null references public.crm_wa_conversas(id) on delete cascade,
  usuario_id uuid not null references public.crm_usuarios(id) on delete cascade,
  unidade text references public.crm_unidades(slug),
  adicionado_por uuid references public.crm_usuarios(id) on delete set null,
  criado_em timestamptz not null default now(),
  primary key (conversa_id, usuario_id)
);
alter table public.crm_wa_seguidores enable row level security;
revoke all on public.crm_wa_seguidores from anon, authenticated;
drop trigger if exists a00_herda_unidade on public.crm_wa_seguidores;
create trigger a00_herda_unidade before insert or update on public.crm_wa_seguidores
  for each row execute function public.crm_herda_unidade('crm_wa_conversas', 'conversa_id');

-- acesso a uma conversa: gestão, dono, quem acompanha ou destino de transferência pendente
create or replace function public.crm_wa_conversa_do(s jsonb, p_conversa_id uuid)
returns crm_wa_conversas language plpgsql stable security definer set search_path = public as $$
declare c crm_wa_conversas; uid uuid := (s->>'usuario_id')::uuid;
begin
  select * into c from crm_wa_conversas where id = p_conversa_id and unidade = s->>'unidade';
  if not found then raise exception 'conversa_de_outra_unidade' using errcode = 'P0001'; end if;
  if c.atendente_id is distinct from uid and c.transf_para is distinct from uid
     and not exists (select 1 from crm_wa_seguidores f where f.conversa_id = c.id and f.usuario_id = uid)
     and not crm_wa_ve_tudo(uid, s->>'unidade') then
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
    -- todos os agentes aparecem para todos (transferir e acompanhar); contagens só para a gestão
    'agentes', coalesce((select jsonb_agg(jsonb_build_object(
                  'usuario_id', a.usuario_id, 'nome', a.nome, 'no_rodizio', a.no_rodizio,
                  'abertas', case when vt then (select count(*) from crm_wa_conversas c where c.unidade = un and c.atendente_id = a.usuario_id and c.status <> 'resolvida') end,
                  'nao_lidas', case when vt then (select coalesce(sum(c.nao_lidas), 0) from crm_wa_conversas c where c.unidade = un and c.atendente_id = a.usuario_id) end)
                  order by a.nome)
                from crm_wa_agentes(un) a), '[]'::jsonb),
    'sem_dono', case when vt then (select count(*) from crm_wa_conversas c where c.unidade = un and c.atendente_id is null) else 0 end,
    'transf_para_mim', (select count(*) from crm_wa_conversas c where c.unidade = un and c.transf_para = uid));
end $$;

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
             'transf_para_nome', tp.nome, 'transf_de_nome', td.nome,
             'acompanho', exists (select 1 from crm_wa_seguidores f where f.conversa_id = c.id and f.usuario_id = uid),
             'seguidores', coalesce((select jsonb_agg(jsonb_build_object('usuario_id', f.usuario_id, 'nome', u.nome) order by u.nome)
                                       from crm_wa_seguidores f join crm_usuarios u on u.id = f.usuario_id where f.conversa_id = c.id), '[]'::jsonb),
             'lead', case when l.id is null then null else jsonb_build_object('id', l.id, 'nome', l.nome, 'etapa', l.etapa, 'responsavel', l.responsavel) end) j
      from crm_wa_conversas c
      join crm_wa_contas ct on ct.id = c.conta_id
      left join crm_usuarios au on au.id = c.atendente_id
      left join crm_usuarios tp on tp.id = c.transf_para
      left join crm_usuarios td on td.id = c.transf_de
      left join crm_leads l on l.id = c.lead_id and l.unidade = un
     where c.unidade = un and (p_conta_id is null or c.conta_id = p_conta_id)
       and case when not vt then (c.atendente_id = uid or c.transf_para = uid
                                  or exists (select 1 from crm_wa_seguidores f where f.conversa_id = c.id and f.usuario_id = uid))
                when p_sem_dono then c.atendente_id is null
                when p_atendente is not null then c.atendente_id = p_atendente
                else true end
     order by c.ultima_mensagem_em desc nulls last
     limit least(greatest(coalesce(p_limite, 300), 1), 500)) x), '[]'::jsonb);
end $$;

-- aplica a troca de dono e leva o responsável do lead junto
create or replace function public.crm_wa_aplicar_transferencia(p_conversa_id uuid, p_usuario_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare c crm_wa_conversas; v_nome text;
begin
  select * into c from crm_wa_conversas where id = p_conversa_id;
  select a.nome into v_nome from crm_wa_agentes(c.unidade) a where a.usuario_id = p_usuario_id;
  if v_nome is null then raise exception 'agente_invalido' using errcode = 'P0001'; end if;
  update crm_wa_conversas set atendente_id = p_usuario_id, atribuicao = 'manual', atribuida_em = now(),
         transf_para = null, transf_de = null, transf_em = null
   where id = p_conversa_id;
  if c.lead_id is not null then
    update crm_leads set responsavel = v_nome where id = c.lead_id and unidade = c.unidade and responsavel is distinct from v_nome;
  end if;
  return v_nome;
end $$;
revoke execute on function public.crm_wa_aplicar_transferencia(uuid, uuid) from public, anon, authenticated;

-- gestão: troca na hora. Dono (consultor): fica pendente até o destino aceitar.
create or replace function public.crm_wa_conversa_transferir(p_token uuid, p_conversa_id uuid, p_usuario_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s jsonb; un text; uid uuid; c crm_wa_conversas; nome text;
begin
  s := crm_wa_sessao(p_token, 2); un := s->>'unidade'; uid := (s->>'usuario_id')::uuid;
  c := crm_wa_conversa_do(s, p_conversa_id);
  select a.nome into nome from crm_wa_agentes(un) a where a.usuario_id = p_usuario_id;
  if nome is null then raise exception 'agente_invalido' using errcode = 'P0001'; end if;
  if crm_wa_ve_tudo(uid, un) then
    perform crm_wa_aplicar_transferencia(p_conversa_id, p_usuario_id);
    return jsonb_build_object('pendente', false, 'atendente_id', p_usuario_id, 'atendente_nome', nome);
  end if;
  if c.atendente_id is distinct from uid then raise exception 'so_o_dono_transfere' using errcode = 'P0001'; end if;
  if p_usuario_id = uid then raise exception 'agente_invalido' using errcode = 'P0001'; end if;
  update crm_wa_conversas set transf_para = p_usuario_id, transf_de = uid, transf_em = now() where id = p_conversa_id;
  return jsonb_build_object('pendente', true, 'para_nome', nome);
end $$;

-- destino aceita ou recusa; quem enviou (ou a gestão) pode cancelar
create or replace function public.crm_wa_transferencia_decidir(p_token uuid, p_conversa_id uuid, p_aceitar boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s jsonb; un text; uid uuid; c crm_wa_conversas; vt boolean; nome text;
begin
  s := crm_wa_sessao(p_token, 2); un := s->>'unidade'; uid := (s->>'usuario_id')::uuid;
  c := crm_wa_conversa_do(s, p_conversa_id);
  vt := crm_wa_ve_tudo(uid, un);
  if c.transf_para is null then raise exception 'sem_transferencia' using errcode = 'P0001'; end if;
  if p_aceitar then
    if c.transf_para <> uid and not vt then raise exception 'sem_permissao' using errcode = 'P0001'; end if;
    nome := crm_wa_aplicar_transferencia(p_conversa_id, c.transf_para);
    return jsonb_build_object('aceita', true, 'atendente_nome', nome);
  end if;
  if c.transf_para <> uid and c.transf_de is distinct from uid and not vt then raise exception 'sem_permissao' using errcode = 'P0001'; end if;
  update crm_wa_conversas set transf_para = null, transf_de = null, transf_em = null where id = p_conversa_id;
  return jsonb_build_object('aceita', false);
end $$;

-- acompanhar: dono ou gestão adicionam/removem qualquer agente; quem acompanha pode sair
create or replace function public.crm_wa_seguir(p_token uuid, p_conversa_id uuid, p_usuario_id uuid, p_seguir boolean)
returns void language plpgsql security definer set search_path = public as $$
declare s jsonb; un text; uid uuid; c crm_wa_conversas;
begin
  s := crm_wa_sessao(p_token, 2); un := s->>'unidade'; uid := (s->>'usuario_id')::uuid;
  c := crm_wa_conversa_do(s, p_conversa_id);
  if not (crm_wa_ve_tudo(uid, un) or c.atendente_id = uid or (p_usuario_id = uid and not p_seguir)) then
    raise exception 'sem_permissao' using errcode = 'P0001';
  end if;
  if p_seguir then
    if not exists (select 1 from crm_wa_agentes(un) a where a.usuario_id = p_usuario_id) then
      raise exception 'agente_invalido' using errcode = 'P0001';
    end if;
    if p_usuario_id = c.atendente_id then return; end if;
    insert into crm_wa_seguidores(conversa_id, usuario_id, adicionado_por) values (p_conversa_id, p_usuario_id, uid)
      on conflict do nothing;
  else
    delete from crm_wa_seguidores where conversa_id = p_conversa_id and usuario_id = p_usuario_id;
  end if;
end $$;

create or replace function public.crm_wa_sugestao_decidir(p_token uuid, p_conversa_id uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
declare s jsonb;
begin
  s := crm_wa_sessao(p_token, 2);
  if p_status not in ('aceita', 'ignorada') then raise exception 'status_invalido' using errcode = 'P0001'; end if;
  perform crm_wa_conversa_do(s, p_conversa_id);
  update crm_wa_conversas set sugestao_status = p_status where id = p_conversa_id;
end $$;

-- responsável trocado na ficha do lead leva o dono da conversa junto
create or replace function public.crm_wa_lead_responsavel_sync()
returns trigger language plpgsql security definer set search_path = public as $$
declare ag uuid;
begin
  if new.responsavel is not distinct from old.responsavel then return new; end if;
  select a.usuario_id into ag from crm_wa_agentes(new.unidade) a where a.nome = new.responsavel limit 1;
  if ag is null then return new; end if;
  update crm_wa_conversas set atendente_id = ag, atribuicao = 'lead', atribuida_em = now(),
         transf_para = null, transf_de = null, transf_em = null
   where lead_id = new.id and unidade = new.unidade and atendente_id is distinct from ag;
  return new;
end $$;
drop trigger if exists z_wa_lead_responsavel_sync on public.crm_leads;
create trigger z_wa_lead_responsavel_sync after update of responsavel on public.crm_leads
  for each row execute function public.crm_wa_lead_responsavel_sync();

-- histórico vira lead: conversa sem lead ganha um (ou é ligada ao lead que já existe pelo número)
create or replace function public.crm_wa_leads_do_historico(p_conta uuid)
returns integer language plpgsql security definer set search_path = public as $$
declare c record; lid uuid; n int := 0; resp text; prim timestamptz; ult timestamptz;
        tem_in boolean; tem_out boolean; et text; num text; fmt text;
begin
  for c in select * from crm_wa_conversas where conta_id = p_conta and lead_id is null loop
    lid := null;
    if c.wa_chave is not null then
      select id into lid from crm_leads where unidade = c.unidade and wa_chave = c.wa_chave order by created_at desc limit 1;
    end if;
    if lid is null then
      select min(wa_timestamp), max(wa_timestamp), bool_or(direcao = 'entrada'), bool_or(direcao = 'saida')
        into prim, ult, tem_in, tem_out from crm_wa_mensagens where conversa_id = c.id;
      et := case when tem_in and tem_out then 'respondeu' when tem_out then 'contato_feito' else 'novo' end;
      num := regexp_replace(regexp_replace(coalesce(c.wa_id, ''), '\D', '', 'g'), '^55', '');
      fmt := case length(num)
               when 11 then '(' || substr(num, 1, 2) || ') ' || substr(num, 3, 5) || '-' || substr(num, 8)
               when 10 then '(' || substr(num, 1, 2) || ') ' || substr(num, 3, 4) || '-' || substr(num, 7)
               else num end;
      select nome into resp from crm_usuarios where id = c.atendente_id;
      insert into crm_leads (unidade, nome, whatsapp, etapa, origem, responsavel, data_entrada,
                             proximo_atendimento, proximo_atendimento_hora, proximo_canal)
      values (c.unidade, coalesce(nullif(btrim(c.nome_perfil), ''), 'WhatsApp ' || fmt), fmt, et, 'WhatsApp', resp,
              coalesce((prim at time zone 'America/Sao_Paulo')::date, crm_hoje_br()),
              coalesce((ult at time zone 'America/Sao_Paulo')::date + 1, crm_hoje_br()), '10:00', 'whatsapp')
      returning id into lid;
      n := n + 1;
    end if;
    update crm_wa_conversas set lead_id = lid where id = c.id;
  end loop;
  return n;
end $$;
revoke execute on function public.crm_wa_leads_do_historico(uuid) from public, anon, authenticated;

grant execute on function public.crm_wa_transferencia_decidir(uuid, uuid, boolean) to anon;
grant execute on function public.crm_wa_seguir(uuid, uuid, uuid, boolean) to anon;
grant execute on function public.crm_wa_sugestao_decidir(uuid, uuid, text) to anon;

notify pgrst, 'reload schema';