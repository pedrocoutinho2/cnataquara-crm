-- Taquara (unidade='taquara'), base gpnwmsnayrqjcmhqrtpx, aplicado em 26/11/2026.
-- Mapa de turmas 2027.1 a partir do CNA Box (escola 86, turmas 'Em formação'). Só DML.
-- alunos = alunos da turma de referência em 26.2 (TurmaReferenciaId do Box; 5 inferidas por dia/horário/sala) + matrículas novas.
do $$
declare n int;
begin
  select count(*) into n from crm_turmas where unidade='taquara' and semestre='2027.1' and ativa;
  if n <> 51 then raise exception 'esperava 51 turmas ativas Taquara 2027.1, achei %', n; end if;
  if exists (select 1 from crm_turmas where unidade='taquara' and semestre='2027.1' and codigo ~ '^[A-Za-z]') then raise exception 'já existe turma com código do Box em Taquara 2027.1'; end if;

  create temp table _box(codigo text,curso text,dias text,horario text,sala text,professor text,alunos int,obs text) on commit drop;
  insert into _box values
('PADV2-0049','PADV 2','SEG/QUA','17:45 - 19:00',null,null,19,'Em formação · início 15/02/27 · fim 23/06/27 · vem de PADV1-0054 (19 alunos em 26.2) · Box 26/11: 13 reservas, 0 matrículas novas'),
('PADV2-0050','PADV 2','SÁB','08:00 - 10:30',null,null,5,'Em formação · início 20/02/27 · fim 03/07/27 · vem de PADV1-0055 (5 alunos em 26.2) · Box 26/11: 0 reservas, 0 matrículas novas'),
('PADV2-0051','PADV 2','SEG/QUA','19:10 - 20:25',null,null,5,'Em formação · início 15/02/27 · fim 23/06/27 · vem de PADV1-0057 (5 alunos em 26.2) · Box 26/11: 2 reservas, 0 matrículas novas'),
('PADV2-0052','PADV 2','TER/QUI','19:10 - 20:25',null,null,11,'Em formação · início 16/02/27 · fim 24/06/27 · vem de PADV1-0058 (11 alunos em 26.2) · Box 26/11: 1 reservas, 0 matrículas novas'),
('MAST1-0036','MASTER 1','SEG/QUA','16:15 - 17:30',null,null,6,'Em formação · início 15/02/27 · fim 23/06/27 · vem de ADV2-0038 (6 alunos em 26.2) · Box 26/11: 6 reservas, 0 matrículas novas'),
('MAST1-0038','MASTER 1','SÁB','08:00 - 10:30',null,null,10,'Em formação · início 20/02/27 · fim 03/07/27 · vem de ADV2-0040 (10 alunos em 26.2) · Box 26/11: 4 reservas, 0 matrículas novas'),
('MAST1-0037','MASTER 1','TER/QUI','19:10 - 20:25',null,null,12,'Em formação · início 16/02/27 · fim 24/06/27 · vem de ADV2-0039 (12 alunos em 26.2) · Box 26/11: 6 reservas, 0 matrículas novas'),
('MAST2-0033','MASTER 2','SEG/QUA','17:45 - 19:00',null,null,12,'Em formação · início 15/02/27 · fim 23/06/27 · vem de MAST1-0033 (12 alunos em 26.2) · Box 26/11: 0 reservas, 0 matrículas novas'),
('MAST2-0035','MASTER 2','SÁB','08:00 - 10:30',null,null,6,'Em formação · início 20/02/27 · fim 03/07/27 · vem de MAST1-0035 (6 alunos em 26.2) · Box 26/11: 1 reservas, 0 matrículas novas'),
('ADV1-0046','ADV 1','SEG/QUA','19:10 - 20:25',null,null,15,'Em formação · início 15/02/27 · fim 23/06/27 · vem de PADV2-0047 (15 alunos em 26.2) · Box 26/11: 8 reservas, 0 matrículas novas'),
('ADV1-0047','ADV 1','SÁB','10:45 - 13:30',null,null,6,'Em formação · início 20/02/27 · fim 03/07/27 · 10:45-12:00 e 12:15-13:30 · vem de PADV2-0048 (6 alunos em 26.2) · Box 26/11: 0 reservas, 0 matrículas novas'),
('ADV2-0042','ADV 2','TER/QUI','17:45 - 19:00',null,null,11,'Em formação · início 16/02/27 · fim 24/06/27 · vem de ADV1-0044 (11 alunos em 26.2) · Box 26/11: 3 reservas, 0 matrículas novas'),
('ADV2-0041','ADV 2','SEG/QUA','19:10 - 20:25',null,null,14,'Em formação · início 15/02/27 · fim 21/06/27 · vem de ADV1-0043 (14 alunos em 26.2) · Box 26/11: 4 reservas, 0 matrículas novas'),
('ACC2-0002','ACC','SEG/QUA','20:25 - 21:35',null,null,3,'Em formação · início 15/02/27 · fim 23/06/27 · vem de ACC1-0011 (3 alunos em 26.2) · Box 26/11: 0 reservas, 0 matrículas novas'),
('KIDS3-0021','KIDS 3','TER/QUI','18:00 - 19:00',null,null,10,'Em formação · início 16/02/27 · fim 24/06/27 · vem de KIDS2-0022 (10 alunos em 26.2) · Box 26/11: 4 reservas, 0 matrículas novas'),
('KIDS3-0020','KIDS 3','TER/QUI','16:30 - 17:30',null,null,5,'Em formação · início 16/02/27 · fim 24/06/27 · vem de KIDS2-0021 (5 alunos em 26.2) · Box 26/11: 2 reservas, 0 matrículas novas'),
('Teen_UP2-0012','TEEN UP 2','SEG/QUA','19:10 - 20:25',null,null,7,'Em formação · início 15/02/27 · fim 23/06/27 · vem de Teen_UP1-0006 (5 alunos em 26.2) · Box 26/11: 2 reservas, 2 matrículas novas'),
('Teen_UP2-0011','TEEN UP 2','TER/QUI','16:15 - 17:30',null,null,8,'Em formação · início 16/02/27 · fim 01/06/27 · vem de KIDS4-0017 (7 alunos em 26.2) · Box 26/11: 2 reservas, 1 matrículas novas'),
('Teen_UP3-0006','TEEN UP 3','TER/QUI','15:15 - 16:30',null,null,12,'Em formação · início 16/02/27 · fim 24/06/27 · vem de Teen_UP2-0007 (12 alunos em 26.2) · Box 26/11: 4 reservas, 0 matrículas novas'),
('Teen_UP3-0007','TEEN UP 3','TER/QUI','17:45 - 19:00',null,null,13,'Em formação · início 16/02/27 · fim 17/06/27 · vem de Teen_UP2-0008 (12 alunos em 26.2) · Box 26/11: 6 reservas, 1 matrículas novas'),
('Teen_UP3-0008','TEEN UP 3','SÁB','10:45 - 13:30',null,null,12,'Em formação · início 20/02/27 · fim 26/06/27 · 10:45-12:00 e 12:15-13:30 · vem de Teen_UP2-0009 (12 alunos em 26.2) · Box 26/11: 3 reservas, 0 matrículas novas'),
('Teen_UP3-0009','TEEN UP 3','TER/QUI','19:10 - 20:25',null,null,9,'Em formação · início 16/02/27 · fim 24/06/27 · vem de Teen_UP2-0010 (9 alunos em 26.2) · Box 26/11: 3 reservas, 0 matrículas novas'),
('Teen_UP4-0004','TEEN UP 4','TER/QUI','17:45 - 19:00',null,null,11,'Em formação · início 16/02/27 · fim 24/06/27 · vem de Teen_UP3-0004 (11 alunos em 26.2) · Box 26/11: 4 reservas, 0 matrículas novas'),
('Teen_UP4-0005','TEEN UP 4','SEG/QUA','17:45 - 19:00',null,null,14,'Em formação · início 15/02/27 · fim 23/06/27 · vem de Teen_UP3-0005 (14 alunos em 26.2) · Box 26/11: 4 reservas, 0 matrículas novas'),
('Teen_UP4-0003','TEEN UP 4','SEG/QUA','16:15 - 17:30',null,null,17,'Em formação · início 15/02/27 · fim 23/06/27 · vem de Teen_UP3-0003 (17 alunos em 26.2) · Box 26/11: 7 reservas, 0 matrículas novas'),
('Teen_UP5-0002','TEEN UP 5','SEG/QUA','16:15 - 17:30',null,null,7,'Em formação · início 15/02/27 · fim 23/06/27 · vem de Teen_UP4-0002 (7 alunos em 26.2) · Box 26/11: 2 reservas, 0 matrículas novas'),
('Teen_UP6-0001','TEEN UP 6','TER/QUI','19:10 - 20:25',null,null,12,'Em formação · início 16/02/27 · fim 03/06/27 · vem de Teen_UP5-0001 (12 alunos em 26.2, ligação inferida por dia/horário/sala) · Box 26/11: 4 reservas, 0 matrículas novas'),
('A1-2-0013','A1.2/FLY 2','TER/QUI','19:10 - 20:25',null,null,10,'Em formação · início 16/02/27 · fim 24/06/27 · vem de A1-1-0011 (8 alunos em 26.2) · Box 26/11: 0 reservas, 2 matrículas novas'),
('A2-1-0007','A2.1/QUEST 1','SEG/QUA','19:10 - 20:25',null,null,16,'Em formação · início 15/02/27 · fim 23/06/27 · vem de A1-2-0011 (16 alunos em 26.2) · Box 26/11: 2 reservas, 0 matrículas novas'),
('A2-1-0008','A2.1/QUEST 1','SÁB','10:45 - 13:30',null,null,11,'Em formação · início 20/02/27 · fim 03/07/27 · 10:45-12:00 e 12:15-13:30 · vem de A1-2-0012 (11 alunos em 26.2) · Box 26/11: 3 reservas, 0 matrículas novas'),
('A2-2-0005','A2.2/QUEST 2','TER/QUI','17:45 - 19:00',null,null,11,'Em formação · início 16/02/27 · fim 24/06/27 · vem de A2-1-0006 (11 alunos em 26.2) · Box 26/11: 5 reservas, 0 matrículas novas'),
('A2-2-0004','A2.2/QUEST 2','SÁB','10:45 - 13:30',null,null,7,'Em formação · início 20/02/27 · fim 03/07/27 · 10:45-12:00 e 12:15-13:30 · vem de A2-1-0005 (7 alunos em 26.2) · Box 26/11: 1 reservas, 0 matrículas novas'),
('A2-2-0003','A2.2/QUEST 2','TER/QUI','19:10 - 20:25',null,null,12,'Em formação · início 16/02/27 · fim 24/06/27 · vem de A2-1-0004 (12 alunos em 26.2) · Box 26/11: 5 reservas, 0 matrículas novas'),
('B1-1-0002','B1.1','SÁB','08:00 - 10:30',null,null,6,'Em formação · início 20/02/27 · fim 10/07/27 · vem de A2-2-0002 (6 alunos em 26.2, ligação inferida por dia/horário/sala) · Box 26/11: 4 reservas, 0 matrículas novas'),
('B1-1-0001','B1.1','SEG/QUA','19:10 - 20:25',null,null,15,'Em formação · início 15/02/27 · fim 07/07/27 · vem de A2-2-0001 (15 alunos em 26.2, ligação inferida por dia/horário/sala) · Box 26/11: 6 reservas, 0 matrículas novas'),
('KIDS1-0026','KIDS 1','SEG/QUA','16:30 - 17:30','SALA 1',null,0,'Em formação · início 15/02/27 · fim 21/06/27 · sem turma anterior · Box 26/11: 0 reservas, 0 matrículas novas'),
('MAST2-0034','MASTER 2','SEG/QUA','19:10 - 20:25','SALA 6',null,9,'Em formação · início 15/02/27 · fim 23/06/27 · vem de MAST1-0034 (9 alunos em 26.2) · Box 26/11: 2 reservas, 0 matrículas novas'),
('Teen_UP1-0008','TEEN UP 1','SÁB','10:45 - 13:30','AUDITÓRIO',null,0,'Em formação · início 20/02/27 · fim 19/06/27 · 10:45-12:00 e 12:15-13:30 · sem turma anterior · Box 26/11: 0 reservas, 0 matrículas novas'),
('A1-1-0013','A1.1/FLY 1','SÁB','08:00 - 10:30','AUDITÓRIO',null,2,'Em formação · início 20/02/27 · fim 19/06/27 · sem turma anterior · Box 26/11: 0 reservas, 2 matrículas novas'),
('A1-1-0012','A1.1/FLY 1','TER/QUI','19:10 - 20:25','AUDITÓRIO',null,8,'Em formação · início 16/02/27 · fim 10/06/27 · sem turma anterior · Box 26/11: 0 reservas, 8 matrículas novas'),
('PS1-0016','GARDEN 1','SEG/QUA','16:30 - 17:30','GARDEN',null,1,'Em formação · início 15/02/27 · fim 21/06/27 · sem turma anterior · Box 26/11: 0 reservas, 1 matrículas novas'),
('PS2-0011','GARDEN 2','TER/QUI','19:00 - 20:00','GARDEN',null,5,'Em formação · início 16/02/27 · fim 22/06/27 · vem de PS1-0015 (4 alunos em 26.2) · Box 26/11: 0 reservas, 1 matrículas novas'),
('YK2-0017','YOUNG KIDS 2/FUN 2','SÁB','10:45 - 13:30','GARDEN',null,3,'Em formação · início 20/02/27 · fim 05/06/27 · 10:45-12:00 e 12:15-13:30 · vem de YK1-0021 (2 alunos em 26.2) · Box 26/11: 0 reservas, 1 matrículas novas'),
('Teen_UP1-0007','TEEN UP 1','SEG/QUA','17:45 - 19:00','SALA 4',null,0,'Em formação · início 15/02/27 · fim 14/06/27 · sem turma anterior · Box 26/11: 0 reservas, 0 matrículas novas'),
('YK1-0025','YOUNG KIDS 1/FUN 1','TER/QUI','18:00 - 19:00','SALA 2','Raissa',10,'Em formação · início 16/02/27 · fim 17/06/27 · vem de PS4-0005 (10 alunos em 26.2, ligação inferida por dia/horário/sala) · Box 26/11: 7 reservas, 0 matrículas novas'),
('KIDS4-0020','KIDS 4','SEG/QUA','18:00 - 19:00','SALA 2','Raissa',8,'Em formação · início 15/02/27 · fim 31/05/27 · vem de KIDS3-0019 (8 alunos em 26.2) · Box 26/11: 3 reservas, 0 matrículas novas'),
('KIDS4-0019','KIDS 4','TER/QUI','18:00 - 19:00','SALA 1','Rafael',13,'Em formação · início 16/02/27 · fim 24/06/27 · vem de KIDS3-0018 (13 alunos em 26.2) · Box 26/11: 6 reservas, 0 matrículas novas'),
('KIDS4-0018','KIDS 4','SEG/QUA','18:00 - 19:00','SALA 3','Rafael',7,'Em formação · início 15/02/27 · fim 23/06/27 · vem de KIDS3-0017 (7 alunos em 26.2) · Box 26/11: 6 reservas, 0 matrículas novas'),
('YK1-0024','YOUNG KIDS 1/FUN 1','TER/QUI','18:00 - 19:00','GARDEN','Mariana',10,'Em formação · início 16/02/27 · fim 17/06/27 · vem de PS4-0006 (10 alunos em 26.2, ligação inferida por dia/horário/sala) · Box 26/11: 3 reservas, 0 matrículas novas'),
('YK4-0013','YOUNG KIDS 4/FUN 4','SEG/QUA','18:00 - 19:00','GARDEN','Mariana',8,'Em formação · início 15/02/27 · fim 31/05/27 · vem de YK3-0016 (8 alunos em 26.2) · Box 26/11: 2 reservas, 0 matrículas novas'),
('YK4-0012','YOUNG KIDS 4/FUN 4','SEG/QUA','18:00 - 19:00','SALA 1','Carolline',7,'Em formação · início 15/02/27 · fim 23/06/27 · vem de YK3-0015 (7 alunos em 26.2) · Box 26/11: 2 reservas, 0 matrículas novas');

  create temp table _old on commit drop as select * from crm_turmas where unidade='taquara' and semestre='2027.1' and ativa;

  insert into crm_turmas (unidade,semestre,codigo,curso,dias,horario,sala,professor,alunos,capacidade,sem_vaga,ativa,obs)
  select 'taquara','2027.1',b.codigo,b.curso,b.dias,b.horario,
         coalesce(b.sala, case when m.n=1 then m.sala end, 'A DEFINIR'),
         coalesce(b.professor, case when m.n=1 then m.professor end),
         b.alunos,
         coalesce(case when m.n=1 then m.capacidade end, case when b.curso ~ '^(KIDS|YOUNG|GARDEN)' then 10 when b.curso ~ '^TEEN' then 14 else 16 end),
         b.alunos >= coalesce(case when m.n=1 then m.capacidade end, case when b.curso ~ '^(KIDS|YOUNG|GARDEN)' then 10 when b.curso ~ '^TEEN' then 14 else 16 end),
         true, b.obs
  from _box b
  left join lateral (select o.sala,o.professor,o.capacidade,
                            (select count(*) from _old o2 where o2.curso=b.curso and o2.dias=b.dias and left(o2.horario,5)=left(b.horario,5)) n
                     from _old o where o.curso=b.curso and o.dias=b.dias and left(o.horario,5)=left(b.horario,5) limit 1) m on true;
  get diagnostics n = row_count;
  if n <> 51 then raise exception 'insert atingiu %, esperava 51', n; end if;

  update crm_turmas t set ativa=false, atualizado_em=now(),
         obs = coalesce(t.obs||' · ','') || 'Inativada em 26/11/2026: mapa 27.1 substituído pelas turmas do CNA Box'
  where t.id in (select id from _old);
  get diagnostics n = row_count;
  if n <> 51 then raise exception 'inativação atingiu %, esperava 51', n; end if;
end $$;
select ativa, count(*), sum(alunos), count(*) filter (where sala='A DEFINIR') sem_sala, count(*) filter (where professor is null) sem_prof, count(*) filter (where sem_vaga) lotadas
from crm_turmas where unidade='taquara' and semestre='2027.1' group by ativa;