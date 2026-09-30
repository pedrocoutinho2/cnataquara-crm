-- Correção imediata da 2b-5a: crm_painel_equipe e crm_fechar_pendentes leem crm_usuario_unidades,
-- que não tem acesso para anon (de propósito). Como SECURITY INVOKER, o Painel da equipe do front quebrava.
alter function public.crm_painel_equipe(date, text) security definer set search_path to 'public';
alter function public.crm_fechar_pendentes() security definer set search_path to 'public';