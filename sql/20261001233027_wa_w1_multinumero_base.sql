-- WhatsApp multi-número · W1 (aditivo). Spec: 10-cna/sistemas/whatsapp-multinumero.md
-- 1) Cada conta aponta para o NOME do secret do Supabase com o token da Meta daquele número.
--    O token nunca fica no banco. A trava impede apontar para outro secret (ex.: service role).
alter table public.crm_wa_contas add column token_ref text;
alter table public.crm_wa_contas add constraint crm_wa_contas_token_ref_ck
  check (token_ref is null or token_ref ~ '^WA_TOKEN_[A-Z0-9_]{1,40}$');
comment on column public.crm_wa_contas.token_ref is 'Nome do secret (supabase secrets set) com o token da Meta deste número. Só WA_TOKEN_*.';

-- 2) Template pertence ao número (aprovação da Meta é por WABA).
alter table public.crm_wa_templates add column conta_id uuid references public.crm_wa_contas(id) on delete set null;
create index crm_wa_templates_conta_idx on public.crm_wa_templates (conta_id);

notify pgrst, 'reload schema';