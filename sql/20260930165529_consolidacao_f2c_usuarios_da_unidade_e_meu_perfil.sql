-- Consolidação · Fase 2c: pedidos do mapeamento do front (Fase 3).
-- crm_usuarios_unidade(token): pessoas ATIVAS da unidade da sessão, no formato da linha de
--   crm_usuarios, com papel/admin/consultor/permissoes vindos do VÍNCULO da unidade. Exige só
--   sessão válida com unidade (qualquer papel): alimenta USERS/RESP/RESPC e nivelDe() do front.
--   Não devolve senha_hash nem pin_hash.
-- crm_meu_perfil_salvar(token, p): a própria pessoa altera hora_inicio, hora_fim, email_agenda e cor.
--   Mudança em outra pessoa continua indo por crm_equipe_salvar (módulo equipe).

create or replace function public.crm_usuarios_unidade(p_token uuid)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare u crm_usuarios; un text;
begin
  u := crm_sessao_user(p_token);
  un := crm_sessao_unidade(p_token);
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', us.id, 'nome', us.nome, 'email', us.email, 'email_agenda', us.email_agenda, 'cor', us.cor,
      'hora_inicio', us.hora_inicio, 'hora_fim', us.hora_fim, 'ativo', true,
      'senha_temporaria', us.senha_temporaria, 'created_at', us.created_at,
      'papel', v.papel, 'admin', v.admin, 'consultor', v.consultor, 'permissoes', coalesce(v.permissoes, '{}'::jsonb))
    order by us.nome)
    from crm_usuario_unidades v join crm_usuarios us on us.id = v.usuario_id
   where v.unidade = un and v.ativo and us.ativo), '[]'::jsonb);
end $function$;

create or replace function public.crm_meu_perfil_salvar(p_token uuid, p jsonb)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare u crm_usuarios;
begin
  u := crm_sessao_user(p_token);
  perform set_config('crm.sem_espelho', '1', true);
  update crm_usuarios set
    hora_inicio  = coalesce(nullif(p->>'hora_inicio','')::time, hora_inicio),
    hora_fim     = coalesce(nullif(p->>'hora_fim','')::time, hora_fim),
    email_agenda = case when p ? 'email_agenda' then nullif(btrim(p->>'email_agenda'),'') else email_agenda end,
    cor          = case when p ? 'cor' then nullif(p->>'cor','') else cor end
  where id = u.id;
end $function$;

revoke all on function public.crm_usuarios_unidade(uuid) from public;
revoke all on function public.crm_meu_perfil_salvar(uuid, jsonb) from public;
grant execute on function public.crm_usuarios_unidade(uuid) to anon, authenticated;
grant execute on function public.crm_meu_perfil_salvar(uuid, jsonb) to anon, authenticated;

notify pgrst, 'reload schema';