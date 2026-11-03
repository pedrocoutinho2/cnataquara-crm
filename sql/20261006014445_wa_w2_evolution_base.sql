-- WhatsApp · W2 Evolution (fase 1 por API não oficial, decisões de 03/10 e 05/10/2026).
-- Spec: 10-cna/sistemas/whatsapp-multinumero.md
-- 1) token_ref por provedor: conta Cloud aponta para WA_TOKEN_*, conta Evolution para EVO_TOKEN_*
--    (token da instância, usado para enviar e para autenticar o webhook). Segredo só em supabase secrets.
alter table public.crm_wa_contas drop constraint crm_wa_contas_token_ref_ck;
alter table public.crm_wa_contas add constraint crm_wa_contas_token_ref_ck check (
  token_ref is null
  or (provider = 'cloud'     and token_ref ~ '^WA_TOKEN_[A-Z0-9_]{1,40}$')
  or (provider = 'evolution' and token_ref ~ '^EVO_TOKEN_[A-Z0-9_]{1,40}$'));
comment on column public.crm_wa_contas.token_ref is
  'Nome do secret (supabase secrets set) desta conta. Cloud: WA_TOKEN_* (token da Meta). Evolution: EVO_TOKEN_* (token da instância, também exigido no header x-cna-token do webhook).';

-- 2) instância da Evolution é única na rede (o webhook acha a conta por ela)
create unique index crm_wa_contas_evolution_instancia_uq
  on public.crm_wa_contas (evolution_instancia) where evolution_instancia is not null;

-- 3) eventos: conta pela phone_number_id (Meta) ou pela instance (Evolution); o payload da Evolution
--    traz o apikey da instância e ele NUNCA é gravado.
create or replace function public.crm_wa_evento_resolve_conta() returns trigger
language plpgsql security definer set search_path = public as $f$
declare v_pnid text; v_inst text;
begin
  new.payload := new.payload - 'apikey';
  if new.conta_id is null then
    v_pnid := new.payload #>> '{entry,0,changes,0,value,metadata,phone_number_id}';
    if v_pnid is not null then
      select id into new.conta_id from public.crm_wa_contas where phone_number_id = v_pnid;
    else
      v_inst := new.payload ->> 'instance';
      if v_inst is not null then
        select id into new.conta_id from public.crm_wa_contas
         where provider = 'evolution' and evolution_instancia = v_inst;
      end if;
    end if;
  end if;
  if new.provider is null and new.conta_id is not null then
    select provider into new.provider from public.crm_wa_contas where id = new.conta_id;
  end if;
  return new;
end $f$;

notify pgrst, 'reload schema';