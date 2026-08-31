create or replace function crm_fechar_dia(p_data date, p_consultor text, p_por text default null)
returns jsonb
language plpgsql
as $fn$
declare j jsonb; k jsonb;
begin
  j := crm_relatorio_dia(p_data, p_consultor);
  k := j->'kpis';

  insert into crm_relatorio_diario
    (data, consultor, agendados, realizados, efetivos, nao_efetivos, pendentes,
     leads_novos, movimentacoes, matriculas, perdidos, amanha, cumprimento,
     detalhe, fechado_em, fechado_por)
  values
    (p_data, p_consultor,
     (k->>'agendados')::int, (k->>'realizados')::int, (k->>'efetivos')::int,
     (k->>'nao_efetivos')::int, (k->>'pendentes')::int, (k->>'leads_novos')::int,
     (k->>'movimentacoes')::int, (k->>'matriculas')::int, (k->>'perdidos')::int,
     (k->>'amanha')::int, (k->>'cumprimento')::numeric,
     j, now(), coalesce(p_por, p_consultor))
  on conflict (data, consultor) do update set
     agendados = excluded.agendados,
     realizados = excluded.realizados,
     efetivos = excluded.efetivos,
     nao_efetivos = excluded.nao_efetivos,
     pendentes = excluded.pendentes,
     leads_novos = excluded.leads_novos,
     movimentacoes = excluded.movimentacoes,
     matriculas = excluded.matriculas,
     perdidos = excluded.perdidos,
     amanha = excluded.amanha,
     cumprimento = excluded.cumprimento,
     detalhe = excluded.detalhe,
     fechado_em = now(),
     fechado_por = excluded.fechado_por;

  return j;
end;
$fn$;

-- Rede de segurança: fecha automaticamente quem não clicou no botão.
-- Roda de madrugada e cobre o dia anterior em horário de Brasília.
create or replace function crm_fechar_pendentes()
returns int
language plpgsql
as $fn$
declare d date; n int := 0; u record;
begin
  d := (now() at time zone 'America/Sao_Paulo')::date - 1;
  for u in select nome from crm_usuarios where ativo and consultor loop
    if not exists (select 1 from crm_relatorio_diario r
                    where r.data = d and r.consultor = u.nome) then
      perform crm_fechar_dia(d, u.nome, 'automático');
      n := n + 1;
    end if;
  end loop;
  return n;
end;
$fn$;

grant execute on function crm_fechar_dia(date, text, text) to anon;