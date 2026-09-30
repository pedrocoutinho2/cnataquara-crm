-- Consolidação · Fase 2b-5b-3: varredura do WhatsApp (cron */15) por unidade.
-- Cada regra só alcança leads da própria unidade; nome da unidade no texto vem de crm_unidades
-- (antes estava fixo "CNA Taquara"); vínculo fila x conversa exige mesma unidade (número por unidade).
-- Ensaio com as 3 regras ativadas em transação desfeita: mesmas 6 linhas na fila, mesmo texto.
create or replace function public.crm_wa_varrer()
 returns table(regra text, criados integer)
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  r record;
  hoje date := crm_hoje_br();
  agora timestamptz := now();
  dow int := extract(dow from (now() at time zone 'America/Sao_Paulo'))::int;
  hora time := (now() at time zone 'America/Sao_Paulo')::time;
  n int;
  alvo timestamptz;
  dias int;
  v_marca text;
begin
  for r in select * from crm_wa_regras where ativa order by unidade, chave loop
    n := 0;
    -- nome da unidade vem do cadastro, nunca fixo no código
    select 'CNA ' || nome into v_marca from crm_unidades where slug = r.unidade;

    -- janela de horario e dia da semana, avaliadas no fuso de Brasilia
    if not (dow = any(r.dias_semana)) then
      regra := r.chave; criados := 0; return next; continue;
    end if;
    if hora < r.hora_inicio or hora > r.hora_fim then
      regra := r.chave; criados := 0; return next; continue;
    end if;

    -- horario de entrega: agora, respeitando o inicio da janela
    alvo := greatest(agora, (hoje::timestamp + r.hora_inicio) at time zone 'America/Sao_Paulo');
    dias := coalesce((r.params->>'dias')::int, 1);

    if r.gatilho = 'experimental_vespera' then
      -- lead da unidade da regra com aula experimental marcada para daqui a N dias
      insert into crm_wa_fila (regra_id, lead_id, wa_chave, referencia, template_nome,
                               variaveis, texto_previa, agendado_para,
                               status)
      select r.id, l.id, l.wa_chave,
             'exp:'||l.proximo_atendimento::text,
             r.template_nome,
             jsonb_build_array(split_part(coalesce(l.responsavel_legal, l.nome),' ',1),
                               to_char(l.proximo_atendimento,'DD/MM'),
                               coalesce(to_char(l.proximo_atendimento_hora,'HH24:MI'),'a combinar')),
             'Oi '||split_part(coalesce(l.responsavel_legal, l.nome),' ',1)
               ||'! Passando para confirmar a aula experimental no '||v_marca||' dia '
               ||to_char(l.proximo_atendimento,'DD/MM')||' às '
               ||coalesce(to_char(l.proximo_atendimento_hora,'HH24:MI'),'a combinar')
               ||'. Podemos contar com você?',
             alvo,
             case when r.modo = 'automatico' then 'aprovado' else 'sugerido' end
      from crm_leads l
      where l.unidade = r.unidade
        and l.etapa = 'experimental'
        and l.proximo_atendimento = hoje + dias
        and l.wa_chave is not null
        and not l.wa_optout
        and not exists (select 1 from crm_wa_fila f
                         where f.lead_id = l.id and f.regra_id = r.id
                           and f.created_at > agora - (r.cooldown_dias||' days')::interval)
      on conflict (regra_id, lead_id, referencia) do nothing;
      get diagnostics n = row_count;

    elsif r.gatilho = 'agendamento_lembrete' then
      -- proximo atendimento marcado para daqui a N dias, canal WhatsApp
      insert into crm_wa_fila (regra_id, lead_id, wa_chave, referencia, template_nome,
                               variaveis, texto_previa, agendado_para, status)
      select r.id, l.id, l.wa_chave,
             'ag:'||l.proximo_atendimento::text,
             r.template_nome,
             jsonb_build_array(split_part(coalesce(l.responsavel_legal, l.nome),' ',1),
                               to_char(l.proximo_atendimento,'DD/MM'),
                               coalesce(to_char(l.proximo_atendimento_hora,'HH24:MI'),'a combinar')),
             'Oi '||split_part(coalesce(l.responsavel_legal, l.nome),' ',1)
               ||'! Seu teste de nível no '||v_marca||' está marcado para '
               ||to_char(l.proximo_atendimento,'DD/MM')||' às '
               ||coalesce(to_char(l.proximo_atendimento_hora,'HH24:MI'),'a combinar')
               ||'. É gratuito e leva pouco tempo. Confirma para mim?',
             alvo,
             case when r.modo = 'automatico' then 'aprovado' else 'sugerido' end
      from crm_leads l
      where l.unidade = r.unidade
        and l.proximo_atendimento = hoje + dias
        and coalesce(l.proximo_canal,'whatsapp') = 'whatsapp'
        and l.etapa = any(coalesce(
              (select array_agg(value::text) from jsonb_array_elements_text(r.params->'etapas')),
              array['respondeu','contato_feito','negociacao']))
        and l.wa_chave is not null
        and not l.wa_optout
        and not exists (select 1 from crm_wa_fila f
                         where f.lead_id = l.id and f.regra_id = r.id
                           and f.created_at > agora - (r.cooldown_dias||' days')::interval)
      on conflict (regra_id, lead_id, referencia) do nothing;
      get diagnostics n = row_count;

    elsif r.gatilho = 'lead_parado' then
      -- marketing: so com opt-in registrado
      insert into crm_wa_fila (regra_id, lead_id, wa_chave, referencia, template_nome,
                               variaveis, texto_previa, agendado_para, status)
      select r.id, l.id, l.wa_chave,
             'parado:'||to_char(hoje,'IYYY-IW'),
             r.template_nome,
             jsonb_build_array(split_part(coalesce(l.responsavel_legal, l.nome),' ',1)),
             'Oi '||split_part(coalesce(l.responsavel_legal, l.nome),' ',1)
               ||'! Aqui é do '||v_marca||'. Ficamos à disposição para retomar quando fizer sentido. '
               ||'Quer que eu veja um horário de aula experimental para você?',
             alvo,
             case when r.modo = 'automatico' then 'aprovado' else 'sugerido' end
      from crm_leads l
      where l.unidade = r.unidade
        and l.etapa = any(coalesce(
              (select array_agg(value::text) from jsonb_array_elements_text(r.params->'etapas')),
              array['contato_feito','respondeu','negociacao']))
        and coalesce(l.ultimo_contato, l.data_entrada) <= hoje - dias
        and l.wa_chave is not null
        and not l.wa_optout
        and l.wa_optin_em is not null
        and not exists (select 1 from crm_wa_fila f
                         where f.lead_id = l.id and f.regra_id = r.id
                           and f.created_at > agora - (r.cooldown_dias||' days')::interval)
      on conflict (regra_id, lead_id, referencia) do nothing;
      get diagnostics n = row_count;
    end if;

    -- se a janela de 24h estiver aberta, o envio sai como texto livre e nao gasta template.
    -- conversa e fila precisam ser da mesma unidade (cada unidade tem seu número).
    update crm_wa_fila f
       set conversa_id = c.id,
           template_nome = case when c.janela_expira_em > now() then null else f.template_nome end
      from crm_wa_conversas c
     where c.wa_chave = f.wa_chave
       and c.unidade = f.unidade
       and f.regra_id = r.id
       and f.status in ('sugerido','aprovado')
       and f.conversa_id is null;

    regra := r.chave; criados := n; return next;
  end loop;
end;
$function$;