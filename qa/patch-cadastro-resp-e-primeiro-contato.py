#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Cadastro de lead B2C, duas correcoes (10/09/2026).

1. Responsavel pelo aluno menor deixa de ser digitado duas vezes. Na base de
   10/09, 39 dos 57 leads de menor tinham o responsavel IGUAL ao prospect (mais 3
   com o mesmo nome escrito diferente). O padrao passa a ser "e' o proprio
   prospect": o campo some e recebe o nome de cima; so abre em "Outra pessoa".
   Se o prospect for o proprio aluno (adolescente que procurou sozinho), o campo
   abre obrigatoriamente.

2. Primeiro contato no cadastro. Lead novo continua saindo agendado para 10
   minutos (trigger crm_leads_agenda_novo), mas quem cadastra DEPOIS da conversa
   marca "Ja falei com a pessoa": o INSERT leva o proximo contato escolhido (o
   trigger respeita agenda informada) e, logo depois, o contato EFETIVO entra no
   historico. Quem preenche "ultimo contato" continua sendo o trigger da A52.

Uso:  python3 qa/patch-cadastro-resp-e-primeiro-contato.py index.html
Sem mudanca de banco.
"""
import io
import sys

SRC = sys.argv[1] if len(sys.argv) > 1 else 'index.html'
s = io.open(SRC, encoding='utf-8').read()
edits = []


def rep(nome, old, new, n=1):
    global s
    c = s.count(old)
    assert c == n, u'[%s] ancora aparece %d vezes, esperado %d' % (nome, c, n)
    s = s.replace(old, new)
    edits.append(nome)


assert 'function pcRegistrar' not in s, 'patch ja aplicado neste arquivo'

# ------------------------------------------------------------------ CSS
# ancora dentro do <style>; nada de substituicao global de valor
rep('css',
    ".f .mesmoq{margin-top:6px;border:1px solid var(--line);background:var(--white);border-radius:var(--r-pill);padding:4px 10px;font-size:11.5px;font-weight:600;color:var(--blue);cursor:pointer}",
    ".f .mesmoq{margin-top:6px;border:1px solid var(--line);background:var(--white);border-radius:var(--r-pill);padding:4px 10px;font-size:11.5px;font-weight:600;color:var(--blue);cursor:pointer}\n"
    "/* responsavel pelo aluno menor = o proprio prospect, por padrao */\n"
    ".f .rlmesmo{display:flex;align-items:center;gap:8px;flex-wrap:wrap;padding:7px 10px;border:1px solid var(--line);border-radius:var(--r-md);background:var(--surface);font-size:13px;color:var(--ink)}\n"
    ".f .rlmesmo .mesmoq{margin:0 0 0 auto}\n"
    "/* primeiro contato no cadastro do lead novo */\n"
    ".pcbox{border:1px solid var(--line);border-radius:var(--r-md);padding:10px 12px;background:var(--surface)}\n"
    ".pcbox .pcq{display:flex;gap:6px;flex-wrap:wrap}\n"
    ".pcbox .pcq button{border:1px solid var(--line);background:var(--white);border-radius:var(--r-pill);padding:6px 13px;font-size:12.5px;font-weight:600;color:var(--gray);cursor:pointer}\n"
    ".pcbox .pcq button.on{background:var(--blue);border-color:var(--blue);color:var(--white)}\n"
    ".pcbox .pcnota{font-size:12px;color:var(--gray);margin-top:8px;line-height:1.4}\n"
    ".pcbox .pcsim{display:grid;gap:8px;margin-top:10px}\n"
    ".pcbox .pcsim label{margin:4px 0 4px}")

# ------------------------------------------- openModal: bloco no lugar do campo
# Em lead NOVO o campo "Ultimo contato" nao faz sentido (A52: so o historico
# preenche). No lugar dele entra a pergunta do primeiro contato.
rep('open-bloco',
    "  cfg.fields.forEach(function(f){\n"
    "    const d=document.createElement('div');\n"
    "    d.className='f'+(f.full?' full':'');",
    "  cfg.fields.forEach(function(f){\n"
    "    if(f.k==='ultimo_contato'&&!s&&tab==='leads'){\n"
    "      const pc=document.createElement('div');\n"
    "      pc.className='f full';pc.id='fPrimeiro';pc.innerHTML=pcHTML();\n"
    "      form.appendChild(pc);return;\n"
    "    }\n"
    "    const d=document.createElement('div');\n"
    "    d.className='f'+(f.full?' full':'');")

rep('open-etapa',
    "if(selEt)selEt.addEventListener('change',function(){syncPerda();syncNivel(true);syncMatricula();syncAluno();tnSyncBotaoFicha();});",
    "if(selEt)selEt.addEventListener('change',function(){syncPerda();syncNivel(true);syncMatricula();syncAluno();tnSyncBotaoFicha();pcSync();});")

rep('open-init',
    "  syncResp(true);syncFaixa();syncNivel(true);syncMatricula();syncAluno();syncAcao();marcaDatasVazias(form);",
    "  /* o responsavel \"e' o proprio prospect\" acompanha o nome de cima */\n"
    "  const inpNome=form.querySelector('[data-k=nome]');\n"
    "  if(inpNome)inpNome.addEventListener('input',function(){syncResp(true);});\n"
    "  syncResp(true);syncFaixa();syncNivel(true);syncMatricula();syncAluno();syncAcao();marcaDatasVazias(form);\n"
    "  pcInit();")

# ------------------------------------------------------------- syncResp novo
rep('syncresp',
    """/* preserva=true na abertura da ficha, para nao apagar dado ja gravado */
function syncResp(preserva){
  const w=$('fRespLegal');
  if(!w)return;
  const req=respObrigatorio();
  const inp=w.querySelector('[data-k=responsavel_legal]');
  if(inp){
    if(!req&&!preserva)inp.value='';
    inp.disabled=false;
    inp.classList.toggle('need',req&&!inp.value.trim());
    inp.placeholder='Nome do pai, mãe ou responsável';
  }
  /* o bloco do responsavel so abre quando o aluno e menor de idade,
     ou quando ja existe um nome gravado na ficha */
  const tem=!!(inp&&inp.value.trim());
  w.style.display=(req||tem)?'':'none';
  const lab=w.querySelector('label');
  if(lab)lab.innerHTML='Responsável pelo aluno'+(req?' <b class="req">*</b>':'');
}""",
    """/* Responsavel pelo aluno menor. Na maioria dos leads de menor quem procura a
   escola e' o pai ou a mae (39 de 57 na base de 10/09/2026, mais 3 com o nome
   escrito diferente), e o nome era digitado duas vezes. O padrao passa a ser
   "e' o proprio prospect": o campo some e recebe o nome de cima. So abre quando
   a pessoa marca "Outra pessoa", ou quando o prospect e' o proprio aluno.
   O input continua sendo a fonte de verdade: o salvar e a cobranca leem dele.
   preserva=true na abertura da ficha, para nao apagar dado ja gravado. */
function rlNorm(v){return String(v||'').trim().toLowerCase().replace(/\\s+/g,' ');}
function syncResp(preserva){
  const w=$('fRespLegal');
  if(!w)return;
  const req=respObrigatorio();
  const inp=w.querySelector('[data-k=responsavel_legal]');
  if(!inp)return;
  const np=document.querySelector('#form [data-k=nome]');
  const al=document.querySelector('#form [data-k=nome_aluno]');
  const nome=np?np.value.trim():'';
  /* adolescente que procurou sozinho: o prospect e' o aluno, entao o
     responsavel necessariamente e' outra pessoa */
  const alunoEhProspect=!!(al&&nome&&rlNorm(al.value)===rlNorm(nome));
  if(!w.dataset.modo){
    const v=inp.value.trim();
    w.dataset.modo=(v&&rlNorm(v)!==rlNorm(nome))?'outra':'mesmo';
  }
  if(alunoEhProspect&&w.dataset.modo==='mesmo'){
    w.dataset.modo='outra';
    if(rlNorm(inp.value)===rlNorm(nome))inp.value='';
  }
  if(!req&&!preserva)inp.value='';
  const mesmo=req&&w.dataset.modo==='mesmo';
  if(mesmo)inp.value=nome;
  inp.disabled=false;
  inp.placeholder='Nome do pai, mãe ou responsável';
  inp.style.display=mesmo?'none':'';
  inp.classList.toggle('need',req&&!mesmo&&!inp.value.trim());
  if(!w._rl){
    w._rl=true;
    w.addEventListener('click',function(e){
      const b=e.target.closest?e.target.closest('[data-rl]'):null;
      if(!b)return;
      w.dataset.modo=b.dataset.rl;
      if(b.dataset.rl==='outra')inp.value='';
      syncResp(true);
      DIRTY=true;syncPend();
      if(b.dataset.rl==='outra')inp.focus();
    });
  }
  /* monta uma vez e so troca o texto: recriar o botao a cada sync fazia o clique
     se perder quando o blur da idade re-sincronizava entre mousedown e mouseup */
  let lin=w.querySelector('.rlmesmo');
  if(!lin){
    lin=document.createElement('div');lin.className='rlmesmo';
    lin.innerHTML='<span class="rltxt"></span><button type="button" class="mesmoq" data-rl="outra">Outra pessoa</button>';
    inp.insertAdjacentElement('afterend',lin);
  }
  lin.querySelector('.rltxt').innerHTML='É o próprio prospect'+(nome?': <b>'+esc(nome)+'</b>':' (preencha o nome acima)');
  lin.style.display=mesmo?'':'none';
  let volta=w.querySelector('.rlvolta');
  if(!volta){
    volta=document.createElement('button');volta.type='button';volta.className='mesmoq rlvolta';
    volta.dataset.rl='mesmo';volta.textContent='É o próprio prospect';
    w.appendChild(volta);
  }
  volta.style.display=(req&&!mesmo&&!alunoEhProspect)?'':'none';
  /* o bloco so abre quando o aluno e menor de idade,
     ou quando ja existe um nome gravado na ficha */
  const tem=!!inp.value.trim();
  w.style.display=(req||tem)?'':'none';
  const lab=w.querySelector('label');
  if(lab)lab.innerHTML='Responsável pelo aluno'+(req?' <b class="req">*</b>':'');
}""")

# nome do aluno igual ao prospect muda o que o responsavel pode ser
rep('syncaluno',
    "  atalho.style.display=inp.value.trim()?'none':'';\n}",
    "  atalho.style.display=inp.value.trim()?'none':'';\n  syncResp(true);\n}")

# ------------------------------------------------- salvar: valida e leva agenda
rep('save-valida',
    """      body.idade=idn;
    }
  }
  /* datetime com data e sem hora: grava a data, marca o campo e cobra depois */""",
    """      body.idade=idn;
    }
  }
  /* Primeiro contato ja feito (so em lead novo). Valida antes de gravar qualquer
     coisa: quem marcou "Ja falei" afirmou um contato, e contato sem relato nao
     entra no historico. A saida e' um toque: "Ainda nao falei". */
  let PC=null;
  if(tab==='leads'&&!editing&&$('pcBox')&&pcModo()==='sim'){
    const resumo=($('pcResumo').value||'').trim();
    if(!rtTxt(resumo).trim()){
      const r=document.querySelector('#pcBox .rted')||$('pcResumo');
      if(r)r.focus();
      toast('Conte o que foi conversado no primeiro contato, ou marque \\u201cAinda n\\u00e3o falei\\u201d para salvar sem registrar contato.');
      return;
    }
    const e271=body.etapa==='aguardando_271';
    const prox=e271?null:($('pcProx').value||null);
    const proxh=e271?null:($('pcProxH').value||null);
    const pcanal=e271?null:($('pcProxCanal').value||null);
    if(!e271){
      if(!prox||!proxh){toast('Informe data e hora do pr\\u00f3ximo contato. O alerta dispara na data e hora marcadas.');return;}
      if(prox<hojeISO()){toast('O pr\\u00f3ximo contato precisa ser hoje ou uma data futura.');return;}
      if(prox===hojeISO()&&proxh<agoraHM()){toast('Esse hor\\u00e1rio j\\u00e1 passou. Escolha uma hora \\u00e0 frente.');return;}
      /* agenda informada no INSERT: crm_leads_agenda_novo nao aplica os 10 minutos */
      body.proximo_atendimento=prox;body.proximo_atendimento_hora=proxh;body.proximo_canal=pcanal;
    }
    PC={tipo:$('pcCanal').value,resumo:resumo,prox:prox,proxh:proxh,pcanal:pcanal};
  }
  /* datetime com data e sem hora: grava a data, marca o campo e cobra depois */""")

rep('save-registra',
    "        if(tab==='leads')logEtapa(editing,res[0].etapa||'novo');\n",
    "        if(tab==='leads')logEtapa(editing,res[0].etapa||'novo');\n"
    "        if(PC)await pcRegistrar(editing,PC);\n")

# com primeiro contato registrado, o toast de "agendado em 10 minutos" nao vale
rep('save-toast',
    "        setTimeout(function(){\n"
    "          const p=$('ints');if(!p)return;",
    "        if(!PC)setTimeout(function(){\n"
    "          const p=$('ints');if(!p)return;")

# ------------------------------------------------------- funcoes do bloco novo
rep('funcoes',
    "/* Nome do aluno: em muito lead quem procura a escola e a mae ou o pai, entao o",
    """/* ================= Primeiro contato no cadastro =================
   Lead novo sai agendado para daqui a 10 minutos (trigger crm_leads_agenda_novo).
   Mas muito lead e' cadastrado DEPOIS da conversa: quem entrou na recepcao, quem
   ligou, quem ja respondeu no WhatsApp. Ai o alerta cobrava um contato que ja
   tinha acontecido. Quem cadastra diz aqui se ja falou com a pessoa:
   - "Ainda nao falei" (padrao): nada muda, o banco agenda os 10 minutos.
   - "Ja falei": o INSERT leva o proximo contato escolhido e, logo depois, o
     contato EFETIVO entra no historico. Quem preenche "ultimo contato" continua
     sendo o trigger da A52: ele so existe quando houve contato de verdade.
   Etapa "Aguardando 27.1": o banco carimba 01/10 no INSERT, entao o bloco nao
   pede data. */
const PC_CANAIS=['whatsapp','ligacao','visita','email'];
const PC_PROX=['whatsapp','ligacao','email','visita','reuniao','teste_nivel','experimental'];
/* sugestao: proximo dia util, na hora atual arredondada para cima em 15 min */
function pcSugestao(){
  let d=addDias(hojeISO(),1);
  if(new Date(d+'T12:00:00').getDay()===0)d=addDias(d,1);
  const t=new Date();
  const m=Math.min(Math.ceil((t.getHours()*60+t.getMinutes())/15)*15,23*60+45);
  return {d:d,h:String(Math.floor(m/60)).padStart(2,'0')+':'+String(m%60).padStart(2,'0')};
}
function pcHTML(){
  const sg=pcSugestao();
  const op=function(l){return l.map(function(c){return '<option value="'+c+'">'+esc(CANAIS[c])+'</option>';}).join('');};
  return '<label>Primeiro contato</label>'
    +'<div class="pcbox" id="pcBox">'
    +'<div class="pcq" role="group" aria-label="J\\u00e1 falou com essa pessoa?">'
    +'<button type="button" class="on" data-pc="nao">Ainda n\\u00e3o falei</button>'
    +'<button type="button" data-pc="sim">J\\u00e1 falei com a pessoa</button></div>'
    +'<div class="pcnota" id="pcNota"></div>'
    +'<div class="pcsim" id="pcSim" style="display:none">'
    +'<div><label>Canal</label><select id="pcCanal">'+op(PC_CANAIS)+'</select></div>'
    +'<div><label>O que foi conversado <b class="req">*</b></label>'
    +'<textarea id="pcResumo" rows="3" placeholder="O que o cliente falou, o que ficou combinado, o que voc\\u00ea prometeu retornar."></textarea></div>'
    +'<div id="pcProxW"><label>Pr\\u00f3ximo contato (data e hora) <b class="req">*</b></label>'
    +'<div class="dtwrap"><input type="date" id="pcProx" value="'+sg.d+'"><input type="time" step="900" id="pcProxH" value="'+sg.h+'"></div>'
    +'<label>Canal do pr\\u00f3ximo contato</label><select id="pcProxCanal">'+op(PC_PROX)+'</select></div>'
    +'</div></div>';
}
function pcModo(){
  const b=document.querySelector('#pcBox .pcq button.on');
  return b?b.dataset.pc:'nao';
}
function pcSync(){
  const box=$('pcBox');
  if(!box)return;
  const sim=pcModo()==='sim';
  const se=document.querySelector('#form [data-k=etapa]');
  const e271=!!se&&se.value==='aguardando_271';
  $('pcSim').style.display=sim?'':'none';
  $('pcProxW').style.display=e271?'none':'';
  $('pcNota').textContent=e271
    ?'Etapa Aguardando 27.1: o pr\\u00f3ximo contato fica em 01/10, marcado pelo sistema.'
    :(sim?'O contato entra no hist\\u00f3rico como efetivo e o lead fica agendado para a data abaixo.'
         :'O CRM agenda o primeiro contato para daqui a 10 minutos e avisa o respons\\u00e1vel.');
}
function pcInit(){
  const box=$('pcBox');
  if(!box)return;
  box.querySelectorAll('.pcq button').forEach(function(b){
    b.addEventListener('click',function(){
      box.querySelectorAll('.pcq button').forEach(function(x){x.classList.toggle('on',x===b);});
      DIRTY=true;pcSync();
      if(b.dataset.pc==='sim'){const r=box.querySelector('.rted')||$('pcResumo');if(r)r.focus();}
    });
  });
  pcSync();
}
/* depois do INSERT do lead: contato efetivo no historico. Se falhar, o lead ja
   existe e o relato nao pode se perder: vai para o painel do historico, pronto
   para registrar com um toque. */
async function pcRegistrar(id,pc){
  const body={lead_id:id,tipo:pc.tipo,autor:currentUser,efetivo:true,nota:pc.resumo,
    proximo_contato:pc.prox,proximo_contato_hora:pc.prox?pc.proxh:null,proximo_canal:pc.pcanal};
  const box=$('pcBox');
  try{
    await api('/crm_leads_interacoes',{method:'POST',body:JSON.stringify(body)});
  }catch(e){
    $('itipo').value=pc.tipo;
    $('iresumo').value=pc.resumo;
    if($('iresumo')._rtSync)$('iresumo')._rtSync();
    if(pc.prox){$('iprox').value=pc.prox;$('iproxh').value=pc.proxh;$('iproxcanal').value=pc.pcanal||'whatsapp';}
    if(box)box.innerHTML='<div class="pcnota">Cadastro salvo, mas o contato n\\u00e3o entrou no hist\\u00f3rico. Ele est\\u00e1 no hist\\u00f3rico abaixo, pronto para registrar.</div>';
    setTimeout(function(){
      const p=$('ints');if(p)p.scrollIntoView({behavior:'smooth',block:'start'});
      toast('Cadastro salvo, mas o contato n\\u00e3o entrou no hist\\u00f3rico. Confira abaixo e toque em Registrar.');
    },250);
    return false;
  }
  /* o trigger da A52 ja preencheu ultimo_contato: a ficha le do banco, nao supoe */
  try{
    const r=await api('/crm_leads?id=eq.'+id+'&select=*');
    const s=(DATA.leads||[]).find(function(x){return x.id===id;});
    if(s&&r&&r[0])Object.assign(s,r[0]);
    if(s&&editing===id)refletirCarimbo(s);
  }catch(e){}
  await avancaEtapa(id,'respondeu');
  loadInts(id);
  if(box)box.innerHTML='<div class="pcnota">\\u2713 Primeiro contato registrado no hist\\u00f3rico como efetivo.</div>';
  setTimeout(function(){
    toast(pc.prox?('Cadastro salvo com o primeiro contato no hist\\u00f3rico. Pr\\u00f3ximo contato em '+brDate(pc.prox)+' \\u00e0s '+pc.proxh+(pc.pcanal?' por '+canalNome(pc.pcanal):'')+'.')
                 :'Cadastro salvo com o primeiro contato no hist\\u00f3rico.');
  },250);
  return true;
}

/* Nome do aluno: em muito lead quem procura a escola e a mae ou o pai, entao o""")

io.open(SRC, 'w', encoding='utf-8').write(s)
print('ok:', ', '.join(edits))
