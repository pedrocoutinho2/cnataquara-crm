-- wa_w3b_rls_fechada · CRM CNA (gpnwmsnayrqjcmhqrtpx) · escopo: rede (Taquara, Queimados, Jardim América)
-- Fecha a dívida nº 3 no banco: as crm_wa_* e o bucket wa-media deixam de ser acessíveis pela chave anon.
-- Front (W3, no ar) já lê só por RPC com token (crm_wa_painel, _conversas_listar, _mensagens_listar,
-- _conversa_abrir, _vincular_lead, _nao_lidas, _fila_listar, _fila_decidir), todas SECURITY DEFINER.
-- Escrita só pelas Edge Functions (service_role) e por crm_wa_varrer (SECURITY DEFINER, cron).
-- RLS continua LIGADA; sem policy para anon/authenticated = nega tudo.
drop policy if exists anon_all    on public.crm_wa_contas;
drop policy if exists anon_all    on public.crm_wa_conversas;
drop policy if exists anon_all    on public.crm_wa_eventos;
drop policy if exists anon_all    on public.crm_wa_fila;
drop policy if exists anon_all    on public.crm_wa_mensagens;
drop policy if exists anon_insert on public.crm_wa_optout;
drop policy if exists anon_select on public.crm_wa_optout;
drop policy if exists anon_all    on public.crm_wa_regras;
drop policy if exists anon_all    on public.crm_wa_templates;
drop policy if exists wa_media_anon on storage.objects;

revoke all on public.crm_wa_contas, public.crm_wa_conversas, public.crm_wa_eventos, public.crm_wa_fila,
  public.crm_wa_mensagens, public.crm_wa_optout, public.crm_wa_regras, public.crm_wa_templates
  from anon, authenticated;

notify pgrst, 'reload schema';
