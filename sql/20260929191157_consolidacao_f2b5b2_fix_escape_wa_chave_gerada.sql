-- Correção de bug PRÉ-EXISTENTE (desde 20260811194815 crm_whatsapp_base): escape_iniciar inseria
-- wa_chave em crm_leads, que é GENERATED ALWAYS (crm_wa_chave(whatsapp)). Todo não aluno com
-- telefone novo recebia erro. Sem impacto real: 1 jogador de teste, 0 não alunos.
create or replace function public.escape_iniciar(p_nome text, p_apelido text, p_whatsapp text, p_e_aluno boolean, p_para_quem text default null, p_responsavel_nome text default null, p_origem_qr text default null, p_unidade text default 'taquara')
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

  -- Nao aluno vira lead no CRM da unidade (dedupe por wa_chave dentro da unidade).
  -- crm_leads.wa_chave é gerada a partir de whatsapp: não inserir.
  if not p_e_aluno and v_jog.lead_id is null then
    select id into v_lead from crm_leads where unidade = p_unidade and wa_chave = v_chave limit 1;
    if v_lead is null then
      insert into crm_leads (unidade, nome, whatsapp, origem, etapa, observacoes)
      values (p_unidade, trim(p_nome), p_whatsapp, 'Escape Room', 'novo',
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