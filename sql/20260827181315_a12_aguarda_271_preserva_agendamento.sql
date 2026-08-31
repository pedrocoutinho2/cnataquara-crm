-- A12 · plano-correcao-crm-2026-08-27, onda 1
--
-- Antes: entrar em "Aguardando 27.1" carimbava 01/10 09:00 por cima de qualquer
-- agendamento ja combinado com o lead, e ao SAIR da etapa o carimbo de outubro ficava.
-- Em 27/08 havia 2 leads fora da etapa carregando o carimbo residual.
--
-- Agora:
--  * INSERT  -> carimba sempre. Regra 7 do vault ("01/10 se entrar em Aguardando 27.1")
--               depende disso, porque crm_leads_agenda_novo_tg roda antes na ordem
--               alfabetica e ja teria preenchido proximo_atendimento com +10 minutos.
--  * UPDATE entrando na etapa -> so carimba quando nao ha agendamento util:
--               campo vazio ou data no passado. Compromisso combinado com o lead vence
--               a data padrao do semestre seguinte.
--  * UPDATE saindo da etapa -> se o agendamento ainda for exatamente o carimbo do
--               trigger, devolve o lead para a fila do responsavel com a mesma convencao
--               de crm_leads_agenda_novo (+10 minutos), em vez de deixa-lo em outubro.

create or replace function public.crm_leads_aguarda_271()
 returns trigger
 language plpgsql
as $function$
declare
  -- Etapa "Aguardando 27.1": quem entrar na coluna sai com o proximo contato
  -- carimbado em 01/10. Para mudar a data do proximo semestre, altere aqui.
  v_data date := date '2026-10-01';
  v_hora time := time '09:00';
  v_agora timestamp := (now() at time zone 'America/Sao_Paulo') + interval '10 minutes';
  v_entrando boolean;
  v_saindo boolean;
begin
  v_entrando := new.etapa = 'aguardando_271'
                and (tg_op = 'INSERT' or old.etapa is distinct from new.etapa);

  v_saindo := tg_op = 'UPDATE'
              and old.etapa = 'aguardando_271'
              and new.etapa is distinct from old.etapa;

  if v_entrando then
    -- A12: no UPDATE, agendamento futuro ja combinado nao e sobrescrito.
    if tg_op = 'INSERT'
       or new.proximo_atendimento is null
       or new.proximo_atendimento < (now() at time zone 'America/Sao_Paulo')::date then
      new.proximo_atendimento := v_data;
      new.proximo_atendimento_hora := v_hora;
    end if;
    if new.proximo_canal is null then new.proximo_canal := 'whatsapp'; end if;
    new.data_fechamento := null;
    new.motivo_perda := null;
  end if;

  if v_saindo
     and new.proximo_atendimento = v_data
     and new.proximo_atendimento_hora is not distinct from v_hora then
    -- Carimbo do trigger, nao compromisso de ninguem: volta para a fila de hoje.
    new.proximo_atendimento := v_agora::date;
    new.proximo_atendimento_hora := date_trunc('minute', v_agora)::time;
  end if;

  return new;
end $function$;

notify pgrst, 'reload schema';