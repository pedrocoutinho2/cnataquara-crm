// wa-evolution-webhook v6 · recebe eventos da Evolution API (WhatsApp não oficial, fase 1).
// Decisões: 2026-10-03-whatsapp-api-nao-oficial-fase-1 (Evolution escolhida em 05/10/2026).
// Spec: 10-cna/sistemas/whatsapp-multinumero.md
//
// Configuração na Evolution, por instância (POST /webhook/set/{instancia}):
//   url: https://<projeto>.supabase.co/functions/v1/wa-evolution-webhook
//   byEvents: false · base64: false
//   headers: { "x-cna-token": <mesmo valor do secret EVO_TOKEN_* da conta> }  (opcional)
//   v2 (16/11/2026): também aceita o campo `apikey` que a Evolution manda no corpo, que é o
//   token da instância (= secret EVO_TOKEN_*). Na v2.3.7 o header do webhook não chegou.
//   events: MESSAGES_UPSERT, MESSAGES_UPDATE, CONNECTION_UPDATE
//
// v3 (16/11/2026): número novo vira lead na hora (etapa novo, origem WhatsApp, responsável = dono da
//   conversa pelo rodízio/etiqueta). Só no recebimento ao vivo; a importação de histórico não cria lead.
// v4 (16/11/2026): o que a equipe faz no celular chega ao CRM sem perda:
//   - reação (reactionMessage no messages.upsert) grava em crm_wa_mensagens.reacoes {nos|contato: emoji}
//   - edição (evento messages.edited, protocolMessage MESSAGE_EDIT) troca o texto e marca editada
//   - exclusão (evento messages.delete, ou protocolMessage REVOKE) marca apagada e MANTÉM o texto
//   Assinar MESSAGES_EDITED e MESSAGES_DELETE no webhook da instância (wa-evolution-importar acao 'finalizar').
//   Sugestão de etapa por IA (modo sugestão): ~40s depois da última mensagem da conversa, se nada novo
//   chegou, o modelo (env WA_SUGESTAO_MODELO, padrão claude-haiku-5-5, chave ANTHROPIC_API_KEY) lê as
//   últimas mensagens e, se a etapa do lead deveria mudar, grava sugestao_* na conversa. Nada muda sozinho.
// v5 (17/11/2026): nome do lead. Lead criado aqui nasce com nome_auto (o banco troca por nome melhor
//   até alguém editar: crm_wa_lead_nome_sync). Eventos contacts.upsert/contacts.update gravam o nome da
//   agenda em crm_wa_conversas.nome_contato. A IA da sugestão também lê o nome que o cliente disser
//   ("meu nome é...", assinatura) e grava em nome_ia. Número de sistema (ex.: 0@s.whatsapp.net) é ignorado.
// v6 (17/11/2026, W7): etiquetas. labels.edit e labels.association (assinar LABELS_EDIT e
//   LABELS_ASSOCIATION). A etiqueta de consultor decide o dono da conversa e o responsável do lead
//   (crm_wa_etiqueta_aplicar, no banco). O CRM nunca escreve etiqueta no WhatsApp.
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
  const curto = (n: string) => n.length < 10 ? { numero: null, ignorar: 'sistema' } : { numero: n, ignorar: null };
  if (jid.endsWith('@s.whatsapp.net')) return curto(jid.split('@')[0].replace(/\D/g, ''));
  const alt: string = key?.remoteJidAlt ?? key?.senderPn ?? data?.senderPn ?? '';
  if (alt.includes('@s.whatsapp.net')) return curto(alt.split('@')[0].replace(/\D/g, ''));
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

function fmtNum(numero: string): string {
  const d = numero.replace(/\D/g, '').replace(/^55/, '');
  if (d.length === 11) return `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}`;
  if (d.length === 10) return `(${d.slice(0, 2)}) ${d.slice(2, 6)}-${d.slice(6)}`;
  return d;
}

// número novo no WhatsApp vira lead (falha nunca impede gravar a conversa)
async function leadAutomatico(conta: Conta, conversaId: string, atendenteId: string | null, numero: string, nomePerfil: string | null) {
  try {
    let resp: string | null = null;
    if (atendenteId) {
      const { data: u } = await db.from('crm_usuarios').select('nome').eq('id', atendenteId).maybeSingle();
      resp = u?.nome ?? null;
    }
    const { data: lead, error } = await db.from('crm_leads').insert({
      unidade: conta.unidade, nome: (nomePerfil ?? '').trim() || `WhatsApp ${fmtNum(numero)}`, nome_auto: true,
      whatsapp: fmtNum(numero), etapa: 'novo', origem: 'WhatsApp', responsavel: resp,
    }).select('id').single();
    if (error) throw error;
    await db.from('crm_wa_conversas').update({ lead_id: lead.id }).eq('id', conversaId);
  } catch (e) {
    console.log(JSON.stringify({ diag: 'lead_automatico_falhou', conversa: conversaId, erro: String((e as Error)?.message ?? e).slice(0, 200) }));
  }
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
  }).select('id, atendente_id').single();
  if (error?.code === '23505') {
    // corrida com outro evento da mesma conversa
    const { data: outra } = await db.from('crm_wa_conversas').select('id').eq('conta_id', conta.id).eq('wa_id', numero).single();
    return outra!.id as string;
  }
  if (error) throw error;
  if (!leadId) await leadAutomatico(conta, nova.id as string, nova.atendente_id as string | null, numero, nomePerfil);
  return nova.id as string;
}

async function mensagem(conta: Conta, data: J): Promise<string | null> {
  const key = data?.key ?? {};
  const { numero, ignorar } = numeroDoJid(key, data);
  if (ignorar) return `ignorado:${ignorar}`;
  // reação, edição e exclusão acham a mensagem pelo id (não dependem do número)
  const bruto: J = data?.message ?? {};
  if (bruto.reactionMessage) return await reacao(conta, data, bruto.reactionMessage);
  const proto = bruto.protocolMessage ?? bruto.editedMessage?.message?.protocolMessage;
  if (proto) return await protocolo(conta, proto);
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
  if (!error && key?.id && (info.texto || !fromMe)) {
    // deno-lint-ignore no-explicit-any
    (globalThis as any).EdgeRuntime?.waitUntil?.(sugerirEtapa(conversaId, key.id));
  }
  return null;
}

// ---- celular: reação, edição, exclusão -------------------------------------------------
async function alvo(conta: Conta, id: string | null | undefined): Promise<J | null> {
  if (!id) return null;
  const { data } = await db.from('crm_wa_mensagens').select('id, reacoes, texto, conversa_id')
    .eq('wa_message_id', id).eq('unidade', conta.unidade).maybeSingle();
  return data;
}

async function reacao(conta: Conta, data: J, r: J) {
  const m = await alvo(conta, r?.key?.id);
  if (!m) return 'ignorado:reacao_sem_alvo';
  const quem = data?.key?.fromMe === true ? 'nos' : 'contato';
  const reacoes: J = { ...(m.reacoes ?? {}) };
  const emoji = String(r?.text ?? '');
  if (emoji) reacoes[quem] = emoji; else delete reacoes[quem];
  await db.from('crm_wa_mensagens').update({ reacoes }).eq('id', m.id);
  return null;
}

function textoEditado(e: J | undefined): string | null {
  if (!e) return null;
  if (typeof e.conversation === 'string') return e.conversation;
  if (e.extendedTextMessage?.text) return e.extendedTextMessage.text;
  for (const k of ['imageMessage', 'videoMessage', 'documentMessage']) if (e[k]?.caption != null) return e[k].caption;
  return null;
}

async function protocolo(conta: Conta, p: J): Promise<string | null> {
  const tipo = String(p?.type ?? '');
  const m = await alvo(conta, p?.key?.id);
  if (!m) return 'ignorado:protocolo_sem_alvo';
  if (tipo === '0' || tipo === 'REVOKE') {
    await db.from('crm_wa_mensagens').update({ apagada: true }).eq('id', m.id);
    return null;
  }
  const novo = textoEditado(p?.editedMessage);
  if (novo == null) return `ignorado:protocolo_${tipo || 'sem_tipo'}`;
  await db.from('crm_wa_mensagens').update({ texto: novo, editada: true }).eq('id', m.id);
  return null;
}

// ---- sugestão de etapa (IA, modo sugestão) ---------------------------------------------
const ETAPAS: Record<string, string> = {
  novo: 'Novo (ainda não houve contato da escola)',
  contato_feito: 'Contato feito (a escola falou, o lead ainda não respondeu)',
  respondeu: 'Respondeu (há conversa dos dois lados)',
  experimental: 'Aula experimental ou teste de nível marcado/feito',
  negociacao: 'Negociação (preço, plano, condição, matrícula sendo discutida)',
  fechado: 'Fechado (matrícula confirmada, pagamento ou contrato)',
  perdido: 'Perdido (desistiu, não tem interesse, foi para outra escola)',
  aguardando_271: 'Aguardando próximo semestre (quer começar só no semestre seguinte)',
};
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function sugerirEtapa(conversaId: string, msgId: string) {
  const KEY = Deno.env.get('ANTHROPIC_API_KEY') ?? '';
  if (!KEY) return;
  await sleep(40000);
  // só a última mensagem da conversa dispara (debounce natural)
  const { data: ult } = await db.from('crm_wa_mensagens').select('wa_message_id').eq('conversa_id', conversaId)
    .order('wa_timestamp', { ascending: false }).limit(1).maybeSingle();
  if (!ult || ult.wa_message_id !== msgId) return;
  const { data: c } = await db.from('crm_wa_conversas').select('id, lead_id, unidade, sugestao_etapa, sugestao_status').eq('id', conversaId).maybeSingle();
  if (!c?.lead_id) return;
  const { data: lead } = await db.from('crm_leads').select('etapa, nome').eq('id', c.lead_id).eq('unidade', c.unidade).maybeSingle();
  if (!lead) return;
  const { data: msgs } = await db.from('crm_wa_mensagens').select('direcao, tipo, texto, apagada, wa_timestamp')
    .eq('conversa_id', conversaId).order('wa_timestamp', { ascending: false }).limit(40);
  const linhas = (msgs ?? []).reverse().map((m: J) =>
    `${m.direcao === 'saida' ? 'ESCOLA' : 'LEAD'}: ${m.texto ? String(m.texto).slice(0, 500) : `[${m.tipo}]`}${m.apagada ? ' (apagada)' : ''}`).join('\n');
  if (!linhas) return;
  const prompt = `Você ajuda consultores de uma escola de idiomas (CNA) a manter o funil de vendas atualizado.
Etapas possíveis:
${Object.entries(ETAPAS).map(([k, v]) => `- ${k}: ${v}`).join('\n')}

Etapa atual do lead: ${lead.etapa}.
Conversa de WhatsApp (mais antiga primeiro):
${linhas}

Responda SOMENTE com JSON: {"etapa": "<uma das chaves acima>", "motivo": "<frase curta em português, até 120 caracteres, citando o fato da conversa>", "confianca": <0 a 1>, "nome": "<nome e sobrenome do LEAD (a pessoa que fala com a escola) se ele disser ou assinar na conversa, senão null>"}.
Se não houver evidência clara de mudança, repita a etapa atual. Não use o nome de quem trabalha na escola nem o nome do aluno quando quem fala é o responsável.`;
  try {
    const r = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: { 'x-api-key': KEY, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' },
      body: JSON.stringify({ model: Deno.env.get('WA_SUGESTAO_MODELO') ?? 'claude-haiku-5-5', max_tokens: 250,
        messages: [{ role: 'user', content: prompt }] }),
    });
    const j = await r.json().catch(() => ({}));
    if (!r.ok) { console.log(JSON.stringify({ diag: 'sugestao_http', status: r.status, erro: j?.error?.type, msg: String(j?.error?.message ?? '').slice(0, 240) })); return; }
    const txt: string = (j?.content ?? []).map((x: J) => x?.text ?? '').join('');
    const o = JSON.parse(txt.slice(txt.indexOf('{'), txt.lastIndexOf('}') + 1));
    const nm = typeof o?.nome === 'string' ? o.nome.trim() : '';
    if (nm && nm.toLowerCase() !== 'null') await db.from('crm_wa_conversas').update({ nome_ia: nm.slice(0, 80) }).eq('id', conversaId);
    const et = String(o?.etapa ?? '');
    if (lead.etapa === 'fechado' || !ETAPAS[et] || et === lead.etapa || Number(o?.confianca ?? 0) < 0.6) return;
    if (c.sugestao_etapa === et && c.sugestao_status === 'ignorada') return; // não insiste no que foi recusado
    await db.from('crm_wa_conversas').update({ sugestao_etapa: et, sugestao_motivo: String(o?.motivo ?? '').slice(0, 200),
      sugestao_em: new Date().toISOString(), sugestao_status: 'pendente' }).eq('id', conversaId);
  } catch (e) {
    console.log(JSON.stringify({ diag: 'sugestao_falhou', erro: String((e as Error)?.message ?? e).slice(0, 200) }));
  }
}

// ---- agenda do celular -> nome_contato -------------------------------------------------
async function contatos(conta: Conta, itens: J[]) {
  for (const d of itens) {
    const { numero } = numeroDoJid({ remoteJid: d?.remoteJid ?? d?.id ?? '' }, d);
    const nome = String(d?.name ?? d?.pushName ?? d?.notify ?? d?.verifiedName ?? '').trim();
    if (!numero || !nome || nome.replace(/\D/g, '') === numero) continue;
    await db.from('crm_wa_conversas').update({ nome_contato: nome })
      .eq('conta_id', conta.id).eq('wa_id', numero).neq('nome_contato', nome);
    await db.from('crm_wa_conversas').update({ nome_contato: nome })
      .eq('conta_id', conta.id).eq('wa_id', numero).is('nome_contato', null);
  }
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

// ---- W7 (17/11/2026): etiquetas do WhatsApp Business decidem o dono --------------------------
// O CRM só LÊ etiqueta; nunca cria, tira ou troca etiqueta no WhatsApp.
// labels.edit -> crm_wa_etiquetas (nome/cor; o consultor dono da etiqueta é configurado no banco).
// labels.association -> estado por LID em crm_wa_lid_etiquetas; o LID é ligado à conversa do CRM
// (crm_wa_lids) e o banco aplica o dono (crm_wa_etiqueta_aplicar): uma etiqueta de consultor = dono.
const EVO_URL = (Deno.env.get('EVO_URL') ?? 'https://evo.cnataquara.com.br').replace(/\/+$/, '');

async function etiquetaEdit(conta: Conta, d: J) {
  const id = String(d?.id ?? d?.labelId ?? '');
  if (!id) return;
  await db.from('crm_wa_etiquetas').upsert({
    conta_id: conta.id, label_id: id, nome: d?.name ?? null, cor: Number.isFinite(Number(d?.color)) ? Number(d.color) : null,
    apagada: !!d?.deleted, atualizado_em: new Date().toISOString(), unidade: conta.unidade,
  }, { onConflict: 'conta_id,label_id', ignoreDuplicates: false });
}

async function lidParaConversa(conta: Conta, instancia: string, tk: string, jid: string): Promise<{ conversa: string | null; numero: string | null; origem: string }> {
  // 1) jid já é número
  if (jid.endsWith('@s.whatsapp.net')) {
    const numero = jid.split('@')[0].replace(/\D/g, '');
    const { data: c } = await db.from('crm_wa_conversas').select('id').eq('conta_id', conta.id).eq('wa_id', numero).maybeSingle();
    return { conversa: c?.id ?? null, numero, origem: 'numero' };
  }
  const h = { apikey: tk, 'Content-Type': 'application/json' };
  const inst = encodeURIComponent(instancia);
  // 2) mensagens desse LID na Evolution: o id da mensagem é o mesmo que o CRM gravou
  try {
    const r = await fetch(`${EVO_URL}/chat/findMessages/${inst}`, { method: 'POST', headers: h,
      body: JSON.stringify({ where: { key: { remoteJid: jid } }, page: 1, offset: 50 }) });
    const resp = r.ok ? await r.json().catch(() => ({})) : {};
    const regs: J[] = resp?.messages?.records ?? [];
    for (const m of regs) {
      const alt = String(m?.key?.remoteJidAlt ?? m?.key?.senderPn ?? '');
      if (alt.endsWith('@s.whatsapp.net')) {
        const numero = alt.split('@')[0].replace(/\D/g, '');
        const { data: c } = await db.from('crm_wa_conversas').select('id').eq('conta_id', conta.id).eq('wa_id', numero).maybeSingle();
        if (c) return { conversa: c.id, numero, origem: 'alt' };
      }
    }
    const ids = regs.map((m) => m?.key?.id).filter(Boolean);
    if (ids.length) {
      const { data: ms } = await db.from('crm_wa_mensagens').select('conversa_id, crm_wa_conversas!inner(conta_id, wa_id)')
        .in('wa_message_id', ids).eq('crm_wa_conversas.conta_id', conta.id).limit(1);
      // deno-lint-ignore no-explicit-any
      const m0: any = ms?.[0];
      if (m0) return { conversa: m0.conversa_id, numero: m0.crm_wa_conversas?.wa_id ?? null, origem: 'mensagem' };
    }
    // 3) cadastro do chat na Evolution: a última mensagem às vezes traz o número (remoteJidAlt)
    const rc = await fetch(`${EVO_URL}/chat/findChats/${inst}`, { method: 'POST', headers: h,
      body: JSON.stringify({ where: { remoteJid: jid } }) });
    const chats = rc.ok ? await rc.json().catch(() => []) : [];
    for (const c of Array.isArray(chats) ? chats : []) {
      if (c?.remoteJid !== jid) continue;
      const alt = String(c?.lastMessage?.key?.remoteJidAlt ?? '');
      if (alt.endsWith('@s.whatsapp.net')) {
        const numero = alt.split('@')[0].replace(/\D/g, '');
        const { data: cv } = await db.from('crm_wa_conversas').select('id').eq('conta_id', conta.id).eq('wa_id', numero).maybeSingle();
        return { conversa: cv?.id ?? null, numero, origem: cv ? 'chat' : 'chat_sem_conversa' };
      }
    }
  } catch (_) { /* sem resolução agora: fica pendente */ }
  return { conversa: null, numero: null, origem: 'pendente' };
}

async function etiquetaAssociacao(conta: Conta, instancia: string, tk: string, d: J): Promise<string> {
  const jid = String(d?.chatId ?? d?.jid ?? '');
  const label = String(d?.labelId ?? d?.label_id ?? '');
  if (!jid || !label || jid.endsWith('@g.us')) return 'ignorado:etiqueta';
  const lid = jid.split('@')[0];
  if (d?.type === 'remove') {
    await db.from('crm_wa_lid_etiquetas').delete().eq('conta_id', conta.id).eq('lid', lid).eq('label_id', label);
    return 'etiqueta_removida'; // tirar etiqueta não troca o dono
  }
  await db.from('crm_wa_lid_etiquetas').upsert({ conta_id: conta.id, lid, label_id: label, em: new Date().toISOString(), unidade: conta.unidade },
    { onConflict: 'conta_id,lid,label_id', ignoreDuplicates: true });
  const { data: ja } = await db.from('crm_wa_lids').select('conversa_id').eq('conta_id', conta.id).eq('lid', lid).maybeSingle();
  if (!ja?.conversa_id) {
    const r = await lidParaConversa(conta, instancia, tk, jid);
    await db.from('crm_wa_lids').upsert({ conta_id: conta.id, lid, conversa_id: r.conversa, numero: r.numero, origem: r.origem,
      atualizado_em: new Date().toISOString(), unidade: conta.unidade }, { onConflict: 'conta_id,lid' });
    if (!r.conversa) return 'etiqueta_pendente';
  }
  const { data: res } = await db.rpc('crm_wa_etiqueta_aplicar', { p_conta: conta.id, p_lid: lid });
  return 'etiqueta:' + String(res ?? '');
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('method not allowed', { status: 405 });

  let body: J;
  try { body = JSON.parse(await req.text()); } catch { return new Response('bad json', { status: 400 }); }
  const apikeyCorpo = typeof body.apikey === 'string' ? body.apikey : '';
  delete body.apikey;

  const instancia = typeof body.instance === 'string' ? body.instance : '';
  const { data: conta } = await db.from('crm_wa_contas')
    .select('id, unidade, token_ref, ativa')
    .eq('provider', 'evolution').eq('evolution_instancia', instancia).maybeSingle<Conta>();

  // autenticação: header x-cna-token igual ao secret da conta. Sem conta, sem secret ou
  // header errado: 401 sem gravar nada (a Evolution não reenvia 401).
  const segredo = conta?.token_ref ? (Deno.env.get(conta.token_ref) ?? '') : '';
  const recebido = req.headers.get('x-cna-token') ?? '';
  const okHeader = !!segredo && iguais(recebido, segredo);
  const okCorpo = !!segredo && iguais(apikeyCorpo, segredo);
  if (!conta || !segredo || !(okHeader || okCorpo)) {
    // diagnóstico sem valores: só presença e tamanho
    console.log(JSON.stringify({ diag: 'wa_evo_401', instancia, conta: !!conta, segredo_len: segredo.length,
      header_len: recebido.length, corpo_len: apikeyCorpo.length }));
    return new Response('unauthorized', { status: 401 });
  }

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
    } else if (evento === 'messages.edited') {
      const itens = Array.isArray(body.data) ? body.data : [body.data];
      const notas: string[] = [];
      for (const d of itens) { const n = await protocolo(conta, d); if (n) notas.push(n); }
      nota = notas.length ? notas.join(',') : null;
    } else if (evento === 'messages.delete') {
      const itens = Array.isArray(body.data) ? body.data : [body.data];
      for (const d of itens) {
        const m = await alvo(conta, d?.id ?? d?.key?.id ?? d?.keyId);
        if (m) await db.from('crm_wa_mensagens').update({ apagada: true }).eq('id', m.id);
        else nota = 'ignorado:delete_sem_alvo';
      }
    } else if (evento === 'contacts.upsert' || evento === 'contacts.update') {
      await contatos(conta, Array.isArray(body.data) ? body.data : [body.data]);
    } else if (evento === 'labels.edit') {
      const itens = Array.isArray(body.data) ? body.data : [body.data];
      for (const d of itens) await etiquetaEdit(conta, d);
    } else if (evento === 'labels.association') {
      const itens = Array.isArray(body.data) ? body.data : [body.data];
      const notas: string[] = [];
      for (const d of itens) notas.push(await etiquetaAssociacao(conta, instancia, segredo, d));
      nota = notas.join(',');
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
