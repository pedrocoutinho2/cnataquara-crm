#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Filtro de ultimo contato no quadro de Clientes B2C (10/09/2026).

Preset (hoje, ultimos 7 dias, 8 a 30 dias, mais de 30 dias, nunca) + faixa de
datas, no mesmo padrao de "Agenda" + "Proximo contato". Ultimo contato e' so'
contato EFETIVO (A52), por isso o rotulo diz "efetivo".
De quebra: o contador do botao Filtros passa a contar o filtro de Agenda, que
filtrava sem aparecer no numero.

Uso: python3 qa/patch-filtro-ultimo-contato.py index.html
"""
import io
import sys

SRC = sys.argv[1] if len(sys.argv) > 1 else 'index.html'
s = io.open(SRC, encoding='utf-8').read()
feitas = []


def rep(nome, old, new):
    global s
    c = s.count(old)
    assert c == 1, u'[%s] ancora aparece %d vezes' % (nome, c)
    s = s.replace(old, new)
    feitas.append(nome)


assert 'filters.uc' not in s, 'patch ja aplicado'

rep('estado',
    "const f={q:'',prio:null,tipo:null,resp:null,ag:null,per:null,entradaDe:null,entradaAte:null,proxDe:null,proxAte:null};",
    "const f={q:'',prio:null,tipo:null,resp:null,ag:null,per:null,entradaDe:null,entradaAte:null,proxDe:null,proxAte:null,uc:null,ucDe:null,ucAte:null};")

rep('matches',
    "    if(filters.ag==='sem'&&_d)return false;\n  }\n",
    "    if(filters.ag==='sem'&&_d)return false;\n  }\n"
    "  /* ultimo contato: so' contato efetivo (A52). Lead que nunca teve contato\n"
    "     efetivo so' aparece no preset \"nunca\"; faixa de datas o exclui. */\n"
    "  if(tab==='leads'&&(filters.uc||filters.ucDe||filters.ucAte)){\n"
    "    const _u=s.ultimo_contato?String(s.ultimo_contato).slice(0,10):'',_hu=hojeISO();\n"
    "    if(filters.uc==='nunca'&&_u)return false;\n"
    "    if(filters.uc&&filters.uc!=='nunca'&&!_u)return false;\n"
    "    if(filters.uc==='hoje'&&_u!==_hu)return false;\n"
    "    if(filters.uc==='7'&&_u<addDias(_hu,-7))return false;\n"
    "    if(filters.uc==='8a30'&&(_u<addDias(_hu,-30)||_u>addDias(_hu,-8)))return false;\n"
    "    if(filters.uc==='mais30'&&_u>=addDias(_hu,-30))return false;\n"
    "    if(filters.ucDe&&(!_u||_u<filters.ucDe))return false;\n"
    "    if(filters.ucAte&&(!_u||_u>filters.ucAte))return false;\n"
    "  }\n")

rep('contagem',
    "  if(filters.proxDe||filters.proxAte)n++;\n  return n;",
    "  if(filters.proxDe||filters.proxAte)n++;\n"
    "  if(filters.ag)n++;\n"
    "  if(tab==='leads'&&filters.uc)n++;\n"
    "  if(tab==='leads'&&(filters.ucDe||filters.ucAte))n++;\n"
    "  return n;")

rep('painel',
    "  html+=dateGroup('Próximo contato','proxDe','proxAte');\n"
    "  html+='<div class=\"factions\"><button class=\"btn\" id=\"fclear\">Limpar filtros</button></div>';",
    "  html+=dateGroup('Próximo contato','proxDe','proxAte');\n"
    "  if(tab==='leads'){\n"
    "    html+=selGroup('Último contato efetivo','uc',[['hoje','Hoje'],['7','Últimos 7 dias'],['8a30','De 8 a 30 dias atrás'],['mais30','Há mais de 30 dias'],['nunca','Nunca teve contato efetivo']]);\n"
    "    html+=dateGroup('Último contato (faixa)','ucDe','ucAte');\n"
    "  }\n"
    "  html+='<div class=\"factions\"><button class=\"btn\" id=\"fclear\">Limpar filtros</button></div>';")

io.open(SRC, 'w', encoding='utf-8').write(s)
print('ok:', ', '.join(feitas))
