-- 20260908170041_agenda_calendar_id_por_evento.sql · 08/09/2026
-- O Apps Script serve TODO evento do CRM. Fixar o calendario nele levaria acao
-- comercial e reuniao junto para a agenda de testes, e trocar o padrao quebraria
-- a edicao e o cancelamento dos eventos ja sincronizados ("Not Found").
-- Entao o calendario passa a ser propriedade do evento; nulo = padrao do script.
alter table crm_agenda_eventos add column if not exists calendar_id text;

-- Calendario dedicado aos testes de nivel, trocavel sem deploy.
alter table crm_agenda_config add column if not exists cal_testes text;

update crm_agenda_config
   set cal_testes = '8a84694af0b2b09f5c8df635c96b99bf44f6df1aa23f46fc8f318cd5fb4c42c8@group.calendar.google.com'
 where cal_testes is null;

notify pgrst, 'reload schema';
