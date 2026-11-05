import sys
p=sys.argv[1]; s=open(p,encoding='utf-8').read()
def rep(old,new,n=1):
    global s
    assert s.count(old)==n,(s.count(old),old[:70])
    s=s.replace(old,new)

# 1. repRow mostra o consultor quando o item traz "quem" (visao da unidade)
rep("  const sub=[it.etapa,it.curso,it.canal?canalNome(it.canal):'',\n    modo==='atr'?",
    "  const sub=[it.quem,it.etapa,it.curso,it.canal?canalNome(it.canal):'',\n    modo==='atr'?")
# repCard aceita titulo e cabecalho extra
rep("function repCard(atr,hj,px,hoje){", "function repCard(atr,hj,px,hoje,titulo,cab){")
rep("'<div class=\"rcard wide repcard\"><h3>Repiques · Clientes B2C'+(cont?",
    "'<div class=\"rcard wide repcard\"><h3>'+(titulo||'Repiques · Clientes B2C')+(cont?")
rep("    '<div class=\"rsub reptabs\">'+abas.map(", "    (cab||'')+'<div class=\"rsub reptabs\">'+abas.map(")

# 2. visao da unidade busca os repiques B2C de toda a equipe
rep("""var UNI={dados:null,ts:0,erro:''};""",
"""var UNI={dados:null,ts:0,erro:'',rep:[],repResp:''};
/* repiques B2C de toda a equipe da unidade (o api() ja filtra a unidade) */
async function uniRepLoad(){
  const hoje=hojeISO(),st=CFG.leads.stages;
  const rows=await api('/crm_leads?select=id,nome,whatsapp,responsavel,curso,etapa,proximo_atendimento,proximo_atendimento_hora,proximo_canal,tentativas_sem_retorno'
    +'&proximo_atendimento=lte.'+addDias(hoje,7)+'&order=proximo_atendimento.asc');
  const out=[];
  (rows||[]).forEach(function(r){
    const e=st.find(function(x){return x.id===r.etapa;});
    if(e&&(e.ok||e.off))return;
    if(!r.proximo_atendimento)return;
    out.push({tab:'leads',id:r.id,nome:r.nome,whatsapp:r.whatsapp,data:r.proximo_atendimento,
      hora:hhmm(r.proximo_atendimento_hora)||'09:00',rot:'Cliente B2C',etapa:e?e.n:'',canal:r.proximo_canal||'',
      curso:r.curso||'',tent:r.tentativas_sem_retorno||0,quem:r.responsavel||'Sem responsável'});
  });
  UNI.rep=out;
}""")
rep("""      api('/rpc/crm_painel_equipe',{method:'POST',body:JSON.stringify({p_data:hojeISO()})}),
      relLoad().catch(function(){return null;})
    ]);""","""      api('/rpc/crm_painel_equipe',{method:'POST',body:JSON.stringify({p_data:hojeISO()})}),
      relLoad().catch(function(){return null;}),
      uniRepLoad().catch(function(){UNI.rep=UNI.rep||[];})
    ]);""")

# 3. render: tabela por consultor + bloco filtravel
rep("""  /* matriculas mes a mes, ultimos 8 meses */""","""  /* ---- repiques da equipe: quem esta devendo, e o bloco filtravel por consultor ---- */
  var ord=function(a,b){var ka=a.data+' '+a.hora,kb=b.data+' '+b.hora;return ka<kb?-1:(ka>kb?1:0);};
  var reps=(UNI.rep||[]).slice().sort(ord);
  var porQuem={};
  reps.forEach(function(it){
    var q=porQuem[it.quem]||(porQuem[it.quem]={a7:0,a30:0,a31:0,hj:0,px:0});
    var d=diasEntre(it.data,hoje);
    if(d>30)q.a31++;else if(d>7)q.a30++;else if(d>0)q.a7++;else if(d===0)q.hj++;else q.px++;
  });
  var nomes=Object.keys(porQuem).sort(function(a,b){
    var A=porQuem[a],B=porQuem[b];return (B.a7+B.hj)-(A.a7+A.hj)||a.localeCompare(b);
  });
  if(UNI.repResp&&!porQuem[UNI.repResp])UNI.repResp='';
  var tabRep=nomes.length?'<div class="rtabw"><table class="rtab reptab">'+
    '<tr class="hd"><th>Consultor</th><th class="num">Hoje</th><th class="num">Atraso até 7 dias</th><th class="num">8 a 30</th><th class="num">Mais de 30</th><th class="num">Próx. 7 dias</th></tr>'+
    nomes.map(function(n){var q=porQuem[n];
      return '<tr class="clik'+(UNI.repResp===n?' on':'')+'" data-rr="'+esc(n)+'"><td>'+esc(n)+'</td>'+
        '<td class="num" data-l="Hoje">'+q.hj+'</td>'+
        '<td class="num'+(q.a7?' bd':'')+'" data-l="Atraso até 7 dias">'+q.a7+'</td>'+
        '<td class="num'+(q.a30?' bd':'')+'" data-l="8 a 30">'+q.a30+'</td>'+
        '<td class="num" data-l="Mais de 30">'+q.a31+'</td>'+
        '<td class="num" data-l="Próx. 7 dias">'+q.px+'</td></tr>';
    }).join('')+'</table></div>':'';
  var cardRepEq='<div class="rcard wide"><h3>Repiques da equipe · Clientes B2C</h3>'+
    (tabRep||'<div class="rempty">Nenhum repique B2C agendado na unidade.</div>')+
    '<div class="rnote">Toque num consultor para ver os repiques dele no bloco abaixo. Ordenado por quem tem mais para hoje e atraso de até 7 dias.</div></div>';
  var repF=UNI.repResp?reps.filter(function(it){return it.quem===UNI.repResp;}):reps;
  var cab='<div class="repfiltro">'+(UNI.repResp
    ?'Mostrando <b>'+esc(UNI.repResp)+'</b> <button class="dctl" data-rr="">Ver toda a equipe</button>'
    :'Mostrando <b>toda a equipe</b>')+'</div>';
  var cardRepU=repCard(
    repF.filter(function(it){return it.data<hoje;}),
    repF.filter(function(it){return it.data===hoje;}),
    repF.filter(function(it){return it.data>hoje;}),
    hoje,'Repiques · Clientes B2C'+(UNI.repResp?' · '+esc(UNI.repResp):''),cab);

  /* matriculas mes a mes, ultimos 8 meses */""")
rep("""    '<div class="rgrid">'+cardEquipe+cardMes+cardPerda+'</div>'+""",
    """    '<div class="rgrid">'+cardEquipe+cardRepEq+cardRepU+cardMes+cardPerda+'</div>'+""")
rep("""  document.querySelectorAll('#uniwrap [data-uv]').forEach(function(b){""","""  document.querySelectorAll('#uniwrap [data-rr]').forEach(function(el){
    el.onclick=function(){UNI.repResp=(UNI.repResp===el.dataset.rr)?'':el.dataset.rr;renderUnidade();};
  });
  document.querySelectorAll('#uniwrap .reptabs button').forEach(function(b){
    b.onclick=function(){
      REPTAB=b.dataset.rt;
      document.querySelectorAll('#uniwrap .reptabs button').forEach(function(x){x.classList.toggle('on',x===b);});
      document.querySelectorAll('#uniwrap .repcol').forEach(function(c){c.classList.toggle('on',c.dataset.rc===REPTAB);});
    };
  });
  document.querySelectorAll('#uniwrap .repfx').forEach(function(d){
    d.addEventListener('toggle',function(){REPABERTO[d.dataset.fx]=d.open;});
  });
  document.querySelectorAll('#uniwrap .drow.clik').forEach(function(el){
    el.onclick=function(e){
      if(e.target.tagName==='A'||e.target.closest('a'))return;
      goToAlert(el.dataset.t,el.dataset.id);
    };
  });
  document.querySelectorAll('#uniwrap [data-uv]').forEach(function(b){""")

# 4. CSS
rep(".reptabs{display:none;", """.repfiltro{font-size:12px;color:var(--gray);margin:-4px 0 10px;display:flex;gap:8px;align-items:center;flex-wrap:wrap}
.repfiltro b{color:var(--ink)}
.reptab tr.clik{cursor:pointer}
.reptab tr.clik:hover td{background:var(--pastelBlue)}
.reptab tr.on td{background:var(--pastelBlue);font-weight:700}
.reptab td.bd{color:var(--redDark);font-weight:700}
.reptabs{display:none;""")
open(p,'w',encoding='utf-8').write(s); print('ok')
