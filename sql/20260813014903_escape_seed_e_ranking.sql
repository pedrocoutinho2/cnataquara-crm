
-- Temporada padrao
insert into escape_temporadas (slug, nome, mote, paleta, ativa, ordem)
values (
  'padrao',
  'O Sumico do Dani',
  'Voce monstrao no Ingles',
  '{"primaria":"#E6143C","secundaria":"#19408B","acento":"#FFC800","fundo":"#FDECEF"}'::jsonb,
  true, 0
)
on conflict (slug) do nothing;

-- Salas (percurso real da unidade)
insert into escape_salas (slug, nome, andar, ordem, mecanica, teto_ms) values
  ('recepcao',      'Recepcao',       'Terreo',   1, 'objetos_ocultos', 240000),
  ('garden',        'Sala Garden',    '1o andar', 2, 'arrastar_palavra', 240000),
  ('sala-espera',   'Sala de Espera', '2o andar', 3, 'erros_diferenca',  180000),
  ('sala-aula',     'Sala de Aula',   '2o andar', 4, 'frase_audio',      300000),
  ('auditorio',     'Auditorio',      '3o andar', 5, 'luz_negra',        300000)
on conflict (slug) do nothing;

-- =========================================================
-- RANKING
-- =========================================================

-- Melhor sessao concluida por jogador, por temporada
create or replace view escape_ranking_geral as
select
  r.temporada_id,
  t.slug            as temporada_slug,
  j.id              as jogador_id,
  j.apelido,
  j.e_aluno,
  r.sessao_id,
  r.tempo_total_ms,
  r.penalidade_ms,
  r.pontuacao,
  r.finalizada_em,
  rank() over (partition by r.temporada_id order by r.pontuacao desc, r.tempo_total_ms asc) as posicao
from (
  select distinct on (s.jogador_id, s.temporada_id)
    s.id as sessao_id, s.jogador_id, s.temporada_id,
    s.tempo_total_ms, s.penalidade_ms, s.pontuacao, s.finalizada_em
  from escape_sessoes s
  where s.status = 'concluida' and s.pontuacao is not null
  order by s.jogador_id, s.temporada_id, s.pontuacao desc, s.tempo_total_ms asc
) r
join escape_jogadores j on j.id = r.jogador_id
join escape_temporadas t on t.id = r.temporada_id;

-- Melhor tempo por jogador em cada sala
create or replace view escape_ranking_sala as
select
  r.sala_id,
  sl.slug           as sala_slug,
  sl.nome           as sala_nome,
  r.temporada_id,
  j.id              as jogador_id,
  j.apelido,
  j.e_aluno,
  r.tempo_ms,
  r.penalidade_ms,
  r.pontuacao,
  rank() over (partition by r.sala_id, r.temporada_id
               order by r.pontuacao desc, r.tempo_ms asc) as posicao
from (
  select distinct on (s.jogador_id, ss.sala_id, s.temporada_id)
    ss.sala_id, s.jogador_id, s.temporada_id,
    ss.tempo_ms, ss.penalidade_ms, ss.pontuacao
  from escape_sessao_salas ss
  join escape_sessoes s on s.id = ss.sessao_id
  where ss.pontuacao is not null
  order by s.jogador_id, ss.sala_id, s.temporada_id,
           ss.pontuacao desc, ss.tempo_ms asc
) r
join escape_salas sl on sl.id = r.sala_id
join escape_jogadores j on j.id = r.jogador_id;

grant select on escape_ranking_geral, escape_ranking_sala to anon;
