
-- 1) Captura inicial + criacao de lead + abertura de sessao
create or replace function escape_iniciar(
  p_nome text,
  p_apelido text,
  p_whatsapp text,
  p_e_aluno boolean,
  p_para_quem text default null,
  p_responsavel_nome text default null,
  p_origem_qr text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
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
   where ativa order by ordem desc, created_at desc limit 1;
  if v_temp.id is null then
    raise exception 'nenhuma temporada ativa';
  end if;

  insert into escape_jogadores
    (apelido, nome, whatsapp, wa_chave, e_aluno, para_quem, responsavel_nome, origem_qr)
  values
    (coalesce(nullif(trim(p_apelido),''), split_part(trim(p_nome),' ',1)),
     trim(p_nome), p_whatsapp, v_chave, p_e_aluno,
     p_para_quem, p_responsavel_nome, p_origem_qr)
  on conflict (wa_chave) do update
    set apelido    = excluded.apelido,
        nome       = excluded.nome,
        e_aluno    = excluded.e_aluno,
        para_quem  = coalesce(excluded.para_quem, escape_jogadores.para_quem),
        origem_qr  = coalesce(excluded.origem_qr, escape_jogadores.origem_qr),
        updated_at = now()
  returning * into v_jog;

  -- Nao aluno vira lead no CRM (dedupe por wa_chave)
  if not p_e_aluno and v_jog.lead_id is null then
    select id into v_lead from crm_leads where wa_chave = v_chave limit 1;
    if v_lead is null then
      insert into crm_leads (nome, whatsapp, origem, etapa, wa_chave, observacoes)
      values (trim(p_nome), p_whatsapp, 'Escape Room', 'novo', v_chave,
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
end $$;

-- 2) Sorteia variante inedita e cronometra o inicio da sala
create or replace function escape_sala_iniciar(
  p_sessao_id uuid,
  p_sala_slug text
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_sess escape_sessoes%rowtype;
  v_sala escape_salas%rowtype;
  v_var  escape_variantes%rowtype;
begin
  select * into v_sess from escape_sessoes where id = p_sessao_id;
  if v_sess.id is null or v_sess.status <> 'em_andamento' then
    raise exception 'sessao invalida ou encerrada';
  end if;
  select * into v_sala from escape_salas where slug = p_sala_slug and ativa;
  if v_sala.id is null then raise exception 'sala inexistente'; end if;

  -- ja em andamento: devolve a mesma variante (evita reset de cronometro)
  select v.* into v_var from escape_sessao_salas ss
    join escape_variantes v on v.id = ss.variante_id
   where ss.sessao_id = p_sessao_id and ss.sala_id = v_sala.id
     and ss.finalizada_em is null;
  if v_var.id is not null then
    return jsonb_build_object('sala', to_jsonb(v_sala), 'variante',
      jsonb_build_object('id', v_var.id, 'titulo', v_var.titulo,
                         'foto_url', v_var.foto_url, 'payload', v_var.payload),
      'retomada', true);
  end if;

  -- sorteia priorizando o que o jogador nunca viu
  select v.* into v_var
    from escape_variantes v
   where v.sala_id = v_sala.id and v.temporada_id = v_sess.temporada_id and v.ativa
   order by (exists (
       select 1 from escape_sessao_salas ss2
        join escape_sessoes s2 on s2.id = ss2.sessao_id
       where s2.jogador_id = v_sess.jogador_id and ss2.variante_id = v.id
     )), random()
   limit 1;
  if v_var.id is null then
    raise exception 'sem variante cadastrada para % nesta temporada', p_sala_slug;
  end if;

  insert into escape_sessao_salas (sessao_id, sala_id, variante_id, ordem)
  values (p_sessao_id, v_sala.id, v_var.id, v_sala.ordem)
  on conflict (sessao_id, sala_id) do update
    set variante_id = excluded.variante_id, iniciada_em = now(),
        finalizada_em = null, tempo_ms = null, pontuacao = null;

  return jsonb_build_object('sala', to_jsonb(v_sala), 'variante',
    jsonb_build_object('id', v_var.id, 'titulo', v_var.titulo,
                       'foto_url', v_var.foto_url, 'payload', v_var.payload),
    'retomada', false);
end $$;

-- 3) Fecha a sala, cronometrado no servidor
create or replace function escape_sala_concluir(
  p_sessao_id uuid,
  p_sala_slug text,
  p_erros int default 0,
  p_dicas int default 0
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_sala escape_salas%rowtype;
  v_ms int; v_pen int; v_pts int;
begin
  select * into v_sala from escape_salas where slug = p_sala_slug;
  if v_sala.id is null then raise exception 'sala inexistente'; end if;

  v_pen := greatest(p_erros,0) * 5000 + greatest(p_dicas,0) * 15000;

  update escape_sessao_salas ss
     set finalizada_em = now(),
         tempo_ms = (extract(epoch from (now() - ss.iniciada_em)) * 1000)::int,
         erros = greatest(p_erros,0),
         dicas = greatest(p_dicas,0),
         penalidade_ms = v_pen,
         pontuacao = greatest(0, v_sala.teto_ms
                       - ((extract(epoch from (now() - ss.iniciada_em)) * 1000)::int + v_pen)) / 100
   where ss.sessao_id = p_sessao_id and ss.sala_id = v_sala.id
     and ss.finalizada_em is null
  returning ss.tempo_ms, ss.penalidade_ms, ss.pontuacao into v_ms, v_pen, v_pts;

  if v_ms is null then raise exception 'sala nao estava em andamento'; end if;
  return jsonb_build_object('tempo_ms', v_ms, 'penalidade_ms', v_pen, 'pontuacao', v_pts);
end $$;

-- 4) Fecha a sessao e devolve posicao no ranking
create or replace function escape_sessao_concluir(p_sessao_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_total int; v_pen int; v_pts int; v_faltam int; v_pos int; v_sess escape_sessoes%rowtype;
begin
  select * into v_sess from escape_sessoes where id = p_sessao_id;
  if v_sess.id is null then raise exception 'sessao inexistente'; end if;

  select count(*) into v_faltam from escape_salas s
   where s.ativa and not exists (
     select 1 from escape_sessao_salas ss
      where ss.sessao_id = p_sessao_id and ss.sala_id = s.id and ss.finalizada_em is not null);
  if v_faltam > 0 then raise exception 'ainda faltam % salas', v_faltam; end if;

  select sum(tempo_ms), sum(penalidade_ms), sum(pontuacao)
    into v_total, v_pen, v_pts
    from escape_sessao_salas where sessao_id = p_sessao_id;

  update escape_sessoes
     set status='concluida', finalizada_em=now(),
         tempo_total_ms=v_total, penalidade_ms=v_pen, pontuacao=v_pts
   where id = p_sessao_id;

  select posicao into v_pos from escape_ranking_geral where sessao_id = p_sessao_id;

  return jsonb_build_object('tempo_total_ms', v_total, 'penalidade_ms', v_pen,
                            'pontuacao', v_pts, 'posicao', v_pos);
end $$;

grant execute on function escape_iniciar(text,text,text,boolean,text,text,text) to anon;
grant execute on function escape_sala_iniciar(uuid,text) to anon;
grant execute on function escape_sala_concluir(uuid,text,int,int) to anon;
grant execute on function escape_sessao_concluir(uuid) to anon;

notify pgrst, 'reload schema';
