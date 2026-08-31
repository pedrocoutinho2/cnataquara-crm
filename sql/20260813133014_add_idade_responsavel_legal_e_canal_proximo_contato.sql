-- Idade do aluno e responsavel legal (pai/mae), so no funil B2C
alter table crm_leads add column if not exists idade smallint;
alter table crm_leads add column if not exists responsavel_legal text;

-- Canal por onde o proximo contato sera feito
alter table crm_leads              add column if not exists proximo_canal text;
alter table crm_escolas            add column if not exists proximo_canal text;
alter table crm_empresas           add column if not exists proximo_canal text;
alter table crm_leads_interacoes   add column if not exists proximo_canal text;
alter table crm_interacoes         add column if not exists proximo_canal text;

-- Idade plausivel, sem travar registro em branco
alter table crm_leads drop constraint if exists crm_leads_idade_ck;
alter table crm_leads add constraint crm_leads_idade_ck
  check (idade is null or (idade >= 1 and idade <= 120));

comment on column crm_leads.responsavel_legal is 'Nome do pai/mae/responsavel pelo aluno. Obrigatorio quando idade < 16. Nao confundir com crm_leads.responsavel, que e o consultor dono do lead.';
comment on column crm_leads.proximo_canal is 'Canal previsto do proximo contato: whatsapp, ligacao, email, visita, reuniao.';

notify pgrst, 'reload schema';