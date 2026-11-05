-- Base: gpnwmsnayrqjcmhqrtpx (CRM CNA) · escopo: rede
drop trigger if exists crm_leads_trava_cadastro_tg on public.crm_leads;
create trigger crm_leads_trava_cadastro_tg
  before update on public.crm_leads
  for each row execute function public.crm_leads_trava_cadastro();

notify pgrst, 'reload schema';