-- Rastro de quem mexeu no agendamento depois de registrado
alter table crm_leads_interacoes add column if not exists agenda_editada_em  timestamptz;
alter table crm_leads_interacoes add column if not exists agenda_editada_por text;
alter table crm_interacoes       add column if not exists agenda_editada_em  timestamptz;
alter table crm_interacoes       add column if not exists agenda_editada_por text;

comment on column crm_leads_interacoes.agenda_editada_em is 'Quando o proximo contato desta interacao foi corrigido ou removido apos o registro.';

notify pgrst, 'reload schema';