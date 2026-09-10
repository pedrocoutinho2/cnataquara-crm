-- Carga do mapa de turmas 2027.1 a partir da planilha "Mapa geral", aba MAPA GERAL 2027.1
-- (docs.google.com/spreadsheets/d/1sSjpFYiLnY4tBep5evdkAnDJOXEovMV6F5VuaFXqObw, gid 54513685), lida em 10/09/2026.
-- Aplicado no cnataquara-comercial (gpnwmsnayrqjcmhqrtpx) em 10/09/2026 via execute_sql.
--
-- Regras da carga:
--  * nivel na grafia do mapa (CNA Box): PS n -> GARDEN n; FUN n / YOUNG KIDS n -> YOUNG KIDS n/FUN n;
--    FLY 1 / A1.1 -> A1.1/FLY 1; A2.x -> A2.x/QUEST x; "B1" e "B1.1" -> B1.1
--  * alunos e SEM VAGA como estao na planilha; celula sem numero entra com 0 e obs explicando
--  * horario e capacidade herdados da turma 2026.2 do mesmo dia/sala/faixa de horario;
--    sem turma anterior: faixa infantil pega o 1o horario do cabecalho, as demais o 2o;
--    capacidade padrao por faixa (Garden/Fun/Kids 10, Teen Up 14, jovens e adultos 16)
--  * codigo so onde a planilha traz (0033, 0057, 0011)
--  * idempotente: nao insere nada se ja existir turma 2027.1
--  * resultado: 51 turmas, 443 alunos (planilha). As obs foram encurtadas num segundo UPDATE no
--    mesmo dia; este arquivo ja traz o texto final.
insert into crm_turmas (semestre,dias,horario,sala,curso,codigo,professor,alunos,capacidade,sem_vaga,obs,ativa)
select '2027.1',v.dias,v.horario,v.sala,v.curso,v.codigo,v.professor,v.alunos,v.capacidade,v.sem_vaga,v.obs,true
from (values
  ('SEG/QUA', '16:15 - 17:30', 'SALA 3', 'TEEN UP 5', null, 'Rafael', 7, 14, false, null),
  ('SEG/QUA', '16:15 - 17:30', 'SALA 4', 'TEEN UP 4', null, 'Nathalia', 18, 16, true, null),
  ('SEG/QUA', '16:30 - 17:30', 'SALA 5', 'KIDS 1', null, null, 0, 10, false, 'Turma nova'),
  ('SEG/QUA', '16:15 - 17:30', 'SALA 6', 'MASTER 1', null, 'Iago', 6, 16, false, null),
  ('SEG/QUA', '16:30 - 17:30', 'AUDITÓRIO', 'GARDEN 1', null, null, 0, 10, false, 'Turma nova'),
  ('SEG/QUA', '17:45 - 19:10', 'SALA 1', 'YOUNG KIDS 4/FUN 4', null, 'Carolline', 15, 10, true, 'Conferir: 15 na planilha, 7 no Fun 3 0015 hoje'),
  ('SEG/QUA', '17:45 - 19:10', 'SALA 2', 'KIDS 4', null, 'Raissa', 0, 16, false, 'Sem nº de alunos na planilha (Kids 3 extra hoje: 8)'),
  ('SEG/QUA', '17:45 - 19:10', 'SALA 3', 'KIDS 4', null, 'Rafael', 15, 10, true, 'Conferir: 15 na planilha, 7 no Kids 3 0017 hoje'),
  ('SEG/QUA', '17:45 - 19:10', 'SALA 4', 'TEEN UP 1', null, 'Nathalia', 0, 14, false, 'Turma nova'),
  ('SEG/QUA', '17:45 - 19:10', 'SALA 5', 'TEEN UP 4', null, 'Carol', 14, 14, true, null),
  ('SEG/QUA', '17:45 - 19:10', 'SALA 6', 'MASTER 2', '0033', 'Nathalia', 12, 16, false, null),
  ('SEG/QUA', '17:45 - 19:10', 'AUDITÓRIO', 'PADV 2', null, 'Izabelle', 19, 16, true, 'Conferir: 19 na planilha, 18 no PADV 1 0054 hoje'),
  ('SEG/QUA', '18:00 - 19:00', 'GARDEN', 'YOUNG KIDS 4/FUN 4', null, null, 0, 10, false, 'Sem alunos e professor na planilha (Fun 3 0016 hoje: 8)'),
  ('SEG/QUA', '19:10 - 20:25', 'SALA 1', 'ADV 1', null, 'Carolline', 16, 16, true, null),
  ('SEG/QUA', '19:10 - 20:25', 'SALA 2', 'A2.1/QUEST 1', null, 'Raissa', 16, 16, true, null),
  ('SEG/QUA', '19:10 - 20:25', 'SALA 3', 'ADV 2', null, 'Rafael', 14, 16, false, null),
  ('SEG/QUA', '19:10 - 20:25', 'SALA 4', 'PADV 2', '0057', 'Pedro', 5, 16, false, null),
  ('SEG/QUA', '19:10 - 20:25', 'SALA 5', 'B1.1', null, 'Carol', 14, 16, false, null),
  ('SEG/QUA', '19:10 - 20:25', 'SALA 6', 'MASTER 2', null, 'Iago', 10, 16, false, null),
  ('SEG/QUA', '19:10 - 20:25', 'AUDITÓRIO', 'TEEN UP 2', null, 'Izabelle', 5, 14, false, null),
  ('SEG/QUA', '20:25 - 21:40', 'SALA 6', 'ACC', '0011', 'Iago', 3, 16, false, null),
  ('TER/QUI', '15:15 - 16:30', 'SALA 5', 'TEEN UP 3', null, 'Izabelle', 12, 14, false, null),
  ('TER/QUI', '16:30 - 17:30', 'SALA 5', 'KIDS 3', null, 'Izabelle', 5, 10, false, null),
  ('TER/QUI', '16:30 - 17:30', 'SALA 6', 'TEEN UP 2', null, 'Nathalia', 8, 14, false, null),
  ('TER/QUI', '17:45 - 19:00', 'SALA 1', 'KIDS 4', null, 'Rafael', 13, 16, true, null),
  ('TER/QUI', '17:45 - 19:00', 'SALA 2', 'YOUNG KIDS 2/FUN 2', null, 'Raissa', 9, 10, true, null),
  ('TER/QUI', '17:45 - 19:00', 'SALA 3', 'TEEN UP 4', null, 'Pedro', 10, 16, false, null),
  ('TER/QUI', '17:45 - 19:00', 'SALA 4', 'A2.2/QUEST 2', null, 'Carol', 11, 16, false, null),
  ('TER/QUI', '17:45 - 19:00', 'SALA 5', 'KIDS 3', null, 'Izabelle', 10, 10, true, 'Antigo FUN 4'),
  ('TER/QUI', '17:45 - 19:00', 'SALA 6', 'TEEN UP 3', null, 'Nathalia', 10, 16, false, null),
  ('TER/QUI', '17:45 - 19:00', 'AUDITÓRIO', 'ADV 2', null, 'Iago', 11, 16, false, null),
  ('TER/QUI', '17:45 - 19:00', 'GARDEN', 'YOUNG KIDS 2/FUN 2', null, 'Mariana', 11, 10, true, null),
  ('TER/QUI', '19:10 - 20:25', 'SALA 1', 'PADV 2', null, 'Rafael', 12, 16, false, null),
  ('TER/QUI', '19:10 - 20:25', 'SALA 2', 'TEEN UP 6', null, 'Raissa', 12, 16, false, null),
  ('TER/QUI', '19:10 - 20:25', 'SALA 3', 'TEEN UP 3', null, 'Pedro', 11, 16, false, null),
  ('TER/QUI', '19:10 - 20:25', 'SALA 4', 'MASTER 1', null, 'Carol', 13, 16, false, null),
  ('TER/QUI', '19:10 - 20:25', 'SALA 5', 'A1.2/FLY 2', null, 'Henrique', 11, 16, false, null),
  ('TER/QUI', '19:10 - 20:25', 'SALA 6', 'A2.2/QUEST 2', null, 'Izabelle', 12, 16, false, null),
  ('TER/QUI', '19:10 - 20:25', 'AUDITÓRIO', 'A1.1/FLY 1', null, null, 0, 16, false, 'Turma nova'),
  ('TER/QUI', '19:10 - 20:25', 'GARDEN', 'GARDEN 2', null, 'Mariana', 4, 10, false, null),
  ('SÁB', '08:00 - 10:30', 'SALA 1', 'B1.1', null, 'Pedro', 8, 16, false, null),
  ('SÁB', '08:00 - 10:30', 'SALA 2', 'A1.1/FLY 1', null, null, 0, 16, false, 'Turma nova'),
  ('SÁB', '08:00 - 10:30', 'SALA 3', 'MASTER 2', null, 'Izabelle', 6, 16, false, null),
  ('SÁB', '08:00 - 10:30', 'SALA 4', 'PADV 2', null, 'Rafael', 5, 16, false, null),
  ('SÁB', '08:00 - 10:30', 'SALA 5', 'MASTER 1', null, 'Carol', 10, 16, false, null),
  ('SÁB', '10:45 - 13:30', 'SALA 1', 'TEEN UP 3', null, 'Henrique', 12, 14, false, null),
  ('SÁB', '10:45 - 13:30', 'SALA 2', 'A2.2/QUEST 2', null, 'Iago', 6, 16, false, null),
  ('SÁB', '10:45 - 13:30', 'SALA 3', 'A2.1/QUEST 1', null, 'Izabelle', 13, 16, false, null),
  ('SÁB', '10:45 - 13:30', 'SALA 4', 'ADV 1', null, 'Rafael', 7, 16, false, null),
  ('SÁB', '10:45 - 13:30', 'SALA 5', 'YOUNG KIDS 2/FUN 2', null, 'Mariana', 2, 10, false, null),
  ('SÁB', '10:45 - 13:30', 'SALA 6', 'TEEN UP 1', null, null, 0, 14, false, 'Turma nova')
) as v(dias,horario,sala,curso,codigo,professor,alunos,capacidade,sem_vaga,obs)
where not exists (select 1 from crm_turmas where semestre='2027.1');

-- Correcao de dado em 2026.2: a turma de sabado 10:45 SALA 5 foi importada com o nome da
-- professora no campo nivel. Planilha 2026.2: "FUN 1 (2) MARIANA".
-- Antes: curso='Mariana', professor=null.
update crm_turmas set curso='YOUNG KIDS 1/FUN 1', professor='Mariana', atualizado_em=now()
where semestre='2026.2' and dias='SÁB' and horario='10:45 - 13:30' and sala='SALA 5' and curso='Mariana' and professor is null;
