
alter table escape_sessao_salas
  add column if not exists estourou boolean not null default false;

-- Fecha a sala por tempo esgotado: zero ponto, jogo continua
create or replace function escape_sala_estourar(
  p_sessao_id uuid,
  p_sala_slug text,
  p_erros int default 0,
  p_dicas int default 0
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_sala escape_salas%rowtype;
  v_ms int;
begin
  select * into v_sala from escape_salas where slug = p_sala_slug;
  if v_sala.id is null then raise exception 'sala inexistente'; end if;

  update escape_sessao_salas ss
     set finalizada_em = now(),
         tempo_ms = greatest(v_sala.teto_ms,
                    (extract(epoch from (now() - ss.iniciada_em)) * 1000)::int),
         erros = greatest(p_erros,0),
         dicas = greatest(p_dicas,0),
         penalidade_ms = 0,
         pontuacao = 0,
         estourou = true
   where ss.sessao_id = p_sessao_id and ss.sala_id = v_sala.id
     and ss.finalizada_em is null
  returning ss.tempo_ms into v_ms;

  if v_ms is null then raise exception 'sala nao estava em andamento'; end if;
  return jsonb_build_object('tempo_ms', v_ms, 'pontuacao', 0, 'estourou', true);
end $$;

-- Trava tambem no servidor: se passou do teto, nao pontua
create or replace function escape_sala_concluir(
  p_sessao_id uuid,
  p_sala_slug text,
  p_erros int default 0,
  p_dicas int default 0
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_sala escape_salas%rowtype;
  v_ms int; v_pen int; v_pts int; v_est boolean;
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
         estourou = (extract(epoch from (now() - ss.iniciada_em)) * 1000)::int > v_sala.teto_ms,
         pontuacao = case
           when (extract(epoch from (now() - ss.iniciada_em)) * 1000)::int > v_sala.teto_ms then 0
           else greatest(0, v_sala.teto_ms
                - ((extract(epoch from (now() - ss.iniciada_em)) * 1000)::int + v_pen)) / 100
         end
   where ss.sessao_id = p_sessao_id and ss.sala_id = v_sala.id
     and ss.finalizada_em is null
  returning ss.tempo_ms, ss.penalidade_ms, ss.pontuacao, ss.estourou
  into v_ms, v_pen, v_pts, v_est;

  if v_ms is null then raise exception 'sala nao estava em andamento'; end if;
  return jsonb_build_object('tempo_ms', v_ms, 'penalidade_ms', v_pen,
                            'pontuacao', v_pts, 'estourou', v_est);
end $$;

grant execute on function escape_sala_estourar(uuid,text,int,int) to anon;
grant execute on function escape_sala_concluir(uuid,text,int,int) to anon;
notify pgrst, 'reload schema';
