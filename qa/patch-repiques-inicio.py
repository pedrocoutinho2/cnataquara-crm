import sys
p=sys.argv[1]; s=open(p,encoding='utf-8').read()
def rep(old,new,n=1):
    global s
    assert s.count(old)==n,(s.count(old),old[:60])
    s=s.replace(old,new)

# A. janela de 7 dias e campos extras so para B2C
rep("  leads:{table:'crm_leads',nf:'proximo_atendimento',sf:'etapa',rot:'Cliente B2C',tel:false},",
    "  leads:{table:'crm_leads',nf:'proximo_atendimento',sf:'etapa',rot:'Cliente B2C',tel:false,janela:7,extra:'curso,tentativas_sem_retorno,'},")
rep("+(ac.tel?'telefone,':'')+'responsavel,proximo_canal,'",
    "+(ac.tel?'telefone,':'')+(ac.extra||'')+'responsavel,proximo_canal,'")
rep("'&'+ac.nf+'=lte.'+limite", "'&'+ac.nf+'=lte.'+(ac.janela?addDias(hoje,ac.janela):limite)")
rep("etapa:st?st.n:'',canal:r.proximo_canal||''});",
    "etapa:st?st.n:'',canal:r.proximo_canal||'',curso:r.curso||'',tent:r.tentativas_sem_retorno||0});")

# B. bucket novo "adiante" (D+4 a D+7): so o Inicio usa; badge e modal de alertas nao mudam
rep("let ALERTS={atrasados:[],agora:[],hoje:[],proximos:[],posvenda:[],total:0};",
    "let ALERTS={atrasados:[],agora:[],hoje:[],proximos:[],posvenda:[],adiante:[],total:0};")
rep("  const at=[],ag=[],hj=[],px=[],pv=[];", "  const at=[],ag=[],hj=[],px=[],pv=[],ad=[];")
rep("    else if(it.pv&&it.data>addDias(hoje,3))pv.push(it);   /* pos-venda distante tem lista propria */",
    "    else if(it.data>addDias(hoje,3)){if(it.pv)pv.push(it);else ad.push(it);}   /* pos-venda distante tem lista propria; B2C de D+4 a D+7 so aparece no Inicio */")
rep("  at.sort(ord);ag.sort(ord);hj.sort(ord);px.sort(ord);pv.sort(ord);",
    "  at.sort(ord);ag.sort(ord);hj.sort(ord);px.sort(ord);pv.sort(ord);ad.sort(ord);")
rep("  ALERTS={atrasados:at,agora:ag,hoje:hj,proximos:px,posvenda:pv,total:at.length+ag.length};",
    "  ALERTS={atrasados:at,agora:ag,hoje:hj,proximos:px,posvenda:pv,adiante:ad,total:at.length+ag.length};")
rep("ALERTS.proximos.length,ALERTS.posvenda.length].join('/')",
    "ALERTS.proximos.length,ALERTS.posvenda.length,(ALERTS.adiante||[]).length].join('/')",2)

# C. funcoes do bloco
FUNCS=r"""/* ===== Repiques B2C no Inicio: atrasados em faixas, hoje e proximos 7 dias (05/11/2026) ===== */
var REPTAB='hoje';      /* coluna visivel no celular */
var REPABERTO={};       /* faixa aberta/fechada sobrevive ao redesenho de 60s */
function diasEntre(a,b){
  const p=String(a).split('-'),q=String(b).split('-');
  return Math.round((Date.UTC(+q[0],+q[1]-1,+q[2])-Date.UTC(+p[0],+p[1]-1,+p[2]))/86400000);
}
function repRow(it,hoje,modo){
  const wa=waLink(it.whatsapp);
  var quando,late=false,tit='';
  if(modo==='atr'){const d=diasEntre(it.data,hoje);quando=d+'d';late=true;tit=d+' dia'+(d>1?'s':'')+' de atraso';}
  else{quando=it.hora||'--:--';late=modo==='hoje'&&(it.hora||'09:00')<=agoraHM();}
  const sub=[it.etapa,it.curso,it.canal?canalNome(it.canal):'',
    modo==='atr'?'era '+brDate(it.data).slice(0,5):'',
    it.tent?it.tent+' sem retorno':''].filter(Boolean).join(' · ');
  return '<div class="drow clik" data-t="'+it.tab+'" data-id="'+esc(it.id)+'">'+
    '<span class="dh'+(late?' late':'')+'"'+(tit?' title="'+tit+'"':'')+'>'+esc(quando)+'</span>'+
    '<span class="dn">'+esc(it.nome||'')+(sub?'<span class="dsub">'+esc(sub)+'</span>':'')+'</span>'+
    (wa?'<a class="wa" target="_blank" rel="noopener" href="'+wa+'" aria-label="WhatsApp">'+WAICO+'</a>':'<span></span>')+
  '</div>';
}
function repFaixas(arr,hoje){
  const fx=[['1 a 3 dias',1,3,true],['4 a 7 dias',4,7,true],['8 a 30 dias',8,30,true],['Mais de 30 dias',31,1e9,false]];
  return fx.map(function(f,i){
    const l=arr.filter(function(it){const d=diasEntre(it.data,hoje);return d>=f[1]&&d<=f[2];}).reverse();
    if(!l.length)return '';
    const aberto=(i in REPABERTO)?REPABERTO[i]:f[3];
    return '<details class="repfx'+(i===3?' velho':'')+'" data-fx="'+i+'"'+(aberto?' open':'')+'>'+
      '<summary>'+f[0]+' <span>'+l.length+'</span></summary>'+
      l.map(function(it){return repRow(it,hoje,'atr');}).join('')+'</details>';
  }).join('');
}
function repProximos(arr,hoje){
  var dias={},ord=[];
  arr.forEach(function(it){if(!dias[it.data]){dias[it.data]=[];ord.push(it.data);}dias[it.data].push(it);});
  ord.sort();
  return ord.map(function(d){
    return '<div class="repdia">'+diaSemana(d).slice(0,3)+' '+brDate(d).slice(0,5)+' <span>'+dias[d].length+'</span></div>'+
      dias[d].map(function(it){return repRow(it,hoje,'prox');}).join('');
  }).join('');
}
function repCard(atr,hj,px,hoje){
  const atr7=atr.filter(function(it){return diasEntre(it.data,hoje)<=7;}).length;
  const cont=hj.length+atr7;
  const col=function(id,tit,n,corpo,cls){
    return '<div class="repcol'+(REPTAB===id?' on':'')+'" data-rc="'+id+'"><h4 class="'+cls+'">'+tit+' <span>'+n+'</span></h4>'+corpo+'</div>';
  };
  const abas=[['atr','Atrasados',atr.length],['hoje','Hoje',hj.length],['prox','Próximos',px.length]];
  return '<div class="rcard wide repcard"><h3>Repiques · Clientes B2C'+(cont?' <span class="repcnt" title="Hoje + atrasados de até 7 dias">'+cont+'</span>':'')+'</h3>'+
    '<div class="rsub reptabs">'+abas.map(function(t){
      return '<button data-rt="'+t[0]+'"'+(REPTAB===t[0]?' class="on"':'')+'>'+t[1]+' ('+t[2]+')</button>';
    }).join('')+'</div>'+
    '<div class="repgrid">'+
      col('atr','Atrasados',atr.length,atr.length?repFaixas(atr,hoje):'<div class="empty">Nenhum repique atrasado.</div>','late')+
      col('hoje','Hoje',hj.length,hj.length?hj.map(function(it){return repRow(it,hoje,'hoje');}).join(''):'<div class="empty">Nada para hoje.</div>','')+
      col('prox','Próximos 7 dias',px.length,px.length?repProximos(px,hoje):'<div class="empty">Nada agendado para os próximos 7 dias.</div>','')+
    '</div>'+
    '<div class="rnote">O número ao lado do título soma hoje e os atrasados de até 7 dias. O que está atrasado há mais de 30 dias fica recolhido: atualize a agenda desses leads.</div></div>';
}

function iniLista(arr,hoje,vazio){"""
rep("function iniLista(arr,hoje,vazio){", FUNCS)

# D. troca os dois cards antigos pelo bloco novo
i=s.index("  /* ---- repiques ---- */"); j=s.index("  /* ---- agendamentos presenciais do dia ---- */")
velho=s[i:j]
assert "cardHoje=" in velho and "cardAtras=" in velho and velho.count("\n")<12, velho
s=s[:i]+r"""  /* ---- repiques: bloco B2C em tres colunas ---- */
  const ehB2C=function(it){return it.tab==='leads'&&!it.pv&&!it.agenda;};
  const repAtras=(ALERTS.atrasados||[]).filter(ehB2C);
  const repHoje=(ALERTS.agora||[]).concat(ALERTS.hoje||[]).filter(ehB2C);
  const repProx=(ALERTS.proximos||[]).concat(ALERTS.adiante||[]).filter(ehB2C);
  const cardRep=repCard(repAtras,repHoje,repProx,hoje);
  /* pos-venda, escolas, empresas e agenda vencidos ou de hoje continuam no Inicio, fora do bloco B2C */
  const outros=(ALERTS.atrasados||[]).concat(ALERTS.agora||[],ALERTS.hoje||[]).filter(function(it){return !ehB2C(it);});
  const cardOutros=outros.length
    ? '<div class="rcard"><h3>Pós-venda, escolas, empresas e agenda ('+outros.length+')</h3>'+iniLista(outros,hoje,'')+'</div>'
    : '';

"""+s[j:]
rep("'<div class=\"rgrid\">'+cardAtras+cardHoje+cardEvo", "'<div class=\"rgrid\">'+cardRep+cardOutros+cardEvo")

# E. eventos do bloco
rep("""  drawCharts();
  bindIniToggle();
  mtHomeFill();

  document.querySelectorAll('#iniwrap .drow.clik')""","""  drawCharts();
  bindIniToggle();
  mtHomeFill();
  document.querySelectorAll('#iniwrap .reptabs button').forEach(function(b){
    b.onclick=function(){
      REPTAB=b.dataset.rt;
      document.querySelectorAll('#iniwrap .reptabs button').forEach(function(x){x.classList.toggle('on',x===b);});
      document.querySelectorAll('#iniwrap .repcol').forEach(function(c){c.classList.toggle('on',c.dataset.rc===REPTAB);});
    };
  });
  document.querySelectorAll('#iniwrap .repfx').forEach(function(d){
    d.addEventListener('toggle',function(){REPABERTO[d.dataset.fx]=d.open;});
  });

  document.querySelectorAll('#iniwrap .drow.clik')""")

# F. CSS no style principal
rep(".rgrid>.wide{grid-column:1/-1}\n", """.rgrid>.wide{grid-column:1/-1}
/* repiques B2C no Inicio */
.repcard>h3 .repcnt{display:inline-block;background:var(--red);color:var(--white);border-radius:var(--r-pill);font-size:11px;padding:1px 8px;margin-left:6px;vertical-align:1px;letter-spacing:0}
.repgrid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:12px;align-items:start}
.repcol{min-width:0;background:var(--surface);border:1px solid var(--line);border-radius:var(--r-md);padding:10px 12px;max-height:560px;overflow-y:auto}
.repcol>h4{font-family:'Poppins';font-size:12px;text-transform:uppercase;letter-spacing:.4px;color:var(--blue);margin-bottom:6px;display:flex;justify-content:space-between;gap:8px}
.repcol>h4.late{color:var(--redDark)}
.repcol>h4 span{color:var(--gray)}
.repfx{border-top:1px solid var(--line);padding:2px 0}
.repfx:first-of-type{border-top:none}
.repfx>summary{cursor:pointer;font-size:11.5px;font-weight:700;color:var(--ink);padding:6px 0}
.repfx>summary span{color:var(--gray);font-weight:600}
.repfx.velho>summary{color:var(--gray)}
.repfx>summary:focus-visible{outline:2px solid var(--blue);outline-offset:2px}
.repdia{font-size:11.5px;font-weight:700;color:var(--ink);padding:8px 0 2px;border-top:1px solid var(--line)}
.repdia:first-of-type{border-top:none;padding-top:2px}
.repdia span{color:var(--gray);font-weight:600}
.reptabs{display:none;margin-bottom:10px;width:max-content;max-width:100%}
@media(max-width:760px){.reptabs{display:flex}.repgrid{grid-template-columns:1fr}.repcol{display:none;max-height:none}.repcol.on{display:block}}
""")
open(p,'w',encoding='utf-8').write(s)
print('ok')
