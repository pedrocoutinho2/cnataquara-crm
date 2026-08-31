-- 1. campos de fila de espera por falta de turma
alter table crm_leads add column if not exists sem_turma boolean not null default false;
alter table crm_leads add column if not exists turno_desejado text;
alter table crm_leads add column if not exists espera_desde date;

create index if not exists crm_leads_sem_turma_idx on crm_leads(sem_turma) where sem_turma;

-- marca automaticamente quem for perdido por falta de turma
create or replace function crm_leads_marca_espera() returns trigger language plpgsql as $$
begin
  if new.motivo_perda = 'Sem turma disponível' and new.etapa = 'perdido' then
    new.sem_turma := true;
    if new.espera_desde is null then new.espera_desde := coalesce(new.data_fechamento, current_date); end if;
  end if;
  if new.etapa = 'fechado' then
    new.sem_turma := false;
  end if;
  return new;
end $$;

drop trigger if exists crm_leads_espera_tg on crm_leads;
create trigger crm_leads_espera_tg before insert or update on crm_leads
for each row execute function crm_leads_marca_espera();

-- 2. novo modulo de permissao
insert into crm_modulos(modulo,nome,grupo,ordem)
values ('rel_unidade','Relatórios · Unidade e gargalos','Gestão',135)
on conflict (modulo) do update set nome=excluded.nome, grupo=excluded.grupo, ordem=excluded.ordem;

insert into crm_papel_permissoes(papel,modulo,nivel) values
  ('admin','rel_unidade','total'),
  ('coordenacao','rel_unidade','ver'),
  ('comercial','rel_unidade','nenhum'),
  ('pedagogico','rel_unidade','nenhum'),
  ('secretaria','rel_unidade','nenhum')
on conflict (papel,modulo) do update set nivel=excluded.nivel;

notify pgrst, 'reload schema';