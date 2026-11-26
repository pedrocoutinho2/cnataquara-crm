-- Vínculo do lead com parceiro (26/11/2026). Rede: vale para as três unidades.
-- O lead pode ser aluno, colaborador ou morador de um parceiro já cadastrado em
-- crm_parceiros (aba Parcerias). Os dois campos são opcionais: o CRM cobra, não bloqueia.
-- Parceiro e lead da MESMA unidade, garantido por FK composta (parceiro_id, unidade).
-- Não existe exclusão de parceiro (só inativar), por isso a FK não tem ON DELETE.

alter table public.crm_parceiros
  add constraint crm_parceiros_id_unidade_uk unique (id, unidade);

alter table public.crm_leads
  add column if not exists parceiro_id uuid,
  add column if not exists parceiro_vinculo text;

alter table public.crm_leads
  add constraint crm_leads_parceiro_vinculo_check
    check (parceiro_vinculo in ('aluno','trabalha','mora')),
  add constraint crm_leads_parceiro_fkey
    foreign key (parceiro_id, unidade) references public.crm_parceiros (id, unidade);

create index if not exists crm_leads_parceiro_idx
  on public.crm_leads (parceiro_id) where parceiro_id is not null;

-- Opções da ficha do lead: quem edita lead precisa escolher o parceiro sem ter
-- acesso à aba Parcerias. Devolve só id, nome, tipo e status da unidade da sessão.
create or replace function public.parceiros_opcoes(p_token uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare u crm_usuarios; un text;
begin
  u  := crm_exige(p_token, 'leads', 1);
  un := crm_sessao_unidade(p_token);
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id',p.id,'tipo',p.tipo,'nome',p.nome,'status',p.status)
    order by p.tipo, p.nome)
    from crm_parceiros p where p.unidade = un), '[]'::jsonb);
end $fn$;

revoke all on function public.parceiros_opcoes(uuid) from public;
grant execute on function public.parceiros_opcoes(uuid) to anon, authenticated;

notify pgrst, 'reload schema';
