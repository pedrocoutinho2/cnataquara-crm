#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Onda 4 - A15 e A18.

A15: "Efetividade" media canal, nao capacidade. Tres defeitos somados:
  1. `nota` contava como contato E como contato efetivo. Sao 55 anotacoes
     internas na base, todas com efetivo=true, inflando os dois lados.
  2. `if(i.efetivo!==false)` fazia nulo e indefinido virarem efetivo.
  3. A taxa agregada por pessoa mistura canais com taxa de resposta muito
     diferente: WhatsApp responde 85,6% e ligacao 5,8% na base inteira.
     Marlon 113 de 119 tentativas por WhatsApp; Camila 116 de 156 por ligacao.
     O numero virava um julgamento sobre a pessoa quando media o canal.

A18: o filtro de Responsavel do funil so lista usuario ATIVO, entao lead que
ficou com quem saiu nao e' filtravel - some da tela em vez de aparecer como
problema. Hoje sao 34 leads (Sabrina 24, Joao 7, Sergio 3), 2 deles ativos."""
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


# ================================================================ A15 · helper único
rep('a15-helper',
    "function canalNome(c){return CANAIS[c]||'';}",
    """function canalNome(c){return CANAIS[c]||'';}

/* ===== A15 - fonte unica das metricas de contato =====
   Antes cada relatorio contava do seu jeito, e os tres jeitos estavam errados
   do mesmo modo. As regras, agora num lugar so:

   1. `nota` NAO e' contato. E' anotacao interna, entao nao entra em tentativa
      nem em contato efetivo.
   2. Efetivo e' `=== true`. O `!==false` antigo transformava nulo em efetivo.
   3. A taxa de resposta e' guardada POR CANAL e nunca deve ser exibida como um
      numero unico por pessoa: na base da unidade o WhatsApp responde ~86% e a
      ligacao ~6%, entao a taxa agregada mede o canal escolhido, nao a
      capacidade de quem ligou. */
var TIPO_NAO_CONTATO={nota:1};
function ehContato(i){return !!i&&!TIPO_NAO_CONTATO[i.tipo||''];}
function statsContato(lista){
  var out={n:0,ef:0,notas:0,porCanal:{}};
  (lista||[]).forEach(function(i){
    if(!ehContato(i)){out.notas++;return;}
    var k=i.tipo||'—';
    var c=out.porCanal[k]||(out.porCanal[k]={n:0,ef:0});
    out.n++;c.n++;
    if(i.efetivo===true){out.ef++;c.ef++;}
  });
  return out;
}
/* "WhatsApp 50% · Ligação 6%" - o formato que impede a leitura injusta */
function respostaCanais(st,max){
  var ks=Object.keys(st.porCanal).sort(function(a,b){return st.porCanal[b].n-st.porCanal[a].n;});
  if(!ks.length)return '—';
  return ks.slice(0,max||3).map(function(k){
    var c=st.porCanal[k];
    return (canalNome(k)||k)+' '+pct(c.ef,c.n)+' <i>('+c.n+')</i>';
  }).join(' · ');
}
var NOTA_A15='A <b>resposta</b> é quanto do que se tenta volta, e depende muito mais do canal '
  +'do que de quem tentou: na base da unidade o WhatsApp responde perto de 86% e a ligação perto de 6%. '
  +'Por isso ela aparece <b>por canal</b>, e nunca como uma nota única da pessoa. '
  +'Anotação interna (“nota”) não conta como tentativa. '
  +'Leads e matrículas contam quem está como responsável pelo lead.';""")

# ================================================================ A15 · ranking do funil
rep('a15-funil-calc',
    """  interB2C.forEach(function(i){
    const g=rkGet(i.autor||'—');
    g.ct++;if(i.efetivo!==false)g.ef++;
  });""",
    """  /* A15: nota nao e' contato, e efetivo e' === true. Guarda tambem o canal. */
  const rkStats={};
  const rkPorAutor={};
  interB2C.forEach(function(i){
    const k=i.autor||'—';
    (rkPorAutor[k]=rkPorAutor[k]||[]).push(i);
  });
  Object.keys(rkPorAutor).forEach(function(k){
    const st=statsContato(rkPorAutor[k]);
    rkStats[k]=st;
    const g=rkGet(k);
    g.ct=st.n;g.ef=st.ef;
  });""")

rep('a15-funil-tabela',
    """    '<tr class="hd"><th>Consultor</th><th class="num">Leads</th><th class="num">Contatos</th><th class="num">Efetividade</th><th class="num">Matrículas</th><th class="num">Conversão</th></tr>'+
    rkKeys.map(function(k){
      const g=rk[k];
      return '<tr><td>'+esc(k)+(g.p?'<span class="sub">'+g.p+' perdidos</span>':'')+'</td>'+
        '<td class="num" data-l="Leads">'+g.n+'</td><td class="num" data-l="Contatos">'+g.ct+'</td>'+
        '<td class="num" data-l="Efetividade">'+(g.ct?pct(g.ef,g.ct):'—')+'</td>'+
        '<td class="num'+(g.f?' hl':'')+'" data-l="Matrículas">'+g.f+'</td>'+
        '<td class="num" data-l="Conversão">'+pct(g.f,g.n)+'</td></tr>';
    }).join('')+'</table></div>'+
    '<div class="rnote">Contatos e efetividade contam as interações registradas por cada um no período. Leads e matrículas contam quem está como responsável.</div></div>':'';""",
    """    '<tr class="hd"><th>Consultor</th><th class="num">Leads</th><th class="num">Tentativas</th><th class="num">Falaram</th><th>Resposta por canal</th><th class="num">Matrículas</th><th class="num">Conversão</th></tr>'+
    rkKeys.map(function(k){
      const g=rk[k];
      const st=rkStats[k]||{n:0,ef:0,porCanal:{}};
      return '<tr><td>'+esc(k)+(g.p?'<span class="sub">'+g.p+' perdidos</span>':'')+'</td>'+
        '<td class="num" data-l="Leads">'+g.n+'</td>'+
        '<td class="num" data-l="Tentativas">'+g.ct+'</td>'+
        '<td class="num" data-l="Falaram">'+g.ef+'</td>'+
        '<td data-l="Resposta por canal">'+(g.ct?respostaCanais(st):'—')+'</td>'+
        '<td class="num'+(g.f?' hl':'')+'" data-l="Matrículas">'+g.f+'</td>'+
        '<td class="num" data-l="Conversão">'+pct(g.f,g.n)+'</td></tr>';
    }).join('')+'</table></div>'+
    '<div class="rnote">'+NOTA_A15+'</div></div>':'';""")

# ================================================================ A15 · relatório de equipe
rep('a15-equipe-calc',
    "  inter.forEach(function(i){var g=get(i.autor||'—');g.ct++;if(i.efetivo!==false)g.ef++;});",
    """  /* A15: mesma fonte unica do funil - nota fora, efetivo === true, canal guardado */
  var eqStats={},eqPorAutor={};
  inter.forEach(function(i){var k=i.autor||'—';(eqPorAutor[k]=eqPorAutor[k]||[]).push(i);});
  Object.keys(eqPorAutor).forEach(function(k){
    var st=statsContato(eqPorAutor[k]);
    eqStats[k]=st;
    var g=get(k);g.ct=st.n;g.ef=st.ef;
  });
  var eqUnidade=statsContato(inter);""")

rep('a15-equipe-tabela',
    """    '<tr class="hd"><th>Consultor</th><th class="num">Leads</th><th class="num">Contatos</th><th class="num">Efetividade</th>'+
    '<th class="num">Matrículas</th><th class="num">Conversão</th><th class="num">Tempo até matrícula</th></tr>'+
    ks.map(function(k){
      var g=rk[k];
      var tm=g.dias.length?Math.round(g.dias.reduce(function(a,b){return a+b;},0)/g.dias.length)+'d':'—';
      return '<tr><td>'+esc(k)+(g.p?'<span class="sub">'+g.p+' perdidos'+(g.b2b?' · '+g.b2b+' contatos B2B':'')+'</span>':(g.b2b?'<span class="sub">'+g.b2b+' contatos B2B</span>':''))+'</td>'+
        '<td class="num" data-l="Leads">'+g.n+'</td>'+
        '<td class="num" data-l="Contatos">'+g.ct+'</td>'+
        '<td class="num" data-l="Efetividade">'+(g.ct?pct(g.ef,g.ct):'—')+'</td>'+
        '<td class="num'+(g.f?' hl':'')+'" data-l="Matrículas">'+g.f+'</td>'+
        '<td class="num" data-l="Conversão">'+pct(g.f,g.n)+'</td>'+
        '<td class="num" data-l="Tempo até matrícula">'+tm+'</td></tr>';
    }).join('')+'</table></div>'+
    '<div class="rnote">Leads e matrículas contam quem está como responsável pelo lead. Contatos e efetividade contam as interações registradas por cada um no período.</div></div>';""",
    """    '<tr class="hd"><th>Consultor</th><th class="num">Leads</th><th class="num">Tentativas</th><th class="num">Falaram</th>'+
    '<th>Resposta por canal</th><th class="num">Matrículas</th><th class="num">Conversão</th><th class="num">Tempo até matrícula</th></tr>'+
    ks.map(function(k){
      var g=rk[k];
      var st=eqStats[k]||{n:0,ef:0,porCanal:{}};
      var tm=g.dias.length?Math.round(g.dias.reduce(function(a,b){return a+b;},0)/g.dias.length)+'d':'—';
      return '<tr><td>'+esc(k)+(g.p?'<span class="sub">'+g.p+' perdidos'+(g.b2b?' · '+g.b2b+' contatos B2B':'')+'</span>':(g.b2b?'<span class="sub">'+g.b2b+' contatos B2B</span>':''))+'</td>'+
        '<td class="num" data-l="Leads">'+g.n+'</td>'+
        '<td class="num" data-l="Tentativas">'+g.ct+'</td>'+
        '<td class="num" data-l="Falaram">'+g.ef+'</td>'+
        '<td data-l="Resposta por canal">'+(g.ct?respostaCanais(st):'—')+'</td>'+
        '<td class="num'+(g.f?' hl':'')+'" data-l="Matrículas">'+g.f+'</td>'+
        '<td class="num" data-l="Conversão">'+pct(g.f,g.n)+'</td>'+
        '<td class="num" data-l="Tempo até matrícula">'+tm+'</td></tr>';
    }).join('')+'</table></div>'+
    '<div class="rnote">'+NOTA_A15+'</div></div>';""")

rep('a15-equipe-card',
    """  var cEf='<div class="rcard"><h3>Contatos e efetividade</h3>'+
    hbars(ks.filter(function(k){return rk[k].ct;}).map(function(k,i){
      return {label:k,value:rk[k].ct,color:corIdx(i+2),right:rk[k].ct+' · '+pct(rk[k].ef,rk[k].ct)+' efetivo',
        tip:rk[k].ct+' contatos · '+rk[k].ef+' efetivos'};
    }))+'<div class="rnote">Média da equipe no período: '+pct(totE,totC)+' de contatos efetivos.</div></div>';""",
    """  /* A15: o grafico passa a comparar VOLUME DE TENTATIVA, que e' o que a pessoa
     controla. A taxa fica ao lado como leitura, com o canal explicito. */
  var canaisUn=Object.keys(eqUnidade.porCanal).sort(function(a,b){return eqUnidade.porCanal[b].n-eqUnidade.porCanal[a].n;});
  var baseUn=canaisUn.map(function(k){
    var c=eqUnidade.porCanal[k];
    return (canalNome(k)||k)+' '+pct(c.ef,c.n);
  }).join(' · ');
  var cEf='<div class="rcard"><h3>Tentativas de contato</h3>'+
    hbars(ks.filter(function(k){return rk[k].ct;}).map(function(k,i){
      var st=eqStats[k]||{porCanal:{}};
      var mix=Object.keys(st.porCanal).sort(function(a,b){return st.porCanal[b].n-st.porCanal[a].n;})
        .map(function(c){return (canalNome(c)||c)+' '+st.porCanal[c].n;}).join(' · ');
      return {label:k,value:rk[k].ct,color:corIdx(i+2),right:rk[k].ct+' · '+rk[k].ef+' falaram',
        tip:rk[k].ct+' tentativas · '+rk[k].ef+' conversas\\n'+mix};
    }))+'<div class="rnote">Volume de tentativa é o que a pessoa controla; a resposta depende do canal. '
    +'Taxa da unidade no período: '+esc(baseUn||'sem contato registrado')+'.</div></div>';""")

rep('a15-equipe-kpi',
    """      '<div class="rkpi"><b>'+totC+'</b><span>Contatos registrados</span></div>'+
      '<div class="rkpi"><b>'+pct(totE,totC)+'</b><span>Efetividade média</span></div>'+""",
    """      '<div class="rkpi"><b>'+totC+'</b><span>Tentativas de contato</span></div>'+
      '<div class="rkpi"><b>'+totE+'</b><span>Conversas de fato</span></div>'+""")

rep('a15-equipe-csv',
    """    baixaCSV('cna-equipe-'+hojeISO(),['Consultor','Leads','Contatos','Efetivos','Matrículas','Perdidos','Conversão'],
      ks.map(function(k){return [k,rk[k].n,rk[k].ct,rk[k].ef,rk[k].f,rk[k].p,pct(rk[k].f,rk[k].n)];}));""",
    """    baixaCSV('cna-equipe-'+hojeISO(),['Consultor','Leads','Tentativas','Falaram','Resposta por canal','Matrículas','Perdidos','Conversão'],
      ks.map(function(k){
        var st=eqStats[k]||{porCanal:{}};
        var mix=Object.keys(st.porCanal).sort(function(a,b){return st.porCanal[b].n-st.porCanal[a].n;})
          .map(function(c){return (canalNome(c)||c)+' '+pct(st.porCanal[c].ef,st.porCanal[c].n)+' ('+st.porCanal[c].n+')';}).join(' | ');
        return [k,rk[k].n,rk[k].ct,rk[k].ef,mix,rk[k].f,rk[k].p,pct(rk[k].f,rk[k].n)];
      }));""")

# ================================================================ A18 · donos fora do cadastro
rep('a18-filtro',
    "  html+=selGroup('Responsável','resp',RESP.map(function(r){return [r,r];}));",
    """  /* A18: o filtro listava so' usuario ativo, entao lead que ficou com quem saiu
     nao era filtravel e sumia da tela em vez de aparecer como problema. Agora a
     lista sai da BASE, e quem nao esta no cadastro ativo vem marcado. */
  html+=selGroup('Responsável','resp',responsaveisDaBase());""")

rep('a18-helper',
    "function buildChips(){\n  const cfg=CFG[tab];\n  var html='';",
    """/* A18: donos que existem NOS DADOS, nao so' no cadastro de usuarios ativos.
   Quem nao esta mais na equipe entra no fim da lista, marcado, para o lead
   orfao poder ser encontrado e reatribuido. */
function responsaveisDaBase(){
  const cfg=CFG[tab];
  const naBase={};
  (DATA[tab]||[]).forEach(function(s){
    const r=(s.responsavel||'').trim();
    if(r)naBase[r]=(naBase[r]||0)+1;
  });
  const ativos=RESP.slice();
  const fora=Object.keys(naBase).filter(function(r){return ativos.indexOf(r)<0;})
    .sort(function(a,b){return naBase[b]-naBase[a];});
  return ativos.map(function(r){return [r,r+(naBase[r]?' ('+naBase[r]+')':'')];})
    .concat(fora.map(function(r){return [r,r+' — fora da equipe ('+naBase[r]+')'];}));
}

function buildChips(){
  const cfg=CFG[tab];
  var html='';""")

io.open(SRC, 'w', encoding='utf-8').write(s)
print(u'%d edicoes aplicadas: %s' % (len(edits), ', '.join(edits)))
