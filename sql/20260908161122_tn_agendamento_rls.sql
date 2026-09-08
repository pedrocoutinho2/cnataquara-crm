-- 002-teste-de-nivel-agendamento.sql
-- Projeto: cnataquara-comercial (gpnwmsnayrqjcmhqrtpx)
-- Aplicado em producao em 08/09/2026, nas migracoes:
--   tn_agendamento_tabelas · tn_agendamento_rls · tn_disponibilidade_fn · tn_agendar_fn
--
-- O que este arquivo cria:
--   1. crm_tn_grade        — grade semanal recorrente publicada pelo pedagogico
--   2. crm_tn_avulsos      — vagas extras e bloqueios pontuais (dia inteiro ou faixa)
--   3. crm_tn_agendamentos — o teste marcado, sempre amarrado a um lead do funil B2C
--   4. crm_leads.email     — coluna nova; nao existia e e' o que permite convidar no Google
--   5. crm_tn_disponibilidade() — expande grade + avulsos - bloqueios - ocupados
--   6. crm_tn_agendar()         — reserva o slot com guarda de concorrencia
--
-- Validado em BEGIN..ROLLBACK (08/09/2026): 13 slots em 14 dias, bloqueio de dia
-- inteiro zera o dia, slot ocupado barra o segundo agendamento, horario fora da
-- grade e' recusado, lead sai com proximo_canal = 'teste_nivel'.

-- ============================================================ 2. RLS
-- Mesmo padrao permissivo das demais tabelas do CRM. Quem pode publicar
-- disponibilidade e' filtrado no front pelo modulo de permissao, como no calendario.
-- (Segue valendo a divida de seguranca no 1: chave anon no HTML com anon_all.)

drop policy if exists anon_all on crm_tn_grade;
create policy anon_all on crm_tn_grade for all to anon using (true) with check (true);

drop policy if exists anon_all on crm_tn_avulsos;
create policy anon_all on crm_tn_avulsos for all to anon using (true) with check (true);

drop policy if exists anon_all on crm_tn_agendamentos;
create policy anon_all on crm_tn_agendamentos for all to anon using (true) with check (true);

