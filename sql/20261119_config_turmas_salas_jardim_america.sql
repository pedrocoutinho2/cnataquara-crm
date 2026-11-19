-- Unidade: jardim-america · base gpnwmsnayrqjcmhqrtpx (CRM CNA)
-- Aplicado via execute_sql em 19/11/2026.
-- Salas fixas do mapa de turmas, na ordem das colunas (lidas pelo front em tSalasUn()).
insert into crm_configs (unidade, chave, valor, descricao, atualizado_em)
values ('jardim-america','turmas_salas','["GARDEN","SALA 2","SALA 3","SALA 4"]',
 'Salas fixas do mapa de turmas, na ordem das colunas. Aparecem mesmo sem turma; o select de sala oferece so elas.', now())
on conflict (unidade, chave) do update set valor=excluded.valor, descricao=excluded.descricao, atualizado_em=now();
