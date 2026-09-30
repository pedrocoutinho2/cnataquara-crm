-- Consolidação · Fase 2b-1c: filhos herdam a unidade do pai.
-- Prefixo a00_ para rodar antes dos demais BEFORE triggers (ordem alfabética).
create trigger a00_herda_unidade before insert or update on public.crm_leads_interacoes      for each row execute function public.crm_herda_unidade('crm_leads','lead_id');
create trigger a00_herda_unidade before insert or update on public.crm_leads_etapas          for each row execute function public.crm_herda_unidade('crm_leads','lead_id');
create trigger a00_herda_unidade before insert or update on public.crm_tarefas               for each row execute function public.crm_herda_unidade('crm_leads','lead_id');
create trigger a00_herda_unidade before insert or update on public.crm_tn_agendamentos       for each row execute function public.crm_herda_unidade('crm_leads','lead_id');
create trigger a00_herda_unidade before insert or update on public.crm_wa_fila               for each row execute function public.crm_herda_unidade('crm_leads','lead_id');
create trigger a00_herda_unidade_empresa before insert or update on public.crm_interacoes    for each row execute function public.crm_herda_unidade('crm_empresas','empresa_id');
create trigger a01_herda_unidade_escola  before insert or update on public.crm_interacoes    for each row execute function public.crm_herda_unidade('crm_escolas','escola_id');
create trigger a00_herda_unidade before insert or update on public.crm_wa_conversas          for each row execute function public.crm_herda_unidade('crm_wa_contas','conta_id');
create trigger a00_herda_unidade before insert or update on public.crm_wa_mensagens          for each row execute function public.crm_herda_unidade('crm_wa_conversas','conversa_id');
create trigger a00_herda_unidade before insert or update on public.crm_wa_eventos            for each row execute function public.crm_herda_unidade('crm_wa_contas','conta_id');
create trigger a00_herda_unidade before insert or update on public.crm_wa_optout             for each row execute function public.crm_herda_unidade('crm_wa_contas','conta_id');
create trigger a00_herda_unidade before insert or update on public.crm_reuniao_participantes for each row execute function public.crm_herda_unidade('crm_reunioes','reuniao_id');
create trigger a00_herda_unidade before insert or update on public.crm_reuniao_assinaturas   for each row execute function public.crm_herda_unidade('crm_reunioes','reuniao_id');
create trigger a00_herda_unidade before insert or update on public.crm_demanda_itens         for each row execute function public.crm_herda_unidade('crm_demandas','demanda_id');
create trigger a00_herda_unidade before insert or update on public.crm_demanda_anexos        for each row execute function public.crm_herda_unidade('crm_demandas','demanda_id');
create trigger a00_herda_unidade before insert or update on public.crm_metas_indicador       for each row execute function public.crm_herda_unidade('crm_metas_periodo','periodo_id');
create trigger a00_herda_unidade before insert or update on public.crm_metas_mes             for each row execute function public.crm_herda_unidade('crm_metas_periodo','periodo_id');
create trigger a00_herda_unidade before insert or update on public.crm_rema_aluno            for each row execute function public.crm_herda_unidade('crm_metas_periodo','periodo_id');
create trigger a00_herda_unidade before insert or update on public.crm_rema_import           for each row execute function public.crm_herda_unidade('crm_metas_periodo','periodo_id');
create trigger a00_herda_unidade before insert or update on public.crm_metas_faixa           for each row execute function public.crm_herda_unidade('crm_metas_indicador','indicador_id');
create trigger a00_herda_unidade before insert or update on public.escape_sessoes            for each row execute function public.crm_herda_unidade('escape_jogadores','jogador_id');
create trigger a00_herda_unidade before insert or update on public.escape_sessao_salas       for each row execute function public.crm_herda_unidade('escape_sessoes','sessao_id');
create trigger a00_herda_unidade before insert or update on public.escape_variantes          for each row execute function public.crm_herda_unidade('escape_salas','sala_id');