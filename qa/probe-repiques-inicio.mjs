import { chromium } from 'playwright';
const FILE='file://'+process.argv[2];
const W=+process.argv[3]||1440;
const b=await chromium.launch();
const ctx=await b.newContext({viewport:{width:W,height:900}});
const json=(r,x)=>r.fulfill({status:200,contentType:'application/json',body:JSON.stringify(x)});
await ctx.route('**/*supabase.co/**',r=>json(r,[]));
const p=await ctx.newPage();
const errs=[];p.on('pageerror',e=>errs.push(e.message));
await p.goto(FILE);await p.waitForTimeout(1200);
const out=await p.evaluate(()=>{
  const h=hojeISO();
  const mk=(id,d,hora,extra)=>Object.assign({tab:'leads',id,nome:'Lead '+id,whatsapp:'21999990000',data:addDias(h,d),hora,rot:'Cliente B2C',etapa:'Respondeu',canal:'whatsapp',curso:'Inglês',tent:1},extra||{});
  document.getElementById('login').classList.add('off');currentUser='Admin QA';tab='inicio';INI.dia={kpis:{}};INI.serie=[];
  AGITENS=[mk('a1',-1,'10:00'),mk('a2',-2,'09:00'),mk('a3',-5,'09:00'),mk('a4',-20,'09:00'),mk('a5',-45,'09:00'),mk('a6',-60,'09:00'),
    mk('h1',0,'00:01'),mk('h2',0,'23:59'),mk('p1',1,'09:00'),mk('p2',2,'14:00'),mk('p3',6,'09:00'),
    {tab:'escolas',id:'e1',nome:'Escola X',data:addDias(h,-3),hora:'09:00',rot:'Escola',etapa:'Contato'},
    mk('pv1',-1,'09:00',{pv:true,rot:'Pós-venda'}),mk('pv2',20,'09:00',{pv:true,rot:'Pós-venda'})];
  bucketAlerts();renderInicio();
  const q=s=>Array.from(document.querySelectorAll(s));
  const col=id=>{const c=document.querySelector('.repcol[data-rc="'+id+'"]');return {n:c.querySelector('h4 span').textContent,rows:Array.from(c.querySelectorAll('.drow')).map(r=>r.dataset.id),vis:getComputedStyle(c).display};};
  return {cnt:(document.querySelector('.repcnt')||{}).textContent,atr:col('atr'),hoje:col('hoje'),prox:col('prox'),
    faixas:q('.repfx').map(d=>[d.querySelector('summary').textContent,d.open]),
    dias:q('.repdia').map(d=>d.textContent),
    outros:(q('.rcard h3').map(x=>x.textContent).find(t=>t.startsWith('Pós-venda'))||''),
    badge:ALERTS.total,modalProx:ALERTS.proximos.map(x=>x.id),adiante:ALERTS.adiante.map(x=>x.id),
    tabsVis:getComputedStyle(document.querySelector('.reptabs')).display};
});
console.log(JSON.stringify(out,null,1));
if(W<800){await p.click('.reptabs button[data-rt="prox"]');console.log(await p.evaluate(()=>Array.from(document.querySelectorAll('.repcol')).map(c=>c.dataset.rc+':'+getComputedStyle(c).display)));}
await p.screenshot({path:'./shot'+W+'.png',fullPage:false,clip:undefined});
const el=await p.$('.repcard');await el.screenshot({path:'./card'+W+'.png'});
console.log('errs',errs);await b.close();
