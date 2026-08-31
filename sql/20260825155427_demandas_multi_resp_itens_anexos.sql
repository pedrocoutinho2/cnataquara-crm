-- 1) multiplos responsaveis + colunas visiveis da lista
alter table public.crm_demandas
  add column if not exists responsaveis text[] not null default '{}',
  add column if not exists lista_cols text[] not null default '{}',
  add column if not exists lista_titulo text;

update public.crm_demandas
   set responsaveis = array[responsavel]
 where responsavel is not null and btrim(responsavel) <> '' and cardinality(responsaveis) = 0;

create or replace function public.crm_demandas_sync_resp()
returns trigger language plpgsql as $$
declare v text[];
begin
  if tg_op = 'UPDATE'
     and new.responsaveis is not distinct from old.responsaveis
     and new.responsavel is distinct from old.responsavel then
    new.responsaveis := case when new.responsavel is null or btrim(new.responsavel) = ''
                             then '{}'::text[] else array[new.responsavel] end;
  end if;

  if tg_op = 'INSERT'
     and cardinality(coalesce(new.responsaveis,'{}')) = 0
     and new.responsavel is not null and btrim(new.responsavel) <> '' then
    new.responsaveis := array[new.responsavel];
  end if;

  select coalesce(array_agg(x order by ord),'{}')
    into v
    from (select x, min(ord) as ord
            from unnest(coalesce(new.responsaveis,'{}')) with ordinality as t(x,ord)
           where x is not null and btrim(x) <> ''
           group by x) s;

  new.responsaveis := v;
  new.responsavel  := case when cardinality(v)=0 then null else v[1] end;
  return new;
end $$;

drop trigger if exists trg_crm_demandas_sync_resp on public.crm_demandas;
create trigger trg_crm_demandas_sync_resp
  before insert or update on public.crm_demandas
  for each row execute function public.crm_demandas_sync_resp();

create index if not exists idx_crm_demandas_responsaveis on public.crm_demandas using gin (responsaveis);

-- 2) itens da demanda (linhas de planilha / checklist)
create table if not exists public.crm_demanda_itens(
  id uuid primary key default gen_random_uuid(),
  demanda_id uuid not null references public.crm_demandas(id) on delete cascade,
  ordem int not null default 0,
  titulo text not null,
  detalhes jsonb not null default '[]'::jsonb,
  telefone text,
  status text not null default 'pendente',
  responsavel text,
  obs text,
  atualizado_em timestamptz,
  atualizado_por text,
  criado_em timestamptz not null default now()
);
create index if not exists idx_crm_demanda_itens_dem on public.crm_demanda_itens(demanda_id, ordem);
alter table public.crm_demanda_itens enable row level security;
drop policy if exists anon_all on public.crm_demanda_itens;
create policy anon_all on public.crm_demanda_itens for all to anon using (true) with check (true);

-- 3) anexos
create table if not exists public.crm_demanda_anexos(
  id uuid primary key default gen_random_uuid(),
  demanda_id uuid not null references public.crm_demandas(id) on delete cascade,
  item_id uuid references public.crm_demanda_itens(id) on delete cascade,
  nome text not null,
  path text not null,
  mime text,
  tamanho bigint,
  enviado_por text,
  criado_em timestamptz not null default now()
);
create index if not exists idx_crm_demanda_anexos_dem on public.crm_demanda_anexos(demanda_id, criado_em);
alter table public.crm_demanda_anexos enable row level security;
drop policy if exists anon_all on public.crm_demanda_anexos;
create policy anon_all on public.crm_demanda_anexos for all to anon using (true) with check (true);

-- 4) bucket privado de anexos
insert into storage.buckets (id, name, public, file_size_limit)
values ('demandas','demandas',false, 26214400)
on conflict (id) do update set file_size_limit = excluded.file_size_limit;

drop policy if exists demandas_anon on storage.objects;
create policy demandas_anon on storage.objects for all to anon
  using (bucket_id = 'demandas') with check (bucket_id = 'demandas');

notify pgrst, 'reload schema';