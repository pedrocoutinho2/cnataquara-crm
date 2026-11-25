-- Notas internas nas conversas do WhatsApp (rede: vale para as três unidades)
-- Nota interna NÃO é mensagem: vive fora de crm_wa_mensagens, então não passa
-- por wa-send, não mexe no funil (crm_wa_msg_funil), na prévia nem em nao_lidas.

create table if not exists public.crm_wa_notas (
  id          uuid primary key default gen_random_uuid(),
  conversa_id uuid not null references public.crm_wa_conversas(id) on delete cascade,
  unidade     text not null,
  autor_id    uuid not null references public.crm_usuarios(id),
  texto       text not null check (length(btrim(texto)) between 1 and 4000),
  mencoes     uuid[] not null default '{}',
  apagada     boolean not null default false,
  created_at  timestamptz not null default now()
);
comment on table public.crm_wa_notas is 'Nota interna da equipe dentro de uma conversa do WhatsApp. Nunca é enviada ao contato. Acesso só por RPC com token de sessão.';
create index if not exists crm_wa_notas_conversa_idx on public.crm_wa_notas (conversa_id, created_at);

create table if not exists public.crm_wa_notas_mencoes (
  nota_id    uuid not null references public.crm_wa_notas(id) on delete cascade,
  usuario_id uuid not null references public.crm_usuarios(id),
  unidade    text not null,
  lida_em    timestamptz,
  primary key (nota_id, usuario_id)
);
comment on table public.crm_wa_notas_mencoes is 'Menção a um usuário numa nota interna. lida_em nulo = pendente (badge).';
create index if not exists crm_wa_notas_mencoes_pend_idx on public.crm_wa_notas_mencoes (usuario_id, unidade) where lida_em is null;

alter table public.crm_wa_notas enable row level security;
alter table public.crm_wa_notas_mencoes enable row level security;
-- sem policy de propósito: nada para anon/authenticated direto pelo PostgREST

drop trigger if exists a00_herda_unidade on public.crm_wa_notas;
create trigger a00_herda_unidade before insert or update on public.crm_wa_notas
  for each row execute function crm_herda_unidade('crm_wa_conversas', 'conversa_id');
drop trigger if exists a00_herda_unidade on public.crm_wa_notas_mencoes;
create trigger a00_herda_unidade before insert or update on public.crm_wa_notas_mencoes
  for each row execute function crm_herda_unidade('crm_wa_notas', 'nota_id');

-- Usuários que podem ser mencionados: ativos na unidade e com pelo menos "ver" em conversas
create or replace function public.crm_wa_notas_pessoas(p_token uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare s jsonb; un text;
begin
  s := crm_wa_sessao(p_token, 1); un := s->>'unidade';
  return coalesce((select jsonb_agg(jsonb_build_object('usuario_id', u.id, 'nome', u.nome) order by u.nome)
    from crm_usuario_unidades uu join crm_usuarios u on u.id = uu.usuario_id
   where uu.unidade = un and uu.ativo and u.ativo
     and crm_nivel_num(u.id, 'conversas', un) >= 1), '[]'::jsonb);
end $$;

create or replace function public.crm_wa_notas_listar(p_token uuid, p_conversa_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare s jsonb;
begin
  s := crm_wa_sessao(p_token, 1);
  perform crm_wa_conversa_do(s, p_conversa_id);
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', n.id, 'conversa_id', n.conversa_id, 'autor_id', n.autor_id, 'autor_nome', a.nome,
      'texto', case when n.apagada then null else n.texto end, 'apagada', n.apagada,
      'created_at', n.created_at,
      'mencoes', coalesce((select jsonb_agg(jsonb_build_object('usuario_id', m.usuario_id, 'nome', u.nome, 'lida_em', m.lida_em))
                   from crm_wa_notas_mencoes m join crm_usuarios u on u.id = m.usuario_id
                  where m.nota_id = n.id), '[]'::jsonb)
    ) order by n.created_at)
    from crm_wa_notas n join crm_usuarios a on a.id = n.autor_id
   where n.conversa_id = p_conversa_id and n.unidade = s->>'unidade'), '[]'::jsonb);
end $$;

create or replace function public.crm_wa_nota_criar(p_token uuid, p_conversa_id uuid, p_texto text, p_mencoes uuid[] default '{}')
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare s jsonb; un text; uid uuid; c crm_wa_conversas; v_id uuid; m uuid; v_ment uuid[] := '{}';
begin
  s := crm_wa_sessao(p_token, 1); un := s->>'unidade'; uid := (s->>'usuario_id')::uuid;
  c := crm_wa_conversa_do(s, p_conversa_id);
  if p_texto is null or length(btrim(p_texto)) = 0 then raise exception 'texto_vazio' using errcode = 'P0001'; end if;

  foreach m in array coalesce(p_mencoes, '{}') loop
    if m = uid or m = any(v_ment) then continue; end if;
    if not exists (select 1 from crm_usuario_unidades uu join crm_usuarios u on u.id = uu.usuario_id
                    where uu.usuario_id = m and uu.unidade = un and uu.ativo and u.ativo
                      and crm_nivel_num(m, 'conversas', un) >= 1) then
      raise exception 'mencao_invalida' using errcode = 'P0001';
    end if;
    v_ment := v_ment || m;
  end loop;

  insert into crm_wa_notas (conversa_id, unidade, autor_id, texto, mencoes)
    values (p_conversa_id, un, uid, btrim(p_texto), v_ment) returning id into v_id;

  foreach m in array v_ment loop
    insert into crm_wa_notas_mencoes (nota_id, usuario_id, unidade) values (v_id, m, un);
    -- quem é mencionado e não enxerga a conversa passa a segui-la
    if c.atendente_id is distinct from m and c.transf_para is distinct from m
       and not crm_wa_ve_tudo(m, un) then
      insert into crm_wa_seguidores (conversa_id, usuario_id, adicionado_por)
        values (p_conversa_id, m, uid) on conflict do nothing;
    end if;
  end loop;

  return jsonb_build_object('id', v_id, 'mencoes', to_jsonb(v_ment));
end $$;

create or replace function public.crm_wa_nota_apagar(p_token uuid, p_nota_id uuid)
returns void language plpgsql security definer set search_path to 'public' as $$
declare s jsonb; uid uuid;
begin
  s := crm_wa_sessao(p_token, 1); uid := (s->>'usuario_id')::uuid;
  update crm_wa_notas set apagada = true
   where id = p_nota_id and unidade = s->>'unidade' and autor_id = uid and not apagada;
  if not found then raise exception 'sem_permissao' using errcode = 'P0001'; end if;
end $$;

-- Badge: menções pendentes do usuário na unidade da sessão
create or replace function public.crm_wa_mencoes_pendentes(p_token uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare s jsonb; un text; uid uuid;
begin
  s := crm_wa_sessao(p_token, 0);
  if (s->>'nivel')::int < 1 then return '[]'::jsonb; end if;
  un := s->>'unidade'; uid := (s->>'usuario_id')::uuid;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'nota_id', n.id, 'conversa_id', n.conversa_id, 'autor_nome', a.nome,
      'texto', left(n.texto, 200), 'created_at', n.created_at,
      'contato', coalesce(l.nome, c.nome_contato, c.nome_perfil, c.numero_e164)
    ) order by n.created_at desc)
    from crm_wa_notas_mencoes m
    join crm_wa_notas n on n.id = m.nota_id and not n.apagada
    join crm_usuarios a on a.id = n.autor_id
    join crm_wa_conversas c on c.id = n.conversa_id
    left join crm_leads l on l.id = c.lead_id and l.unidade = un
   where m.usuario_id = uid and m.unidade = un and m.lida_em is null), '[]'::jsonb);
end $$;

-- Ao abrir a conversa: marca como lidas as menções do usuário nela
create or replace function public.crm_wa_mencoes_marcar_lidas(p_token uuid, p_conversa_id uuid)
returns integer language plpgsql security definer set search_path to 'public' as $$
declare s jsonb; n int;
begin
  s := crm_wa_sessao(p_token, 1);
  perform crm_wa_conversa_do(s, p_conversa_id);
  update crm_wa_notas_mencoes m set lida_em = now()
    from crm_wa_notas n
   where n.id = m.nota_id and n.conversa_id = p_conversa_id
     and m.usuario_id = (s->>'usuario_id')::uuid and m.unidade = s->>'unidade' and m.lida_em is null;
  get diagnostics n = row_count;
  return n;
end $$;

revoke all on function public.crm_wa_notas_pessoas(uuid) from public;
revoke all on function public.crm_wa_notas_listar(uuid, uuid) from public;
revoke all on function public.crm_wa_nota_criar(uuid, uuid, text, uuid[]) from public;
revoke all on function public.crm_wa_nota_apagar(uuid, uuid) from public;
revoke all on function public.crm_wa_mencoes_pendentes(uuid) from public;
revoke all on function public.crm_wa_mencoes_marcar_lidas(uuid, uuid) from public;
grant execute on function public.crm_wa_notas_pessoas(uuid) to anon, authenticated;
grant execute on function public.crm_wa_notas_listar(uuid, uuid) to anon, authenticated;
grant execute on function public.crm_wa_nota_criar(uuid, uuid, text, uuid[]) to anon, authenticated;
grant execute on function public.crm_wa_nota_apagar(uuid, uuid) to anon, authenticated;
grant execute on function public.crm_wa_mencoes_pendentes(uuid) to anon, authenticated;
grant execute on function public.crm_wa_mencoes_marcar_lidas(uuid, uuid) to anon, authenticated;
revoke all on public.crm_wa_notas, public.crm_wa_notas_mencoes from anon, authenticated;

notify pgrst, 'reload schema';
