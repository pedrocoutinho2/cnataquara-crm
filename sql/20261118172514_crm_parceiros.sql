-- crm_parceiros: aba Parcerias do CRM (rede). Condomínios, escolas e empresas
-- que JÁ SÃO parceiros da unidade (crm_empresas/crm_escolas seguem como prospecção).
-- Segurança: RLS ligada e SEM policy para anon. Acesso só pelas RPCs abaixo,
-- que validam o token de sessão (crm_exige) e filtram pela unidade da sessão.

create table if not exists public.crm_parceiros (
  id             uuid primary key default gen_random_uuid(),
  unidade        text not null references public.crm_unidades(slug),
  tipo           text not null check (tipo in ('condominio','escola','empresa','outro')),
  nome           text not null check (length(btrim(nome)) > 0),
  endereco       text,
  contato_nome   text,
  contato_funcao text,
  telefone       text,
  email          text,
  divulgacao     text check (divulgacao in ('digital','panfletagem','portaria')),
  obs            text,
  status         text not null default 'ativo' check (status in ('ativo','inativo')),
  responsavel_id uuid references public.crm_usuarios(id),
  criado_por     text,
  alterado_por   text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create unique index if not exists crm_parceiros_unidade_tipo_nome_uk
  on public.crm_parceiros (unidade, tipo, lower(btrim(nome)));
create index if not exists crm_parceiros_unidade_idx on public.crm_parceiros (unidade, tipo, status);

alter table public.crm_parceiros enable row level security;
revoke all on public.crm_parceiros from anon, authenticated;

-- módulo + permissão padrão por papel (igual a Empresas)
insert into public.crm_modulos (modulo, nome, grupo, ordem)
values ('parceiros', 'Parcerias', 'Comercial', 42)
on conflict (modulo) do nothing;

insert into public.crm_papel_permissoes (papel, modulo, nivel) values
  ('admin','parceiros','total'),
  ('coordenacao','parceiros','total'),
  ('comercial','parceiros','editar'),
  ('pedagogico','parceiros','nenhum'),
  ('secretaria','parceiros','nenhum')
on conflict do nothing;

-- LISTA: tudo da unidade da sessão; filtros ficam no front
create or replace function public.parceiros_lista(p_token uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare u crm_usuarios; un text;
begin
  u  := crm_exige(p_token, 'parceiros', 1);
  un := crm_sessao_unidade(p_token);
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id',p.id,'tipo',p.tipo,'nome',p.nome,'endereco',p.endereco,
      'contato_nome',p.contato_nome,'contato_funcao',p.contato_funcao,
      'telefone',p.telefone,'email',p.email,'divulgacao',p.divulgacao,'obs',p.obs,
      'status',p.status,'responsavel_id',p.responsavel_id,'responsavel',r.nome,
      'alterado_por',p.alterado_por,'updated_at',p.updated_at)
    order by p.status, p.tipo, p.nome)
    from crm_parceiros p left join crm_usuarios r on r.id = p.responsavel_id
    where p.unidade = un), '[]'::jsonb);
end $fn$;

-- SALVAR: cria (sem id) ou edita (com id, só da própria unidade). Exclusão = status 'inativo'.
create or replace function public.parceiros_salvar(p_token uuid, p jsonb)
returns uuid language plpgsql security definer set search_path to 'public' as $fn$
declare u crm_usuarios; un text; v_id uuid;
begin
  u  := crm_exige(p_token, 'parceiros', 2);
  un := crm_sessao_unidade(p_token);
  v_id := nullif(p->>'id','')::uuid;
  if v_id is null then
    insert into crm_parceiros (unidade, tipo, nome, endereco, contato_nome, contato_funcao,
      telefone, email, divulgacao, obs, status, responsavel_id, criado_por, alterado_por)
    values (un, p->>'tipo', btrim(p->>'nome'), nullif(p->>'endereco',''), nullif(p->>'contato_nome',''),
      nullif(p->>'contato_funcao',''), nullif(p->>'telefone',''), nullif(p->>'email',''),
      nullif(p->>'divulgacao',''), nullif(p->>'obs',''), coalesce(nullif(p->>'status',''),'ativo'),
      nullif(p->>'responsavel_id','')::uuid, u.nome, u.nome)
    returning id into v_id;
  else
    update crm_parceiros set
      tipo = p->>'tipo', nome = btrim(p->>'nome'),
      endereco = nullif(p->>'endereco',''), contato_nome = nullif(p->>'contato_nome',''),
      contato_funcao = nullif(p->>'contato_funcao',''), telefone = nullif(p->>'telefone',''),
      email = nullif(p->>'email',''), divulgacao = nullif(p->>'divulgacao',''),
      obs = nullif(p->>'obs',''), status = coalesce(nullif(p->>'status',''),'ativo'),
      responsavel_id = nullif(p->>'responsavel_id','')::uuid,
      alterado_por = u.nome, updated_at = now()
    where id = v_id and unidade = un;
    if not found then raise exception 'parceiro_nao_encontrado' using errcode = 'P0001'; end if;
  end if;
  return v_id;
end $fn$;

revoke all on function public.parceiros_lista(uuid), public.parceiros_salvar(uuid, jsonb) from public;
grant execute on function public.parceiros_lista(uuid), public.parceiros_salvar(uuid, jsonb) to anon, authenticated;

notify pgrst, 'reload schema';