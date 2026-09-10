-- 10/09/2026 · cnataquara-comercial (gpnwmsnayrqjcmhqrtpx) · aplicado via execute_sql
-- 1) Mapa 2027.1: Pedro confirmou que as turmas de origem foram divididas em duas.
--    A planilha trazia 15 no YK4 da Carolline e no Kids 4 do Rafael; vale o que o CRM 2026.2 tem.
update crm_turmas set alunos=7, sem_vaga=false, obs=null, atualizado_em=now()
 where semestre='2027.1' and dias='SEG/QUA' and sala='SALA 1' and curso='YOUNG KIDS 4/FUN 4' and professor='Carolline';
update crm_turmas set alunos=8, obs=null, atualizado_em=now()
 where semestre='2027.1' and dias='SEG/QUA' and sala='GARDEN' and curso='YOUNG KIDS 4/FUN 4';
update crm_turmas set alunos=7, sem_vaga=false, obs=null, atualizado_em=now()
 where semestre='2027.1' and dias='SEG/QUA' and sala='SALA 3' and curso='KIDS 4' and professor='Rafael';
update crm_turmas set alunos=8, obs=null, atualizado_em=now()
 where semestre='2027.1' and dias='SEG/QUA' and sala='SALA 2' and curso='KIDS 4' and professor='Raissa';

-- 2) Decisao 10/09/2026: lead novo so matricula em turma de 2027.1 (as de 2026.2 ja comecaram).
--    O front le esta chave (tSemRef). Valor anterior ao semestre em aulas e ignorado.
insert into crm_configs (chave, valor, descricao, atualizado_em)
values ('turmas_semestre_matricula','2027.1','Semestre em que lead novo matricula (campo Turma da ficha, dica de faixa, fila de espera, demanda por nivel). Anterior ao semestre em aulas e ignorado.', now())
on conflict (chave) do update set valor=excluded.valor, descricao=excluded.descricao, atualizado_em=now();
