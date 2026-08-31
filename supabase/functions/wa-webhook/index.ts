import { createClient } from 'jsr:@supabase/supabase-js@2';

const db = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

const VERIFY_TOKEN = Deno.env.get('WA_VERIFY_TOKEN') ?? '';
const APP_SECRET = Deno.env.get('WA_APP_SECRET') ?? '';

// Mesma chave canonica da funcao SQL crm_wa_chave: DDD + 8 ultimos digitos
function chave(num: string | null | undefined): string | null {
  let d = (num ?? '').replace(/\D/g, '');
  if (d.length >= 12 && d.startsWith('55')) d = d.slice(2);
  if (d.length < 10) return null;
  return d.slice(0, 2) + d.slice(-8);
}

// Valida X-Hub-Signature-256 (HMAC SHA-256 do corpo cru com o app secret)
async function assinaturaOk(raw: string, header: string | null): Promise<boolean> {
  if (!APP_SECRET) return true; // ainda nao configurado: nao bloqueia o setup inicial
  if (!header?.startsWith('sha256=')) return false;
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(APP_SECRET),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const mac = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(raw));
  const esperado = Array.from(new Uint8Array(mac))
    .map((b) => b.toString(16).padStart(2, '0')).join('');
  const recebido = header.slice(7);
  if (recebido.length !== esperado.length) return false;
  let diff = 0;
  for (let i = 0; i < esperado.length; i++) diff |= esperado.charCodeAt(i) ^ recebido.charCodeAt(i);
  return diff === 0;
}

function extrairTexto(m: Record<string, any>): { tipo: string; texto: string | null; midiaId: string | null; mime: string | null; nome: string | null } {
  const t = m.type as string;
  switch (t) {
    case 'text':
      return { tipo: 'texto', texto: m.text?.body ?? null, midiaId: null, mime: null, nome: null };
    case 'image':
    case 'audio':
    case 'video':
    case 'document':
    case 'sticker': {
      const mapa: Record<string, string> = { image: 'imagem', audio: 'audio', video: 'video', document: 'documento', sticker: 'sticker' };
      const obj = m[t] ?? {};
      return { tipo: mapa[t], texto: obj.caption ?? null, midiaId: obj.id ?? null, mime: obj.mime_type ?? null, nome: obj.filename ?? null };
    }
    case 'location':
      return { tipo: 'localizacao', texto: [m.location?.name, m.location?.address, `${m.location?.latitude},${m.location?.longitude}`].filter(Boolean).join(' | '), midiaId: null, mime: null, nome: null };
    case 'contacts':
      return { tipo: 'contato', texto: (m.contacts ?? []).map((c: any) => c?.name?.formatted_name).filter(Boolean).join(', '), midiaId: null, mime: null, nome: null };
    case 'button':
      return { tipo: 'interativo', texto: m.button?.text ?? null, midiaId: null, mime: null, nome: null };
    case 'interactive':
      return { tipo: 'interativo', texto: m.interactive?.button_reply?.title ?? m.interactive?.list_reply?.title ?? null, midiaId: null, mime: null, nome: null };
    default:
      return { tipo: 'sistema', texto: `[${t}]`, midiaId: null, mime: null, nome: null };
  }
}

async function resolverConversa(phoneNumberId: string, waId: string, nomePerfil: string | null) {
  const { data: conta } = await db.from('crm_wa_contas')
    .select('id').eq('phone_number_id', phoneNumberId).maybeSingle();
  if (!conta) throw new Error(`conta nao cadastrada para phone_number_id ${phoneNumberId}`);

  const { data: existente } = await db.from('crm_wa_conversas')
    .select('id, lead_id, nome_perfil').eq('conta_id', conta.id).eq('wa_id', waId).maybeSingle();
  if (existente) {
    if (nomePerfil && nomePerfil !== existente.nome_perfil) {
      await db.from('crm_wa_conversas').update({ nome_perfil: nomePerfil }).eq('id', existente.id);
    }
    return existente.id as string;
  }

  const k = chave(waId);
  let leadId: string | null = null;
  let ambiguo = false;
  if (k) {
    const { data: leads } = await db.from('crm_leads')
      .select('id, created_at').eq('wa_chave', k).order('created_at', { ascending: false });
    if (leads?.length) {
      leadId = leads[0].id;
      ambiguo = leads.length > 1;
    }
  }

  const { data: nova, error } = await db.from('crm_wa_conversas').insert({
    conta_id: conta.id,
    wa_id: waId,
    numero_e164: '+' + waId.replace(/\D/g, ''),
    wa_chave: k,
    nome_perfil: nomePerfil,
    lead_id: leadId,
    lead_ambiguo: ambiguo,
  }).select('id').single();
  if (error) throw error;
  return nova.id as string;
}

async function processar(body: Record<string, any>) {
  for (const entry of body.entry ?? []) {
    for (const change of entry.changes ?? []) {
      const v = change.value ?? {};
      const phoneNumberId = v.metadata?.phone_number_id;
      if (!phoneNumberId) continue;

      const perfis: Record<string, string> = {};
      for (const c of v.contacts ?? []) {
        if (c?.wa_id) perfis[c.wa_id] = c?.profile?.name ?? '';
      }

      for (const m of v.messages ?? []) {
        const conversaId = await resolverConversa(phoneNumberId, m.from, perfis[m.from] || null);
        const info = extrairTexto(m);
        const { error } = await db.from('crm_wa_mensagens').insert({
          conversa_id: conversaId,
          direcao: 'entrada',
          tipo: info.tipo,
          texto: info.texto,
          midia_path: info.midiaId ? `meta:${info.midiaId}` : null,
          midia_mime: info.mime,
          midia_nome: info.nome,
          wa_message_id: m.id,
          responde_a: m.context?.id ?? null,
          status: 'entregue',
          wa_timestamp: new Date(Number(m.timestamp) * 1000).toISOString(),
        });
        // 23505 = reentrega do mesmo webhook, ignorar
        if (error && error.code !== '23505') throw error;
      }

      for (const s of v.statuses ?? []) {
        const mapa: Record<string, string> = { sent: 'enviado', delivered: 'entregue', read: 'lido', failed: 'falhou' };
        const novo = mapa[s.status];
        if (!novo) continue;
        const patch: Record<string, unknown> = { status: novo };
        if (novo === 'falhou') {
          patch.erro_codigo = String(s.errors?.[0]?.code ?? '');
          patch.erro_msg = s.errors?.[0]?.title ?? s.errors?.[0]?.message ?? null;
        }
        await db.from('crm_wa_mensagens').update(patch).eq('wa_message_id', s.id);
      }
    }
  }
}

Deno.serve(async (req) => {
  const url = new URL(req.url);

  // Handshake de verificacao do webhook na Meta
  if (req.method === 'GET') {
    const modo = url.searchParams.get('hub.mode');
    const token = url.searchParams.get('hub.verify_token');
    const challenge = url.searchParams.get('hub.challenge') ?? '';
    if (modo === 'subscribe' && VERIFY_TOKEN && token === VERIFY_TOKEN) {
      return new Response(challenge, { status: 200 });
    }
    return new Response('forbidden', { status: 403 });
  }

  if (req.method !== 'POST') return new Response('method not allowed', { status: 405 });

  const raw = await req.text();
  if (!(await assinaturaOk(raw, req.headers.get('x-hub-signature-256')))) {
    return new Response('bad signature', { status: 401 });
  }

  let body: Record<string, any>;
  try {
    body = JSON.parse(raw);
  } catch {
    return new Response('bad json', { status: 400 });
  }

  const { data: evento } = await db.from('crm_wa_eventos')
    .insert({ tipo: body.entry?.[0]?.changes?.[0]?.field ?? 'desconhecido', payload: body })
    .select('id').single();

  try {
    await processar(body);
    if (evento) await db.from('crm_wa_eventos').update({ processado: true }).eq('id', evento.id);
  } catch (e) {
    // 200 mesmo assim: a Meta desativa o webhook apos falhas repetidas.
    // O payload cru fica em crm_wa_eventos com processado = false para replay.
    if (evento) await db.from('crm_wa_eventos').update({ erro: String(e) }).eq('id', evento.id);
  }

  return new Response('ok', { status: 200 });
});
