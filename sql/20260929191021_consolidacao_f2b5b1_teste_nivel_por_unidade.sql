-- Consolidação · Fase 2b-5b-1: teste de nível por unidade.
-- crm_tn_disponibilidade ganha p_unidade (default 'taquara'); grade, vagas avulsas, bloqueios
-- e agendamentos filtrados pela unidade. crm_tn_agendar mantém a assinatura: a unidade vem do lead.
-- Regra preservada: slot ocupado é a única exceção que bloqueia (regra 2 do CRM).

drop function if exists public.crm_tn_disponibilidade(date, date, text, text, boolean);

create function public.crm_tn_disponibilidade(p_de date, p_ate date, p_modalidade text default null, p_aplicador text default null, p_incluir_ocupados boolean default false, p_unidade text default 'taquara')
 returns table(data date, hora_inicio time without time zone, hora_fim time without time zone, duracao_min smallint, modalidade text, aplicador text, origem_tipo text, origem_id uuid, ocupado boolean, agendamento_id uuid, ocupado_por text)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
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
     and g.unidade = p_unidade
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
   where a.ativo and a.tipo = 'vaga' and a.unidade = p_unidade
     and a.data between p_de and p_ate
),
livres as (
  select b.*
    from brutos b
   where not exists (
     select 1 from crm_tn_avulsos bl
      where bl.ativo and bl.tipo = 'bloqueio' and bl.unidade = p_unidade and bl.data = b.data
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
    on ag.unidade = p_unidade
   and ag.data = l.data and ag.hora_inicio = l.hora_inicio
   and ag.aplicador = l.aplicador and ag.status <> 'cancelado'
 -- faixa marcada como 'ambas' atende os dois filtros
 where (p_modalidade is null or l.modalidade = p_modalidade or l.modalidade = 'ambas')
   and (p_aplicador is null or l.aplicador = p_aplicador)
   and (p_incluir_ocupados or ag.id is null)
   and (l.data > (now() at time zone 'America/Sao_Paulo')::date
        or (l.data = (now() at time zone 'America/Sao_Paulo')::date
            and l.hora_inicio > (now() at time zone 'America/Sao_Paulo')::time))
 order by l.data, l.hora_inicio, l.aplicador;
$function$;

grant execute on function public.crm_tn_disponibilidade(date, date, text, text, boolean, text) to anon, authenticated;

create or replace function public.crm_tn_agendar(p_lead_id uuid, p_data date, p_hora_inicio time without time zone, p_aplicador text, p_modalidade text, p_email text default null, p_observacoes text default null, p_criado_por text default null, p_origem_tipo text default 'grade', p_origem_id uuid default null, p_duracao_min smallint default null)
 returns crm_tn_agendamentos
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
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

  -- o slot e' identificado por data, hora e aplicadora, dentro da unidade do lead.
  -- A modalidade e' validada depois, porque a faixa pode aceitar as duas.
  select * into v_slot
    from crm_tn_disponibilidade(p_data, p_data, null, p_aplicador, true, v_lead.unidade)
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
    unidade, lead_id, data, hora_inicio, hora_fim, duracao_min, modalidade, aplicador,
    origem_tipo, origem_id, nome_aluno, email, whatsapp, observacoes, criado_por)
  values(
    v_lead.unidade, p_lead_id, p_data, p_hora_inicio, v_slot.hora_fim, v_dur, v_mod, v_slot.aplicador,
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
$function$;

notify pgrst, 'reload schema';