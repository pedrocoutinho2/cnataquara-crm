create or replace function public.crm_leads_aguarda_271()
returns trigger language plpgsql as $fn$
declare
  -- Etapa "Aguardando 27.1": quem entrar na coluna sai com o proximo contato
  -- carimbado em 01/10. Para mudar a data do proximo semestre, altere aqui.
  v_data date := date '2026-10-01';
  v_hora time := time '09:00';
begin
  if new.etapa = 'aguardando_271'
     and (tg_op = 'INSERT' or old.etapa is distinct from new.etapa) then
    new.proximo_atendimento := v_data;
    new.proximo_atendimento_hora := v_hora;
    if new.proximo_canal is null then new.proximo_canal := 'whatsapp'; end if;
    new.data_fechamento := null;
    new.motivo_perda := null;
  end if;
  return new;
end $fn$;

drop trigger if exists crm_leads_aguarda_271_tg on public.crm_leads;
create trigger crm_leads_aguarda_271_tg
before insert or update on public.crm_leads
for each row execute function public.crm_leads_aguarda_271();

notify pgrst, 'reload schema';