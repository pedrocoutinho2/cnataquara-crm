-- Consolidação · Fase 2b-1b: função genérica de herança de unidade.
-- Uso: trigger BEFORE INSERT OR UPDATE com argumentos (tabela_pai, coluna_fk).
-- Se o filho aponta para um pai, a unidade do filho passa a ser a do pai, sempre.
-- Filho sem pai (fk nula) mantém a unidade que recebeu.
create or replace function public.crm_herda_unidade()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_id text; v_un text;
begin
  v_id := to_jsonb(new) ->> tg_argv[1];
  if v_id is null then return new; end if;
  execute format('select unidade from public.%I where id = $1', tg_argv[0]) into v_un using v_id::uuid;
  if v_un is not null then new.unidade := v_un; end if;
  return new;
end $function$;

revoke all on function public.crm_herda_unidade() from public, anon, authenticated;
comment on function public.crm_herda_unidade() is 'Trigger: filho herda a unidade do pai. Args: tabela_pai, coluna_fk.';