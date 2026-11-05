-- Base: gpnwmsnayrqjcmhqrtpx (CRM CNA) · escopo: rede
-- Data de cadastro (data_entrada) e carimbo do sistema (created_at) imutaveis apos o INSERT.
-- UPDATE que tente muda-los e revertido em silencio; o resto do registro salva.
-- Correcao legitima so por SQL: begin; set local crm.libera_data_cadastro = 'on'; update ...; commit;
create or replace function public.crm_leads_trava_cadastro()
returns trigger
language plpgsql
as $f$
begin
  if coalesce(current_setting('crm.libera_data_cadastro', true), '') = 'on' then
    return new;
  end if;
  new.data_entrada := old.data_entrada;
  new.created_at   := old.created_at;
  return new;
end
$f$;

comment on function public.crm_leads_trava_cadastro() is
  'Trava data_entrada e created_at de crm_leads apos o cadastro. Liberacao: set local crm.libera_data_cadastro = on.';