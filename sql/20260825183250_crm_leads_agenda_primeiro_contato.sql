create or replace function public.crm_leads_agenda_novo()
returns trigger language plpgsql as $fn$
declare
  -- Lead novo cai na fila do responsavel 10 minutos depois do cadastro:
  -- e o gatilho do primeiro contato. Para mudar a folga, altere o intervalo.
  -- So age quando ninguem informou agenda: import com data propria e a etapa
  -- "Aguardando 27.1" (que carimba 01/10) continuam mandando.
  v_quando timestamp := (now() at time zone 'America/Sao_Paulo') + interval '10 minutes';
begin
  if new.proximo_atendimento is null then
    new.proximo_atendimento := v_quando::date;
    new.proximo_atendimento_hora := date_trunc('minute', v_quando)::time;
    if new.proximo_canal is null then new.proximo_canal := 'whatsapp'; end if;
  end if;
  return new;
end $fn$;

drop trigger if exists crm_leads_agenda_novo_tg on public.crm_leads;
create trigger crm_leads_agenda_novo_tg
before insert on public.crm_leads
for each row execute function public.crm_leads_agenda_novo();

notify pgrst, 'reload schema';