-- Unidade: taquara. Divisão da lista de rema entre a secretaria (Pedro, 13/10/2026):
-- primeira metade (ordem alfabética) Natanny, segunda metade Raphaela.
insert into public.crm_metas_config(unidade, chave, valor) values ('taquara','rema_divisao',
  '{"responsaveis":["20113c84-6871-4c6c-bf14-1b9616f942fd","992b7d2b-8493-484a-b783-ebd696ecdb4e"],"obs":"1a metade alfabetica Natanny, 2a Raphaela"}'::jsonb)
on conflict (unidade, chave) do update set valor = excluded.valor;
select public.rema_dividir(p.id) from public.crm_metas_periodo p where p.unidade = 'taquara';