-- 20260908170953_tn_disponibilidade_ambas.sql · 08/09/2026
-- Recria crm_tn_disponibilidade: faixa 'ambas' aparece nos dois filtros.

-- 002-teste-de-nivel-agendamento.sql
-- Projeto: cnataquara-comercial (gpnwmsnayrqjcmhqrtpx)
-- Aplicado em producao em 08/09/2026, nas migracoes:
--   tn_agendamento_tabelas · tn_agendamento_rls · tn_disponibilidade_fn · tn_agendar_fn
--
-- O que este arquivo cria:
--   1. crm_tn_grade        — grade semanal recorrente publicada pelo pedagogico
--   2. crm_tn_avulsos      — vagas extras e bloqueios pontuais (dia inteiro ou faixa)
--   3. crm_tn_agendamentos — o teste marcado, sempre amarrado a um lead do funil B2C
--   4. crm_leads.email     — coluna nova; nao existia e e' o que permite convidar no Google
--   5. crm_tn_disponibilidade() — expande grade + avulsos - bloqueios - ocupados
--   6. crm_tn_agendar()         — reserva o slot com guarda de concorrencia
--
-- Validado em BEGIN..ROLLBACK (08/09/2026): 13 slots em 14 dias, bloqueio de dia
-- inteiro zera o dia, slot ocupado barra o segundo agendamento, horario fora da
-- grade e' recusado, lead sai com proximo_canal = 'teste_nivel'.

-- ============================================================ 3. disponibilidade

create or replace function crm_tn_disponibilidade(
  p_de date,
  p_ate date,
  p_modalidade text default null,
  p_aplicador text default null,
  p_incluir_ocupados boolean default false
) returns table(
  data date, hora_inicio time, hora_fim time, duracao_min smallint,
  modalidade text, aplicador text, origem_tipo text, origem_id uuid,
  ocupado boolean, agendamento_id uuid, ocupado_por text
)
language sql
stable
security definer
set search_path = public
as $fn$
with dias as (
  select d::date as data from generate_series(p_de, p_ate, interval '1 day') d
),
brutos as (
  select di.data,
         (g.hora_inicio + (n * make_interval(mins => g.duracao_min)))::time as hora_inicio,
         (g.hora_inicio + ((n+1) * make_interval(mins => g.duracao_min)))::time as hora_fim,
         g.duracao_min, g.modalidade, g.aplicador,
         'grade'::text as origem_tipo, g.id as origem_id
    from dias di
    join crm_tn_grade g
      on g.ativo
     and g.dia_semana = extract(dow from di.data)::smallint
     and di.data >= g.vigencia_inicio
     and (g.vigencia_fim is null or di.data <= g.vigencia_fim)
   cross join lateral generate_series(
      0,
      greatest(floor(extract(epoch from (g.hora_fim - g.hora_inicio)) / (g.duracao_min * 60))::int - 1, 0)
   ) as n
   where (g.hora_inicio + ((n+1) * make_interval(mins => g.duracao_min)))::time <= g.hora_fim
  union all
  select a.data, a.hora_inicio,
         coalesce(a.hora_fim, (a.hora_inicio + make_interval(mins => a.duracao_min))::time),
         a.duracao_min, a.modalidade, a.aplicador,
         'avulso'::text, a.id
    from crm_tn_avulsos a
   where a.ativo and a.tipo = 'vaga'
     and a.data between p_de and p_ate
),
livres as (
  select b.*
    from brutos b
   where not exists (
     select 1 from crm_tn_avulsos bl
      where bl.ativo and bl.tipo = 'bloqueio' and bl.data = b.data
        and (bl.aplicador is null or bl.aplicador = b.aplicador)
        and (bl.hora_inicio is null
             or (b.hora_inicio < coalesce(bl.hora_fim, time '23:59:59') and b.hora_fim > bl.hora_inicio))
   )
)
select l.data, l.hora_inicio, l.hora_fim, l.duracao_min, l.modalidade, l.aplicador,
       l.origem_tipo, l.origem_id,
       (ag.id is not null) as ocupado,
       ag.id as agendamento_id,
       ag.nome_aluno as ocupado_por
  from livres l
  left join crm_tn_agendamentos ag
    on ag.data = l.data and ag.hora_inicio = l.hora_inicio
   and ag.aplicador = l.aplicador and ag.status <> 'cancelado'
 -- faixa marcada como 'ambas' atende os dois filtros
 where (p_modalidade is null or l.modalidade = p_modalidade or l.modalidade = 'ambas')
   and (p_aplicador is null or l.aplicador = p_aplicador)
   and (p_incluir_ocupados or ag.id is null)
   and (l.data > (now() at time zone 'America/Sao_Paulo')::date
        or (l.data = (now() at time zone 'America/Sao_Paulo')::date
            and l.hora_inicio > (now() at time zone 'America/Sao_Paulo')::time))
 order by l.data, l.hora_inicio, l.aplicador;
$fn$;

