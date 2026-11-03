// wa-evolution-webhook · recebe eventos da Evolution API (WhatsApp não oficial, fase 1).
// Decisões: 2026-10-03-whatsapp-api-nao-oficial-fase-1 (Evolution escolhida em 05/10/2026).
// Spec: 10-cna/sistemas/whatsapp-multinumero.md
//
// Configuração na Evolution, por instância (POST /webhook/set/{instancia}):
//   url: https://<projeto>.supabase.co/functions/v1/wa-evolution-webhook
//   byEvents: false · base64: false
//   headers: { "x-cna-token": <mesmo valor do secret EVO_TOKEN_* da conta> }
//   events: MESSAGES_UPSERT, MESSAGES_UPDATE, CONNECTION_UPDATE
//
// Regras: falha FECHADO (conta sem token configurado não recebe nada); lead procurado só na
// unidade da conta; grupo, status e canal ignorados; reentrega deduplicada pelo id da mensagem;
// o apikey que a Evolution manda no corpo nunca é gravado (o trigger do banco também remove).
import { createClient } from 'jsr:@supabase/supabase-js@2';

const db = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

type Conta = { id: string; unidade: string; token_ref: string | null; ativa: boolean };
// deno-lint-ignore no-explicit-any
type J = Record<string, any>;

// Mesma chave canônica da função SQL crm_wa_chave: DDD + 8 últimos dígitos
function chave(num: string | null | undefined): string | null {
  let d = (num ?? '').replace(/\D/g, '');
  if (d.length >= 12 && d.startsWith('55')) d = d.slice(2);
  if (d.length < 10) return null;
  return d.slice(0, 2) + d.slice(-8);
}

function iguais(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

// Número da conversa. JID de grupo, status e canal não viram conversa.
// Contas novas do WhatsApp podem vir como @lid (sem telefone): usa o alternativo se existir.
function numeroDoJid(key: J, data: J): { numero: string | null; ignorar: string | null } {
  const jid: string = key?.remoteJid ?? '';
  if (jid.endsWith('@g.us')) return { numero: null, ignorar: 'grupo' };
  if (jid === 'status@broadcast') return { numero: null, ignorar: 'status' };
  if (jid.endsWith('@newsletter') || jid.endsWith('@broadcast')) return { numero: null, ignorar: 'canal' };
  if (jid.endsWith('@s.whatsapp.net')) return { numero: jid.split('@')[0].replace(/\D/g, ''), ignorar: null };
  const alt: string = key?.remoteJidAlt ?? key?.senderPn ?? data?.senderPn ?? '';
  if (alt.includes('@s.whatsapp.net')) return { numero: alt.split('@')[0].replace(/\D/g, ''), ignorar: null };
  return { numero: null, ignorar: null };
}

function ts(v: unknown): string {
  // messageTimestamp em segundos (número, string ou Long {low, high})
  let s = 0;
  if (typeof v === 'number') s = v;
  else if (typeof v === 'string') s = Number(v);
  else if (v && typeof v === 'object' && 'low' in (v as J)) s = Number((v as J).low) >>> 0;
  return s > 0 ? new Date(s * 1000).toISOString() : new Date().toISOString();
}

type Info = { tipo: string; texto: string | null; mime: string | null; nome: string | null; midia: boolean; contexto: string | null } | null;

function extrair(msg: J | undefined): Info {
  if (!msg) return null;
  let m = msg;
  // envelopes que só embrulham a mensagem real
  for (const env of ['ephemeralMessage', 'viewOnceMessage', 'viewOnceMessageV2', 'documentWithCaptionMessage', 'editedMessage']) {
    if (m[env]?.message) m = m[env].message;
  }
  const ctx = (o: J | undefined) => o?.contextInfo?.stanzaId ?? null;
  if (typeof m.conversation === 'string') return { tipo: 'texto', texto: m.conversation, mime: null, nome: null, midia: false, contexto: null };
  if (m.extendedTextMessage) return { tipo: 'texto', texto: m.extendedTextMessage.text ?? null, mime: null, nome: null, midia: false, contexto: ctx(m.extendedTextMessage) };
  const midias: Array<[string, string]> = [['imageMessage', 'imagem'], ['videoMessage', 'video'], ['audioMessage', 'audio'], ['documentMessage', 'documento'], ['stickerMessage', 'sticker']];
  for (const [k, tipo] of midias) {
    if (m[k]) return { tipo, texto: m[k].caption ?? null, mime: m[k].mimetype ?? null, nome: m[k].fileName ?? null, midia: true, contexto: ctx(m[k]) };
  }
  if (m.locationMessage) {
    const l = m.locationMessage;
    return { tipo: 'localizacao', texto: [l.name, l.address, `${l.degreesLatitude},${l.degreesLongitude}`].filter(Boolean).join(' | '), mime: null, nome: null, midia: false, contexto: null };
  }
  if (m.contactMessage) return { tipo: 'contato', texto: m.contactMessage.displayName ?? null, mime: null, nome: null, midia: false, contexto: null };
  if (m.contactsArrayMessage) return { tipo: 'contato', texto: (m.contactsArrayMessage.contacts ?? []).map((c: J) => c?.displayName).filter(Boolean).join(', '), mime: null, nome: null, midia: false, contexto: null };
  if (m.buttonsResponseMessage) return { tipo: 'interativo', texto: m.buttonsResponseMessage.selectedDisplayText ?? null, mime: null, nome: null, midia: false, contexto: null };
  if (m.listResponseMessage) return { tipo: 'interativo', texto: m.listResponseMessage.title ?? null, mime: null, nome: null, midia: false, contexto: null };
  // reação, apagar, protocolo e afins não viram mensagem na caixa
  if (m.reactionMessage || m.protocolMessage || m.senderKeyDistributionMessage || m.messageContextInfo && Object.keys(m).length === 1) return null;
  const k = Object.keys(m).find((x) => x !== 'messageContextInfo') ?? 'desconhecido';
  return { tipo: 'sistema', texto: `[${k}]`, mime: null, nome: null, midia: false, contexto: null };
}

async function resolverConversa(conta: Conta, numero: string, nomePerfil: string | null): Promise<string> {
  const { data: existente } = await db.from('crm_wa_conversas')
    .select('id, nome_perfil').eq('conta_id', conta.id).eq('wa_id', numero).maybeSingle();
  if (existente) {
    if (nomePerfil && nomePerfil !== existente.nome_perfil) {
      await db.from('crm_wa_conversas').update({ nome_perfil: nomePerfil }).eq('id', existente.id);
    }
    return existente.id as string;
  }
  const k = chave(numero);
  let leadId: string | null = null;
  let ambiguo = false;
  if (k) {
    const { data: leads } = await db.from('crm_leads')
      .select('id, created_at').eq('wa_chave', k).eq('unidade', conta.unidade)
      .order('created_at', { ascending: false });
    if (leads?.length) { leadId = leads[0].id; ambiguo = leads.length > 1; }
  }
  const { data: nova, error } = await db.from('crm_wa_conversas').insert({
    conta_id: conta.id, wa_id: numero, numero_e164: '+' + numero, wa_chave: k,
    nome_perfil: nomePerfil, lead_id: leadId, lead_ambiguo: ambiguo,
  }).select('id').single();
  if (error?.code === '23505') {
    // corrida com outro evento da mesma conversa
    const { data: outra } = await db.from('crm_wa_conversas').select('id').eq('conta_id', conta.id).eq('wa_id', numero).single();
    return outra!.id as string;
  }
  if (error) throw error;
  return nova.id as string;
}

async function mensagem(conta: Conta, data: J): Promise<string | null> {
  const key = data?.key ?? {};
  const { numero, ignorar } = numeroDoJid(key, data);
  if (ignorar) return `ignorado:${ignorar}`;
  if (!numero) throw new Error(`numero_nao_identificado:${key?.remoteJid ?? ''}`);
  const info = extrair(data?.message);
  if (!info) return 'ignorado:sem_conteudo';
  const fromMe = key?.fromMe === true;
  const conversaId = await resolverConversa(conta, numero, fromMe ? null : (data?.pushName ?? null));
  const { error } = await db.from('crm_wa_mensagens').insert({
    conversa_id: conversaId,
    direcao: fromMe ? 'saida' : 'entrada',
    tipo: info.tipo,
    texto: info.texto,
    midia_path: info.midia && key?.id ? `evo:${key.id}` : null,
    midia_mime: info.mime,
    midia_nome: info.nome,
    wa_message_id: key?.id ?? null,
    responde_a: info.contexto,
    status: fromMe ? 'enviado' : 'entregue',
    wa_timestamp: ts(data?.messageTimestamp),
  });
  // 23505 = reentrega, ou eco de mensagem que o próprio CRM enviou
  if (error && error.code !== '23505') throw error;
  return null;
}

const STATUS: Record<string, string> = {
  SERVER_ACK: 'enviado', DELIVERY_ACK: 'entregue', READ: 'lido', PLAYED: 'lido', ERROR: 'falhou',
};

async function atualizacao(data: J) {
  const id = data?.keyId ?? data?.key?.id ?? data?.messageId ?? null;
  const novo = STATUS[String(data?.status ?? '').toUpperCase()];
  if (!id || !novo) return;
  // só avança: entregue não volta para enviado
  const ordem = ['pendente', 'enviado', 'entregue', 'lido'];
  const { data: atual } = await db.from('crm_wa_mensagens').select('id, status').eq('wa_message_id', id).maybeSingle();
  if (!atual) return;
  if (novo !== 'falhou' && ordem.indexOf(novo) <= ordem.indexOf(atual.status)) return;
  await db.from('crm_wa_mensagens').update({ status: novo }).eq('id', atual.id);
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('method not allowed', { status: 405 });

  let body: J;
  try { body = JSON.parse(await req.text()); } catch { return new Response('bad json', { status: 400 }); }
  delete body.apikey;

  const instancia = typeof body.instance === 'string' ? body.instance : '';
  const { data: conta } = await db.from('crm_wa_contas')
    .select('id, unidade, token_ref, ativa')
    .eq('provider', 'evolution').eq('evolution_instancia', instancia).maybeSingle<Conta>();

  // autenticação: header x-cna-token igual ao secret da conta. Sem conta, sem secret ou
  // header errado: 401 sem gravar nada (a Evolution não reenvia 401).
  const segredo = conta?.token_ref ? (Deno.env.get(conta.token_ref) ?? '') : '';
  const recebido = req.headers.get('x-cna-token') ?? '';
  if (!conta || !segredo || !iguais(recebido, segredo)) return new Response('unauthorized', { status: 401 });

  const evento = String(body.event ?? 'desconhecido');
  const { data: ev } = await db.from('crm_wa_eventos')
    .insert({ tipo: evento, payload: body, conta_id: conta.id, provider: 'evolution' })
    .select('id').single();

  let nota: string | null = null;
  try {
    if (!conta.ativa) nota = 'ignorado:conta_inativa';
    else if (evento === 'messages.upsert') {
      const itens = Array.isArray(body.data) ? body.data : [body.data];
      const notas: string[] = [];
      for (const d of itens) { const n = await mensagem(conta, d); if (n) notas.push(n); }
      nota = notas.length ? notas.join(',') : null;
    } else if (evento === 'messages.update') {
      const itens = Array.isArray(body.data) ? body.data : [body.data];
      for (const d of itens) await atualizacao(d);
    }
    // connection.update, qrcode.updated e o resto: só ficam registrados em crm_wa_eventos
    if (ev) await db.from('crm_wa_eventos').update({ processado: true, erro: nota }).eq('id', ev.id);
  } catch (e) {
    // 200 mesmo assim: o payload fica com processado = false para replay
    if (ev) await db.from('crm_wa_eventos').update({ erro: String(e) }).eq('id', ev.id);
  }
  return new Response('ok', { status: 200 });
});
