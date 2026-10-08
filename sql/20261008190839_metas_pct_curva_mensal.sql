-- Metas: % da faixa em coluna própria, curva mensal da rema por indicador e histórico mensal por semestre
alter table public.crm_metas_faixa     add column if not exists pct numeric(6,2);
alter table public.crm_metas_indicador add column if not exists curva jsonb;
alter table public.crm_metas_semestre  add column if not exists mensal jsonb;
comment on column public.crm_metas_faixa.pct is 'Percentual da meta sobre base_ref do indicador (rema). alvo = teto(pct x base_ref)';
comment on column public.crm_metas_indicador.curva is 'Rema: % do período realizado em cada mês, na ordem dos meses do período (soma 100)';
comment on column public.crm_metas_semestre.mensal is 'Rema realizada mês a mês: [{mes, contratual, automatica}] (CNA Box)';
notify pgrst, 'reload schema';