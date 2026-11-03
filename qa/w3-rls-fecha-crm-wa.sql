-- RASCUNHO, NÃO APLICADO. Fecha a RLS das crm_wa_* (dívida nº 3), depois do deploy do front W3.
-- Base: gpnwmsnayrqjcmhqrtpx (CRM CNA) · escopo: rede (vale para as três unidades).
-- O front W3 lê e age só por RPC com token (crm_wa_painel, *_listar, *_abrir, *_vincular_lead,
-- crm_wa_nao_lidas, crm_wa_fila_*) e as Edge Functions usam service role: nenhum dos dois precisa
-- de policy para anon. Ao aplicar: renomear para sql/<version>_wa_w3b_rls_fecha_crm_wa.sql.
-- crm_wa_optout fica como está (anon_insert/anon_select): conferir antes quem grava opt-out por anon.
-- Ensaio antes: BEGIN; <isto>; set local role anon; select count(*) from crm_wa_conversas; -- 0
--               select crm_wa_nao_lidas('<token real>'); ROLLBACK;
drop policy if exists anon_all on public.crm_wa_contas;
drop policy if exists anon_all on public.crm_wa_conversas;
drop policy if exists anon_all on public.crm_wa_eventos;
drop policy if exists anon_all on public.crm_wa_fila;
drop policy if exists anon_all on public.crm_wa_mensagens;
drop policy if exists anon_all on public.crm_wa_regras;
drop policy if exists anon_all on public.crm_wa_templates;
notify pgrst, 'reload schema';
