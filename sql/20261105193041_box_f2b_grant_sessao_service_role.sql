-- box-prospect-sync valida o token de gestão chamando crm_box_sessao com service_role.
grant execute on function public.crm_box_sessao(uuid, integer) to service_role;
grant execute on function public.crm_box_pendencias(uuid) to service_role;
notify pgrst, 'reload schema';