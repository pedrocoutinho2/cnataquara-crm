# Semestre de matricula (10/09/2026): lead novo so matricula em 2027.1.
# Uso: python3 qa/patch-turmas-semestre-matricula.py index.html
import sys
p=sys.argv[1]; s=open(p,encoding='utf-8').read(); orig=s
def sub(a,b,rotulo):
    global s
    n=s.count(a); assert n==1,(rotulo,n); s=s.replace(a,b)

# 1. ordem de niveis: PADV antes de ADV; B1.1 na lista canonica
sub("   com grafia mista (A1.1/FLY 1, PADV 1, YOUNG KIDS 3/FUN 3), entao o casamento e por padrao. */",
    "   com grafia mista (A1.1/FLY 1, PADV 1, YOUNG KIDS 3/FUN 3), entao o casamento e por padrao.\n   PADV (pre-advanced) vem ANTES de ADV: no mapa 2027.1, PADV 2 vira ADV 1 e ADV 2 vira MASTER 1. */",'coment nivel')
sub("  [/PADV\\s*(\\d)?/,800],[/(?:ADV\\w*|EXPANS\\w*)\\s*(\\d)?/,700],",
    "  [/PADV\\s*(\\d)?/,690],[/(?:ADV\\w*|EXPANS\\w*)\\s*(\\d)?/,700],",'PADV ordem')
sub("  'ADV 1','ADV 2','PADV 1','PADV 2','MASTER 1','MASTER 2',",
    "  'B1.1','PADV 1','PADV 2','ADV 1','ADV 2','MASTER 1','MASTER 2',",'T_NIVEIS')

# 2. semestre: em aulas (data) x matriculas (config)
old_sem=s[s.index("/* Semestre. O ATUAL sai da data"):s.index("function tVagas(t){")]
assert s.count(old_sem)==1
new_sem='''/* Semestre. Dois conceitos:
   - EM AULAS: sai da data (jan-jun = .1, jul-dez = .2). Vira sozinho, sem deploy.
   - MATRICULAS: onde lead novo matricula. Vem de crm_configs.turmas_semestre_matricula,
     trocado na tela do mapa por quem tem Turmas total. Config anterior ao semestre em
     aulas e ignorada (volta a regra da data), entao a config nunca prende a unidade no passado.
   Ficha do lead (campo Turma), dica de faixa, fila de espera e demanda por nivel usam o de
   MATRICULAS, via tSemRef(). Decisao 10/09/2026: matricula nova so em 2027.1. */
var TSEMMAT={v:null,ok:false};
async function tSemMatCarrega(force){
  if(TSEMMAT.ok&&!force)return TSEMMAT.v;
  try{
    var r=await api('/crm_configs?select=valor&chave=eq.turmas_semestre_matricula');
    TSEMMAT.v=(r&&r[0]&&r[0].valor)?String(r[0].valor).trim():null;
  }catch(e){TSEMMAT.v=null;}
  TSEMMAT.ok=true;
  return TSEMMAT.v;
}
function semVigente(){var d=new Date();return d.getFullYear()+'.'+(d.getMonth()<6?'1':'2');}
function tSemestres(rows){
  var out=[];
  (rows||[]).forEach(function(t){if(t&&t.semestre&&out.indexOf(t.semestre)<0)out.push(t.semestre);});
  return out.sort();
}
/* em aulas: o da data, se existir no mapa; senao o mais recente anterior a ele; senao o primeiro */
function tSemAulas(rows){
  var ss=tSemestres(rows),v=semVigente();
  if(!ss.length)return null;
  if(ss.indexOf(v)>-1)return v;
  var ant=ss.filter(function(x){return x<v;});
  return ant.length?ant[ant.length-1]:ss[0];
}
/* matriculas: a config, se o semestre existir no mapa e nao for anterior ao em aulas */
function tSemRef(rows){
  var ss=tSemestres(rows),c=TSEMMAT.v,v=semVigente();
  if(c&&ss.indexOf(c)>-1&&c>=v)return c;
  return tSemAulas(rows);
}
function tSemRotulo(x,mat,aulas){
  if(x===mat&&x===aulas)return 'atual';
  if(x===mat)return 'matrículas';
  if(x===aulas)return 'em aulas';
  return x>mat?'próximo':'anterior';
}
/* troca o semestre de matriculas (vale para toda a equipe) */
async function tSemMatSalvar(x){
  if(!podeTotal('turmas'))return;
  if(!confirm('A partir de agora, lead novo matricula só em turmas de '+x+'. O campo Turma da ficha, a dica de faixa, a fila de espera e a demanda por nível passam a usar o '+x+'. Confirmar?'))return;
  try{
    await api('/crm_configs',{method:'POST',
      headers:{'Prefer':'return=representation,resolution=merge-duplicates'},
      body:JSON.stringify({chave:'turmas_semestre_matricula',valor:x,
        descricao:'Semestre em que lead novo matricula (campo Turma da ficha, dica de faixa, fila de espera, demanda por nivel). Anterior ao semestre em aulas e ignorado.',
        atualizado_em:new Date().toISOString(),atualizado_por:meuId()})});
    TSEMMAT.v=x;TSEMMAT.ok=true;TCACHE=null;
    toast('Matrículas agora em '+x+'. Vale para toda a equipe.');
    renderTurmas();
  }catch(e){toast('Não foi possível salvar: '+(e&&e.message?e.message:e));}
}

'''
s=s.replace(old_sem,new_sem)

# 3. carregar a config antes de qualquer uso de tSemRef
sub("async function turmasCache(){\n  if(TCACHE)return TCACHE;",
    "async function turmasCache(){\n  await tSemMatCarrega();\n  if(TCACHE)return TCACHE;",'turmasCache')
sub("    TURMAS=await api('/crm_turmas?select=*&ativa=eq.true&order=dias.asc,horario.asc,sala.asc')||[];",
    "    await tSemMatCarrega(true);\n    TURMAS=await api('/crm_turmas?select=*&ativa=eq.true&order=dias.asc,horario.asc,sala.asc')||[];",'openTurmas load')
sub("    if(!DEMF.turmas||force)DEMF.turmas=",
    "    await tSemMatCarrega(!!force);\n    if(!DEMF.turmas||force)DEMF.turmas=",'DEMF')
sub("    if(!ESP.turmas||force)ESP.turmas=",
    "    await tSemMatCarrega(!!force);\n    if(!ESP.turmas||force)ESP.turmas=",'ESP')
# troca de unidade: cache de turmas e da config e por banco
sub("  AGITENS=[];AGVISTOS={};AGBOOT=false;renderAlertBadge();\n}\nasync function trocarUnidade(alvo){",
    "  AGITENS=[];AGVISTOS={};AGBOOT=false;renderAlertBadge();\n  TCACHE=null;TSEMMAT={v:null,ok:false};TURMAS=[];tSemestre='';DEMF.turmas=null;ESP.turmas=null;\n}\nasync function trocarUnidade(alvo){",'limpar unidade')

# 4. valor gravado na ficha leva o semestre; valor antigo mostra de qual semestre e
sub("function turmaValor(t){\n  return (t.curso||'?')+' · '+(t.dias||'')+' '+(t.horario||'')+' · '+(t.sala||'');\n}",
    "function turmaValorBase(t){\n  return (t.curso||'?')+' · '+(t.dias||'')+' '+(t.horario||'')+' · '+(t.sala||'');\n}\n"
    "/* a partir de 10/09/2026 o valor leva o semestre: o mesmo nivel/horario/sala pode existir em dois mapas */\n"
    "function turmaValor(t){\n  return turmaValorBase(t)+(t.semestre?' · '+t.semestre:'');\n}",'turmaValor')
sub("  if(atual&&!achou)h='<option value=\"'+esc(atual)+'\" selected>'+esc(atual)+' (fora do mapa)</option>'+h;",
    "  if(atual&&!achou){\n    var dono=rows.filter(function(t){return turmaValor(t)===atual||turmaValorBase(t)===atual;})[0];\n"
    "    var sfx=dono?' (turma de '+dono.semestre+(sem&&dono.semestre!==sem?', fora das matrículas':'')+')':' (fora do mapa)';\n"
    "    h='<option value=\"'+esc(atual)+'\" selected>'+esc(atual)+sfx+'</option>'+h;\n  }",'fora do mapa')

# 5. dica de faixa diz de qual semestre e a vaga
sub("    ?'<br>Com vaga hoje: <b>'+esc(lista)+'</b>'",
    "    ?'<br>Com vaga'+(sem&&sem!==semVigente()?' em '+esc(sem):' hoje')+': <b>'+esc(lista)+'</b>'",'dica')

# 6. tela do mapa: rotulos, aviso e botao de trocar o semestre de matriculas
sub("  var semRef=tSemRef(TURMAS.filter(function(t){return !t.__nova;}))||tSemestre;",
    "  var semRef=tSemRef(TURMAS.filter(function(t){return !t.__nova;}))||tSemestre;\n"
    "  var semAulas=tSemAulas(TURMAS.filter(function(t){return !t.__nova;}))||semRef;",'semAulas')
sub("+esc(x)+' <span class=\"tsemr\">'+esc(tSemRotulo(x,semRef))+'</span></button>';",
    "+esc(x)+' <span class=\"tsemr\">'+esc(tSemRotulo(x,semRef,semAulas))+'</span></button>';",'rotulo chip')
old_nota=s[s.index("  if(tSemestre!==semRef){\n    h+='<div class=\"tsemnota\">'"):s.index("  h+='<div class=\"tsum\">")]
assert s.count(old_nota)==1
new_nota='''  var usos='campo Turma da ficha, dica de faixa, fila de espera e demanda por nível';
  var podeMat=podeTotal('turmas')&&TURMAS.some(function(t){return t.semestre===tSemestre&&!t.__nova;})&&tSemestre>=semVigente();
  var nota='';
  if(tSemestre===semRef&&semRef!==semAulas){
    nota='Matrículas abertas para <b>'+esc(semRef)+'</b>: lead novo só entra em turma deste mapa ('+usos+'). O <b>'+esc(semAulas)+'</b> segue em aulas.';
  }else if(tSemestre!==semRef){
    nota=(tSemestre===semAulas?'Mapa de <b>'+esc(tSemestre)+'</b>, semestre em aulas.'
      :(tSemestre>semRef?'Mapa de <b>'+esc(tSemestre)+'</b> em planejamento.':'Mapa de <b>'+esc(tSemestre)+'</b>, semestre anterior.'))
      +' Matrícula nova vai para o <b>'+esc(semRef)+'</b> ('+usos+').';
  }
  if(nota){
    h+='<div class="tsemnota">'+nota;
    if(podeMat&&tSemestre!==semRef)h+=' <button class="btn" id="tmat" data-sem="'+esc(tSemestre)+'" style="margin-left:6px">Matricular em '+esc(tSemestre)+'</button>';
    h+='</div>';
  }
'''
s=s.replace(old_nota,new_nota)
sub("  var vg=$('tvaga');\n  if(vg)vg.onclick=function(){tSoVaga=!tSoVaga;renderTurmas();};",
    "  var vg=$('tvaga');\n  if(vg)vg.onclick=function(){tSoVaga=!tSoVaga;renderTurmas();};\n"
    "  var tm=$('tmat');\n  if(tm)tm.onclick=function(){tSemMatSalvar(tm.dataset.sem);};",'bind tmat')

assert s!=orig
open(p,'w',encoding='utf-8').write(s)
print('ok', len(orig),'->',len(s))
