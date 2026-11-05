-- Integração CRM → CNA Box, fase 2: credenciais, fila e enfileiramento (rede, base gpnwmsnayrqjcmhqrtpx)
-- Senha do Box de cada consultor fica no Supabase Vault (criptografada). Nenhuma senha passa por tabela legível,
-- por nota ou por chat: o consultor digita no CRM e a RPC grava direto no Vault.
-- Modo sugestão: item entra 'pendente'; só 'aprovado' é enviado.

-- 1. Configuração por unidade
create table if not exists public.crm_box_config (
  unidade text primary key,
  ativo boolean not null default false,
  modo text not null default 'sugestao' check (modo in ('sugestao','direto')),
  desde date not null default current_date,
  atualizado_em timestamptz not null default now()
);
alter table public.crm_box_config enable row level security;
insert into public.crm_box_config (unidade, ativo, modo, desde)
values ('taquara', true, 'sugestao', date '2026-11-05')
on conflict (unidade) do nothing;

-- 2. Credenciais (referência ao segredo do Vault; a senha não fica aqui)
create table if not exists public.crm_box_credenciais (
  id uuid primary key default gen_random_uuid(),
  unidade text not null,
  usuario_id uuid not null references public.crm_usuarios(id) on delete cascade,
  email_box text not null,
  secret_id uuid not null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  ultimo_ok_em timestamptz,
  ultimo_erro text,
  unique (unidade, usuario_id)
);
alter table public.crm_box_credenciais enable row level security;

-- Sessão do CRM -> usuário e unidade, exigindo nível mínimo no módulo leads
create or replace function public.crm_box_sessao(p_token uuid, p_min integer default 2)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare uid uuid; un text; u crm_usuarios; nv int;
begin
  select usuario_id, unidade into uid, un from crm_sessoes where token = p_token and expira_em > now();
  if uid is null then raise exception 'sessao_invalida' using errcode = 'P0001'; end if;
  if un is null then raise exception 'unidade_nao_escolhida' using errcode = 'P0001'; end if;
  select * into u from crm_usuarios where id = uid and ativo;
  if not found then raise exception 'sessao_invalida' using errcode = 'P0001'; end if;
  nv := crm_nivel_num(uid, 'leads', un);
  if nv < p_min then raise exception 'sem_permissao' using errcode = 'P0001'; end if;
  return jsonb_build_object('usuario_id', u.id, 'nome', u.nome, 'unidade', un, 'nivel', nv);
end $$;
revoke all on function public.crm_box_sessao(uuid, integer) from public, anon, authenticated;

-- O próprio usuário grava ou troca a senha do Box dele
create or replace function public.crm_box_credencial_salvar(p_token uuid, p_email text, p_senha text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare s jsonb; v_id uuid; v_secret uuid; v_un text; v_uid uuid;
begin
  s := crm_box_sessao(p_token, 2);
  v_un := s->>'unidade'; v_uid := (s->>'usuario_id')::uuid;
  if coalesce(trim(p_email),'') = '' or coalesce(p_senha,'') = '' then
    raise exception 'email_e_senha_obrigatorios' using errcode = 'P0001';
  end if;
  select id, secret_id into v_id, v_secret from crm_box_credenciais where unidade = v_un and usuario_id = v_uid;
  if v_id is null then
    v_secret := vault.create_secret(p_senha, 'crm_box_' || v_un || '_' || v_uid::text, 'Senha do CNA Box de usuário do CRM');
    insert into crm_box_credenciais (unidade, usuario_id, email_box, secret_id)
    values (v_un, v_uid, lower(trim(p_email)), v_secret);
  else
    perform vault.update_secret(v_secret, p_senha);
    update crm_box_credenciais
       set email_box = lower(trim(p_email)), atualizado_em = now(), ultimo_erro = null
     where id = v_id;
  end if;
  return jsonb_build_object('ok', true, 'email_box', lower(trim(p_email)));
end $$;
revoke all on function public.crm_box_credencial_salvar(uuid, text, text) from public;
grant execute on function public.crm_box_credencial_salvar(uuid, text, text) to anon, authenticated;

create or replace function public.crm_box_credencial_status(p_token uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare s jsonb; r crm_box_credenciais;
begin
  s := crm_box_sessao(p_token, 1);
  select * into r from crm_box_credenciais
   where unidade = s->>'unidade' and usuario_id = (s->>'usuario_id')::uuid;
  if not found then return jsonb_build_object('conectado', false); end if;
  return jsonb_build_object('conectado', true, 'email_box', r.email_box, 'atualizado_em', r.atualizado_em,
                            'ultimo_ok_em', r.ultimo_ok_em, 'ultimo_erro', r.ultimo_erro);
end $$;
revoke all on function public.crm_box_credencial_status(uuid) from public;
grant execute on function public.crm_box_credencial_status(uuid) to anon, authenticated;

create or replace function public.crm_box_credencial_remover(p_token uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare s jsonb; v_secret uuid;
begin
  s := crm_box_sessao(p_token, 1);
  delete from crm_box_credenciais
   where unidade = s->>'unidade' and usuario_id = (s->>'usuario_id')::uuid
  returning secret_id into v_secret;
  if v_secret is not null then delete from vault.secrets where id = v_secret; end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.crm_box_credencial_remover(uuid) from public;
grant execute on function public.crm_box_credencial_remover(uuid) to anon, authenticated;

-- Só a Edge Function (service_role) lê a senha
create or replace function public.crm_box_credencial_ler(p_unidade text, p_consultor text)
returns table (usuario_id uuid, email_box text, senha text)
language sql
stable
security definer
set search_path = public
as $$
  select c.usuario_id, c.email_box, d.decrypted_secret
  from crm_box_credenciais c
  join crm_usuarios u on u.id = c.usuario_id and u.ativo
  join vault.decrypted_secrets d on d.id = c.secret_id
  where c.unidade = p_unidade and u.nome = p_consultor
  limit 1;
$$;
revoke all on function public.crm_box_credencial_ler(text, text) from public, anon, authenticated;
grant execute on function public.crm_box_credencial_ler(text, text) to service_role;

-- Segredo do agendamento (cron -> Edge Function), gerado e guardado só no Vault
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'crm_box_cron') then
    perform vault.create_secret(encode(gen_random_bytes(32), 'hex'), 'crm_box_cron', 'Chamada agendada da box-prospect-sync');
  end if;
end $$;

create or replace function public.crm_box_cron_valida(p_segredo text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from vault.decrypted_secrets where name = 'crm_box_cron' and decrypted_secret = p_segredo);
$$;
revoke all on function public.crm_box_cron_valida(text) from public, anon, authenticated;
grant execute on function public.crm_box_cron_valida(text) to service_role;

-- 3. Pendências de um item (o sistema cobra, não bloqueia: item fica aguardando dados)
create or replace function public.crm_box_pendencias(p_fila_id uuid)
returns text[]
language plpgsql
stable
security definer
set search_path = public
as $$
declare f crm_box_fila; l crm_leads; i crm_leads_interacoes; p text[] := '{}';
begin
  select * into f from crm_box_fila where id = p_fila_id;
  if not found then return array['item_inexistente']; end if;
  select * into l from crm_leads where id = f.lead_id;
  if f.interacao_id is not null then select * into i from crm_leads_interacoes where id = f.interacao_id; end if;
  if l.data_nascimento is null then p := array_append(p, 'data_nascimento'); end if;
  if coalesce(array_length(l.disponibilidade, 1), 0) = 0 then p := array_append(p, 'disponibilidade'); end if;
  if coalesce(l.whatsapp, '') = '' and coalesce(l.email, '') = '' then p := array_append(p, 'contato'); end if;
  if i.id is not null then
    if i.efetivo is false and i.motivo_nao_efetivo is null then p := array_append(p, 'motivo_nao_efetivo'); end if;
    if i.efetivo is not false and i.proximo_contato is not null
       and coalesce(i.proximo_canal, '') not in ('visita', 'teste_nivel')
       and i.motivo_repique is null then p := array_append(p, 'motivo_repique'); end if;
  end if;
  if not exists (select 1 from crm_box_credenciais c join crm_usuarios u on u.id = c.usuario_id
                  where c.unidade = f.unidade and u.nome = l.responsavel) then
    p := array_append(p, 'consultor_sem_box');
  end if;
  return p;
end $$;
revoke all on function public.crm_box_pendencias(uuid) from public, anon, authenticated;

-- 4. Enfileiramento: toda interação de contato (fora notas) de unidade com o Box ligado
create or replace function public.crm_box_enfileirar()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare c crm_box_config; v_resp text;
begin
  begin
    if new.tipo = 'nota' then return new; end if;
    select * into c from crm_box_config where unidade = new.unidade and ativo;
    if not found or new.data < c.desde then return new; end if;
    select responsavel into v_resp from crm_leads where id = new.lead_id;
    insert into crm_box_fila (unidade, lead_id, interacao_id, operacao, consultor, status)
    values (new.unidade, new.lead_id, new.id, 'atendimento', v_resp,
            case when c.modo = 'direto' then 'aprovado' else 'pendente' end)
    on conflict (interacao_id) where interacao_id is not null do nothing;
  exception when others then
    -- Regra 2: falha de integração nunca impede salvar o contato.
    raise warning 'crm_box_enfileirar: %', sqlerrm;
  end;
  return new;
end $$;

drop trigger if exists z_box_enfileirar on public.crm_leads_interacoes;
create trigger z_box_enfileirar after insert on public.crm_leads_interacoes
  for each row execute function public.crm_box_enfileirar();

-- 5. RPCs da tela (token de sessão). Consultor vê e aprova os próprios; nível total vê e aprova a unidade.
create or replace function public.crm_box_fila_listar(p_token uuid, p_status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare s jsonb; v_todos boolean;
begin
  s := crm_box_sessao(p_token, 1);
  v_todos := (s->>'nivel')::int >= 3;
  return coalesce((
    select jsonb_agg(x order by x->>'criado_em' desc) from (
      select jsonb_build_object(
        'id', f.id, 'status', f.status, 'operacao', f.operacao, 'criado_em', f.criado_em,
        'enviado_em', f.enviado_em, 'erro', f.erro, 'tentativas', f.tentativas,
        'lead_id', l.id, 'lead_nome', coalesce(nullif(l.nome_aluno, ''), l.nome), 'consultor', l.responsavel,
        'box_id', l.box_id, 'interacao_data', i.data, 'interacao_tipo', i.tipo, 'efetivo', i.efetivo,
        'receptivo', crm_box_receptivo(i.id),
        'pendencias', case when f.status in ('enviado', 'ignorado') then '{}'::text[] else crm_box_pendencias(f.id) end
      ) x
      from crm_box_fila f
      join crm_leads l on l.id = f.lead_id
      left join crm_leads_interacoes i on i.id = f.interacao_id
      where f.unidade = s->>'unidade'
        and (v_todos or l.responsavel = s->>'nome')
        and (p_status is null or f.status = p_status)
      order by f.criado_em desc
      limit 500
    ) t), '[]'::jsonb);
end $$;
revoke all on function public.crm_box_fila_listar(uuid, text) from public;
grant execute on function public.crm_box_fila_listar(uuid, text) to anon, authenticated;

create or replace function public.crm_box_fila_decidir(p_token uuid, p_ids uuid[], p_acao text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare s jsonb; v_todos boolean; r record; n_ok int := 0; n_pend int := 0; pend text[];
begin
  if p_acao not in ('aprovar', 'ignorar', 'reabrir') then raise exception 'acao_invalida' using errcode = 'P0001'; end if;
  s := crm_box_sessao(p_token, 2);
  v_todos := (s->>'nivel')::int >= 3;
  for r in
    select f.id, f.status from crm_box_fila f join crm_leads l on l.id = f.lead_id
     where f.id = any(p_ids) and f.unidade = s->>'unidade'
       and (v_todos or l.responsavel = s->>'nome')
       and f.status <> 'enviado'
  loop
    if p_acao = 'aprovar' then
      pend := crm_box_pendencias(r.id);
      if coalesce(array_length(pend, 1), 0) > 0 then
        update crm_box_fila set status = 'aguardando_dados', pendencias = pend where id = r.id;
        n_pend := n_pend + 1;
      else
        update crm_box_fila set status = 'aprovado', pendencias = null, aprovado_por = s->>'nome', aprovado_em = now(), erro = null
         where id = r.id;
        n_ok := n_ok + 1;
      end if;
    elsif p_acao = 'ignorar' then
      update crm_box_fila set status = 'ignorado', aprovado_por = s->>'nome', aprovado_em = now() where id = r.id;
      n_ok := n_ok + 1;
    else
      update crm_box_fila set status = 'pendente', erro = null where id = r.id;
      n_ok := n_ok + 1;
    end if;
  end loop;
  return jsonb_build_object('ok', n_ok, 'aguardando_dados', n_pend);
end $$;
revoke all on function public.crm_box_fila_decidir(uuid, uuid[], text) from public;
grant execute on function public.crm_box_fila_decidir(uuid, uuid[], text) to anon, authenticated;

-- 6. Funções da Edge Function (service_role)
create or replace function public.crm_box_fila_proximos(p_limite integer default 50)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(x), '[]'::jsonb) from (
    select jsonb_build_object(
      'fila_id', f.id, 'unidade', f.unidade, 'operacao', f.operacao, 'tentativas', f.tentativas,
      'consultor', l.responsavel,
      'lead', jsonb_build_object('id', l.id, 'nome', coalesce(nullif(l.nome_aluno, ''), l.nome), 'prospect', l.nome,
              'whatsapp', l.whatsapp, 'email', l.email, 'origem', l.origem, 'curso', l.curso,
              'data_nascimento', l.data_nascimento, 'sexo', l.sexo, 'disponibilidade', l.disponibilidade,
              'box_id', l.box_id, 'observacoes', l.observacoes),
      'interacao', case when i.id is null then null else jsonb_build_object(
              'id', i.id, 'data', i.data, 'tipo', i.tipo, 'nota', i.nota, 'efetivo', i.efetivo,
              'motivo_nao_efetivo', i.motivo_nao_efetivo, 'proximo_contato', i.proximo_contato,
              'proximo_contato_hora', i.proximo_contato_hora, 'proximo_canal', i.proximo_canal,
              'motivo_repique', i.motivo_repique, 'receptivo', crm_box_receptivo(i.id)) end,
      'pendencias', crm_box_pendencias(f.id)
    ) x
    from crm_box_fila f
    join crm_leads l on l.id = f.lead_id
    left join crm_leads_interacoes i on i.id = f.interacao_id
    join crm_box_config c on c.unidade = f.unidade and c.ativo
    where f.status = 'aprovado' and f.tentativas < 5
    order by f.unidade, l.responsavel, i.data, i.created_at
    limit p_limite
  ) t;
$$;
revoke all on function public.crm_box_fila_proximos(integer) from public, anon, authenticated;
grant execute on function public.crm_box_fila_proximos(integer) to service_role;

create or replace function public.crm_box_fila_resultado(p_fila_id uuid, p_ok boolean, p_box_id bigint,
                                                        p_payload jsonb, p_resposta jsonb, p_erro text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare f crm_box_fila;
begin
  select * into f from crm_box_fila where id = p_fila_id for update;
  if not found then return; end if;
  if p_box_id is not null then
    update crm_leads set box_id = p_box_id, box_vinculado_em = coalesce(box_vinculado_em, now())
     where id = f.lead_id and box_id is null;
  end if;
  if p_ok then
    update crm_box_fila set status = 'enviado', enviado_em = now(), payload = p_payload, resposta = p_resposta,
                            erro = null, tentativas = tentativas + 1 where id = p_fila_id;
    if f.interacao_id is not null then
      update crm_leads_interacoes set box_enviado_em = now() where id = f.interacao_id;
    end if;
  else
    update crm_box_fila set status = 'erro', payload = p_payload, resposta = p_resposta, erro = p_erro,
                            tentativas = tentativas + 1 where id = p_fila_id;
  end if;
end $$;
revoke all on function public.crm_box_fila_resultado(uuid, boolean, bigint, jsonb, jsonb, text) from public, anon, authenticated;
grant execute on function public.crm_box_fila_resultado(uuid, boolean, bigint, jsonb, jsonb, text) to service_role;

create or replace function public.crm_box_credencial_resultado(p_unidade text, p_consultor text, p_ok boolean, p_erro text)
returns void
language sql
security definer
set search_path = public
as $$
  update crm_box_credenciais c
     set ultimo_ok_em = case when p_ok then now() else c.ultimo_ok_em end,
         ultimo_erro = case when p_ok then null else p_erro end
    from crm_usuarios u
   where u.id = c.usuario_id and c.unidade = p_unidade and u.nome = p_consultor;
$$;
revoke all on function public.crm_box_credencial_resultado(text, text, boolean, text) from public, anon, authenticated;
grant execute on function public.crm_box_credencial_resultado(text, text, boolean, text) to service_role;

notify pgrst, 'reload schema';