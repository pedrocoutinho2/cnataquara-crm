#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Calendario: arrastar evento para outro dia remarca o evento.
Mesma mecanica do kanban de leads (dragstart/dragover/drop), mesma regra de
permissao do clique (podeEditar('calendario')), e a sincronizacao com o Google
reaproveita agdSyncEvento, que ja existe e ja trata falha sem travar o CRM."""
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


# ---------------------------------------------------------------- CSS
rep('cal-css',
    ".agev.op,.agevb.op{opacity:.42}",
    "/* arrastar evento para outro dia */\n"
    ".agev[draggable=true],.agevb[draggable=true]{cursor:grab}\n"
    ".agev.dragging,.agevb.dragging{opacity:.4;cursor:grabbing}\n"
    ".agcell.drop,.agcol.drop{outline:2px dashed var(--blue);outline-offset:-2px;background:var(--pastelBlue)}\n"
    ".agev.op,.agevb.op{opacity:.42}")

# ------------------------------------------------- eventos ficam arrastaveis
rep('cal-drag-mes',
    """      h+='<div class="agev'+(meu?'':' op')+'" data-ev="'+ev.id+'" style="border-left-color:'+esc(c?c.cor:'#5A5A5A')+'" title="'+esc(ev.titulo+(ev.responsavel?' · '+ev.responsavel:''))+'">'+""",
    """      h+='<div class="agev'+(meu?'':' op')+'" data-ev="'+ev.id+'" data-de="'+esc(iso)+'"'+(adm?' draggable="true"':'')+' style="border-left-color:'+esc(c?c.cor:'#5A5A5A')+'" title="'+esc(ev.titulo+(ev.responsavel?' · '+ev.responsavel:'')+(adm?' · arraste para outro dia para remarcar':''))+'">'+""")

rep('cal-drag-col',
    """      h+='<div class="agevb'+(meu?'':' op')+'" data-ev="'+ev.id+'" style="border-left-color:'+esc(c?c.cor:'#5A5A5A')+'">'+""",
    """      h+='<div class="agevb'+(meu?'':' op')+'" data-ev="'+ev.id+'" data-de="'+esc(iso)+'"'+(adm?' draggable="true"':'')+' style="border-left-color:'+esc(c?c.cor:'#5A5A5A')+'"'+(adm?' title="Arraste para outro dia para remarcar"':'')+'>'+""")

# ------------------------------------------------- listeners
rep('cal-listeners',
    """  if(adm)document.querySelectorAll('.agcell.clik,.agcol.clik').forEach(function(el){
    el.onclick=function(){agdOpenEvento({data:el.dataset.d});};
  });
}""",
    """  if(adm)document.querySelectorAll('.agcell.clik,.agcol.clik').forEach(function(el){
    el.onclick=function(){agdOpenEvento({data:el.dataset.d});};
  });
  if(adm)agdLigarArrasto();
}

/* Arrastar evento de um dia para outro. Espelha o kanban de leads: o card
   guarda a data de origem em data-de, a celula do dia e' o alvo, e nada e'
   gravado quando a data nao muda. Quem nao pode editar o calendario nao
   recebe draggable, entao nao ha caminho de arrasto sem permissao. */
var AGDRAG=null;
function agdLigarArrasto(){
  document.querySelectorAll('.agev[draggable=true],.agevb[draggable=true]').forEach(function(el){
    el.addEventListener('dragstart',function(e){
      AGDRAG={id:el.dataset.ev,de:el.dataset.de};
      el.classList.add('dragging');
      try{e.dataTransfer.setData('text/plain',el.dataset.ev);e.dataTransfer.effectAllowed='move';}catch(_){}
    });
    el.addEventListener('dragend',function(){el.classList.remove('dragging');AGDRAG=null;});
  });
  document.querySelectorAll('.agcell[data-d],.agcol[data-d]').forEach(function(col){
    col.addEventListener('dragover',function(e){
      if(!AGDRAG)return;
      e.preventDefault();
      col.classList.add('drop');
    });
    col.addEventListener('dragleave',function(){col.classList.remove('drop');});
    col.addEventListener('drop',function(e){
      e.preventDefault();
      col.classList.remove('drop');
      if(!AGDRAG)return;
      var alvo=col.dataset.d,id=AGDRAG.id,de=AGDRAG.de;
      AGDRAG=null;
      if(!alvo||alvo===de)return;
      agdRemarcar(id,alvo);
    });
  });
}

async function agdRemarcar(id,novaData){
  if(!podeEditar('calendario'))return;
  var ev=AGD.eventos.find(function(x){return x.id===id;});
  if(!ev)return;
  var antes=ev.data;
  /* pinta na hora e desfaz se o banco recusar: arrastar tem que parecer imediato */
  ev.data=novaData;
  renderCalendario();
  var salvo=null;
  try{
    var r=await api('/crm_agenda_eventos?id=eq.'+id,{method:'PATCH',
      body:JSON.stringify({data:novaData,atualizado_em:new Date().toISOString(),gcal_sync:'pendente'})});
    salvo=r&&r[0];
    if(salvo)Object.keys(salvo).forEach(function(k){ev[k]=salvo[k];});
  }catch(e){
    ev.data=antes;
    renderCalendario();
    toast('Não foi possível remarcar o evento. Nada mudou.');
    return;
  }
  renderCalendario();
  toast('\\u201c'+ev.titulo+'\\u201d remarcado para '+brDate(novaData)+'.');
  loadAlerts();
  /* regra 14: falha de sincronizacao com o Google nunca desfaz o que ja foi
     gravado no CRM. agdSyncEvento avisa e marca gcal_sync='erro' por dentro. */
  if(salvo)agdSyncEvento(salvo,'upsert');
}""")

io.open(SRC, 'w', encoding='utf-8').write(s)
print(u'%d edicoes aplicadas: %s' % (len(edits), ', '.join(edits)))
