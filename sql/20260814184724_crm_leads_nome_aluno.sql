alter table crm_leads add column if not exists nome_aluno text;
comment on column crm_leads.nome_aluno is 'Nome do aluno. Pode ser diferente do campo nome, que guarda quem fez o contato (prospect).';
notify pgrst, 'reload schema';