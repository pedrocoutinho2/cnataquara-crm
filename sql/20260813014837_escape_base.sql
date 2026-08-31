
-- =========================================================
-- ESCAPE ROOM CNA TAQUARA — camada de conteudo
-- =========================================================

-- Temporada: define a camada visual/tematica (Padrao, Halloween, Natal...)
create table if not exists escape_temporadas (
  id            uuid primary key default gen_random_uuid(),
  slug          text not null unique,
  nome          text not null,
  mote          text,
  paleta        jsonb not null default '{}'::jsonb,
  ativa         boolean not null default false,
  inicio        date,
  fim           date,
  ordem         int not null default 0,
  created_at    timestamptz not null default now()
);

-- Sala: o ambiente fisico. A foto base nao muda entre temporadas.
create table if not exists escape_salas (
  id            uuid primary key default gen_random_uuid(),
  slug          text not null unique,
  nome          text not null,
  andar         text,
  ordem         int not null,
  mecanica      text not null,
  teto_ms       int not null default 300000,
  ativa         boolean not null default true,
  created_at    timestamptz not null default now()
);

-- Variante: o enigma em si. Sorteada por rodada.
-- payload guarda hotspots, palavras, audio, camada de decoracao digital.
create table if not exists escape_variantes (
  id            uuid primary key default gen_random_uuid(),
  sala_id       uuid not null references escape_salas(id) on delete cascade,
  temporada_id  uuid not null references escape_temporadas(id) on delete cascade,
  slug          text not null unique,
  titulo        text not null,
  dificuldade   int not null default 2,
  foto_url      text,
  payload       jsonb not null default '{}'::jsonb,
  ativa         boolean not null default true,
  created_at    timestamptz not null default now()
);
create index if not exists idx_escape_variantes_sorteio
  on escape_variantes(sala_id, temporada_id) where ativa;

-- =========================================================
-- JOGADORES E SESSOES
-- =========================================================

create table if not exists escape_jogadores (
  id                uuid primary key default gen_random_uuid(),
  apelido           text not null,
  nome              text not null,
  whatsapp          text not null,
  wa_chave          text not null unique,
  e_aluno           boolean not null,
  para_quem         text,
  responsavel_nome  text,
  lead_id           uuid references crm_leads(id) on delete set null,
  origem_qr         text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create table if not exists escape_sessoes (
  id             uuid primary key default gen_random_uuid(),
  jogador_id     uuid not null references escape_jogadores(id) on delete cascade,
  temporada_id   uuid not null references escape_temporadas(id),
  status         text not null default 'em_andamento',
  iniciada_em    timestamptz not null default now(),
  finalizada_em  timestamptz,
  tempo_total_ms int,
  penalidade_ms  int not null default 0,
  pontuacao      int,
  origem_qr      text,
  constraint escape_sessoes_status_chk
    check (status in ('em_andamento','concluida','abandonada'))
);
create index if not exists idx_escape_sessoes_jogador on escape_sessoes(jogador_id);
create index if not exists idx_escape_sessoes_rank
  on escape_sessoes(temporada_id, pontuacao desc) where status = 'concluida';

create table if not exists escape_sessao_salas (
  id             uuid primary key default gen_random_uuid(),
  sessao_id      uuid not null references escape_sessoes(id) on delete cascade,
  sala_id        uuid not null references escape_salas(id),
  variante_id    uuid not null references escape_variantes(id),
  ordem          int not null,
  iniciada_em    timestamptz not null default now(),
  finalizada_em  timestamptz,
  tempo_ms       int,
  erros          int not null default 0,
  dicas          int not null default 0,
  penalidade_ms  int not null default 0,
  pontuacao      int,
  unique (sessao_id, sala_id)
);
create index if not exists idx_escape_sessao_salas_rank
  on escape_sessao_salas(sala_id, pontuacao desc);

-- =========================================================
-- RLS (padrao anon_all da unidade)
-- =========================================================
do $$
declare t text;
begin
  foreach t in array array[
    'escape_temporadas','escape_salas','escape_variantes',
    'escape_jogadores','escape_sessoes','escape_sessao_salas'
  ] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists anon_all on %I', t);
    execute format(
      'create policy anon_all on %I for all to anon using (true) with check (true)', t);
  end loop;
end $$;
