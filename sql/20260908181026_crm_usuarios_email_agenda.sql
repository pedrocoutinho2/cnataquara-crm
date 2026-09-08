-- 20260908_crm_usuarios_email_agenda.sql · 08/09/2026
-- E-mail que recebe o convite do Google. Nem sempre e' o e-mail de login:
-- quem aplica o teste pode usar uma conta Google pessoal na agenda.
-- Nulo = cai no e-mail de login do usuario.
-- Editavel em Testes de nivel > Grade semanal > Convites do Google.
alter table crm_usuarios add column if not exists email_agenda text;

update crm_usuarios
   set email_agenda = 'izabelleximenesf@gmail.com'
 where nome = 'Izabelle';

notify pgrst, 'reload schema';
