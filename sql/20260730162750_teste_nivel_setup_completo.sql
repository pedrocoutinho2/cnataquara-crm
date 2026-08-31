-- CNA Taquara — Teste de Nível Online (setup completo v1+v2)

create table if not exists public.leads_teste_nivel (
  id uuid primary key,
  created_at timestamptz not null default now(),

  -- dados do lead
  nome text not null,
  idade int,
  telefone text not null,
  aceite_lgpd boolean not null default false,
  aceite_cookies boolean not null default false,
  responsavel_autorizou boolean,          -- true quando idade < 18

  -- atribuição de campanha
  utm_source text,
  utm_medium text,
  utm_campaign text,
  utm_content text,

  -- resultado do teste
  resultado_nivel text,
  curso_recomendado text,
  acertos int,
  total_perguntas int,
  respostas jsonb,
  concluido boolean not null default false,
  concluido_em timestamptz,

  -- v2: conversação e avaliação por IA
  respostas_abertas jsonb,
  avaliacao_ia jsonb,
  avaliado_em timestamptz
);

create index if not exists idx_leads_tn_created on public.leads_teste_nivel (created_at desc);
create index if not exists idx_leads_tn_concluido on public.leads_teste_nivel (concluido);
create index if not exists idx_leads_tn_campanha on public.leads_teste_nivel (utm_campaign);

alter table public.leads_teste_nivel enable row level security;

drop policy if exists "anon pode inserir lead" on public.leads_teste_nivel;
create policy "anon pode inserir lead"
  on public.leads_teste_nivel
  for insert
  to anon
  with check (true);

drop policy if exists "anon pode atualizar resultado" on public.leads_teste_nivel;
create policy "anon pode atualizar resultado"
  on public.leads_teste_nivel
  for update
  to anon
  using (true)
  with check (true);
