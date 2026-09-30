-- Consolidação · Fase 2b-1a: chaves únicas por unidade (EXPAND).
-- As chaves antigas continuam existindo até a importação de Queimados (Fase 4), porque
-- crm_fechar_dia, escape_iniciar e metas_salvar_* e possivelmente o front fazem upsert por elas.
-- Chaves que dependem de um pai (periodo_id, lead_id, reuniao_id, sessao_id, conta_id, regra_id)
-- já isolam por unidade e não mudam. crm_wa_contas (phone_number_id, numero) segue global de propósito.

create unique index crm_configs_unidade_uk            on public.crm_configs (unidade, chave);
create unique index crm_metas_config_unidade_uk       on public.crm_metas_config (unidade, chave);
create unique index crm_agenda_config_unidade_uk      on public.crm_agenda_config (unidade, id);
create unique index crm_relatorio_diario_unidade_uk   on public.crm_relatorio_diario (unidade, data, consultor);
create unique index crm_tn_agend_slot_unidade_uk      on public.crm_tn_agendamentos (unidade, data, hora_inicio, aplicador) where (status <> 'cancelado');
create unique index crm_metas_unidade_uk              on public.crm_metas (unidade, competencia, escopo, coalesce(consultor, ''));
create unique index crm_metas_periodo_unidade_uk      on public.crm_metas_periodo (unidade, inicio);
create unique index crm_metas_semestre_unidade_uk     on public.crm_metas_semestre (unidade, inicio);
create unique index crm_precos_materiais_unidade_uk   on public.crm_precos_materiais (unidade, ano, codigo);
create unique index crm_precos_niveis_unidade_uk      on public.crm_precos_niveis (unidade, ano, codigo);
create unique index crm_respostas_rapidas_unidade_uk  on public.crm_respostas_rapidas (unidade, lower(atalho)) where (atalho is not null);
create unique index crm_wa_optout_unidade_uk          on public.crm_wa_optout (unidade, wa_chave);
create unique index crm_wa_regras_unidade_uk          on public.crm_wa_regras (unidade, chave);
create unique index crm_wa_templates_unidade_uk       on public.crm_wa_templates (unidade, nome, idioma);
create unique index crm_acoes_materiais_unidade_uk    on public.crm_acoes_materiais (unidade, nome);
create unique index escape_jogadores_unidade_uk       on public.escape_jogadores (unidade, wa_chave);
create unique index escape_salas_unidade_uk           on public.escape_salas (unidade, slug);
create unique index escape_temporadas_unidade_uk      on public.escape_temporadas (unidade, slug);
create unique index escape_variantes_unidade_uk       on public.escape_variantes (unidade, slug);

notify pgrst, 'reload schema';