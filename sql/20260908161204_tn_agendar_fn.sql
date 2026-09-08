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

-- ============================================================ 4. reserva

create or replace function crm_tn_agendar(
  p_lead_id uuid,
  p_data date,
  p_hora_inicio time,
  p_aplicador text,
  p_modalidade text,
  p_email text default null,
  p_observacoes text default null,
  p_criado_por text default null,
  p_origem_tipo text default 'grade',
  p_origem_id uuid default null,
  p_duracao_min smallint default null
) returns crm_tn_agendamentos
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_slot record;
  v_lead record;
  v_ag   crm_tn_agendamentos;
  v_dur  smallint;
begin
  select * into v_lead from crm_leads where id = p_lead_id;
  if not found then
    raise exception 'Lead não encontrado.' using errcode = 'P0002';
  end if;

  select * into v_slot
    from crm_tn_disponibilidade(p_data, p_data, null, p_aplicador, true)
   where hora_inicio = p_hora_inicio
     and (p_modalidade is null or modalidade = p_modalidade)
   limit 1;

  if not found then
    raise exception 'Este horário não está mais na disponibilidade publicada.' using errcode = 'P0001';
  end if;
  if v_slot.ocupado then
    raise exception 'Horário já ocupado por %.', coalesce(v_slot.ocupado_por,'outro agendamento') using errcode = 'P0001';
  end if;

  v_dur := coalesce(p_duracao_min, v_slot.duracao_min);

  insert into crm_tn_agendamentos(
    lead_id, data, hora_inicio, hora_fim, duracao_min, modalidade, aplicador,
    origem_tipo, origem_id, nome_aluno, email, whatsapp, observacoes, criado_por)
  values(
    p_lead_id, p_data, p_hora_inicio, v_slot.hora_fim, v_dur, v_slot.modalidade, v_slot.aplicador,
    coalesce(v_slot.origem_tipo, p_origem_tipo), coalesce(v_slot.origem_id, p_origem_id),
    coalesce(v_lead.nome_aluno, v_lead.nome), p_email, v_lead.whatsapp, p_observacoes, p_criado_por)
  returning * into v_ag;

  if p_email is not null and coalesce(v_lead.email,'') = '' then
    update crm_leads set email = p_email, updated_at = now() where id = p_lead_id;
  end if;

  update crm_leads
     set proximo_atendimento = p_data,
         proximo_atendimento_hora = p_hora_inicio,
         proximo_canal = 'teste_nivel',
         updated_at = now()
   where id = p_lead_id;

  return v_ag;
end;
$fn$;

notify pgrst, 'reload schema';
