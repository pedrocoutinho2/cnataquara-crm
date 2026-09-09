-- 2026-09-09 · calculadora: linha de desconto na mensagem da proposta
-- Depende do index.html a partir do commit b558ade, que criou as variaveis
-- {desconto} e {desconto_material} e os blocos [desconto] / [desconto_material].
-- Aplicado via MCP no projeto gpnwmsnayrqjcmhqrtpx.

update crm_configs set valor = $tpl$*Investimento*
{curso_parcela}
[desconto]
Com {desconto} de desconto no cartão ou boleto
[/desconto]

[material]
*Material didático*
{material_parcela}
[desconto_material]
Com {desconto_material} de desconto no cartão ou boleto
[/desconto_material]
[/material]

[matricula]
*Taxa de matrícula*
{taxa}
[/matricula]

[validade]
Mas essa proposta só vale até {validade}, ta bom?
[/validade]$tpl$, atualizado_em = now()
where chave = 'calculadora_mensagem';
