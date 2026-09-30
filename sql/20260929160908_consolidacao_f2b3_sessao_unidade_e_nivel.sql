-- Consolidação · Fase 2b-3: permissão passa a ser por unidade.
-- crm_sessao_unidade: unidade ativa da sessão (erro se a pessoa ainda não escolheu).
-- crm_nivel_num(usuario, modulo, unidade): mesma regra papel -> padrão -> exceção,
--   lida do vínculo da unidade. A versão de 2 argumentos segue existindo (aridade diferente,
--   sem ambiguidade) até o front novo; ela lê crm_usuarios, que a ponte legada espelha no vínculo.
-- crm_exige: mesma assinatura e retorno; checa o nível na unidade da sessão.

create or replace function public.crm_sessao_unidade(p_token uuid)
 returns text
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare v text; ok boolean;
begin
  select true, s.unidade into ok, v from crm_sessoes s where s.token = p_token and s.expira_em > now();
  if ok is null then raise exception 'sessao_invalida' using errcode = 'P0001'; end if;
  if v is null then raise exception 'unidade_nao_escolhida' using errcode = 'P0001'; end if;
  return v;
end $function$;
revoke all on function public.crm_sessao_unidade(uuid) from public, anon, authenticated;

create or replace function public.crm_nivel_num(p_usuario uuid, p_mod text, p_unidade text)
 returns integer
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare v record; n text;
begin
  select uu.* into v
    from crm_usuario_unidades uu
    join crm_usuarios u on u.id = uu.usuario_id and u.ativo = true
   where uu.usuario_id = p_usuario and uu.unidade = p_unidade and uu.ativo;
  if not found then return 0; end if;
  n := v.permissoes ->> p_mod;
  if n is null then
    select nivel into n from crm_papel_permissoes
     where papel = coalesce(v.papel, case when v.admin then 'admin' else 'comercial' end) and modulo = p_mod;
  end if;
  if n is null then n := case when v.admin then 'total' else 'nenhum' end; end if;
  return case n when 'total' then 3 when 'editar' then 2 when 'ver' then 1 else 0 end;
end $function$;
revoke all on function public.crm_nivel_num(uuid, text, text) from public, anon, authenticated;

create or replace function public.crm_exige(p_token uuid, p_mod text, p_min integer)
 returns crm_usuarios
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare u crm_usuarios; uid uuid; v_un text;
begin
  select usuario_id, unidade into uid, v_un from crm_sessoes where token = p_token and expira_em > now();
  if uid is null then raise exception 'sessao_invalida' using errcode = 'P0001'; end if;
  if v_un is null then raise exception 'unidade_nao_escolhida' using errcode = 'P0001'; end if;
  select * into u from crm_usuarios where id = uid and ativo = true;
  if not found then raise exception 'sessao_invalida' using errcode = 'P0001'; end if;
  if crm_nivel_num(uid, p_mod, v_un) < p_min then raise exception 'sem_permissao' using errcode = 'P0001'; end if;
  return u;
end $function$;