-- Rede (todas as unidades). Promocoes ofertadas e fechadas por lead do funil B2C.
-- Lista de nomes do catalogo (crm_configs.promocoes da unidade ou PROMO_PADRAO do front).
-- O % vai no proprio item ("30% de desconto"). Mais de uma promocao por lead.
alter table public.crm_leads
  add column if not exists promo_ofertada text[],
  add column if not exists promo_fechada text[];
comment on column public.crm_leads.promo_ofertada is 'Promocoes passadas ao cliente (nomes do catalogo). 16/11/2026';
comment on column public.crm_leads.promo_fechada is 'Promocoes com que o cliente fechou (nomes do catalogo). 16/11/2026';
notify pgrst, 'reload schema';
