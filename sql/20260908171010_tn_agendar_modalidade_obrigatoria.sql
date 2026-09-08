-- 20260908171010_tn_agendar_modalidade_obrigatoria.sql · 08/09/2026
-- Recria crm_tn_agendar. Mudancas:
--   1. o slot passa a ser identificado por data + hora + aplicadora; a modalidade
--      e' validada depois, porque a faixa pode aceitar as duas;
--   2. faixa 'ambas' grava a modalidade escolhida por quem agendou;
--   3. faixa fechada recusa modalidade divergente;
--   4. agendamento sem presencial/online definido e' recusado — o Meet depende disso.
-- Validado em BEGIN..ROLLBACK: faixa 'ambas' aparece nos dois filtros, agendar sem
-- modalidade e' barrado com mensagem propria, e a escolha e' gravada corretamente.

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
  v_mod  text;
begin
  select * into v_lead from crm_leads where id = p_lead_id;
  if not found then
    raise exception 'Lead não encontrado.' using errcode = 'P0002';
  end if;

  select * into v_slot
    from crm_tn_disponibilidade(p_data, p_data, null, p_aplicador, true)
   where hora_inicio = p_hora_inicio
   limit 1;

  if not found then
    raise exception 'Este horário não está mais na disponibilidade publicada.' using errcode = 'P0001';
  end if;
  if v_slot.ocupado then
    raise exception 'Horário já ocupado por %.', coalesce(v_slot.ocupado_por,'outro agendamento') using errcode = 'P0001';
  end if;

  if v_slot.modalidade = 'ambas' then
    v_mod := p_modalidade;
  else
    v_mod := v_slot.modalidade;
    if p_modalidade is not null and p_modalidade <> v_slot.modalidade then
      raise exception 'Este horário é só %.', v_slot.modalidade using errcode = 'P0001';
    end if;
  end if;

  if v_mod is null or v_mod not in ('presencial','online') then
    raise exception 'Informe se o teste é presencial ou online.' using errcode = 'P0001';
  end if;

  v_dur := coalesce(p_duracao_min, v_slot.duracao_min);

  insert into crm_tn_agendamentos(
    lead_id, data, hora_inicio, hora_fim, duracao_min, modalidade, aplicador,
    origem_tipo, origem_id, nome_aluno, email, whatsapp, observacoes, criado_por)
  values(
    p_lead_id, p_data, p_hora_inicio, v_slot.hora_fim, v_dur, v_mod, v_slot.aplicador,
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
