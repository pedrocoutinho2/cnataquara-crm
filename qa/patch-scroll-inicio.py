#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""A tela de Inicio (e mais cinco) nao rolava com a roda do mouse.

Causa: o handler de `wheel` do #board converte rolagem vertical em horizontal,
que e' o comportamento certo do kanban. A guarda era uma LISTA DE EXCECOES com
6 abas, e nasceu incompleta: das 15 abas do CRM, so 3 sao kanban, e as outras
9 que nao estavam na lista tinham a rolagem vertical engolida por
`e.preventDefault()`. Inicio, Conversas, Calendario, Atas, Demandas e Acoes.

Correcao: inverter a guarda. Em vez de listar quem esta de fora, listar quem
e' kanban de verdade - lista que nao cresce quando alguem cria uma aba nova."""
import io

SRC = '/tmp/crm/index.html'
s = io.open(SRC, encoding='utf-8').read()
edits = []


def rep(nome, old, new, n=1):
    global s
    c = s.count(old)
    assert c == n, u'[%s] ancora aparece %d vezes, esperado %d' % (nome, c, n)
    s = s.replace(old, new)
    edits.append(nome)


rep('kanban-const',
    "var NAVMOD={inicio:'inicio',leads:'leads',escolas:'escolas',empresas:'empresas',acoes:'acoes',conversas:'conversas',",
    """/* As UNICAS abas em quadro (colunas que rolam na horizontal). Todo o resto e'
   tela comum e rola na vertical. Aba nova entra aqui SO se for kanban - e' o
   que impede a rolagem de quebrar de novo a cada tela nova. */
var KANBAN={leads:1,escolas:1,empresas:1};
function telaKanban(t){return !!KANBAN[t||tab];}

var NAVMOD={inicio:'inicio',leads:'leads',escolas:'escolas',empresas:'empresas',acoes:'acoes',conversas:'conversas',""")

rep('wheel-guarda',
    """$('board').addEventListener('wheel',function(e){
  if(tab==='relatorios'||tab==='equipe'||tab==='mural'||tab==='faq'||tab==='calc'||tab==='turmas')return;
  if(e.target.closest('.cards'))return;""",
    """/* Roda do mouse vira rolagem horizontal SOMENTE no quadro. Fora dele, deixa o
   navegador rolar a pagina: era isso que travava a tela de Inicio. */
$('board').addEventListener('wheel',function(e){
  if(!telaKanban())return;
  if(e.target.closest('.cards'))return;""")

rep('settab-outro',
    "  const outro=(t==='inicio'||t==='relatorios'||t==='equipe'||t==='mural'||t==='faq'||t==='calc'||t==='turmas'||t==='conversas'||t==='calendario'||t==='atas'||t==='demandas'||t==='acoes');",
    "  /* mesma fonte da guarda da roda do mouse: ou e' quadro, ou e' tela comum */\n  const outro=!telaKanban(t);")

io.open(SRC, 'w', encoding='utf-8').write(s)
print(u'%d edicoes aplicadas: %s' % (len(edits), ', '.join(edits)))
