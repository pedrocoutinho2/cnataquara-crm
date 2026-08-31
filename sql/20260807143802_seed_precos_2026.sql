insert into crm_precos_materiais (ano, codigo, nome, valor_cents, ordem) values
(2026,'garden','Garden',52990,10),
(2026,'fun','Fun',52990,20),
(2026,'kids','Kids',52990,30),
(2026,'teen-up','Teen Up',52990,40),
(2026,'fly-essentials','Fly (Essentials)',52990,50),
(2026,'quest','Quest',59990,60),
(2026,'progression','Progression',59990,70),
(2026,'expansion','Expansion',59990,80),
(2026,'gold','Gold',59990,90),
(2026,'platinum','Platinum',59990,100),
(2026,'en-contacto-12','En Contacto 1/2',52990,110),
(2026,'en-contacto-34','En Contacto 3/4',59990,120),
(2026,'en-contacto-5','En Contacto 5',59990,130),
(2026,'21st-century','21st Century',20000,140)
on conflict (ano, codigo) do update set
  nome = excluded.nome, valor_cents = excluded.valor_cents, ordem = excluded.ordem;

insert into crm_precos_niveis (ano, idioma, codigo, nome, valor_periodo_cents, material_codigo, ordem) values
(2026,'ingles','garden','Garden (Pre-School)',213408,'garden',10),
(2026,'ingles','fun','Fun (Young Kids)',213408,'fun',20),
(2026,'ingles','kids','Kids',237044,'kids',30),
(2026,'ingles','teen-up-1234','Teen Up 1/2/3/4',244437,'teen-up',40),
(2026,'ingles','teen-up-56','Teen Up 5/6',263223,'teen-up',50),
(2026,'ingles','a1-fly','A1/Fly',263223,'fly-essentials',60),
(2026,'ingles','a2-quest','A2/Quest',275600,'quest',70),
(2026,'ingles','inter','Inter',263223,'progression',80),
(2026,'ingles','pre-adv','Pre-Adv',275600,'expansion',90),
(2026,'ingles','b1','B1',275600,'expansion',100),
(2026,'ingles','adv','Adv',289522,'gold',110),
(2026,'ingles','master','Master',289522,'platinum',120),
(2026,'ingles','acc','Acc',289522,null,130),
(2026,'espanhol','en-contacto-12','En Contacto 1/2',263224,'en-contacto-12',140),
(2026,'espanhol','en-contacto-34','En Contacto 3/4',263224,'en-contacto-34',150),
(2026,'espanhol','en-contacto-5','En Contacto 5',289522,'en-contacto-5',160)
on conflict (ano, codigo) do update set
  nome = excluded.nome, valor_periodo_cents = excluded.valor_periodo_cents,
  material_codigo = excluded.material_codigo, idioma = excluded.idioma, ordem = excluded.ordem;

insert into crm_precos_certificacoes (ano, exame, modalidade, valor_cents, descricao, ordem) values
(2026,'LinguaSkill','4 skills',94000,'Reading, Listening, Writing, Speaking',10),
(2026,'LinguaSkill','2 skills',49000,'Reading, Listening',20);