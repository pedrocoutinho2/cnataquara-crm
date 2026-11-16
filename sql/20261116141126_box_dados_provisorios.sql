-- Rede (base única do CRM). Decisão de 16/11/2026: falta de nascimento ou disponibilidade
-- não segura mais o envio ao CNA Box. A Edge Function manda valor provisório
-- (01/01/2000 e todos os horários) e marca em crm_leads.box_provisorio o que foi provisório;
-- o card do lead cobra o dado real e o próximo atendimento corrige o Box.
alter table public.crm_leads add column if not exists box_provisorio text[] not null default '{}';
comment on column public.crm_leads.box_provisorio is
  'Campos enviados ao CNA Box com valor provisório (data_nascimento, disponibilidade). O dado real preenchido no CRM substitui o do Box no próximo envio.';

create or replace function public.crm_box_pendencias(p_fila_id uuid) returns text[]
language plpgsql stable security definer set search_path to 'public' as $f$
declare f crm_box_fila; l crm_leads; i crm_leads_interacoes; p text[] := '{}';
begin
  select * into f from crm_box_fila where id = p_fila_id;
  if not found then return array['item_inexistente']; end if;
  select * into l from crm_leads where id = f.lead_id;
  if f.interacao_id is not null then select * into i from crm_leads_interacoes where id = f.interacao_id; end if;
  -- nascimento e disponibilidade saíram daqui em 16/11/2026: vão com valor provisório
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
end $f$;

create or replace function public.crm_box_fila_proximos(p_limite integer default 50) returns jsonb
language sql stable security definer set search_path to 'public' as $f$
  select coalesce(jsonb_agg(x), '[]'::jsonb) from (
    select jsonb_build_object(
      'fila_id', f.id, 'unidade', f.unidade, 'operacao', f.operacao, 'tentativas', f.tentativas,
      'consultor', l.responsavel,
      'lead', jsonb_build_object('id', l.id, 'nome', coalesce(nullif(l.nome_aluno, ''), l.nome), 'prospect', l.nome,
              'whatsapp', l.whatsapp, 'email', l.email, 'origem', l.origem, 'curso', l.curso,
              'data_nascimento', l.data_nascimento, 'sexo', l.sexo, 'disponibilidade', l.disponibilidade,
              'box_id', l.box_id, 'observacoes', l.observacoes, 'box_provisorio', l.box_provisorio),
      'interacao', case when i.id is null then null else jsonb_build_object(
              'id', i.id, 'data', i.data, 'tipo', i.tipo, 'nota', i.nota, 'efetivo', i.efetivo,
              'motivo_nao_efetivo', i.motivo_nao_efetivo, 'proximo_contato', i.proximo_contato,
              'proximo_contato_hora', i.proximo_contato_hora, 'proximo_canal', i.proximo_canal,
              'motivo_repique', i.motivo_repique, 'receptivo', crm_box_receptivo(i.id)) end,
      'pendencias', crm_box_pendencias(f.id)
    ) x
    from crm_box_fila f
    join crm_leads l on l.id = f.lead_id
    left join crm_leads_interacoes i on i.id = f.interacao_id
    join crm_box_config c on c.unidade = f.unidade and c.ativo
    where f.status = 'aprovado' and f.tentativas < 5
    order by f.unidade, l.responsavel, i.data, i.created_at
    limit p_limite
  ) t;
$f$;

-- itens que alguém já aprovou e só estavam presos por nascimento/disponibilidade
update public.crm_box_fila f
   set status = 'aprovado', pendencias = null, aprovado_em = now(),
       aprovado_por = coalesce(f.aprovado_por, f.consultor || ' (reavaliado em 16/11)')
 where f.status = 'aguardando_dados' and cardinality(public.crm_box_pendencias(f.id)) = 0;

notify pgrst, 'reload schema';