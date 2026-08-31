alter table crm_precos_niveis add column if not exists valor_2periodos_cents int;

update crm_precos_niveis set valor_2periodos_cents = v.val
from (values
  ('garden',426816),('fun',426816),('kids',474087),
  ('teen-up-1234',488874),('teen-up-56',526447),('a1-fly',526447),
  ('a2-quest',551200),('inter',526447),('pre-adv',551200),('b1',551200),
  ('adv',579044),('master',579044),('acc',579044),
  ('en-contacto-12',526449),('en-contacto-34',526449),('en-contacto-5',579044)
) as v(cod,val)
where crm_precos_niveis.ano=2026 and crm_precos_niveis.codigo=v.cod;

update crm_precos_niveis set valor_2periodos_cents = valor_periodo_cents*2
where valor_2periodos_cents is null;

alter table crm_precos_niveis alter column valor_2periodos_cents set not null;
alter table crm_precos_niveis add constraint crm_precos_niveis_v2p_pos check (valor_2periodos_cents >= 0);