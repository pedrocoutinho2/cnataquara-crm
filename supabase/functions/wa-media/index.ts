import { createClient } from 'jsr:@supabase/supabase-js@2';

const db = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

const TOKEN = Deno.env.get('WA_TOKEN') ?? '';
const GRAPH = Deno.env.get('WA_GRAPH_VERSION') ?? 'v21.0';
const BUCKET = 'wa-media';
const EXPIRA = 3600;

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

const EXT: Record<string, string> = {
  'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp',
  'audio/ogg': 'ogg', 'audio/mpeg': 'mp3', 'audio/mp4': 'm4a', 'audio/amr': 'amr',
  'video/mp4': 'mp4', 'video/3gpp': '3gp',
  'application/pdf': 'pdf',
};

function extensao(mime: string | null, nome: string | null): string {
  if (nome && nome.includes('.')) return nome.split('.').pop()!.toLowerCase().slice(0, 8);
  const base = (mime ?? '').split(';')[0].trim();
  return EXT[base] ?? 'bin';
}

// Baixa da Meta e guarda no bucket. A URL da Cloud API expira em minutos e exige bearer.
async function ingerir(msg: Record<string, any>) {
  if (!TOKEN) throw new Error('WA_TOKEN nao configurado');
  const midiaId = String(msg.midia_path).slice(5); // remove o prefixo meta:

  const r1 = await fetch(`https://graph.facebook.com/${GRAPH}/${midiaId}`, {
    headers: { Authorization: `Bearer ${TOKEN}` },
  });
  if (!r1.ok) throw new Error(`metadados da midia: ${r1.status}`);
  const meta = await r1.json();

  const r2 = await fetch(meta.url, { headers: { Authorization: `Bearer ${TOKEN}` } });
  if (!r2.ok) throw new Error(`download da midia: ${r2.status}`);
  const bytes = new Uint8Array(await r2.arrayBuffer());

  const mime = meta.mime_type ?? msg.midia_mime ?? 'application/octet-stream';
  const path = `${msg.conversa_id}/${msg.id}.${extensao(mime, msg.midia_nome)}`;

  const { error: errUp } = await db.storage.from(BUCKET)
    .upload(path, bytes, { contentType: mime, upsert: true });
  if (errUp) throw errUp;

  await db.from('crm_wa_mensagens')
    .update({ midia_path: path, midia_mime: mime })
    .eq('id', msg.id);

  return path;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ erro: 'method not allowed' }, 405);

  let b: Record<string, any>;
  try { b = await req.json(); } catch { return json({ erro: 'json invalido' }, 400); }
  if (!b.mensagem_id) return json({ erro: 'informe mensagem_id' }, 400);

  try {
    const { data: msg } = await db.from('crm_wa_mensagens')
      .select('id, conversa_id, midia_path, midia_mime, midia_nome')
      .eq('id', b.mensagem_id).maybeSingle();
    if (!msg) return json({ erro: 'mensagem nao encontrada' }, 404);
    if (!msg.midia_path) return json({ erro: 'mensagem sem midia' }, 400);

    // Ainda apontando para a Meta: baixa agora. Ja no bucket: so assina.
    const path = String(msg.midia_path).startsWith('meta:')
      ? await ingerir(msg)
      : String(msg.midia_path);

    const { data: assinada, error } = await db.storage.from(BUCKET)
      .createSignedUrl(path, EXPIRA);
    if (error) throw error;

    return json({ ok: true, url: assinada.signedUrl, path, mime: msg.midia_mime, expira_em: EXPIRA });
  } catch (e) {
    return json({ erro: String(e) }, 500);
  }
});
