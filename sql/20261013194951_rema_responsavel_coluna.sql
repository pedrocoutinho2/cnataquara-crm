-- Rema: responsável pelo contato com cada aluno da lista (divisão da secretaria). Pedro, 13/10/2026.
alter table public.crm_rema_aluno add column if not exists responsavel_id uuid references public.crm_usuarios(id);
create index if not exists crm_rema_aluno_periodo_resp_idx on public.crm_rema_aluno(periodo_id, responsavel_id);
notify pgrst, 'reload schema';