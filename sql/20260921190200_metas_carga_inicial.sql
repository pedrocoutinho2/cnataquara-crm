-- Carga inicial: histórico por semestre (Abr/2022 em diante, conferido em 21/09/2026)
-- e metas de Abr a Set/2026 (planilha) e Out/2026 a Mar/2027 (rascunho).
insert into crm_metas_semestre(inicio,fim,matriculas,rema_auto,rema_contratual,base_auto,base_contratual,obs,atualizado_por) values
 ('2022-04-01','2022-09-30',153,283,99,284,104,null,'carga inicial'),
 ('2022-10-01','2023-03-31',144,221,221,221,287,null,'carga inicial'),
 ('2023-04-01','2023-09-30',81,318,172,318,223,null,'carga inicial'),
 ('2023-10-01','2024-03-31',127,209,226,209,317,null,'carga inicial'),
 ('2024-04-01','2024-09-30',80,311,138,311,184,null,'carga inicial'),
 ('2024-10-01','2025-03-31',120,177,241,177,316,'bloco do próprio período dizia 117 matrículas','carga inicial'),
 ('2025-04-01','2025-09-30',57,333,135,337,177,'bloco do próprio período dizia 56 matrículas','carga inicial'),
 ('2025-10-01','2026-03-31',97,159,252,170,331,null,'carga inicial'),
 ('2026-04-01','2026-09-30',60,322,127,324,162,'em andamento: setembro aberto','carga inicial')
on conflict (inicio) do nothing;

do $$
declare p1 uuid; p2 uuid; i uuid;
begin
  -- Abr a Set/2026 (em andamento)
  insert into crm_metas_periodo(inicio,fim,status,atualizado_por) values ('2026-04-01','2026-09-30','ativa','carga inicial')
  on conflict (inicio) do nothing returning id into p1;
  if p1 is not null then
    insert into crm_metas_indicador(periodo_id,indicador,base_media,base_ref,obs) values (p1,'matricula',null,null,'meta geral 127 da planilha') returning id into i;
    insert into crm_metas_faixa(indicador_id,nivel,alvo,regra,valor_rs) values (i,1,105,'faixa 105 a 110',300),(i,2,111,'faixa 111 a 120',400),(i,3,121,'faixa 121 a 130',500),(i,4,130,'130 ou mais',600);
    insert into crm_metas_indicador(periodo_id,indicador,base_media,base_ref,obs) values (p1,'rema_contratual',null,162,'meta de 151 alunos') returning id into i;
    insert into crm_metas_faixa(indicador_id,nivel,alvo,regra,valor_rs) values (i,1,122,'81% de 151',200),(i,2,125,'83% de 151',400),(i,3,128,'85% de 151',600),(i,4,134,'89% de 151',1000);
    insert into crm_metas_indicador(periodo_id,indicador,base_media,base_ref,obs) values (p1,'rema_total',null,508,'metas não definidas na planilha');
    insert into crm_metas_mes(periodo_id,mes,ritmo_1,ajuste) values
      (p1,'2026-04-01',15,2),(p1,'2026-05-01',18,8),(p1,'2026-06-01',24,11),(p1,'2026-07-01',35,18),(p1,'2026-08-01',27,20),(p1,'2026-09-01',8,1);
  end if;
  -- Out/2026 a Mar/2027 (rascunho)
  insert into crm_metas_periodo(inicio,fim,status,atualizado_por) values ('2026-10-01','2027-03-31','rascunho','carga inicial')
  on conflict (inicio) do nothing returning id into p2;
  if p2 is not null then
    insert into crm_metas_indicador(periodo_id,indicador,base_media,base_ref,obs) values (p2,'matricula',114.7,97,'média de 3 anos 114,7 · último ano 97') returning id into i;
    insert into crm_metas_faixa(indicador_id,nivel,alvo,regra) values (i,1,102,'último ano + 5%'),(i,2,115,'média de 3 anos'),(i,3,126,'média + 10%'),(i,4,138,'média + 20%');
    insert into crm_metas_indicador(periodo_id,indicador,base_media,base_ref,obs) values (p2,'rema_contratual',74.56,322,'base contratual projetada') returning id into i;
    insert into crm_metas_faixa(indicador_id,nivel,alvo,regra) values (i,1,235,'73,1% · média − 1,5 pt'),(i,2,245,'76,1%'),(i,3,255,'79,1%'),(i,4,264,'82,1%');
    insert into crm_metas_indicador(periodo_id,indicador,base_media,base_ref,obs) values (p2,'rema_total',77.83,509,'pico de Abr a Set/2026, parcial') returning id into i;
    insert into crm_metas_faixa(indicador_id,nivel,alvo,regra) values (i,1,389,'76,3% · média − 1,5 pt'),(i,2,404,'79,3%'),(i,3,419,'82,3%'),(i,4,434,'85,3%');
    insert into crm_metas_mes(periodo_id,mes,ritmo_1,ritmo_ult) values
      (p2,'2026-10-01',8,11),(p2,'2026-11-01',16,21),(p2,'2026-12-01',8,10),(p2,'2027-01-01',32,44),(p2,'2027-02-01',25,34),(p2,'2027-03-01',13,18);
  end if;
end $$;
