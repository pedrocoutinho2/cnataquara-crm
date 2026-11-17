// wa-evolution-importar v4 · importa o histórico de uma instância da Evolution para o CRM (uso pontual).
// 16/11/2026: Jardim América, últimos 30 dias (decisão do Pedro), sem grupos, status e canais.
// Autenticação: token de sessão do CRM (no corpo) com visão da unidade inteira (crm_wa_ve_tudo) e
// unidade da sessão igual à da conta. Falha fechado.
// Corpo: { conta_id | instancia, dias (1..90, padrão 30), simular (padrão true), pagina_inicial?, max_paginas? }
// Regras: mensagem já existente (wa_message_id) é pulada; conversa nova nasce pelo trigger de
// atribuição (lead da unidade -> responsável, senão rodízio); no fim, as conversas tocadas ficam
// como lidas (histórico não vira "não lida" para a equipe).
// v3 (16/11/2026): etiquetas do WhatsApp Business com o nome do consultor definem o dono da conversa.
//   { acao: 'etiquetas', simular } lê /label/findLabels + /chat/findChats e reatribui as conversas que
//   não foram transferidas à mão (atribuicao <> 'manual'). Na importação, conversa nova já nasce com o
//   dono da etiqueta. Etiqueta que não casa com nenhum agente é só relatada.
// v4 (16/11/2026): { acao: 'finalizar' } depois da importação (e das etiquetas):
//   - conversa sem lead vira lead (crm_wa_leads_do_historico: liga ao lead do mesmo número se existir;
//     senão cria com a data do primeiro contato, etapa pela conversa e próximo atendimento no dia
//     seguinte à última mensagem, 10h, para não nascer tudo vencido)
//   - garante MESSAGES_EDITED e MESSAGES_DELETE no webhook da instância (edição e exclusão feitas no
//     celular chegam ao CRM), mantendo url, headers e os eventos que já existiam
// v5 (17/11/2026): 'finalizar' também lê a agenda (/chat/findContacts -> crm_wa_conversas.nome_contato,
//   e o banco atualiza o nome dos leads automáticos), assina CONTACTS_UPSERT/CONTACTS_UPDATE e liga
//   syncFullHistory na instância (vale na próxima conexão por QR: é o que traz o histórico completo).
//   Número de sistema (menos de 10 dígitos, ex.: 0@s.whatsapp.net) é ignorado.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const EVO_URL = (Deno.env.get('EVO_URL') ?? 'https://evo.cnataquara.com.br').replace(/\/+$/, '');

// deno-lint-ignore no-explicit-any
type J = Record<string, any>;

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
function json(b: unknown, status = 200) {
  return new Response(JSON.stringify(b), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });
}
function chave(num: string | null | undefined): string | null {
  let d = (num ?? '').replace(/\D/g, '');
  if (d.length >= 12 && d.startsWith('55')) d = d.slice(2);
  if (d.length < 10) return null;
  return d.slice(0, 2) + d.slice(-8);
}
function numeroDoJid(key: J, r: J): { numero: string | null; ignorar: string | null } {
  const jid: string = key?.remoteJid ?? '';
  if (jid.endsWith('@g.us')) return { numero: null, ignorar: 'grupo' };
  if (jid === 'status@broadcast') return { numero: null, ignorar: 'status' };
  if (jid.endsWith('@newsletter') || jid.endsWith('@broadcast')) return { numero: null, ignorar: 'canal' };
  const curto = (n: string) => n.length < 10 ? { numero: null, ignorar: 'sistema' } : { numero: n, ignorar: null };
  if (jid.endsWith('@s.whatsapp.net')) return curto(jid.split('@')[0].replace(/\D/g, ''));
  const alt: string = key?.remoteJidAlt ?? key?.senderPn ?? r?.senderPn ?? '';
  if (alt.includes('@s.whatsapp.net')) return curto(alt.split('@')[0].replace(/\D/g, ''));
  return { numero: null, ignorar: 'sem_numero' };
}
function tsSeg(v: unknown): number {
  if (typeof v === 'number') return v;
  if (typeof v === 'string') return Number(v);
  if (v && typeof v === 'object' && 'low' in (v as J)) return Number((v as J).low) >>> 0;
  return 0;
}
type Info = { tipo: string; texto: string | null; mime: string | null; nome: string | null; midia: boolean; contexto: string | null } | null;
function extrair(msg: J | undefined): Info {
  if (!msg) return null;
  let m = msg;
  for (const env of ['ephemeralMessage', 'viewOnceMessage', 'viewOnceMessageV2', 'documentWithCaptionMessage', 'editedMessage']) {
    if (m[env]?.message) m = m[env].message;
  }
  const ctx = (o: J | undefined) => o?.contextInfo?.stanzaId ?? null;
  if (typeof m.conversation === 'string') return { tipo: 'texto', texto: m.conversation, mime: null, nome: null, midia: false, contexto: null };
  if (m.extendedTextMessage) return { tipo: 'texto', texto: m.extendedTextMessage.text ?? null, mime: null, nome: null, midia: false, contexto: ctx(m.extendedTextMessage) };
  const midias: Array<[string, string]> = [['imageMessage', 'imagem'], ['videoMessage', 'video'], ['audioMessage', 'audio'], ['documentMessage', 'documento'], ['stickerMessage', 'sticker']];
  for (const [k, tipo] of midias) if (m[k]) return { tipo, texto: m[k].caption ?? null, mime: m[k].mimetype ?? null, nome: m[k].fileName ?? null, midia: true, contexto: ctx(m[k]) };
  if (m.locationMessage) { const l = m.locationMessage; return { tipo: 'localizacao', texto: [l.name, l.address, `${l.degreesLatitude},${l.degreesLongitude}`].filter(Boolean).join(' | '), mime: null, nome: null, midia: false, contexto: null }; }
  if (m.contactMessage) return { tipo: 'contato', texto: m.contactMessage.displayName ?? null, mime: null, nome: null, midia: false, contexto: null };
  if (m.contactsArrayMessage) return { tipo: 'contato', texto: (m.contactsArrayMessage.contacts ?? []).map((c: J) => c?.displayName).filter(Boolean).join(', '), mime: null, nome: null, midia: false, contexto: null };
  if (m.buttonsResponseMessage) return { tipo: 'interativo', texto: m.buttonsResponseMessage.selectedDisplayText ?? null, mime: null, nome: null, midia: false, contexto: null };
  if (m.listResponseMessage) return { tipo: 'interativo', texto: m.listResponseMessage.title ?? null, mime: null, nome: null, midia: false, contexto: null };
  if (m.reactionMessage || m.protocolMessage || m.senderKeyDistributionMessage || (m.messageContextInfo && Object.keys(m).length === 1)) return null;
  const k = Object.keys(m).find((x) => x !== 'messageContextInfo') ?? 'desconhecido';
  return { tipo: 'sistema', texto: `[${k}]`, mime: null, nome: null, midia: false, contexto: null };
}

function norm(v: unknown): string {
  return String(v ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().trim();
}
type Agente = { usuario_id: string; nome: string };
function casaAgente(etiqueta: string, agentes: Agente[]): Agente | null {
  const e = norm(etiqueta);
  if (!e) return null;
  const achados = agentes.filter((a) => {
    const primeiro = norm(a.nome).split(/\s+/)[0];
    const completo = norm(a.nome);
    return e === completo || e === primeiro || (e.length >= 3 && primeiro.startsWith(e))
      || e.split(/[\s\-_/]+/).includes(primeiro);
  });
  return achados.length === 1 ? achados[0] : null;
}
async function lerEtiquetas(conta: J, tk: string, agentes: Agente[]) {
  const inst = encodeURIComponent(conta.evolution_instancia);
  const h = { apikey: tk, 'Content-Type': 'application/json' };
  const rl = await fetch(`${EVO_URL}/label/findLabels/${inst}`, { headers: h });
  const labels: J[] = rl.ok ? await rl.json().catch(() => []) : [];
  if (!rl.ok) throw new Error(`evolution_labels_http_${rl.status}`);
  const rc = await fetch(`${EVO_URL}/chat/findChats/${inst}`, { method: 'POST', headers: h, body: JSON.stringify({}) });
  const chatsResp = rc.ok ? await rc.json().catch(() => []) : [];
  if (!rc.ok) throw new Error(`evolution_chats_http_${rc.status}`);
  const chats: J[] = Array.isArray(chatsResp) ? chatsResp : (chatsResp?.records ?? chatsResp?.chats ?? []);
  const nomeDe = new Map<string, string>();
  for (const l of Array.isArray(labels) ? labels : []) nomeDe.set(String(l.id ?? l.labelId ?? ''), String(l.name ?? ''));
  const resumo = new Map<string, { etiqueta: string; agente: string | null; conversas: number }>();
  for (const [, nome] of nomeDe) resumo.set(nome, { etiqueta: nome, agente: casaAgente(nome, agentes)?.nome ?? null, conversas: 0 });
  const porNumero = new Map<string, Agente>();
  let semNumero = 0, ambiguas = 0;
  for (const c of chats) {
    const ls: unknown[] = Array.isArray(c.labels) ? c.labels : [];
    if (!ls.length) continue;
    const nomes = ls.map((x) => typeof x === 'object' && x ? String((x as J).name ?? nomeDe.get(String((x as J).id)) ?? '') : (nomeDe.get(String(x)) ?? ''))
      .filter(Boolean);
    nomes.forEach((n) => { const r = resumo.get(n) ?? { etiqueta: n, agente: casaAgente(n, agentes)?.nome ?? null, conversas: 0 }; r.conversas++; resumo.set(n, r); });
    const ags = [...new Set(nomes.map((n) => casaAgente(n, agentes)).filter(Boolean).map((a) => a!.usuario_id))];
    if (ags.length !== 1) { if (ags.length > 1) ambiguas++; continue; }
    const { numero } = numeroDoJid({ remoteJid: c.remoteJid ?? c.id, remoteJidAlt: c.remoteJidAlt }, c);
    if (!numero) { semNumero++; continue; }
    porNumero.set(numero, agentes.find((a) => a.usuario_id === ags[0])!);
  }
  return { porNumero, resumo: [...resumo.values()].sort((a, b) => b.conversas - a.conversas), semNumero, ambiguas, total_chats: chats.length };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ erro: 'method not allowed' }, 405);
  let b: J; try { b = await req.json(); } catch { return json({ erro: 'json invalido' }, 400); }
  if (typeof b.token !== 'string' || !/^[0-9a-f-]{36}$/i.test(b.token)) return json({ erro: 'sessao_invalida' }, 401);
  const { data: s, error: es } = await db.rpc('crm_wa_sessao', { p_token: b.token, p_min: 2 });
  if (es || !s) return json({ erro: 'sessao_invalida' }, 401);
  const { data: vt } = await db.rpc('crm_wa_ve_tudo', { p_usuario: s.usuario_id, p_unidade: s.unidade });
  if (!vt) return json({ erro: 'sem_permissao' }, 403);
  const instancia = String(b.instancia ?? '');
  const dias = Math.min(Math.max(Number(b.dias ?? 30), 1), 365);
  const simular = b.simular !== false;
  const pagIni = Math.max(Number(b.pagina_inicial ?? 1), 1);
  const maxPag = Math.min(Math.max(Number(b.max_paginas ?? 5), 1), 40);
  const corte = Math.floor(Date.now() / 1000) - dias * 86400;

  let q = db.from('crm_wa_contas').select('*').eq('provider', 'evolution');
  q = b.conta_id ? q.eq('id', String(b.conta_id)) : q.eq('evolution_instancia', instancia);
  const { data: conta } = await q.maybeSingle();
  if (!conta || conta.unidade !== s.unidade) return json({ erro: 'conta_nao_encontrada' }, 404);
  const tk = conta.token_ref ? (Deno.env.get(conta.token_ref) ?? '') : '';
  if (!tk) return json({ erro: 'conta_sem_token' }, 500);

  const { data: ags } = await db.rpc('crm_wa_agentes', { p_unidade: conta.unidade });
  const agentes: Agente[] = (ags ?? []).map((a: J) => ({ usuario_id: a.usuario_id, nome: a.nome }));

  if (b.acao === 'finalizar') {
    const out: J = { ok: true, acao: 'finalizar', simular };
    if (simular) {
      const { count } = await db.from('crm_wa_conversas').select('id', { count: 'exact', head: true }).eq('conta_id', conta.id).is('lead_id', null);
      out.conversas_sem_lead = count;
    } else {
      const { data: n, error } = await db.rpc('crm_wa_leads_do_historico', { p_conta: conta.id });
      out.leads_criados = error ? null : n;
      if (error) out.erro_leads = error.message;
    }
    try {
      const inst = encodeURIComponent(conta.evolution_instancia);
      const h = { apikey: tk, 'Content-Type': 'application/json' };
      const rf = await fetch(`${EVO_URL}/webhook/find/${inst}`, { headers: h });
      const w: J = rf.ok ? await rf.json().catch(() => ({})) : {};
      if (!rf.ok || !w?.url) throw new Error(`webhook_find_http_${rf.status}`);
      const atuais: string[] = Array.isArray(w.events) ? w.events : [];
      const faltam = ['MESSAGES_EDITED', 'MESSAGES_DELETE', 'CONTACTS_UPSERT', 'CONTACTS_UPDATE'].filter((e) => !atuais.includes(e));
      out.webhook_eventos_antes = atuais;
      if (faltam.length && !simular) {
        const eventos = [...atuais, ...faltam];
        const rs = await fetch(`${EVO_URL}/webhook/set/${inst}`, { method: 'POST', headers: h, body: JSON.stringify({ webhook: {
          enabled: w.enabled !== false, url: w.url, headers: w.headers ?? {}, byEvents: !!(w.webhookByEvents ?? w.byEvents),
          base64: !!(w.webhookBase64 ?? w.base64), events: eventos } }) });
        if (!rs.ok) throw new Error(`webhook_set_http_${rs.status}`);
        const rv = await fetch(`${EVO_URL}/webhook/find/${inst}`, { headers: h });
        const v: J = rv.ok ? await rv.json().catch(() => ({})) : {};
        out.webhook_eventos_depois = v?.events ?? null;
        out.webhook_url_mantida = v?.url === w.url;
      } else out.webhook_faltam = faltam;
    } catch (e) { out.erro_webhook = String((e as Error).message); }
    const inst = encodeURIComponent(conta.evolution_instancia);
    const h = { apikey: tk, 'Content-Type': 'application/json' };
    // agenda do celular
    try {
      const rc = await fetch(`${EVO_URL}/chat/findContacts/${inst}`, { method: 'POST', headers: h, body: JSON.stringify({ where: {} }) });
      const lista: J[] = rc.ok ? await rc.json().catch(() => []) : [];
      if (!rc.ok) throw new Error(`contatos_http_${rc.status}`);
      const { data: convs } = await db.from('crm_wa_conversas').select('id, wa_id, nome_contato').eq('conta_id', conta.id);
      const porNum = new Map((convs ?? []).map((c: J) => [c.wa_id, c]));
      let nomes = 0;
      for (const ct of Array.isArray(lista) ? lista : []) {
        const { numero } = numeroDoJid({ remoteJid: ct.remoteJid ?? ct.id ?? '' }, ct);
        const nome = String(ct.name ?? ct.pushName ?? '').trim();
        const c = numero ? porNum.get(numero) : null;
        if (!c || !nome || nome.replace(/\D/g, '') === numero || c.nome_contato === nome) continue;
        if (!simular) await db.from('crm_wa_conversas').update({ nome_contato: nome }).eq('id', c.id);
        nomes++;
      }
      out.contatos_lidos = Array.isArray(lista) ? lista.length : 0;
      out.nomes_da_agenda = nomes;
    } catch (e) { out.erro_contatos = String((e as Error).message); }
    // histórico completo na próxima conexão
    try {
      const rs = await fetch(`${EVO_URL}/settings/find/${inst}`, { headers: h });
      const st: J = rs.ok ? await rs.json().catch(() => ({})) : {};
      if (!rs.ok) throw new Error(`settings_find_http_${rs.status}`);
      out.sync_full_history_antes = !!st.syncFullHistory;
      if (!st.syncFullHistory && !simular) {
        const corpo = { rejectCall: !!st.rejectCall, msgCall: st.msgCall ?? '', groupsIgnore: !!st.groupsIgnore,
          alwaysOnline: !!st.alwaysOnline, readMessages: !!st.readMessages, readStatus: !!st.readStatus, syncFullHistory: true };
        const rw = await fetch(`${EVO_URL}/settings/set/${inst}`, { method: 'POST', headers: h, body: JSON.stringify(corpo) });
        if (!rw.ok) throw new Error(`settings_set_http_${rw.status}`);
        out.sync_full_history_depois = true;
      }
    } catch (e) { out.erro_settings = String((e as Error).message); }
    return json(out);
  }

  if (b.acao === 'etiquetas') {
    let et;
    try { et = await lerEtiquetas(conta, tk, agentes); } catch (e) { return json({ erro: String((e as Error).message) }, 502); }
    let aplicadas = 0, ja_certas = 0, manuais = 0, fora_do_crm = 0;
    for (const [numero, ag] of et.porNumero) {
      const { data: c } = await db.from('crm_wa_conversas').select('id, atendente_id, atribuicao').eq('conta_id', conta.id).eq('wa_id', numero).maybeSingle();
      if (!c) { fora_do_crm++; continue; }
      if (c.atendente_id === ag.usuario_id) { ja_certas++; continue; }
      if (c.atribuicao === 'manual') { manuais++; continue; }
      if (!simular) await db.from('crm_wa_conversas').update({ atendente_id: ag.usuario_id, atribuicao: 'etiqueta', atribuida_em: new Date().toISOString() }).eq('id', c.id);
      aplicadas++;
    }
    return json({ ok: true, simular, acao: 'etiquetas', etiquetas: et.resumo, conversas_com_dono_pela_etiqueta: et.porNumero.size,
      aplicadas, ja_certas, mantidas_por_transferencia_manual: manuais, ainda_nao_estao_no_crm: fora_do_crm,
      ambiguas: et.ambiguas, sem_numero: et.semNumero, total_chats: et.total_chats });
  }

  let mapaEtiqueta = new Map<string, Agente>();
  try { mapaEtiqueta = (await lerEtiquetas(conta, tk, agentes)).porNumero; } catch (_) { /* sem etiquetas: segue pelo rodízio */ }

  const cont: J = { paginas: 0, total_evolution: null, lidas: 0, no_periodo: 0, fora_do_periodo: 0, ignoradas: {}, ja_existiam: 0, inseridas: 0, conversas_novas: 0, erros: [] as string[] };
  const convCache = new Map<string, string>();
  const tocadas = new Set<string>();
  let amostra: J | null = null;
  let proxima: number | null = null;
  let parouPorIdade = false;

  for (let p = pagIni; p < pagIni + maxPag; p++) {
    const r = await fetch(`${EVO_URL}/chat/findMessages/${encodeURIComponent(conta.evolution_instancia)}`, {
      method: 'POST', headers: { apikey: tk, 'Content-Type': 'application/json' },
      body: JSON.stringify({ where: {}, page: p, offset: 500 }),
    });
    const resp = await r.json().catch(() => ({}));
    if (!r.ok) { cont.erros.push(`evolution_http_${r.status}`); break; }
    const pac = resp?.messages ?? resp;
    const regs: J[] = Array.isArray(pac?.records) ? pac.records : (Array.isArray(pac) ? pac : []);
    cont.total_evolution = pac?.total ?? cont.total_evolution;
    cont.paginas++;
    if (!amostra && regs[0]) amostra = { chaves: Object.keys(regs[0]), key: Object.keys(regs[0].key ?? {}), ts: regs[0].messageTimestamp };
    if (!regs.length) break;

    let todasVelhas = true;
    const ids = regs.map((x) => x?.key?.id).filter(Boolean);
    const { data: existentes } = await db.from('crm_wa_mensagens').select('wa_message_id').in('wa_message_id', ids);
    const ja = new Set((existentes ?? []).map((x: J) => x.wa_message_id));

    for (const rg of regs) {
      cont.lidas++;
      const t = tsSeg(rg.messageTimestamp);
      if (t < corte) { cont.fora_do_periodo++; continue; }
      todasVelhas = false;
      cont.no_periodo++;
      const key = rg.key ?? {};
      const { numero, ignorar } = numeroDoJid(key, rg);
      if (ignorar || !numero) { cont.ignoradas[ignorar ?? 'sem_numero'] = (cont.ignoradas[ignorar ?? 'sem_numero'] ?? 0) + 1; continue; }
      const info = extrair(rg.message);
      if (!info) { cont.ignoradas.sem_conteudo = (cont.ignoradas.sem_conteudo ?? 0) + 1; continue; }
      if (key.id && ja.has(key.id)) { cont.ja_existiam++; continue; }
      if (simular) { cont.inseridas++; continue; }

      try {
        let convId = convCache.get(numero);
        if (!convId) {
          const { data: ex } = await db.from('crm_wa_conversas').select('id').eq('conta_id', conta.id).eq('wa_id', numero).maybeSingle();
          if (ex) convId = ex.id;
          else {
            const k = chave(numero);
            let leadId: string | null = null; let amb = false;
            if (k) {
              const { data: leads } = await db.from('crm_leads').select('id').eq('wa_chave', k).eq('unidade', conta.unidade).order('created_at', { ascending: false });
              if (leads?.length) { leadId = leads[0].id; amb = leads.length > 1; }
            }
            const { data: nova, error } = await db.from('crm_wa_conversas').insert({
              conta_id: conta.id, wa_id: numero, numero_e164: '+' + numero, wa_chave: k,
              nome_perfil: key.fromMe ? null : (rg.pushName ?? null), lead_id: leadId, lead_ambiguo: amb,
              ...(mapaEtiqueta.has(numero) ? { atendente_id: mapaEtiqueta.get(numero)!.usuario_id, atribuicao: 'etiqueta', atribuida_em: new Date().toISOString() } : {}),
            }).select('id').single();
            if (error?.code === '23505') {
              const { data: o } = await db.from('crm_wa_conversas').select('id').eq('conta_id', conta.id).eq('wa_id', numero).single();
              convId = o!.id;
            } else if (error) throw error;
            else { convId = nova.id; cont.conversas_novas++; }
          }
          convCache.set(numero, convId!);
        }
        tocadas.add(convId!);
        const { error } = await db.from('crm_wa_mensagens').insert({
          conversa_id: convId, direcao: key.fromMe ? 'saida' : 'entrada', tipo: info.tipo, texto: info.texto,
          midia_path: info.midia && key.id ? `evo:${key.id}` : null, midia_mime: info.mime, midia_nome: info.nome,
          wa_message_id: key.id ?? null, responde_a: info.contexto,
          status: key.fromMe ? 'enviado' : 'entregue', wa_timestamp: new Date(t * 1000).toISOString(),
        });
        if (error && error.code !== '23505') throw error;
        if (error) cont.ja_existiam++; else cont.inseridas++;
      } catch (e) {
        if (cont.erros.length < 10) cont.erros.push(String((e as Error)?.message ?? e).slice(0, 200));
      }
    }
    proxima = p + 1;
    if (todasVelhas) { parouPorIdade = true; proxima = null; break; }
    if (regs.length < 500) { proxima = null; break; }
  }

  // histórico não vira "não lida"
  if (!simular && tocadas.size) {
    await db.from('crm_wa_conversas').update({ nao_lidas: 0 }).in('id', [...tocadas]);
  }
  return json({ ok: true, simular, instancia: conta.evolution_instancia, dias, ...cont, parou_por_idade: parouPorIdade, proxima_pagina: proxima, amostra });
});
