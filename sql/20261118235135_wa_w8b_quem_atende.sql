-- W8b (18/11/2026): quem aparece como atendente do WhatsApp em cada unidade.
-- crm_usuario_unidades.wa_atende: null = padrão (quem tem nível editar em Conversas aparece);
-- false = não aparece como atendente (lista de agentes, rodízio, transferência), mas mantém o acesso
-- que a permissão de Conversas der.
alter table crm_usuario_unidades add column if not exists wa_atende boolean;

create or replace function public.crm_wa_agentes(p_unidade text)
 returns table(usuario_id uuid, nome text, no_rodizio boolean)
 language sql stable security definer set search_path to 'public'
as $function$
  select u.id, u.nome,
         coalesce(uu.wa_rodizio, uu.papel = 'comercial' or uu.consultor)
    from crm_usuario_unidades uu
    join crm_usuarios u on u.id = uu.usuario_id
   where uu.unidade = p_unidade and uu.ativo and u.ativo
     and coalesce(uu.wa_atende, true)
     and crm_nivel_num(u.id, 'conversas', p_unidade) >= 2
   order by u.nome, u.id
$function$;
notify pgrst, 'reload schema';