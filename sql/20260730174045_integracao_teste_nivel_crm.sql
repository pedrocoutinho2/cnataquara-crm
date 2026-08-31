-- Integração Teste de Nível Online → CRM (kanban Clientes B2C)

-- Normaliza telefone: só dígitos, sem o 55 do código do país
create or replace function public.fn_norm_tel(t text)
returns text language sql immutable as $$
  select case
    when length(regexp_replace(coalesce(t,''), '\D', '', 'g')) > 11
         and regexp_replace(coalesce(t,''), '\D', '', 'g') like '55%'
    then substring(regexp_replace(coalesce(t,''), '\D', '', 'g') from 3)
    else regexp_replace(coalesce(t,''), '\D', '', 'g')
  end
$$;

create or replace function public.fn_teste_nivel_para_crm()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tel text := fn_norm_tel(new.telefone);
  v_crm_id uuid;
  v_nota text;
begin
  -- localiza card existente pelo telefone normalizado
  select id into v_crm_id
  from crm_leads
  where fn_norm_tel(whatsapp) = v_tel and v_tel <> ''
  order by created_at desc
  limit 1;

  -- ── 1) Lead começou o teste ──
  if tg_op = 'INSERT' then
    if v_crm_id is null then
      insert into crm_leads (nome, whatsapp, origem, etapa, curso, data_entrada, observacoes)
      values (
        new.nome,
        new.telefone,
        'Teste de Nível Online',
        'novo',
        'Inglês',
        current_date,
        '[' || to_char(now() at time zone 'America/Sao_Paulo','DD/MM/YYYY HH24:MI') || '] Iniciou o teste de nível online.'
        || ' Idade: ' || coalesce(new.idade::text,'—')
        || coalesce(' · Campanha: ' || nullif(new.utm_campaign,''), '')
        || coalesce(' · Fonte: '    || nullif(new.utm_source,''), '')
        || case when coalesce(new.responsavel_autorizou,false) then ' · Menor de idade (autorizado pelo responsável)' else '' end
      );
    else
      insert into crm_leads_interacoes (lead_id, data, autor, tipo, nota)
      values (v_crm_id, current_date, 'Teste de Nível', 'nota',
              'Refez o teste de nível online (lead já existia no CRM).');
    end if;
    return new;
  end if;

  if v_crm_id is null then return new; end if;

  -- ── 2) Teste concluído ──
  if tg_op = 'UPDATE' and new.concluido and not coalesce(old.concluido,false) then
    v_nota := 'Concluiu o teste de nível online: '
           || coalesce(new.acertos::text,'?') || '/' || coalesce(new.total_perguntas::text,'12')
           || ' acertos · Nível (objetivas): ' || coalesce(new.resultado_nivel,'—')
           || case when new.respostas_abertas is not null
                   then ' · Fez a etapa de conversação'
                   else ' · Pulou a conversação' end;
    insert into crm_leads_interacoes (lead_id, data, autor, tipo, nota)
    values (v_crm_id, current_date, 'Teste de Nível', 'nota', v_nota);
    return new;
  end if;

  -- ── 3) Avaliação da IA chegou ──
  if tg_op = 'UPDATE' and new.avaliacao_ia is not null and old.avaliacao_ia is null then
    v_nota := 'Avaliação IA da conversação → Nível sugerido: '
           || coalesce(new.avaliacao_ia->>'nivel_sugerido','—')
           || ' · ' || coalesce(new.avaliacao_ia->>'resumo_consultor','');
    insert into crm_leads_interacoes (lead_id, data, autor, tipo, nota)
    values (v_crm_id, current_date, 'Teste de Nível', 'nota', v_nota);
    return new;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_teste_nivel_insert on public.leads_teste_nivel;
create trigger trg_teste_nivel_insert
  after insert on public.leads_teste_nivel
  for each row execute function public.fn_teste_nivel_para_crm();

drop trigger if exists trg_teste_nivel_update on public.leads_teste_nivel;
create trigger trg_teste_nivel_update
  after update on public.leads_teste_nivel
  for each row execute function public.fn_teste_nivel_para_crm();