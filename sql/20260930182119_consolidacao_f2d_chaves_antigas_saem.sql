-- Consolidação · Fase 2d: chaves únicas globais saem, ficam só as por unidade.
-- Antecipado da Fase 4 a pedido do mapeamento do front: sem isso a segunda unidade não grava
-- config com a mesma chave. Nenhuma FK depende das chaves removidas. As funções já usam as
-- chaves novas desde a 2b. O front atual só faz upsert em crm_configs pela PK, que passa a ser
-- (unidade, chave) e continua casando (unidade cai no default 'taquara').
-- Ensaio em transação desfeita: front atual atualiza sem duplicar, Jardim América grava a mesma chave.

-- PK por unidade (o índice único criado na 2b-1 vira a PK)
alter table public.crm_configs drop constraint crm_configs_pkey;
alter table public.crm_configs add constraint crm_configs_pkey primary key using index crm_configs_unidade_uk;
alter table public.crm_metas_config drop constraint crm_metas_config_pkey;
alter table public.crm_metas_config add constraint crm_metas_config_pkey primary key using index crm_metas_config_unidade_uk;
alter table public.crm_agenda_config drop constraint crm_agenda_config_pkey;
alter table public.crm_agenda_config add constraint crm_agenda_config_pkey primary key using index crm_agenda_config_unidade_uk;
alter table public.crm_wa_optout drop constraint crm_wa_optout_pkey;
alter table public.crm_wa_optout add constraint crm_wa_optout_pkey primary key using index crm_wa_optout_unidade_uk;

-- únicas globais antigas
alter table public.crm_acoes_materiais drop constraint crm_acoes_materiais_nome_key;
alter table public.crm_metas_periodo drop constraint crm_metas_periodo_inicio_key;
alter table public.crm_metas_semestre drop constraint crm_metas_semestre_inicio_key;
alter table public.crm_precos_materiais drop constraint crm_precos_materiais_ano_codigo_key;
alter table public.crm_precos_niveis drop constraint crm_precos_niveis_ano_codigo_key;
alter table public.crm_relatorio_diario drop constraint crm_relatorio_diario_data_consultor_key;
alter table public.crm_wa_regras drop constraint crm_wa_regras_chave_key;
alter table public.crm_wa_templates drop constraint crm_wa_templates_nome_idioma_key;
alter table public.escape_jogadores drop constraint escape_jogadores_wa_chave_key;
alter table public.escape_salas drop constraint escape_salas_slug_key;
alter table public.escape_temporadas drop constraint escape_temporadas_slug_key;
alter table public.escape_variantes drop constraint escape_variantes_slug_key;
drop index public.crm_metas_uk;
drop index public.crm_respostas_rapidas_atalho_uk;
drop index public.crm_tn_agend_slot_uk;

notify pgrst, 'reload schema';