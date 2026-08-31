-- 1. Papel e exceções por pessoa
alter table crm_usuarios
  add column if not exists papel text not null default 'comercial',
  add column if not exists permissoes jsonb not null default '{}'::jsonb;

do $$
begin
  if not exists (select 1 from pg_constraint where conname='crm_usuarios_papel_ck') then
    alter table crm_usuarios add constraint crm_usuarios_papel_ck
      check (papel in ('secretaria','comercial','pedagogico','coordenacao','admin'));
  end if;
end $$;

-- 2. Catálogo de módulos e níveis padrão por papel (editável pela tela de Equipe)
create table if not exists crm_papel_permissoes(
  papel  text not null check (papel in ('secretaria','comercial','pedagogico','coordenacao','admin')),
  modulo text not null,
  nivel  text not null check (nivel in ('nenhum','ver','editar','total')),
  atualizado_em timestamptz not null default now(),
  primary key (papel, modulo)
);

alter table crm_papel_permissoes enable row level security;
drop policy if exists anon_all on crm_papel_permissoes;
create policy anon_all on crm_papel_permissoes for all to anon using (true) with check (true);

create table if not exists crm_modulos(
  modulo text primary key,
  nome   text not null,
  grupo  text not null,
  ordem  int  not null default 0
);
alter table crm_modulos enable row level security;
drop policy if exists anon_all on crm_modulos;
create policy anon_all on crm_modulos for all to anon using (true) with check (true);

insert into crm_modulos(modulo,nome,grupo,ordem) values
  ('inicio','Início','Geral',10),
  ('leads','Clientes B2C','Comercial',20),
  ('escolas','Escolas','Comercial',30),
  ('empresas','Empresas','Comercial',40),
  ('conversas','Conversas (WhatsApp)','Atendimento',50),
  ('fila','Fila de disparo','Atendimento',60),
  ('calc','Calculadora','Atendimento',70),
  ('turmas','Turmas','Operação',80),
  ('calendario','Calendário','Operação',90),
  ('mural','Mural','Operação',100),
  ('tarefas','Tarefas','Operação',110),
  ('rel_meudia','Relatórios · Meu dia','Gestão',120),
  ('rel_funil','Relatórios · Funil e ranking','Gestão',130),
  ('equipe','Equipe e permissões','Gestão',140)
on conflict (modulo) do update set nome=excluded.nome, grupo=excluded.grupo, ordem=excluded.ordem;

-- 3. Padrões por papel
insert into crm_papel_permissoes(papel,modulo,nivel) values
  ('secretaria','inicio','ver'),('secretaria','leads','editar'),('secretaria','escolas','nenhum'),
  ('secretaria','empresas','nenhum'),('secretaria','conversas','ver'),('secretaria','fila','nenhum'),
  ('secretaria','calc','ver'),('secretaria','turmas','ver'),('secretaria','calendario','editar'),
  ('secretaria','mural','ver'),('secretaria','tarefas','editar'),('secretaria','rel_meudia','nenhum'),
  ('secretaria','rel_funil','nenhum'),('secretaria','equipe','nenhum'),

  ('comercial','inicio','ver'),('comercial','leads','editar'),('comercial','escolas','editar'),
  ('comercial','empresas','editar'),('comercial','conversas','editar'),('comercial','fila','ver'),
  ('comercial','calc','ver'),('comercial','turmas','ver'),('comercial','calendario','ver'),
  ('comercial','mural','ver'),('comercial','tarefas','editar'),('comercial','rel_meudia','ver'),
  ('comercial','rel_funil','nenhum'),('comercial','equipe','nenhum'),

  ('pedagogico','inicio','ver'),('pedagogico','leads','nenhum'),('pedagogico','escolas','nenhum'),
  ('pedagogico','empresas','nenhum'),('pedagogico','conversas','nenhum'),('pedagogico','fila','nenhum'),
  ('pedagogico','calc','nenhum'),('pedagogico','turmas','total'),('pedagogico','calendario','editar'),
  ('pedagogico','mural','ver'),('pedagogico','tarefas','editar'),('pedagogico','rel_meudia','nenhum'),
  ('pedagogico','rel_funil','nenhum'),('pedagogico','equipe','nenhum'),

  ('coordenacao','inicio','ver'),('coordenacao','leads','total'),('coordenacao','escolas','total'),
  ('coordenacao','empresas','total'),('coordenacao','conversas','editar'),('coordenacao','fila','editar'),
  ('coordenacao','calc','ver'),('coordenacao','turmas','editar'),('coordenacao','calendario','editar'),
  ('coordenacao','mural','editar'),('coordenacao','tarefas','total'),('coordenacao','rel_meudia','total'),
  ('coordenacao','rel_funil','ver'),('coordenacao','equipe','nenhum'),

  ('admin','inicio','total'),('admin','leads','total'),('admin','escolas','total'),
  ('admin','empresas','total'),('admin','conversas','total'),('admin','fila','total'),
  ('admin','calc','total'),('admin','turmas','total'),('admin','calendario','total'),
  ('admin','mural','total'),('admin','tarefas','total'),('admin','rel_meudia','total'),
  ('admin','rel_funil','total'),('admin','equipe','total')
on conflict (papel,modulo) do nothing;

notify pgrst, 'reload schema';