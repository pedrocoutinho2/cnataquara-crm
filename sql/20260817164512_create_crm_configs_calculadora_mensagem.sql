create table if not exists public.crm_configs (
  chave text primary key,
  valor text,
  descricao text,
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid references public.crm_usuarios(id) on delete set null
);

alter table public.crm_configs enable row level security;

drop policy if exists "anon all crm_configs" on public.crm_configs;
create policy "anon all crm_configs" on public.crm_configs
  for all to anon using (true) with check (true);

insert into public.crm_configs (chave, valor, descricao)
values (
  'calculadora_mensagem',
  null,
  'Template da mensagem gerada pela calculadora de valores. NULL = usa o texto padrao do codigo (fallback / restaurar padrao).'
)
on conflict (chave) do nothing;