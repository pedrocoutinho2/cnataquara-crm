alter table public.crm_leads             add column if not exists proximo_atendimento_hora time;
alter table public.crm_escolas           add column if not exists proximo_contato_hora     time;
alter table public.crm_empresas          add column if not exists proximo_contato_hora     time;
alter table public.crm_leads_interacoes  add column if not exists proximo_contato_hora     time;
alter table public.crm_interacoes        add column if not exists proximo_contato_hora     time;
alter table public.crm_tarefas           add column if not exists hora_prevista            time not null default '09:00';

update public.crm_leads            set proximo_atendimento_hora = '09:00' where proximo_atendimento is not null and proximo_atendimento_hora is null;
update public.crm_escolas          set proximo_contato_hora     = '09:00' where proximo_contato     is not null and proximo_contato_hora     is null;
update public.crm_empresas         set proximo_contato_hora     = '09:00' where proximo_contato     is not null and proximo_contato_hora     is null;
update public.crm_leads_interacoes set proximo_contato_hora     = '09:00' where proximo_contato     is not null and proximo_contato_hora     is null;
update public.crm_interacoes       set proximo_contato_hora     = '09:00' where proximo_contato     is not null and proximo_contato_hora     is null;