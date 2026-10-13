-- Rema: troca manual do responsável pelo contato e divisão inicial pela ordem da lista. Pedro, 13/10/2026.
-- rema_responsavel: só muda o responsável; não mexe em status, data nem "última alteração".
-- rema_dividir: a divisão inicial segue a ordem em que a lista aparece na tela
-- (pendentes e em negociação primeiro, depois nome), a mesma de rema_lista.

create or replace function public.rema_responsavel(p_token uuid, p_id uuid, p_responsavel uuid)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare u crm_usuarios; un text;
begin
  u := crm_exige(p_token, 'rema', 2);
  un := crm_sessao_unidade(p_token);
  if p_responsavel is not null and not exists (
      select 1 from crm_usuario_unidades v join crm_usuarios us on us.id = v.usuario_id
       where v.usuario_id = p_responsavel and v.unidade = un and v.ativo and us.ativo) then
    raise exception 'responsavel_fora_da_unidade' using errcode = 'P0001';
  end if;
  update crm_rema_aluno set responsavel_id = p_responsavel where id = p_id and unidade = un;
  if not found then raise exception 'aluno_nao_encontrado' using errcode = 'P0001'; end if;
end $function$;
grant execute on function public.rema_responsavel(uuid, uuid, uuid) to anon, authenticated;

create or replace function public.rema_dividir(p_periodo uuid)
 returns integer
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare un text; resp uuid[]; k int; n int := 0;
begin
  select unidade into un from crm_metas_periodo where id = p_periodo;
  if un is null then return 0; end if;
  select array(select (jsonb_array_elements_text(valor->'responsaveis'))::uuid) into resp
    from crm_metas_config where chave = 'rema_divisao' and unidade = un;
  k := coalesce(cardinality(resp), 0);
  if k = 0 then return 0; end if;
  if not exists (select 1 from crm_rema_aluno where periodo_id = p_periodo and responsavel_id is not null) then
    -- divisão inicial: ordem da lista na tela (pendentes primeiro, depois nome), blocos iguais
    with o as (
      select id, (row_number() over (order by (status in ('pendente','negociacao')) desc, aluno, chave) - 1) rn, count(*) over () tot
      from crm_rema_aluno where periodo_id = p_periodo and na_lista)
    update crm_rema_aluno a set responsavel_id = resp[1 + ((o.rn * k) / o.tot)::int]
      from o where a.id = o.id;
  else
    -- aluno novo: fica com quem cuida do vizinho anterior na lista por nome (ou do seguinte);
    -- quem já tem responsável, automático ou trocado à mão, não muda
    update crm_rema_aluno a set responsavel_id = coalesce(
      (select b.responsavel_id from crm_rema_aluno b
        where b.periodo_id = p_periodo and b.na_lista and b.responsavel_id is not null and b.aluno <= a.aluno
        order by b.aluno desc limit 1),
      (select b.responsavel_id from crm_rema_aluno b
        where b.periodo_id = p_periodo and b.na_lista and b.responsavel_id is not null and b.aluno > a.aluno
        order by b.aluno limit 1),
      resp[1])
    where a.periodo_id = p_periodo and a.na_lista and a.responsavel_id is null;
  end if;
  get diagnostics n = row_count;
  return n;
end $function$;
revoke all on function public.rema_dividir(uuid) from public, anon, authenticated;

notify pgrst, 'reload schema';