-- 20260929120000_metas_conciliacao_box_taquara.sql
-- CNA Taquara · CRM (gpnwmsnayrqjcmhqrtpx) · unidade = 'taquara'
-- APLICADO em 01/10/2026 pelo Project CNA Sistemas, com aprovação do Pedro. Contagens iguais ao ensaio (6 semestres, 2 indicadores, 4 faixas, 6 meses).
-- Ensaiado antes em 29/09 e 30/09 (este último já na base única, com rollback).
-- Ao aplicar: copiar para sql/ do repo cnataquara-crm com este mesmo nome.
-- Conciliação das metas com as extrações do CNA Box de 29/09/2026:
--   1) matrículas históricas passam a ser as VERIFICADAS do Box
--   2) proposta de metas de matrícula Out/2026 a Mar/2027 (106 · 113 · 124 · 135)
--   3) ritmo mensal recalculado com as verificadas
-- Rema contratual e rema total NÃO mudam (método confere com o dado novo).
-- Pendentes de decisão, fora deste script: base de Abr a Set/2022, tipo dos 10 não-Extensivo de Out/2025 a Mar/2026,
-- ajuste de Set/2026, valores em R$. Nada destrutivo: só UPDATE em linhas identificadas.

begin;

update crm_metas_semestre s set matriculas = v.mat,
       obs = trim(both ' ' from coalesce(s.obs,'') || ' · matrículas = Box verificadas 29/09/2026 (antes ' || s.matriculas || ')'),
       atualizado_em = now(), atualizado_por = 'conciliação Box 29/09'
from (values
  ('2022-04-01'::date,141),('2022-10-01',137),('2023-04-01',80),('2023-10-01',120),
  ('2024-10-01',117),('2025-10-01',101)
) v(inicio,mat)
where s.unidade='taquara' and s.inicio=v.inicio and s.matriculas<>v.mat;

update crm_metas_indicador i set base_media=112.67, base_ref=101,
       obs='média 3 últimos Out a Mar verificados (120, 117, 101) = 112,7 · último 101 · Box 29/09/2026'
from crm_metas_periodo p
where i.periodo_id=p.id and p.unidade='taquara' and p.inicio='2026-10-01' and i.indicador='matricula';

update crm_metas_indicador i set base_media=77.87,
       obs='pico de Abr a Set/2026 (509, set. aberto) · manutenção média 77,9% com matrícula verificada'
from crm_metas_periodo p
where i.periodo_id=p.id and p.unidade='taquara' and p.inicio='2026-10-01' and i.indicador='rema_total';

update crm_metas_faixa f set alvo=v.alvo, regra=v.regra
from crm_metas_indicador i
join crm_metas_periodo p on p.id=i.periodo_id,
(values (1,106,'último ano + 5% (101)'),(2,113,'média de 3 anos (112,7)'),(3,124,'média + 10%'),(4,135,'média + 20%')) v(nivel,alvo,regra)
where f.indicador_id=i.id and i.indicador='matricula' and p.unidade='taquara' and p.inicio='2026-10-01' and f.nivel=v.nivel;

update crm_metas_mes m set ritmo_1=v.r1, ritmo_ult=v.r4
from crm_metas_periodo p,
(values ('2026-10-01'::date,8,11),('2026-11-01',15,19),('2026-12-01',9,11),('2027-01-01',32,41),('2027-02-01',27,34),('2027-03-01',15,19)) v(mes,r1,r4)
where m.periodo_id=p.id and p.unidade='taquara' and p.inicio='2026-10-01' and m.mes=v.mes;

select inicio, matriculas, obs from crm_metas_semestre where unidade='taquara' order by inicio;

commit;
