alter table public.crm_turmas
  add column if not exists situacao text,
  add column if not exists inicio date,
  add column if not exists fim date;
comment on column public.crm_turmas.situacao is 'Situação da turma no CNA Box (Em formação, Em andamento...). Mostrada só no modal, não no card do mapa.';
comment on column public.crm_turmas.inicio is 'Primeiro dia de aula (CNA Box). Mostrado só no modal.';
comment on column public.crm_turmas.fim is 'Último dia de aula (CNA Box). Mostrado só no modal.';
notify pgrst, 'reload schema';