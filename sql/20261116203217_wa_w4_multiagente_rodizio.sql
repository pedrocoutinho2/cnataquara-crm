-- wa_w4_multiagente_rodizio · CRM CNA (gpnwmsnayrqjcmhqrtpx) · escopo: rede (Taquara, Queimados, Jardim América)
-- Pedido do Pedro em 16/11/2026: cada consultor comercial é um agente com as próprias conversas,
-- e conversa nova entra por divisão automática (rodízio) entre os consultores da unidade.
--
-- Regras:
--  * Agente = vínculo ativo na unidade, nível >= editar em Conversas e no rodízio.
--    No rodízio por padrão: papel comercial ou flag consultor. A gestão liga/desliga por pessoa
--    (crm_usuario_unidades.wa_rodizio; null = padrão).
--  * Conversa nova: se o lead já tem responsável que é agente da unidade, vai para ele; senão, rodízio.
--    Sem agente na unidade, fica sem dono (a gestão distribui).
--  * Consultor vê só as próprias conversas. Gestão (nível total em Conversas, papel coordenacao ou admin)
--    vê todas, filtra por agente, transfere e distribui as sem dono.
--  * Abrir a conversa não troca mais o atendente (antes, quem abria virava dono).

alter table public.crm_usuario_unidades add column if not exists wa_rodizio boolean;
comment on column public.crm_usuario_unidades.wa_rodizio is
  'WhatsApp: participa do rodízio de conversas novas. null = padrão (papel comercial ou consultor).';

alter table public.crm_wa_conversas add column if not exists atribuicao text;
alter table public.crm_wa_conversas add column if not exists atribuida_em timestamptz;
comment on column public.crm_wa_conversas.atribuicao is 'lead | rodizio | manual | distribuida';

create table if not exists public.crm_wa_rodizio (
  unidade text primary key references public.crm_unidades(slug),
  ultimo_usuario_id uuid references public.crm_usuarios(id) on delete set null,
  atualizado_em timestamptz not null default now()
);
alter table public.crm_wa_rodizio enable row level security;
revoke all on public.crm_wa_rodizio from anon, authenticated;

-- quem vê a caixa inteira da unidade
create or replace function public.crm_wa_ve_tudo(p_usuario uuid, p_unidade text)
returns boolean language sql stable security definer set search_path = public as $$
  select crm_nivel_num(p_usuario, 'conversas', p_unidade) >= 3
      or exists (select 1 from crm_usuario_unidades uu
                  where uu.usuario_id = p_usuario and uu.unidade = p_unidade and uu.ativo
                    and (uu.admin or uu.papel in ('coordenacao', 'admin'))
                    and crm_nivel_num(p_usuario, 'conversas', p_unidade) >= 1)
$$;

-- agentes da unidade (todos com nível >= editar) e se estão no rodízio
create or replace function public.crm_wa_agentes(p_unidade text)
returns table(usuario_id uuid, nome text, no_rodizio boolean)
language sql stable security definer set search_path = public as $$
  select u.id, u.nome,
         coalesce(uu.wa_rodizio, uu.papel = 'comercial' or uu.consultor)
    from crm_usuario_unidades uu
    join crm_usuarios u on u.id = uu.usuario_id
   where uu.unidade = p_unidade and uu.ativo and u.ativo
     and crm_nivel_num(u.id, 'conversas', p_unidade) >= 2
   order by u.nome, u.id
$$;

-- próximo do rodízio (trava a linha da unidade: duas conversas simultâneas não vão para a mesma pessoa)
create or replace function public.crm_wa_proximo_agente(p_unidade text)
returns uuid language plpgsql security definer set search_path = public as $$
declare ag uuid[]; ult uuid; i int; prox uuid;
begin
  select array_agg(a.usuario_id order by a.nome, a.usuario_id) into ag
    from crm_wa_agentes(p_unidade) a where a.no_rodizio;
  if ag is null then return null; end if;
  insert into crm_wa_rodizio(unidade) values (p_unidade) on conflict (unidade) do nothing;
  select ultimo_usuario_id into ult from crm_wa_rodizio where unidade = p_unidade for update;
  i := array_position(ag, ult);
  prox := ag[case when i is null or i >= array_length(ag, 1) then 1 else i + 1 end];
  update crm_wa_rodizio set ultimo_usuario_id = prox, atualizado_em = now() where unidade = p_unidade;
  return prox;
end $$;

-- dono do lead, se for agente da unidade
create or replace function public.crm_wa_dono_do_lead(p_lead uuid, p_unidade text)
returns uuid language sql stable security definer set search_path = public as $$
  select a.usuario_id
    from crm_leads l
    join crm_wa_agentes(p_unidade) a on a.nome = l.responsavel
   where l.id = p_lead and l.unidade = p_unidade
   limit 1
$$;

-- atribuição automática na criação da conversa (roda depois do a00_herda_unidade)
create or replace function public.crm_wa_conversa_atribuir()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.atendente_id is not null then
    new.atribuicao := coalesce(new.atribuicao, 'manual');
    new.atribuida_em := coalesce(new.atribuida_em, now());
    return new;
  end if;
  if new.lead_id is not null then
    new.atendente_id := crm_wa_dono_do_lead(new.lead_id, new.unidade);
    if new.atendente_id is not null then new.atribuicao := 'lead'; end if;
  end if;
  if new.atendente_id is null then
    new.atendente_id := crm_wa_proximo_agente(new.unidade);
    if new.atendente_id is not null then new.atribuicao := 'rodizio'; end if;
  end if;
  if new.atendente_id is not null then new.atribuida_em := now(); end if;
  return new;
end $$;

drop trigger if exists b10_wa_atribuir on public.crm_wa_conversas;
create trigger b10_wa_atribuir before insert on public.crm_wa_conversas
  for each row execute function public.crm_wa_conversa_atribuir();

-- funções internas: só o banco e as Edge Functions (service role) chamam
revoke execute on function public.crm_wa_ve_tudo(uuid, text) from public, anon, authenticated;
revoke execute on function public.crm_wa_agentes(text) from public, anon, authenticated;
revoke execute on function public.crm_wa_proximo_agente(text) from public, anon, authenticated;
revoke execute on function public.crm_wa_dono_do_lead(uuid, text) from public, anon, authenticated;
revoke execute on function public.crm_wa_conversa_atribuir() from public, anon, authenticated;
