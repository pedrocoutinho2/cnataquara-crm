-- 20260908170935_tn_modalidade_ambas.sql · 08/09/2026
-- A faixa publica a JANELA; presencial ou online e' decidido no atendimento.
-- 'ambas' significa "tanto faz, mas informe na hora de marcar".
-- O agendamento continua exigindo presencial ou online: teste sem modalidade
-- definida nao existe, e o Meet depende disso.
alter table crm_tn_grade drop constraint if exists crm_tn_grade_modalidade_check;
alter table crm_tn_grade add constraint crm_tn_grade_modalidade_check
  check (modalidade in ('presencial','online','ambas'));

alter table crm_tn_avulsos drop constraint if exists crm_tn_avulsos_modalidade_check;
alter table crm_tn_avulsos add constraint crm_tn_avulsos_modalidade_check
  check (modalidade in ('presencial','online','ambas'));

notify pgrst, 'reload schema';
