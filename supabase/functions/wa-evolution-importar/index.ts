// wa-evolution-importar · importa o histórico de uma instância da Evolution para o CRM (uso pontual).
// 16/11/2026: Jardim América, últimos 30 dias (decisão do Pedro), sem grupos, status e canais.
// Autenticação: token de sessão do CRM (no corpo) com visão da unidade inteira (crm_wa_ve_tudo) e
// unidade da sessão igual à da conta. Falha fechado.
// Corpo: { conta_id | instancia, dias (1..90, padrão 30), simular (padrão true), pagina_inicial?, max_paginas? }
// Regras: mensagem já existente (wa_message_id) é pulada; conversa nova nasce pelo trigger de
// atribuição (lead da unidade -> responsável, senão rodízio); no fim, as conversas tocadas ficam
// como lidas (histórico não vira "não lida" para a equipe).
import { createClient } from 'jsr:@supabase/supabase-js@2';

const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const EVO_URL = (Deno.env.get('EVO_URL') ?? 'https://evo.cnataquara.com.br').replace(/\/+$/, '');

// deno-lint-ignore no-explicit-any
type J = Record<string, any>;

function json(b: unknown, status = 200) {
  return new Response(JSON.stringify(b), { status, headers: { 'Content-Type': 'application/json' } });
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
  if (jid.endsWith('@s.whatsapp.net')) return { numero: jid.split('@')[0].replace(/\D/g, ''), ignorar: null };
  const alt: string = key?.remoteJidAlt ?? key?.senderPn ?? r?.senderPn ?? '';
  if (alt.includes('@s.whatsapp.net')) return { numero: alt.split('@')[0].replace(/\D/g, ''), ignorar: null };
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

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ erro: 'method not allowed' }, 405);
  let b: J; try { b = await req.json(); } catch { return json({ erro: 'json invalido' }, 400); }
  if (typeof b.token !== 'string' || !/^[0-9a-f-]{36}$/i.test(b.token)) return json({ erro: 'sessao_invalida' }, 401);
  const { data: s, error: es } = await db.rpc('crm_wa_sessao', { p_token: b.token, p_min: 2 });
  if (es || !s) return json({ erro: 'sessao_invalida' }, 401);
  const { data: vt } = await db.rpc('crm_wa_ve_tudo', { p_usuario: s.usuario_id, p_unidade: s.unidade });
  if (!vt) return json({ erro: 'sem_permissao' }, 403);
  const instancia = String(b.instancia ?? '');
  const dias = Math.min(Math.max(Number(b.dias ?? 30), 1), 90);
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
