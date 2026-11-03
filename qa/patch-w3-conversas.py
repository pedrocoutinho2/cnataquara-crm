# W3 · caixa de entrada do WhatsApp pelas RPCs com token (W1b/W3a) e envio com token de sessão.
# Pré-requisito para fechar a RLS das crm_wa_* (dívida nº 3). Spec: 10-cna/sistemas/whatsapp-multinumero.md
# Uso: python3 qa/patch-w3-conversas.py index.html
import sys

p = sys.argv[1]
s = open(p, encoding='utf-8').read()


def rep(old, new, n=1):
    global s
    c = s.count(old)
    assert c == n, (c, old[:90])
    s = s.replace(old, new)


# CSS (só dentro do <style> principal): selo do número e filtro por conta
rep(".waj.off{background:var(--dangerBg);color:var(--danger)}\n",
    ".waj.off{background:var(--dangerBg);color:var(--danger)}\n"
    ".waselo{display:inline-block;font-size:10.5px;padding:1px 7px;border-radius:var(--r-pill);background:var(--pastelBlue);color:var(--blue);margin-top:3px;white-space:nowrap;max-width:100%;overflow:hidden;text-overflow:ellipsis}\n"
    ".wacontasel{margin-left:auto;border:1px solid var(--line);background:var(--white);border-radius:var(--r-pill);padding:3px 8px;font:inherit;font-size:12px;color:var(--gray);max-width:45%}\n")

# estado
rep("const WA={conta:null,conversas:[]", "const WA={contas:[],contaSel:null,conversas:[]")

# Edge Functions recebem o token de sessão do CRM
rep("body:JSON.stringify(body||{})\n  }).then(function(r){",
    "body:JSON.stringify(Object.assign({token:sessTok()},body||{}))\n  }).then(function(r){")

# helpers
rep("function meuId(){const u=USERS.find(function(x){return x.nome===currentUser;});return u?u.id:null;}\n",
    "function meuId(){const u=USERS.find(function(x){return x.nome===currentUser;});return u?u.id:null;}\n"
    "/* caixa de entrada só por RPC com token: a RLS das crm_wa_* não tem policy para anon */\n"
    "function waRpc(nome,args){\n"
    "  return api('/rpc/'+nome,{method:'POST',body:JSON.stringify(Object.assign({p_token:sessTok()},args||{}))});\n"
    "}\n"
    "function waErro(e,padrao){\n"
    "  const t=String((e&&(e.codigo||e.message))||e||'');\n"
    "  if(t.indexOf('sessao_invalida')>-1)return 'Sua sessão expirou. Saia e entre de novo.';\n"
    "  if(t.indexOf('sem_permissao')>-1)return 'Seu acesso a Conversas não permite esta ação.';\n"
    "  if(t.indexOf('optout')>-1)return 'Este contato pediu para não receber mensagens.';\n"
    "  return padrao;\n"
    "}\n"
    "function waEvo(c){return !!c&&c.conta_provider==='evolution';}\n"
    "function waTemCloud(){return WA.contas.some(function(x){return x.provider!=='evolution';});}\n")

# Evolution não tem janela de 24h
rep("function waJanela(c){\n", "function waJanela(c){\n  if(waEvo(c))return {aberta:true,evo:true,txt:''};\n")

# abrir a aba: painel por RPC (contas da unidade + templates)
i = s.index("async function openConversas(){")
j = s.index("async function waCarregar(render){")
assert s.count("async function openConversas(){") == 1
s = s[:i] + """async function openConversas(){
  $('stats').innerHTML='';
  $('board').innerHTML='<div class="loading">Carregando conversas...</div>';
  let p=null;
  try{p=await waRpc('crm_wa_painel');}
  catch(e){
    $('board').innerHTML='<div class="pane"><div class="loading">'+esc(waErro(e,'Não foi possível abrir as conversas.'))+'</div></div>';
    return;
  }
  WA.contas=(p&&p.contas)||[];
  WA.templates=(p&&p.templates)||[];
  if(WA.contaSel&&!WA.contas.some(function(c){return c.id===WA.contaSel;}))WA.contaSel=null;
  if(!WA.contas.length){
    $('board').innerHTML='<div class="pane"><div class="loading">'
      +'Nenhum número de WhatsApp ativo em '+esc(UN().nome)+'.<br><br>'
      +'Quando o número da unidade for conectado e ativado, as conversas aparecem aqui.'
      +'</div></div>';
    return;
  }
  await waFila();
  await waCarregar(true);
  waStartPoll();
}

""" + s[j:]

rep("""    WA.conversas=await api('/crm_wa_conversas?select=*,lead:crm_leads(id,nome,etapa,responsavel)'
      +'&order=ultima_mensagem_em.desc.nullslast&limit=300');""",
    """    WA.conversas=(await waRpc('crm_wa_conversas_listar',{p_conta_id:WA.contaSel||null,p_limite:300}))||[];""")

rep("""    WA.msgs=await api('/crm_wa_mensagens?select=*&conversa_id=eq.'+id+'&order=wa_timestamp.asc&limit=400');""",
    """    WA.msgs=(await waRpc('crm_wa_mensagens_listar',{p_conversa_id:id,p_limite:400}))||[];""")

# filtro "Janela aberta" só existe se houver número da Cloud API; filtro por número com 2+ contas
rep("""    +['todas|Todas','nao|Não lidas','minhas|Minhas','abertas|Janela aberta'].map(function(o){
      const p=o.split('|');
      return '<button data-f="'+p[0]+'"'+(WA.filtro===p[0]?' class="on"':'')+'>'+p[1]+'</button>';
    }).join('')+'</div>';""",
    """    +['todas|Todas','nao|Não lidas','minhas|Minhas'].concat(waTemCloud()?['abertas|Janela aberta']:[]).map(function(o){
      const p=o.split('|');
      return '<button data-f="'+p[0]+'"'+(WA.filtro===p[0]?' class="on"':'')+'>'+p[1]+'</button>';
    }).join('')
    +(WA.contas.length>1?'<select class="wacontasel" id="waconta" aria-label="Número"><option value="">Todos os números</option>'
      +WA.contas.map(function(c){return '<option value="'+esc(c.id)+'"'+(WA.contaSel===c.id?' selected':'')+'>'+esc(c.rotulo||waFmtNum(c.numero_e164))+'</option>';}).join('')
      +'</select>':'')
    +'</div>';""")

rep("""        +'<span class="p">'+esc(c.ultima_previa||'Sem mensagens')+'</span></span>'""",
    """        +'<span class="p">'+esc(c.ultima_previa||'Sem mensagens')+'</span>'
        +(WA.contas.length>1?'<span class="waselo">'+esc(c.conta_rotulo||waFmtNum(c.conta_numero))+'</span>':'')+'</span>'""")

rep("""(j.aberta?'<span class="waj ok">24h</span>':'')""", """(j.aberta&&!j.evo?'<span class="waj ok">24h</span>':'')""")

rep("""      +'<span class="waj '+(j.aberta?'ok':'off')+'">'+esc(j.txt)+'</span>'""",
    """      +(j.evo?(WA.contas.length>1?'<span class="waselo">'+esc(sel.conta_rotulo||'')+'</span>':''):'<span class="waj '+(j.aberta?'ok':'off')+'">'+esc(j.txt)+'</span>')""")

# templates só do número da conversa
rep("""      if(WA.templates.length){""",
    """      const tpls=WA.templates.filter(function(t){return !t.conta_id||t.conta_id===sel.conta_id;});
      if(tpls.length){""")
rep("""          +WA.templates.map(function(t){return""", """          +tpls.map(function(t){return""")

# ligar o filtro por número
rep("""  document.querySelectorAll('.wafiltros button').forEach(function(b){""",
    """  const wc=$('waconta');
  if(wc)wc.onchange=function(){WA.contaSel=wc.value||null;WA.sel=null;WA.msgs=[];waCarregar(true);};
  document.querySelectorAll('.wafiltros button').forEach(function(b){""")

rep("""    api('/crm_wa_conversas?id=eq.'+id,{method:'PATCH',body:JSON.stringify({nao_lidas:0,atendente_id:meuId()})}).catch(function(){});""",
    """    waRpc('crm_wa_conversa_abrir',{p_conversa_id:id}).catch(function(){});""")

# envio: autor vem da sessão no servidor
rep("""      template:template||null,
      autor_id:meuId()
    });""", """      template:template||null
    });""")
rep("""    else toast('Não foi possível enviar: '+(e.message||e));
    await waCarregar();""", """    else toast(waErro(e,'Não foi possível enviar: '+(e.message||e)));
    await waCarregar();""")

rep("""    const r=await waFn('wa-media',{mensagem_id:msgId});""", """    const r=await waFn('wa-media',{mensagem_id:msgId});""")

rep("""      await api('/crm_wa_conversas?id=eq.'+c.id,{method:'PATCH',body:JSON.stringify({lead_id:novo.id})});""",
    """      await waRpc('crm_wa_conversa_vincular_lead',{p_conversa_id:c.id,p_lead_id:novo.id});""")

rep("""  api('/crm_wa_conversas?select=nao_lidas&nao_lidas=gt.0').then(function(r){
    setNavBadge((r||[]).reduce(function(a,c){return a+(c.nao_lidas||0);},0));
  }).catch(function(){});""",
    """  if(!sessTok())return;
  waRpc('crm_wa_nao_lidas').then(function(n){setNavBadge(Number(n)||0);}).catch(function(){});""")

rep("""    WA.fila=await api('/crm_wa_fila?select=*,lead:crm_leads(id,nome,whatsapp),regra:crm_wa_regras(chave,nome,categoria)'
      +'&status=eq.sugerido&order=agendado_para.asc&limit=100');""",
    """    WA.fila=(await waRpc('crm_wa_fila_listar',{p_limite:100}))||[];""")

rep("""  const body={autor_id:meuId()};
  if(f.conversa_id)body.conversa_id=f.conversa_id;
  else body.wa_id=(f.lead&&f.lead.whatsapp)||f.wa_chave;""",
    """  const body={};
  if(f.conversa_id)body.conversa_id=f.conversa_id;
  else{body.wa_id=(f.lead&&f.lead.whatsapp)||f.wa_chave;if(WA.contaSel)body.conta_id=WA.contaSel;}""")

rep("""    await api('/crm_wa_fila?id=eq.'+id,{method:'PATCH',body:JSON.stringify({
      status:'enviado',decidido_por:currentUser,decidido_em:new Date().toISOString(),
      mensagem_id:r.mensagem_id||null
    })});""",
    """    await waRpc('crm_wa_fila_decidir',{p_id:id,p_status:'enviado',p_mensagem_id:r.mensagem_id||null});""")
rep("""    toast('Não foi possível enviar: '+(e.message||e));
    btn.disabled=false;btn.textContent='Enviar';""",
    """    toast(waErro(e,'Não foi possível enviar: '+(e.message||e)));
    btn.disabled=false;btn.textContent='Enviar';""")

rep("""    await api('/crm_wa_fila?id=eq.'+id,{method:'PATCH',body:JSON.stringify({
      status:'descartado',decidido_por:currentUser,decidido_em:new Date().toISOString()
    })});""",
    """    await waRpc('crm_wa_fila_decidir',{p_id:id,p_status:'descartado'});""")

# nada de acesso direto às crm_wa_* sobrou
import re
resto = re.findall(r"api\('/crm_wa_[a-z_]+", s)
assert not resto, resto

open(p, 'w', encoding='utf-8').write(s)
print('ok')
