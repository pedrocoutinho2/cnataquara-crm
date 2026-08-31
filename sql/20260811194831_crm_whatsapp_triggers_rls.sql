-- Atualiza a conversa a cada mensagem: previa, janela de 24h, nao lidas
create or replace function crm_wa_touch_conversa()
returns trigger
language plpgsql
as $fn$
begin
  update crm_wa_conversas c
     set ultima_mensagem_em = greatest(coalesce(c.ultima_mensagem_em, new.wa_timestamp), new.wa_timestamp),
         ultima_previa = left(coalesce(nullif(new.texto, ''), '[' || new.tipo || ']'), 120),
         janela_expira_em = case when new.direcao = 'entrada'
                                 then new.wa_timestamp + interval '24 hours'
                                 else c.janela_expira_em end,
         nao_lidas = case when new.direcao = 'entrada' then c.nao_lidas + 1 else c.nao_lidas end,
         status = case when new.direcao = 'entrada' and c.status = 'resolvida' then 'aberta' else c.status end,
         updated_at = now()
   where c.id = new.conversa_id;
  return new;
end;
$fn$;

drop trigger if exists trg_crm_wa_touch on crm_wa_mensagens;
create trigger trg_crm_wa_touch
  after insert on crm_wa_mensagens
  for each row execute function crm_wa_touch_conversa();

-- RLS: mesmo padrao permissivo ja usado nas demais tabelas crm_*
do $fn$
declare t text;
begin
  foreach t in array array['crm_wa_contas','crm_wa_conversas','crm_wa_mensagens','crm_wa_templates','crm_wa_eventos']
  loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists anon_all on %I', t);
    execute format('create policy anon_all on %I for all to anon using (true) with check (true)', t);
  end loop;
end;
$fn$;

-- Realtime na aba Conversas
alter publication supabase_realtime add table crm_wa_mensagens;
alter publication supabase_realtime add table crm_wa_conversas;

-- Bucket privado de midia; front acessa por signed URL
insert into storage.buckets (id, name, public, file_size_limit)
values ('wa-media', 'wa-media', false, 104857600)
on conflict (id) do nothing;

drop policy if exists wa_media_anon on storage.objects;
create policy wa_media_anon on storage.objects
  for all to anon using (bucket_id = 'wa-media') with check (bucket_id = 'wa-media');