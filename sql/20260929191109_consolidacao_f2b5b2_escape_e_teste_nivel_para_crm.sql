-- Consolidação · Fase 2b-5b-2: páginas de captação por unidade.
-- escape_iniciar ganha p_unidade (default 'taquara'): temporada ativa, jogador (upsert por
--   (unidade, wa_chave)) e dedupe contra crm_leads, tudo dentro da unidade. Sessão herda do jogador.
-- fn_teste_nivel_para_crm: procura o lead pelo telefone SÓ na unidade do teste e cria o lead nela.

drop function if exists public.escape_iniciar(text, text, text, boolean, text, text, text);

create function public.escape_iniciar(p_nome text, p_apelido text, p_whatsapp text, p_e_aluno boolean, p_para_quem text default null, p_responsavel_nome text default null, p_origem_qr text default null, p_unidade text default 'taquara')
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_chave text := crm_wa_chave(p_whatsapp);
  v_jog   escape_jogadores%rowtype;
  v_temp  escape_temporadas%rowtype;
  v_lead  uuid;
  v_sess  uuid;
begin
  if coalesce(trim(p_nome),'') = '' or coalesce(v_chave,'') = '' then
    raise exception 'nome e whatsapp sao obrigatorios';
  end if;

  select * into v_temp from escape_temporadas
   where ativa and unidade = p_unidade order by ordem desc, created_at desc limit 1;
  if v_temp.id is null then
    raise exception 'nenhuma temporada ativa';
  end if;

  insert into escape_jogadores
    (unidade, apelido, nome, whatsapp, wa_chave, e_aluno, para_quem, responsavel_nome, origem_qr)
  values
    (p_unidade, coalesce(nullif(trim(p_apelido),''), split_part(trim(p_nome),' ',1)),
     trim(p_nome), p_whatsapp, v_chave, p_e_aluno,
     p_para_quem, p_responsavel_nome, p_origem_qr)
  on conflict (unidade, wa_chave) do update
    set apelido    = excluded.apelido,
        nome       = excluded.nome,
        e_aluno    = excluded.e_aluno,
        para_quem  = coalesce(excluded.para_quem, escape_jogadores.para_quem),
        origem_qr  = coalesce(excluded.origem_qr, escape_jogadores.origem_qr),
        updated_at = now()
  returning * into v_jog;

  -- Nao aluno vira lead no CRM da unidade (dedupe por wa_chave dentro da unidade)
  if not p_e_aluno and v_jog.lead_id is null then
    select id into v_lead from crm_leads where unidade = p_unidade and wa_chave = v_chave limit 1;
    if v_lead is null then
      insert into crm_leads (unidade, nome, whatsapp, origem, etapa, wa_chave, observacoes)
      values (p_unidade, trim(p_nome), p_whatsapp, 'Escape Room', 'novo', v_chave,
              'Lead capturado no Escape Room Virtual'
              || case when p_para_quem is not null then ' | Para: ' || p_para_quem else '' end
              || case when p_origem_qr is not null then ' | QR: ' || p_origem_qr else '' end)
      returning id into v_lead;
    end if;
    update escape_jogadores set lead_id = v_lead, updated_at = now() where id = v_jog.id;
    v_jog.lead_id := v_lead;
  end if;

  insert into escape_sessoes (jogador_id, temporada_id, origem_qr)
  values (v_jog.id, v_temp.id, p_origem_qr)
  returning id into v_sess;

  return jsonb_build_object(
    'jogador_id', v_jog.id,
    'apelido', v_jog.apelido,
    'lead_id', v_jog.lead_id,
    'sessao_id', v_sess,
    'temporada', jsonb_build_object(
      'slug', v_temp.slug, 'nome', v_temp.nome,
      'mote', v_temp.mote, 'paleta', v_temp.paleta)
  );
end $function$;

grant execute on function public.escape_iniciar(text, text, text, boolean, text, text, text, text) to anon, authenticated;

create or replace function public.fn_teste_nivel_para_crm()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_tel text := fn_norm_tel(new.telefone);
  v_crm_id uuid;
  v_nota text;
begin
  -- localiza card existente pelo telefone normalizado, só na unidade do teste
  select id into v_crm_id
  from crm_leads
  where unidade = new.unidade and fn_norm_tel(whatsapp) = v_tel and v_tel <> ''
  order by created_at desc
  limit 1;

  -- ── 1) Lead começou o teste ──
  if tg_op = 'INSERT' then
    if v_crm_id is null then
      insert into crm_leads (unidade, nome, whatsapp, origem, etapa, curso, data_entrada, observacoes)
      values (
        new.unidade,
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
$function$;

notify pgrst, 'reload schema';