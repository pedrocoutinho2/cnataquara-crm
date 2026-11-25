-- Número principal por unidade (25/11/2026, decisão do Pedro): conversa NOVA aberta pelo CRM sai sempre por ele.
-- Os demais números só continuam conversas já existentes. Uma principal por unidade (índice parcial).
alter table public.crm_wa_contas add column if not exists principal boolean not null default false;
create unique index if not exists crm_wa_contas_principal_un on public.crm_wa_contas (unidade) where principal;
update public.crm_wa_contas set principal = true
 where id in ('3bc5b465-8f65-48bb-8eea-bcc04bfd8e44',  -- jardim-america, único número
              '99d46488-ab65-4cf5-a676-174d6ca54090',  -- taquara, escola (Roberta)
              '907ced23-f269-444c-8c7e-f12d72fe070d'); -- queimados, único cadastrado (inativo)
notify pgrst, 'reload schema';