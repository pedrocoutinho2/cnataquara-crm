-- A52 — "Último contato" passa a significar contato de verdade.
-- Tentativa sem sucesso deixa de carimbar ultimo_contato e passa a alimentar
-- ultima_tentativa + tentativas_sem_retorno, que é o que permite medir
-- quantas tentativas são necessárias até o lead dar retorno.
-- A regra mora NO BANCO (regra 4): há vários caminhos de registro de contato.

alter table crm_leads
  add column if not exists ultima_tentativa date,
  add column if not exists tentativas_sem_retorno integer not null default 0;

comment on column crm_leads.ultima_tentativa is
  'Data da última tentativa de contato SEM sucesso. Mantida por crm_interacao_atualiza_contato_tg.';
comment on column crm_leads.tentativas_sem_retorno is
  'Quantas tentativas sem sucesso desde o último contato efetivo. Zera quando há contato efetivo.';
comment on column crm_leads.ultimo_contato is
  'Data do último contato EFETIVO. Tentativa sem sucesso não escreve aqui (A52, 31/08/2026).';

create or replace function crm_interacao_atualiza_contato()
returns trigger
language plpgsql
as $fn$
begin
  if new.efetivo then
    update crm_leads
       set ultimo_contato = greatest(coalesce(ultimo_contato, new.data), new.data),
           tentativas_sem_retorno = 0,
           updated_at = now()
     where id = new.lead_id;
  else
    update crm_leads
       set ultima_tentativa = greatest(coalesce(ultima_tentativa, new.data), new.data),
           tentativas_sem_retorno = coalesce(tentativas_sem_retorno, 0) + 1,
           updated_at = now()
     where id = new.lead_id;
  end if;
  return new;
end
$fn$;

drop trigger if exists crm_interacao_atualiza_contato_tg on crm_leads_interacoes;
create trigger crm_interacao_atualiza_contato_tg
  after insert on crm_leads_interacoes
  for each row execute function crm_interacao_atualiza_contato();

notify pgrst, 'reload schema';
