create table if not exists public.crm_metas (
  id uuid primary key default gen_random_uuid(),
  competencia text not null,
  escopo text not null default 'unidade',
  consultor text,
  meta_matriculas integer,
  meta_leads integer,
  obs text,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint crm_metas_competencia_fmt check (competencia ~ '^[0-9]{4}-[0-9]{2}$'),
  constraint crm_metas_escopo_chk check (escopo in ('unidade','consultor')),
  constraint crm_metas_consultor_chk check (
    (escopo = 'consultor' and consultor is not null and consultor <> '')
    or (escopo = 'unidade' and consultor is null)
  ),
  constraint crm_metas_valores_chk check (
    (meta_matriculas is null or meta_matriculas >= 0)
    and (meta_leads is null or meta_leads >= 0)
  )
);

create unique index if not exists crm_metas_uk
  on public.crm_metas (competencia, escopo, coalesce(consultor, ''));

create index if not exists crm_metas_competencia_idx
  on public.crm_metas (competencia);

alter table public.crm_metas enable row level security;

drop policy if exists "anon all crm_metas" on public.crm_metas;
create policy "anon all crm_metas" on public.crm_metas
  for all to anon using (true) with check (true);

drop policy if exists "auth all crm_metas" on public.crm_metas;
create policy "auth all crm_metas" on public.crm_metas
  for all to authenticated using (true) with check (true);

comment on table public.crm_metas is 'Metas mensais da unidade e por consultor. Uma linha por competencia+escopo. Alimenta o painel Cockpit Taquara.';

insert into public.crm_metas (competencia, escopo, meta_matriculas, meta_leads, obs)
values (to_char(current_date,'YYYY-MM'), 'unidade', null, null, 'definir')
on conflict do nothing;