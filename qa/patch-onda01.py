#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Refaz a onda 0 e 1 das correcoes do CRM CNA Taquara sobre o index.html ATUAL do GitHub.
Cada troca e' guardada por assert s.count(anchor) == 1."""
import io, sys, re

SRC = '/tmp/crm/index.html'
s = io.open(SRC, encoding='utf-8').read()
orig = s
edits = []


def rep(nome, old, new, n=1):
    global s
    c = s.count(old)
    assert c == n, u'[%s] ancora aparece %d vezes, esperado %d' % (nome, c, n)
    s = s.replace(old, new)
    edits.append(nome)


# ---------------------------------------------------------------- CSS
rep('css-mx-desktop',
    ".mx{display:none;position:absolute;top:14px;right:14px;",
    "/* A19: o X vale em qualquer largura. No desktop so existia o Fechar do rodape */\n.mx{display:block;position:absolute;top:14px;right:14px;")

rep('css-agt-pend',
    ".agt.done{background:#E9F5EE;color:var(--ok)}",
    ".agt.done{background:#E9F5EE;color:var(--ok)}\n"
    "/* A09: etiqueta de pendencia no card. Cobranca, nao bloqueio */\n"
    ".agt.pend{background:var(--warnBg);color:var(--warn)}\n"
    ".nechips{display:flex;gap:6px;flex-wrap:wrap;margin:2px 0 4px}\n"
    ".nechips button{border:1px solid var(--line);background:var(--white);border-radius:var(--r-pill);padding:6px 12px;font-size:12px;color:var(--gray);cursor:pointer}\n"
    ".nechips button.on{background:var(--blue);border-color:var(--blue);color:var(--white)}\n"
    ".nechips.need{border:1px solid var(--red);background:var(--pastelRed);border-radius:var(--r-pill);padding:4px}")

# ---------------------------------------------------------------- HTML
rep('html-pendbox',
    '    <div class="mbody">\n      <div class="grid" id="form"></div>',
    '    <div class="mbody">\n'
    '      <!-- A09: cobranca do que falta na ficha. Le a mesma pendenciasLead() do card -->\n'
    '      <div class="ibox warn" id="pendbox" style="display:none"></div>\n'
    '      <div class="grid" id="form"></div>')

rep('html-nemotivo-chips',
    """          <select id="nemotivo">
            <option value="">Por que não deu certo?</option>
            <option value="nao_atendeu">Não atendeu</option>
            <option value="caixa_postal">Caiu na caixa postal</option>
            <option value="numero_errado">Número errado ou inválido</option>
            <option value="pediu_retorno">Pediu retorno depois</option>
            <option value="nao_leu">Mensagem não lida</option>
            <option value="recusou">Desligou / recusou falar</option>
            <option value="ausente">Decisor ausente</option>
          </select>""",
    """          <!-- A10: os 7 motivos viraram chips. Um toque em vez de abrir lista e escolher -->
          <div class="nechips" id="nechips"></div>
          <input type="hidden" id="nemotivo" value="">""")

rep('html-neaviso',
    '          <button class="btn primary" id="neadd" disabled>Registrar e agendar</button>',
    '          <div class="ibox warn" id="neaviso" style="display:none"></div>\n'
    '          <button class="btn primary" id="neadd">Registrar e agendar</button>')

# ------------------------------------------------- A01/A02/A03 emptyFilters
rep('a01-emptyfilters',
    """  const f={q:'',prio:null,tipo:null,resp:null,ag:null,per:null,entradaDe:null,entradaAte:null,proxDe:null,proxAte:null};
  if(tab==='leads'){const r=periodoRange('mes');f.per='mes';f.entradaDe=r[0];f.entradaAte=r[1];}
  return f;""",
    """  /* A01/A02/A03: o funil abre com TODO o historico. O recorte automatico por data
     de cadastro escondia lead antigo em negociacao e fazia o cabecalho divergir do
     quadro. Quem quiser o mes escolhe no seletor de periodo da toolbar. */
  const f={q:'',prio:null,tipo:null,resp:null,ag:null,per:null,entradaDe:null,entradaAte:null,proxDe:null,proxAte:null};
  return f;""")

# ------------------------------------------------- A08 cadeia sem etapa terminal
rep('a08-cadeia',
    """  const cadeia=cfg.stages.filter(function(x){return !x.side;});
  const cidx=st.side?-1:cadeia.findIndex(function(x){return x.id===st.id;});""",
    """  const cadeia=cfg.stages.filter(function(x){return !x.side&&!x.off;});
  const cidx=(st.side||st.off)?-1:cadeia.findIndex(function(x){return x.id===st.id;});""")

# ------------------------------------------------- A09 pendenciasLead
rep('a09-pendenciaslead',
    "/* Sub-status mostrado no card da coluna Matrícula fechada */\nfunction pvStatus(lead){",
    """/* A09 - fonte unica das pendencias de uma ficha de lead. O card e o topo da ficha
   leem esta mesma lista, entao nunca discordam. Salvar SEMPRE salva: o que falta
   vira cobranca visivel, nao bloqueio. Continuam bloqueando so o nome vazio
   (identidade do registro) e a idade fora de 1-120 (valor invalido, nao ausencia). */
function pendenciasLead(lead){
  const p=[];
  if(!lead)return p;
  const et=lead.etapa||'';
  if(ETAPAS_NIVEL[et]){
    if(!lead.nome_aluno)p.push('nome do aluno');
    if(!lead.nivel)p.push('n\\u00edvel');
  }
  if(et==='fechado'){
    if(!lead.turma)p.push('turma');
    if(!lead.data_inicio_aulas)p.push('in\\u00edcio das aulas');
  }
  if(et==='perdido'&&!lead.motivo_perda)p.push('motivo da perda');
  if(!lead.curso)p.push('curso de interesse');
  if(!lead.origem)p.push('origem');
  if(lead.origem==='A\\u00e7\\u00e3o comercial'&&!lead.acao_id)p.push('a\\u00e7\\u00e3o comercial de origem');
  const _id=parseInt(lead.idade,10);
  if(!isNaN(_id)&&_id<18&&!lead.responsavel_legal)p.push('respons\\u00e1vel pelo aluno');
  if(lead.proximo_atendimento&&!lead.proximo_atendimento_hora)p.push('hora do pr\\u00f3ximo contato');
  return p;
}

/* Sub-status mostrado no card da coluna Matrícula fechada */
function pvStatus(lead){""")

rep('a09-card-tag',
    """  var pvTag='';
  if(tab==='leads'){const _pv=pvStatus(s);if(_pv)pvTag='<span class="agt '+_pv.cls+'">&#127891; '+esc(_pv.txt)+'</span>';}""",
    """  var pvTag='',pdTag='';
  if(tab==='leads'){
    const _pv=pvStatus(s);
    if(_pv)pvTag='<span class="agt '+_pv.cls+'">&#127891; '+esc(_pv.txt)+'</span>';
    /* A09: o que falta vira etiqueta no card, ao lado do capelo que ja funcionava
       nesse modelo. Nao impede nada, so torna visivel o que estava silencioso. */
    var _pend=pendenciasLead(s);
    if(_pv&&_pv.txt==='Definir in\\u00edcio das aulas')_pend=_pend.filter(function(x){return x!=='in\\u00edcio das aulas';});
    if(_pend.length)pdTag='<span class="agt pend" title="Salvar grava assim mesmo. Complete quando tiver o dado.">&#9888; falta '+esc(_pend.join(', '))+'</span>';
  }""")

rep('a09-card-render', "      agTag+pvTag+\n", "      agTag+pvTag+pdTag+\n")

# ------------------------------------------------- A09 cobranca na ficha
rep('a09-syncpend',
    "function closeModal(){\n  $('ov').classList.remove('open');",
    """/* A09: le a ficha aberta como se fosse um lead e cobra o que falta no topo,
   nomeando a etapa em que a pessoa esta. Mesma fonte da etiqueta do card. */
function formLead(){
  const o={};
  document.querySelectorAll('#form [data-k]').forEach(function(el){
    o[el.getAttribute('data-k')]=el.value.trim()===''?null:el.value.trim();
  });
  const s=recAtual();
  if(s){o.proximo_atendimento=s.proximo_atendimento;o.proximo_atendimento_hora=s.proximo_atendimento_hora;}
  return o;
}
function syncPend(){
  const box=$('pendbox');
  if(!box)return;
  if(tab!=='leads'){box.style.display='none';box.innerHTML='';return;}
  const l=formLead();
  const p=pendenciasLead(l);
  if(!p.length){box.style.display='none';box.innerHTML='';return;}
  const st=CFG.leads.stages.find(function(x){return x.id===(l.etapa||'');});
  box.style.display='';
  box.innerHTML='<div class="itx"><b>Falta completar'+(st?' para a etapa \\u201c'+esc(st.n)+'\\u201d':'')+'</b>'
    +'<p>'+esc(p.join(' \\u00b7 '))+'. Pode salvar assim mesmo: o CRM cobra, n\\u00e3o bloqueia.</p></div>';
}

function closeModal(){
  $('ov').classList.remove('open');""")

rep('a09-closemodal-dirty',
    "function closeModal(){\n  $('ov').classList.remove('open');\n  unlockScroll();\n  editing=null;\n}",
    "function closeModal(){\n  $('ov').classList.remove('open');\n  unlockScroll();\n  DIRTY=false;\n  editing=null;\n}")

# ------------------------------------------------- A19 flag DIRTY
rep('a19-dirty-decl',
    "let editing=null;   // id em edição ou null (novo)",
    "let editing=null;   // id em edição ou null (novo)\n"
    "/* A19: ficha mexida e nao salva. O X, o Escape e o clique no fundo passam por\n"
    "   aqui; o Fechar do rodape continua sendo a saida deliberada. */\n"
    "let DIRTY=false;")

rep('a19-openmodal-reset',
    "  $('ov').classList.add('open');\n  lockScroll();\n  const mb=document.querySelector('.mbody');\n  if(mb)mb.scrollTop=0;\n}",
    "  syncPend();\n  DIRTY=false;\n  $('ov').classList.add('open');\n  lockScroll();\n  const mb=document.querySelector('.mbody');\n  if(mb)mb.scrollTop=0;\n}")

rep('a19-form-listener',
    """['input','change'].forEach(function(ev){
  document.addEventListener(ev,function(e){
    const t=e.target;
    if(t&&t.tagName==='INPUT'&&t.type==='date')t.classList.toggle('dvazio',!t.value);
  },true);
});""",
    """['input','change'].forEach(function(ev){
  document.addEventListener(ev,function(e){
    const t=e.target;
    if(t&&t.tagName==='INPUT'&&t.type==='date')t.classList.toggle('dvazio',!t.value);
    /* A19 + A09: qualquer toque na ficha suja o formulario e recalcula a cobranca */
    if(t&&t.closest&&t.closest('#form')){DIRTY=true;syncPend();}
  },true);
});""")

rep('a19-fechar',
    """$('close').onclick=closeModal;
$('closex').onclick=closeModal;
/* clicar fora NAO fecha a ficha: um toque errado no meio do cadastro perdia tudo */
$('ov').addEventListener('click',function(e){if(e.target===$('ov'))toast('Use o botão Fechar para sair da ficha.');});
document.addEventListener('keydown',function(e){if(e.key==='Escape'&&$('ov').classList.contains('open'))closeModal();});""",
    """/* A19: o Fechar do rodape e' a saida deliberada e sempre fecha. O X, o Escape e o
   clique no fundo so fecham com a ficha limpa; com a ficha suja, avisam. */
function tentarFecharFicha(){
  if(!DIRTY){closeModal();return;}
  toast('Voc\\u00ea mexeu na ficha e ainda n\\u00e3o salvou. Use Salvar, ou o bot\\u00e3o Fechar do rodap\\u00e9 para sair mesmo assim.');
}
$('close').onclick=closeModal;
$('closex').onclick=tentarFecharFicha;
$('ov').addEventListener('click',function(e){if(e.target===$('ov'))tentarFecharFicha();});
document.addEventListener('keydown',function(e){if(e.key==='Escape'&&$('ov').classList.contains('open'))tentarFecharFicha();});""")

# ------------------------------------------------- A11/A10 tentativa sem sucesso
rep('a11-necheck',
    """function neCheck(){
  const ok=!!$('nemotivo').value&&!!$('nedata').value&&!!$('nedatah').value;
  $('neadd').disabled=!ok;
  $('nedata').classList.toggle('ok',!!$('nedata').value);
  $('nedatah').classList.toggle('ok',!!$('nedatah').value);
}
['nemotivo','nedata','nedatah'].forEach(function(idf){
  $(idf).addEventListener('change',neCheck);
  $(idf).addEventListener('input',neCheck);
});""",
    """/* A10: os 7 motivos viram chips, montados a partir do mapa unico MOTIVOS_NE */
(function montaChipsNE(){
  const box=$('nechips');
  if(!box)return;
  box.innerHTML=Object.keys(MOTIVOS_NE).map(function(k){
    return '<button type="button" data-ne="'+esc(k)+'">'+esc(MOTIVOS_NE[k])+'</button>';
  }).join('');
  box.addEventListener('click',function(e){
    const b=e.target.closest('button[data-ne]');
    if(!b)return;
    const k=b.getAttribute('data-ne');
    $('nemotivo').value=($('nemotivo').value===k)?'':k;
    box.querySelectorAll('button').forEach(function(x){x.classList.toggle('on',x.getAttribute('data-ne')===$('nemotivo').value);});
    neCheck();
  });
})();

/* A11: o botao NUNCA fica cinza. Quem nao consegue clicar nao descobre o que falta.
   A cobranca aparece uma vez so, em .ibox warn, e o vermelho do campo (need) so
   entra DEPOIS de uma tentativa de registrar - e sai no primeiro input do campo. */
var neTentou=false;
function neFaltando(){
  const f=[];
  if(!$('nemotivo').value)f.push('o motivo');
  if(!$('nedata').value)f.push('a data do pr\\u00f3ximo contato');
  if(!$('nedatah').value)f.push('a hora');
  return f;
}
function neCheck(){
  const btn=$('neadd');
  if(btn)btn.disabled=false;
  $('nedata').classList.toggle('ok',!!$('nedata').value);
  $('nedatah').classList.toggle('ok',!!$('nedatah').value);
  const ch=$('nechips');
  if(ch)ch.querySelectorAll('button').forEach(function(x){x.classList.toggle('on',x.getAttribute('data-ne')===$('nemotivo').value);});
  $('nedata').classList.toggle('need',neTentou&&!$('nedata').value);
  $('nedatah').classList.toggle('need',neTentou&&!$('nedatah').value);
  if(ch)ch.classList.toggle('need',neTentou&&!$('nemotivo').value);
  const box=$('neaviso'),f=neFaltando();
  if(box){
    if(!neTentou||!f.length){box.style.display='none';box.innerHTML='';}
    else{
      box.style.display='';
      box.innerHTML='<div class="itx"><b>Falta '+esc(f.join(', '))+'</b>'
        +'<p>Sem isso a tentativa n\\u00e3o entra no hist\\u00f3rico nem gera alerta na fila.</p></div>';
    }
  }
}
['nemotivo','nedata','nedatah'].forEach(function(idf){
  $(idf).addEventListener('change',neCheck);
  $(idf).addEventListener('input',neCheck);
});""")

rep('a11-neadd-click',
    """  if(!motivo){toast('Escolha o motivo da tentativa sem sucesso.');return;}
  if(!prox){toast('Agende a data do próximo contato para poder registrar.');return;}
  if(!proxh){toast('Informe a hora do próximo contato. O alerta dispara na data e hora marcadas.');return;}
  if(prox<hojeISO()){""",
    """  /* A11: cobranca UNICA. Antes eram tres toasts em sequencia, um por vez */
  if(!motivo||!prox||!proxh){
    neTentou=true;neCheck();
    const alvo=!motivo?$('nechips'):(!prox?$('nedata'):$('nedatah'));
    if(alvo&&alvo.focus)alvo.focus();
    else if(alvo&&alvo.querySelector('button'))alvo.querySelector('button').focus();
    return;
  }
  if(prox<hojeISO()){""")

rep('a11-neadd-reset',
    """    $('nemotivo').value='';$('neobs').value='';$('nedata').value='';$('nedatah').value='';
    loadInts(editing);
    toast('Tentativa registrada.""",
    """    $('nemotivo').value='';$('neobs').value='';$('nedata').value='';$('nedatah').value='';
    neTentou=false;
    loadInts(editing);
    toast('Tentativa registrada.""")

rep('a11-resetintpanes',
    "  canalTocado.ef=false;canalTocado.ne=false;\n  neCheck();",
    "  canalTocado.ef=false;canalTocado.ne=false;\n  neTentou=false;\n  neCheck();")

# ------------------------------------------------- A21 contato efetivo confirma
rep('a21-iadd-toast',
    """    if($('itipo').value!=='nota')await avancaEtapa(editing,'respondeu');
    $('iresumo').value='';$('iprox').value='';$('iproxh').value='';
    loadInts(editing);
  }catch(e){toast('Não foi possível registrar. Tente de novo.');}""",
    """    if($('itipo').value!=='nota')await avancaEtapa(editing,'respondeu');
    $('iresumo').value='';$('iprox').value='';$('iproxh').value='';
    loadInts(editing);
    /* A21: o contato efetivo nao confirmava nada na tela. Quem registrava nao sabia
       se tinha dado certo e registrava de novo. */
    toast(prox?('Contato registrado. Pr\\u00f3ximo contato em '+brDate(prox)+' \\u00e0s '+proxh+(pcanal?' por '+canalNome(pcanal):'')+'.')
              :'Contato registrado no hist\\u00f3rico. Nenhum pr\\u00f3ximo contato agendado.');
  }catch(e){toast('Não foi possível registrar. Tente de novo.');}""")

rep('a21-dvazio',
    "    if(tab==='leads'){const i2=document.querySelector('#form [data-k=ultimo_contato]');if(i2)i2.value=hoje;}",
    "    /* A21: o campo continuava com a classe dvazio (cinza de campo em branco)\n"
    "       mesmo depois de receber a data de hoje */\n"
    "    if(tab==='leads'){const i2=document.querySelector('#form [data-k=ultimo_contato]');if(i2){i2.value=hoje;i2.classList.remove('dvazio');}syncPend();}")

# ------------------------------------------------- A09 salvar sempre salva
rep('a09-salvar',
    """  if(!body.nome){toast('O nome do prospect é obrigatório.');return;}
  if(tab==='leads'){
    if(!editing&&!body.curso){toast('Escolha o curso de interesse.');return;}
    if(!editing&&!body.origem){toast('Informe a origem do lead. É o que alimenta o relatório de canais.');return;}
    if(body.origem==='Ação comercial'&&!body.acao_id){
      syncAcao();
      const sac=document.querySelector('#form [data-k=acao_id]');
      if(sac)sac.focus();
      toast('Escolha de qual ação comercial veio esse lead.');
      return;
    }
    if(body.origem!=='Ação comercial')body.acao_id=null;
    if(!body.nome_aluno&&alunoObrigatorio()){
      syncAluno();
      const sa=document.querySelector('#form [data-k=nome_aluno]');
      if(sa)sa.focus();
      toast('A partir do teste de nível o nome do aluno é obrigatório.');
      return;
    }
    if(!body.nivel&&nivelObrigatorio()){
      syncNivel(true);
      const sn=document.querySelector('#form [data-k=nivel]');
      if(sn)sn.focus();
      toast('A partir do teste de nível o nível do aluno é obrigatório.');
      return;
    }
    if(body.etapa!=='perdido')body.motivo_perda=null;
    else if(!body.motivo_perda){toast('Escolha o motivo da perda.');syncPerda();return;}
    if(body.idade!=null){
      const idn=parseInt(body.idade,10);
      if(isNaN(idn)||idn<1||idn>120){toast('Idade inválida. Informe um número entre 1 e 120.');return;}
      body.idade=idn;
      if(idn<18&&!body.responsavel_legal){
        syncResp(true);
        const rl=document.querySelector('#form [data-k=responsavel_legal]');
        if(rl)rl.focus();
        toast('Aluno menor de 18 anos: informe o nome do responsável pelo aluno.');
        return;
      }
    }
  }
  var semHora=null;
  cfg.fields.forEach(function(f){
    if(f.t!=='datetime')return;
    if(!body[f.k]){body[f.hk]=null;return;}
    if(!body[f.hk])semHora=f.l;
  });
  if(semHora){
    document.querySelectorAll('#form .dtwrap').forEach(function(w){
      const di=w.querySelector('input[type=date]'),hi=w.querySelector('input[type=time]');
      hi.classList.toggle('need',!!di.value&&!hi.value);
    });
    toast('Informe a hora de \"'+semHora+'\". O alerta dispara na data e hora marcadas.');
    return;
  }""",
    """  /* A09 - SALVAR SEMPRE SALVA.
     Bloqueiam so dois casos: nome vazio (e' a identidade do registro, sem ele nao
     ha card onde pendurar a etiqueta) e idade fora de 1-120 (valor INVALIDO, nao
     ausencia de valor - gravar lixo e' pior que nao gravar).
     Tudo o mais que faltar vira etiqueta no card e cobranca no topo da ficha,
     por pendenciasLead(). Ver 50-decisoes/2026-08-27-crm-salvar-sempre-salva.md */
  if(!body.nome){
    const nn=document.querySelector('#form [data-k=nome]');
    if(nn){nn.classList.add('need');nn.focus();}
    toast('O nome do prospect é obrigatório.');
    return;
  }
  if(tab==='leads'){
    if(body.origem!=='Ação comercial')body.acao_id=null;
    if(body.etapa!=='perdido')body.motivo_perda=null;
    if(body.idade!=null){
      const idn=parseInt(body.idade,10);
      if(isNaN(idn)||idn<1||idn>120){toast('Idade inválida. Informe um número entre 1 e 120.');return;}
      body.idade=idn;
    }
  }
  /* datetime com data e sem hora: grava a data, marca o campo e cobra depois */
  cfg.fields.forEach(function(f){
    if(f.t!=='datetime')return;
    if(!body[f.k])body[f.hk]=null;
  });
  document.querySelectorAll('#form .dtwrap').forEach(function(w){
    const di=w.querySelector('input[type=date]'),hi=w.querySelector('input[type=time]');
    if(di&&hi)hi.classList.toggle('need',!!di.value&&!hi.value);
  });""")

rep('a09-dup-aviso',
    """      const dup=(DATA.leads||[]).find(function(x){return dig(x.whatsapp)===w;});
      if(dup){toast('Já existe um lead com esse número: '+dup.nome+'. Abra o card existente para editar.');return;}""",
    """      const dup=(DATA.leads||[]).find(function(x){return dig(x.whatsapp)===w;});
      /* Regra 2 do vault: duplicidade AVISA, nao impede. O card ja carrega o selo
         "Nx mesmo numero" e o relatorio de duplicados existe. */
      if(dup)toast('Aten\\u00e7\\u00e3o: j\\u00e1 existe um lead com esse n\\u00famero (\\u201c'+dup.nome+'\\u201d). Salvando assim mesmo.');""")

# ------------------------------------------------- A12 front refletirCarimbo
rep('a12-refletircarimbo',
    """      const res=await api('/'+cfg.table+'?id=eq.'+editing,{method:'PATCH',body:JSON.stringify(body)});
      const idx=DATA[tab].findIndex(function(x){return x.id===editing;});
      if(idx>-1&&res&&res[0])DATA[tab][idx]=res[0];""",
    """      const res=await api('/'+cfg.table+'?id=eq.'+editing,{method:'PATCH',body:JSON.stringify(body)});
      const idx=DATA[tab].findIndex(function(x){return x.id===editing;});
      if(idx>-1&&res&&res[0])DATA[tab][idx]=res[0];
      /* A12 (front): o banco carimba proximo_atendimento no PATCH (trigger da etapa
         27.1). Sem isso a ficha continuava mostrando o agendamento antigo ate alguem
         reabrir o cadastro. */
      if(res&&res[0])refletirCarimbo(res[0]);""")

rep('a12-refletir-func',
    "/* Depois de qualquer contato registrado: grava agendamento no registro e atualiza tela */",
    """/* A12 (front): devolve para a tela o que o BANCO carimbou na resposta do PATCH.
   A regra de agenda mora no banco (regra 4 do vault) e ha varios caminhos de
   criacao, entao a ficha tem que ler a resposta, nunca supor o que gravou. */
function refletirCarimbo(row){
  if(!row)return;
  ['ultimo_contato','data_fechamento','data_inicio_aulas'].forEach(function(k){
    const el=document.querySelector('#form [data-k='+k+']');
    if(el)el.value=row[k]==null?'':String(row[k]);
  });
  marcaDatasVazias($('form'));
  syncMsub(row);
  syncAgbar();
  syncPend();
}

/* Depois de qualquer contato registrado: grava agendamento no registro e atualiza tela */""")

rep('a09-pos-save-cobranca',
    """    render();
    $('savedmsg').style.display='inline';
    setTimeout(function(){$('savedmsg').style.display='none';},1800);""",
    """    render();
    DIRTY=false;
    syncPend();
    $('savedmsg').style.display='inline';
    setTimeout(function(){$('savedmsg').style.display='none';},1800);
    /* A09: salvou. Se ainda falta coisa, a ficha diz o que falta - depois de gravar */
    if(tab==='leads'){
      const _p=pendenciasLead(recAtual()||formLead());
      if(_p.length)toast('Salvo. Falta ainda: '+_p.join(', ')+'.');
    }""")

io.open(SRC, 'w', encoding='utf-8').write(s)
print(u'%d edicoes aplicadas:' % len(edits))
for e in edits:
    print(u'  - ' + e)
print(u'linhas: %d -> %d' % (orig.count('\n') + 1, s.count('\n') + 1))
