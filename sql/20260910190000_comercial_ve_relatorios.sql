-- 10/09/2026 · Relatorios liberados para o papel comercial (pedido do Pedro).
-- Comercial passa a ter o mesmo acesso da coordenacao: todos os relatorios,
-- com dados da unidade inteira (rel_unidade) e o Dia a dia da equipe toda
-- (rel_meudia = total). Revoga, para o comercial, a regra "consultor so ve a
-- propria carteira nos relatorios". Excecao individual continua valendo.
-- Aplicado via execute_sql em 10/09/2026. Idempotente.
update crm_papel_permissoes
   set nivel = case modulo when 'rel_meudia' then 'total' else 'ver' end,
       atualizado_em = now()
 where papel = 'comercial'
   and modulo in ('rel_funil', 'rel_unidade', 'rel_meudia');
