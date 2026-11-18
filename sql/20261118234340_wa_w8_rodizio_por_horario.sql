-- W8 (18/11/2026): rodízio do WhatsApp respeita o horário de trabalho de cada atendente.
-- Horário vem de crm_usuarios.hora_inicio/hora_fim (o "Horário" do perfil), em hora de Brasília.
-- Conversa nova sem lead com responsável: vai para quem está no horário agora (rodízio entre eles);
-- se ninguém do rodízio está no horário (fora do expediente), rodízio entre todos.
-- Atendente sem horário cadastrado conta como sempre disponível. Turno que vira a meia-noite é aceito.
create or replace function crm_wa_no_horario(p_ini time, p_fim time, p_agora time)
returns boolean language sql immutable as $$
  select case
    when p_ini is null or p_fim is null then true
    when p_ini < p_fim then p_agora >= p_ini and p_agora < p_fim
    when p_ini > p_fim then p_agora >= p_ini or p_agora < p_fim
    else true end
$$;

create or replace function public.crm_wa_proximo_agente(p_unidade text)
 returns uuid language plpgsql security definer set search_path to 'public'
as $function$
declare ag uuid[]; agh uuid[]; ult uuid; i int; prox uuid;
  v_agora time := (now() at time zone 'America/Sao_Paulo')::time;
begin
  select array_agg(a.usuario_id order by a.nome, a.usuario_id),
         array_agg(a.usuario_id order by a.nome, a.usuario_id)
           filter (where crm_wa_no_horario(u.hora_inicio, u.hora_fim, v_agora))
    into ag, agh
    from crm_wa_agentes(p_unidade) a join crm_usuarios u on u.id = a.usuario_id
   where a.no_rodizio;
  if ag is null then return null; end if;
  if agh is not null and array_length(agh, 1) > 0 then ag := agh; end if;
  insert into crm_wa_rodizio(unidade) values (p_unidade) on conflict (unidade) do nothing;
  select ultimo_usuario_id into ult from crm_wa_rodizio where unidade = p_unidade for update;
  i := array_position(ag, ult);
  prox := ag[case when i is null or i >= array_length(ag, 1) then 1 else i + 1 end];
  update crm_wa_rodizio set ultimo_usuario_id = prox, atualizado_em = now() where unidade = p_unidade;
  return prox;
end $function$;
notify pgrst, 'reload schema';