insert into crm_modulos (modulo, nome, grupo, ordem)
values ('atas','Atas de reunião','Operação',105)
on conflict (modulo) do update set nome=excluded.nome, grupo=excluded.grupo, ordem=excluded.ordem;

insert into crm_papel_permissoes (papel, modulo, nivel) values
  ('admin','atas','total'),
  ('coordenacao','atas','total'),
  ('comercial','atas','editar'),
  ('pedagogico','atas','editar'),
  ('secretaria','atas','editar')
on conflict (papel, modulo) do update set nivel = excluded.nivel;

notify pgrst, 'reload schema';