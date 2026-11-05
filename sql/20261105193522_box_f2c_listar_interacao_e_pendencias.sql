-- Fila do Box: a tela precisa do id do contato (para completar o motivo do repique ali mesmo)
-- e reunião/aula experimental contam como agendamento (Box: atendimento pessoal / teste de nível), não repique.
create or replace function public.crm_box_pendencias(p_fila_id uuid)
returns text[]
language plpgsql
stable
security definer
set search_path = public
as $$
declare f crm_box_fila; l crm_leads; i crm_leads_interacoes; p text[] := '{}';
begin
  select * into f from crm_box_fila where id = p_fila_id;
  if not found then return array['item_inexistente']; end if;
  select * into l from crm_leads where id = f.lead_id;
  if f.interacao_id is not null then select * into i from crm_leads_interacoes where id = f.interacao_id; end if;
  if l.data_nascimento is null then p := array_append(p, 'data_nascimento'); end if;
  if coalesce(array_length(l.disponibilidade, 1), 0) = 0 then p := array_append(p, 'disponibilidade'); end if;
  if coalesce(l.whatsapp, '') = '' and coalesce(l.email, '') = '' then p := array_append(p, 'contato'); end if;
  if i.id is not null then
    if i.efetivo is false and i.motivo_nao_efetivo is null then p := array_append(p, 'motivo_nao_efetivo'); end if;
    if i.efetivo is not false and i.proximo_contato is not null
       and coalesce(i.proximo_canal, '') not in ('visita', 'reuniao', 'teste_nivel', 'experimental')
       and i.motivo_repique is null then p := array_append(p, 'motivo_repique'); end if;
  end if;
  if not exists (select 1 from crm_box_credenciais c join crm_usuarios u on u.id = c.usuario_id
                  where c.unidade = f.unidade and u.nome = l.responsavel) then
    p := array_append(p, 'consultor_sem_box');
  end if;
  return p;
end $$;
revoke all on function public.crm_box_pendencias(uuid) from public, anon, authenticated;
grant execute on function public.crm_box_pendencias(uuid) to service_role;

create or replace function public.crm_box_fila_listar(p_token uuid, p_status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare s jsonb; v_todos boolean;
begin
  s := crm_box_sessao(p_token, 1);
  v_todos := (s->>'nivel')::int >= 3;
  return coalesce((
    select jsonb_agg(x order by x->>'criado_em' desc) from (
      select jsonb_build_object(
        'id', f.id, 'status', f.status, 'operacao', f.operacao, 'criado_em', f.criado_em,
        'enviado_em', f.enviado_em, 'erro', f.erro, 'tentativas', f.tentativas,
        'lead_id', l.id, 'lead_nome', coalesce(nullif(l.nome_aluno, ''), l.nome), 'consultor', l.responsavel,
        'box_id', l.box_id, 'interacao_id', i.id, 'interacao_data', i.data, 'interacao_tipo', i.tipo,
        'efetivo', i.efetivo, 'motivo_repique', i.motivo_repique,
        'receptivo', crm_box_receptivo(i.id),
        'pendencias', case when f.status in ('enviado', 'ignorado') then '{}'::text[] else crm_box_pendencias(f.id) end
      ) x
      from crm_box_fila f
      join crm_leads l on l.id = f.lead_id
      left join crm_leads_interacoes i on i.id = f.interacao_id
      where f.unidade = s->>'unidade'
        and (v_todos or l.responsavel = s->>'nome')
        and (p_status is null or f.status = p_status)
      order by f.criado_em desc
      limit 500
    ) t), '[]'::jsonb);
end $$;
revoke all on function public.crm_box_fila_listar(uuid, text) from public;
grant execute on function public.crm_box_fila_listar(uuid, text) to anon, authenticated;

notify pgrst, 'reload schema';