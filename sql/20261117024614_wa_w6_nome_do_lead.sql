-- wa_w6_nome_do_lead · CRM CNA (gpnwmsnayrqjcmhqrtpx) · escopo: rede
-- Pedido do Pedro em 16/11/2026: leads do WhatsApp entram com nome errado ("WhatsApp (21) 9...",
-- ".", e-mail, "WhatsApp Business", apelido com emoji). O sistema precisa achar o nome do cliente e
-- atualizar sozinho, sem nunca passar por cima de correção feita por gente.
--
-- crm_leads.nome_auto = true: o nome veio da automação e pode ser trocado por um melhor.
-- Edição de nome por qualquer outro caminho (ficha do CRM) zera nome_auto: daí em diante ninguém mexe.
-- Fontes, da mais confiável para a menos: nome dito na conversa (IA) > agenda do celular (contatos
-- da Evolution) > nome do perfil do WhatsApp. Todas passam por crm_wa_nome_limpo.

alter table public.crm_leads add column if not exists nome_auto boolean not null default false;
alter table public.crm_wa_conversas
  add column if not exists nome_contato text,
  add column if not exists nome_ia text;

-- limpa um nome vindo do WhatsApp; null quando não serve como nome de pessoa
create or replace function public.crm_wa_nome_limpo(p text)
returns text language plpgsql immutable set search_path = public as $$
declare n text;
begin
  if p is null or p ~ '@' or p ~* 'https?://|www\.' then return null; end if;
  n := regexp_replace(p, '[^[:alpha:][:space:]''-]', ' ', 'g');      -- emoji, número, pontuação, bandeira
  n := btrim(regexp_replace(n, '\s+', ' ', 'g'), ' -''');
  if length(n) < 2 or n !~ '[[:alpha:]].*[[:alpha:]]' then return null; end if;
  if lower(n) in ('whatsapp', 'whatsapp business', 'business', 'user', 'usuario', 'usuário', 'cliente',
                  'eu', 'meu', 'minha', 'sem nome', 'desconhecido', 'unknown') then return null; end if;
  if lower(n) ~ '^(whatsapp|wpp|zap)\M' then return null; end if;
  -- tudo maiúsculo ou tudo minúsculo vira Nome Próprio
  if n = upper(n) or n = lower(n) then n := initcap(n); end if;
  return left(n, 80);
end $$;

-- escolhe o melhor nome da conversa e aplica no lead, se o nome do lead ainda for automático
create or replace function public.crm_wa_lead_nome_sync(p_conversa uuid)
returns text language plpgsql security definer set search_path = public as $$
declare c record; novo text; atual text; num text;
begin
  select id, lead_id, unidade, wa_id, nome_ia, nome_contato, nome_perfil into c from crm_wa_conversas where id = p_conversa;
  if c.lead_id is null then return null; end if;
  novo := coalesce(crm_wa_nome_limpo(c.nome_ia), crm_wa_nome_limpo(c.nome_contato), crm_wa_nome_limpo(c.nome_perfil));
  if novo is null then
    -- sem nome bom: se o atual é lixo (".", e-mail, "WhatsApp Business"), mostra o número até aparecer nome
    select nome into atual from crm_leads where id = c.lead_id;
    if atual like 'WhatsApp (%' or crm_wa_nome_limpo(atual) is not null then return null; end if;
    num := regexp_replace(regexp_replace(coalesce(c.wa_id, ''), '\D', '', 'g'), '^55', '');
    novo := 'WhatsApp ' || case length(num)
               when 11 then '(' || substr(num, 1, 2) || ') ' || substr(num, 3, 5) || '-' || substr(num, 8)
               when 10 then '(' || substr(num, 1, 2) || ') ' || substr(num, 3, 4) || '-' || substr(num, 7)
               else num end;
  end if;
  perform set_config('crm.nome_auto', '1', true);
  update crm_leads set nome = novo where id = c.lead_id and unidade = c.unidade and nome_auto and nome is distinct from novo;
  perform set_config('crm.nome_auto', '', true);
  return novo;
end $$;
revoke execute on function public.crm_wa_lead_nome_sync(uuid) from public, anon, authenticated;

-- edição feita por gente (qualquer update de nome fora da automação) trava o nome
create or replace function public.crm_leads_nome_manual()
returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'UPDATE' and new.nome is distinct from old.nome
     and coalesce(current_setting('crm.nome_auto', true), '') <> '1' then
    new.nome_auto := false;
  end if;
  return new;
end $$;
drop trigger if exists a05_leads_nome_manual on public.crm_leads;
create trigger a05_leads_nome_manual before update of nome on public.crm_leads
  for each row execute function public.crm_leads_nome_manual();

-- conversa ganhou nome novo (perfil, agenda, IA) ou ganhou lead: tenta atualizar o lead
create or replace function public.crm_wa_conversa_nome_tg()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.lead_id is not null and (tg_op = 'INSERT'
     or new.nome_perfil is distinct from old.nome_perfil or new.nome_contato is distinct from old.nome_contato
     or new.nome_ia is distinct from old.nome_ia or new.lead_id is distinct from old.lead_id) then
    perform crm_wa_lead_nome_sync(new.id);
  end if;
  return null;
end $$;
drop trigger if exists z_wa_conversa_nome on public.crm_wa_conversas;
create trigger z_wa_conversa_nome after insert or update of nome_perfil, nome_contato, nome_ia, lead_id on public.crm_wa_conversas
  for each row execute function public.crm_wa_conversa_nome_tg();

-- leads criados pela automação do WhatsApp nascem com nome automático
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
      insert into crm_leads (unidade, nome, nome_auto, whatsapp, etapa, origem, responsavel, data_entrada,
                             proximo_atendimento, proximo_atendimento_hora, proximo_canal)
      values (c.unidade, coalesce(crm_wa_nome_limpo(c.nome_contato), crm_wa_nome_limpo(c.nome_perfil), 'WhatsApp ' || fmt), true,
              fmt, et, 'WhatsApp', resp,
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

-- carga: leads que a automação criou e ninguém renomeou (nome = perfil cru ou "WhatsApp (..")
update crm_leads l set nome_auto = true
  from crm_wa_conversas c
 where c.lead_id = l.id and c.unidade = l.unidade and l.origem = 'WhatsApp'
   and (l.nome like 'WhatsApp %' or l.nome = btrim(coalesce(c.nome_perfil, '')));
select crm_wa_lead_nome_sync(c.id) from crm_wa_conversas c where c.lead_id is not null;

notify pgrst, 'reload schema';