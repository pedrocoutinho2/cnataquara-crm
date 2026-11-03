// wa-media v2 · devolve URL assinada (1h) da mídia de uma mensagem de WhatsApp.
// Exige o token de sessão do CRM (crm_wa_sessao, nível 1 em 'conversas') e a mensagem tem de ser da
// unidade da sessão. Na primeira abertura baixa do provedor e guarda no bucket privado 'wa-media':
//   midia_path 'meta:<id>' → Meta Cloud API (token do secret em token_ref da conta)
//   midia_path 'evo:<id>'  → Evolution, /chat/getBase64FromMediaMessage (token da instância)
// Depois só assina. Caminho no bucket: <unidade>/<conversa>/<mensagem>.<ext>
import { createClient } from 'jsr:@supabase/supabase-js@2';

const db = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

const GRAPH = Deno.env.get('WA_GRAPH_VERSION') ?? 'v21.0';
const EVO_URL = (Deno.env.get('EVO_URL') ?? 'https://evo.cnataquara.com.br').replace(/\/+$/, '');
const BUCKET = 'wa-media';
const EXPIRA = 3600;

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// deno-lint-ignore no-explicit-any
type J = Record<string, any>;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });
}

const EXT: Record<string, string> = {
  'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp',
  'audio/ogg': 'ogg', 'audio/mpeg': 'mp3', 'audio/mp4': 'm4a', 'audio/amr': 'amr',
  'video/mp4': 'mp4', 'video/3gpp': '3gp', 'application/pdf': 'pdf',
};

function extensao(mime: string | null, nome: string | null): string {
  if (nome && nome.includes('.')) return nome.split('.').pop()!.toLowerCase().replace(/[^a-z0-9]/g, '').slice(0, 8) || 'bin';
  const base = (mime ?? '').split(';')[0].trim();
  return EXT[base] ?? 'bin';
}

function b64(s: string): Uint8Array {
  const bin = atob(s.replace(/^data:[^,]*,/, ''));
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

const ERROS_SESSAO = ['sessao_invalida', 'unidade_nao_escolhida', 'sem_permissao'];

async function sessao(token: unknown, min: number): Promise<J> {
  if (typeof token !== 'string' || !/^[0-9a-f-]{36}$/i.test(token)) throw new Error('sessao_invalida');
  const { data, error } = await db.rpc('crm_wa_sessao', { p_token: token, p_min: min });
  if (error) {
    const m = ERROS_SESSAO.find((x) => (error.message ?? '').includes(x));
    throw new Error(m ?? 'sessao_invalida');
  }
  return data as J;
}

function segredo(conta: J): string {
  const v = conta.token_ref ? (Deno.env.get(conta.token_ref) ?? '') : '';
  if (!v) throw new Error('conta_sem_token');
  return v;
}

async function baixarMeta(conta: J, midiaId: string) {
  const tk = segredo(conta);
  const r1 = await fetch(`https://graph.facebook.com/${GRAPH}/${midiaId}`, { headers: { Authorization: `Bearer ${tk}` } });
  if (!r1.ok) throw new Error(`metadados da midia: ${r1.status}`);
  const meta = await r1.json();
  const r2 = await fetch(meta.url, { headers: { Authorization: `Bearer ${tk}` } });
  if (!r2.ok) throw new Error(`download da midia: ${r2.status}`);
  return { bytes: new Uint8Array(await r2.arrayBuffer()), mime: meta.mime_type ?? null };
}

async function baixarEvolution(conta: J, msgId: string) {
  if (!conta.evolution_instancia) throw new Error('conta_sem_instancia');
  const r = await fetch(`${EVO_URL}/chat/getBase64FromMediaMessage/${encodeURIComponent(conta.evolution_instancia)}`, {
    method: 'POST',
    headers: { apikey: segredo(conta), 'Content-Type': 'application/json' },
    body: JSON.stringify({ message: { key: { id: msgId } }, convertToMp4: false }),
  });
  const resp = await r.json().catch(() => ({}));
  if (!r.ok || !resp?.base64) throw new Error(`midia na evolution: ${r.status}`);
  return { bytes: b64(String(resp.base64)), mime: resp.mimetype ?? null };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ erro: 'method not allowed' }, 405);

  let b: J;
  try { b = await req.json(); } catch { return json({ erro: 'json invalido' }, 400); }

  let s: J;
  try { s = await sessao(b.token, 1); } catch (e) {
    const m = String((e as Error).message);
    return json({ erro: m, detalhe: 'Sessão expirada ou sem acesso a Conversas.' }, m === 'sem_permissao' ? 403 : 401);
  }
  if (!b.mensagem_id) return json({ erro: 'informe mensagem_id' }, 400);

  try {
    const { data: msg } = await db.from('crm_wa_mensagens')
      .select('id, conversa_id, unidade, midia_path, midia_mime, midia_nome')
      .eq('id', b.mensagem_id).eq('unidade', s.unidade).maybeSingle();
    if (!msg) return json({ erro: 'mensagem_de_outra_unidade', detalhe: 'Mensagem não encontrada nesta unidade.' }, 404);
    if (!msg.midia_path) return json({ erro: 'mensagem sem midia' }, 400);

    let path = String(msg.midia_path);
    let mime: string | null = msg.midia_mime;
    const origem = path.startsWith('meta:') ? 'meta' : path.startsWith('evo:') ? 'evo' : null;
    if (origem) {
      const { data: conv } = await db.from('crm_wa_conversas').select('conta_id').eq('id', msg.conversa_id).single();
      const { data: conta } = await db.from('crm_wa_contas').select('*').eq('id', conv!.conta_id).eq('unidade', s.unidade).single();
      const id = path.slice(origem.length + 1);
      const d = origem === 'meta' ? await baixarMeta(conta!, id) : await baixarEvolution(conta!, id);
      mime = (d.mime ?? mime ?? 'application/octet-stream').split(';')[0].trim();
      path = `${s.unidade}/${msg.conversa_id}/${msg.id}.${extensao(mime, msg.midia_nome)}`;
      const { error: errUp } = await db.storage.from(BUCKET).upload(path, d.bytes, { contentType: mime, upsert: true });
      if (errUp) throw errUp;
      await db.from('crm_wa_mensagens').update({ midia_path: path, midia_mime: mime }).eq('id', msg.id);
    }

    const { data: assinada, error } = await db.storage.from(BUCKET).createSignedUrl(path, EXPIRA);
    if (error) throw error;
    return json({ ok: true, url: assinada.signedUrl, path, mime, expira_em: EXPIRA });
  } catch (e) {
    const m = String((e as Error)?.message ?? e);
    if (m === 'conta_sem_token') return json({ erro: m, detalhe: 'O token deste número não está configurado no servidor.' }, 500);
    return json({ erro: m }, 500);
  }
});
