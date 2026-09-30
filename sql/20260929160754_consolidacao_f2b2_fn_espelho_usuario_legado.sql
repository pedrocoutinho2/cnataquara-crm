-- Consolidação · Fase 2b-2a: ponte temporária para a tela de Equipe do front atual.
-- O front atual cria e edita usuário direto em crm_usuarios e só administra a Taquara.
-- Desde a Fase 2a o login exige vínculo em crm_usuario_unidades; sem esta ponte,
-- usuário novo criado pela tela atual não conseguiria entrar.
-- REMOVER quando o front novo (Fase 3) gerenciar vínculos por RPC.
create or replace function public.crm_usuario_espelho_legado()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  insert into crm_usuario_unidades (usuario_id, unidade, papel, admin, consultor, permissoes, ativo)
  values (new.id, 'taquara', new.papel, coalesce(new.admin,false), coalesce(new.consultor,false), new.permissoes, coalesce(new.ativo,true))
  on conflict (usuario_id, unidade) do update
    set papel = excluded.papel, admin = excluded.admin, consultor = excluded.consultor,
        permissoes = excluded.permissoes, ativo = excluded.ativo;
  return new;
end $function$;

revoke all on function public.crm_usuario_espelho_legado() from public, anon, authenticated;
comment on function public.crm_usuario_espelho_legado() is 'TEMPORÁRIA (consolidação): espelha crm_usuarios no vínculo da Taquara enquanto o front atual administra a equipe. Remover na Fase 3.';