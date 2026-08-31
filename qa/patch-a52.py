#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""A52 — "Ultimo contato" passa a significar contato de verdade.
A tentativa sem sucesso alimenta ultima_tentativa e tentativas_sem_retorno,
mantidos pelo trigger crm_interacao_atualiza_contato_tg no banco."""
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
rep('css-agt-tent',
    ".agt.pend{background:var(--warnBg);color:var(--warn)}",
    ".agt.pend{background:var(--warnBg);color:var(--warn)}\n"
    "/* A52: tentativas sem retorno acumuladas desde o ultimo contato efetivo */\n"
    ".agt.tent{background:var(--surface);color:var(--gray);border:1px solid var(--line)}\n"
    ".agt.tent.alta{background:var(--pastelRed);color:var(--redDark);border-color:var(--pastelRed)}")

# ------------------------------------------------- o banco passa a mandar
rep('a52-aftercontato',
    """async function afterContato(id,prox,proxh,pcanal){
  const cfg=CFG[tab];
  const nf=NF(cfg);
  const hf=nf+'_hora';
  const hoje=hojeISO();
  const patch={updated_at:new Date().toISOString()};
  patch[nf]=prox||null;
  patch[hf]=prox?(proxh||null):null;
  patch.proximo_canal=prox?(pcanal||null):null;
  if(tab==='leads')patch.ultimo_contato=hoje;
  try{
    await api('/'+cfg.table+'?id=eq.'+id,{method:'PATCH',body:JSON.stringify(patch)});
    const s=(DATA[tab]||[]).find(function(x){return x.id===id;});
    if(s){s[nf]=prox||null;s[hf]=patch[hf];s.proximo_canal=patch.proximo_canal;if(tab==='leads')s.ultimo_contato=hoje;syncMsub(s);}
    /* A21: o campo continuava com a classe dvazio (cinza de campo em branco)
       mesmo depois de receber a data de hoje */
    if(tab==='leads'){const i2=document.querySelector('#form [data-k=ultimo_contato]');if(i2){i2.value=hoje;i2.classList.remove('dvazio');}syncPend();}
    render();
  }catch(e){}
  loadAlerts();
}""",
    """/* A52: o front NAO escreve mais `ultimo_contato`. Quem escreve e' o trigger
   `crm_interacao_atualiza_contato_tg`, no INSERT da interacao:
     - contato EFETIVO  -> ultimo_contato = data, tentativas_sem_retorno = 0
     - tentativa SEM SUCESSO -> ultima_tentativa = data, tentativas_sem_retorno += 1
   Como o trigger ja rodou quando este PATCH sai, a resposta traz os tres campos
   com o valor final e a ficha reflete o banco em vez de supor (regra 4). */
async function afterContato(id,prox,proxh,pcanal){
  const cfg=CFG[tab];
  const nf=NF(cfg);
  const hf=nf+'_hora';
  const patch={updated_at:new Date().toISOString()};
  patch[nf]=prox||null;
  patch[hf]=prox?(proxh||null):null;
  patch.proximo_canal=prox?(pcanal||null):null;
  try{
    const res=await api('/'+cfg.table+'?id=eq.'+id,{method:'PATCH',body:JSON.stringify(patch)});
    const s=(DATA[tab]||[]).find(function(x){return x.id===id;});
    if(s){
      if(res&&res[0])Object.keys(res[0]).forEach(function(k){s[k]=res[0][k];});
      else{s[nf]=prox||null;s[hf]=patch[hf];s.proximo_canal=patch.proximo_canal;}
      if(editing===id&&tab==='leads')refletirCarimbo(s);
      else syncMsub(s);
    }
    render();
  }catch(e){}
  loadAlerts();
}""")

# ------------------------------------------------- refletirCarimbo cobre os novos campos
rep('a52-refletircarimbo',
    """  ['ultimo_contato','data_fechamento','data_inicio_aulas'].forEach(function(k){
    const el=document.querySelector('#form [data-k='+k+']');
    if(el)el.value=row[k]==null?'':String(row[k]);
  });
  marcaDatasVazias($('form'));
  syncMsub(row);
  syncAgbar();
  syncPend();""",
    """  ['ultimo_contato','data_fechamento','data_inicio_aulas'].forEach(function(k){
    const el=document.querySelector('#form [data-k='+k+']');
    if(el)el.value=row[k]==null?'':String(row[k]);
  });
  marcaDatasVazias($('form'));
  syncMsub(row);
  syncAgbar();
  syncPend();""")

# ------------------------------------------------- msub mostra as tentativas
rep('a52-syncmsub',
    """  if(s){
    const pa=agLabel(s[nf],s[nf+'_hora']);
    if(pa)txt+=' · \\u23F0 Próximo contato: '+pa+(s.proximo_canal?' · '+canalNome(s.proximo_canal):'');
  }""",
    """  if(s){
    const pa=agLabel(s[nf],s[nf+'_hora']);
    if(pa)txt+=' · \\u23F0 Próximo contato: '+pa+(s.proximo_canal?' · '+canalNome(s.proximo_canal):'');
    /* A52: quantas tentativas sem retorno desde o ultimo contato efetivo */
    const t=tentativasLead(s);
    if(t)txt+=' · \\u21bb '+t+' tentativa'+(t>1?'s':'')+' sem retorno'
              +(s.ultima_tentativa?' (a última em '+brDate(s.ultima_tentativa)+')':'');
  }""")

# ------------------------------------------------- helper + etiqueta no card
rep('a52-helper',
    "function pendenciasLead(lead){",
    """/* A52: tentativas sem sucesso acumuladas desde o ultimo contato efetivo.
   Mantido pelo banco; aqui so' se le. Serve para responder "quantas tentativas
   sao necessarias ate o lead dar retorno" sem depender de relatorio. */
function tentativasLead(lead){
  if(!lead)return 0;
  const n=parseInt(lead.tentativas_sem_retorno,10);
  return isNaN(n)||n<0?0:n;
}

function pendenciasLead(lead){""")

rep('a52-card-tag',
    """    var _pend=pendenciasLead(s);
    if(_pv&&_pv.txt==='Definir in\\u00edcio das aulas')_pend=_pend.filter(function(x){return x!=='in\\u00edcio das aulas';});
    if(_pend.length)pdTag='<span class="agt pend" title="Salvar grava assim mesmo. Complete quando tiver o dado.">&#9888; falta '+esc(_pend.join(', '))+'</span>';""",
    """    var _pend=pendenciasLead(s);
    if(_pv&&_pv.txt==='Definir in\\u00edcio das aulas')_pend=_pend.filter(function(x){return x!=='in\\u00edcio das aulas';});
    if(_pend.length)pdTag='<span class="agt pend" title="Salvar grava assim mesmo. Complete quando tiver o dado.">&#9888; falta '+esc(_pend.join(', '))+'</span>';
    /* A52: tentativas sem retorno. A partir de 3 o card avisa em vermelho \\u2014
       e o sinal de que a cadencia nao esta funcionando nesse lead. */
    var _t=tentativasLead(s);
    if(_t)pdTag+='<span class="agt tent'+(_t>=3?' alta':'')+'" title="Tentativas sem sucesso desde o \\u00faltimo contato efetivo'
              +(s.ultima_tentativa?'. \\u00daltima em '+brDate(s.ultima_tentativa):'')+'">&#8635; '+_t+'x sem retorno</span>';""")

io.open(SRC, 'w', encoding='utf-8').write(s)
print(u'%d edicoes aplicadas: %s' % (len(edits), ', '.join(edits)))
