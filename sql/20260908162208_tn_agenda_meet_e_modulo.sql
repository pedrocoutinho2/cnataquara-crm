-- 20260908162208_tn_agenda_meet_e_modulo.sql
-- Projeto: cnataquara-comercial (gpnwmsnayrqjcmhqrtpx) · 08/09/2026
--
-- 1. Convidado externo e sala do Meet passam a ser propriedade do EVENTO de agenda,
--    nao do agendamento do teste. Assim o calendario tambem pode usar quando precisar,
--    e o payload do Apps Script fica com um lugar so de onde ler.
-- 2. Modulo de permissao proprio para a tela de Testes de nivel, com os mesmos niveis
--    do calendario: comercial ve e agenda dentro da disponibilidade publicada;
--    pedagogico e coordenacao publicam a grade.

alter table crm_agenda_eventos add column if not exists convidados text[];
alter table crm_agenda_eventos add column if not exists meet boolean not null default false;
alter table crm_agenda_eventos add column if not exists meet_url text;

insert into crm_modulos(modulo, nome, grupo, ordem)
select 'testes','Testes de nível','Operação',95
where not exists (select 1 from crm_modulos where modulo='testes');

insert into crm_papel_permissoes(papel, modulo, nivel)
select p.papel, 'testes', p.nivel
  from (values ('admin','total'),('coordenacao','editar'),('pedagogico','editar'),
               ('secretaria','ver'),('comercial','ver')) as p(papel,nivel)
 where not exists (select 1 from crm_papel_permissoes x where x.papel=p.papel and x.modulo='testes');

notify pgrst, 'reload schema';
