create extension if not exists pg_cron;

-- 02:30 UTC = 23:30 em Brasília, depois do fim do turno mais tarde (22h)
select cron.unschedule('crm_fechar_dia_pendentes')
 where exists (select 1 from cron.job where jobname = 'crm_fechar_dia_pendentes');

select cron.schedule('crm_fechar_dia_pendentes', '30 2 * * *',
                     $c$select crm_fechar_pendentes();$c$);

-- Jornadas reais da equipe comercial
update crm_usuarios set consultor = true, hora_inicio = '09:00', hora_fim = '18:00' where nome = 'Camila';
update crm_usuarios set consultor = true, hora_inicio = '13:00', hora_fim = '22:00' where nome = 'Marlon';
update crm_usuarios set consultor = true, hora_inicio = '09:00', hora_fim = '18:00' where nome = 'Sabrina';