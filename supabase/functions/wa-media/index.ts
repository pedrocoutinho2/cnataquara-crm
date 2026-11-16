// wa-media v2 · entrega mídia de mensagem do WhatsApp por URL assinada (1 h).
// Spec: 10-cna/sistemas/whatsapp-multinumero.md (W2). Dívida nº 3 fechada aqui:
//   - exige o token de sessão do CRM (crm_wa_sessao, nível 1 em 'conversas'); a chave anon sozinha não lê mídia
//   - mensagem só da unidade da sessão
//   - token do provedor lido do secret apontado por crm_wa_contas.token_ref (WA_TOKEN_* ou EVO_TOKEN_*)
// Origem da mídia pelo prefixo de midia_path:
//   meta:<media_id>  → baixa da Cloud API e guarda no bucket
//   evo:<message_id> → pede o base64 à Evolution (chat/getBase64FromMediaMessage) e guarda no bucket
//   qualquer outro   → já está no bucket, só assina
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

const EXT: Record<string, string> = {
  'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp',
  'audio/ogg': 'ogg', 'audio/mpeg': 'mp3', 'audio/mp4': 'm4a', 'audio/amr': 'amr',
  'video/mp4': 'mp4', 'video/3gpp': '3gp',
  'application/pdf': 'pdf',
};

function extensao(mime: string | null, nome: string | null): string {
  if (nome && nome.includes('.')) return nome.split('.').pop()!.toLowerCase().replace(/[^a-z0-9]/g, '').slice(0, 8) || 'bin';
  const base = (mime ?? '').split(';')[0].trim();
  return EXT[base] ?? 'bin';
}

function deBase64(b64: string): Uint8Array {
  const limpo = b64.includes(',') && b64.startsWith('data:') ? b64.split(',')[1] : b64;
  const bin = atob(limpo);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

async function baixarMeta(conta: J, midiaId: string): Promise<{ bytes: Uint8Array; mime: string | null }> {
  const tk = segredo(conta);
  const r1 = await fetch(`https://graph.facebook.com/${GRAPH}/${midiaId}`, { headers: { Authorization: `Bearer ${tk}` } });
  if (!r1.ok) throw new Error(`metadados da midia: ${r1.status}`);
  const meta = await r1.json();
  const r2 = await fetch(meta.url, { headers: { Authorization: `Bearer ${tk}` } });
  if (!r2.ok) throw new Error(`download da midia: ${r2.status}`);
  return { bytes: new Uint8Array(await r2.arrayBuffer()), mime: meta.mime_type ?? null };
}

async function baixarEvolution(conta: J, msgId: string): Promise<{ bytes: Uint8Array; mime: string | null; nome: string | null }> {
  if (!conta.evolution_instancia) throw new Error('conta_sem_instancia');
  const r = await fetch(`${EVO_URL}/chat/getBase64FromMediaMessage/${encodeURIComponent(conta.evolution_instancia)}`, {
    method: 'POST',
    headers: { apikey: segredo(conta), 'Content-Type': 'application/json' },
    body: JSON.stringify({ message: { key: { id: msgId } }, convertToMp4: false }),
  });
  const resp = await r.json().catch(() => ({}));
  if (!r.ok || typeof resp?.base64 !== 'string') {
    const m = resp?.response?.message ?? resp?.message ?? resp?.error ?? `HTTP ${r.status}`;
    throw new Error(`evolution_midia: ${(Array.isArray(m) ? JSON.stringify(m) : String(m)).slice(0, 200)}`);
  }
  return { bytes: deBase64(resp.base64), mime: resp.mimetype ?? null, nome: resp.fileName ?? null };
}

async function ingerir(msg: J, conta: J): Promise<{ path: string; mime: string }> {
  const origem = String(msg.midia_path);
  let bytes: Uint8Array, mime: string | null, nome: string | null = msg.midia_nome ?? null;
  if (origem.startsWith('meta:')) {
    ({ bytes, mime } = await baixarMeta(conta, origem.slice(5)));
  } else {
    const r = await baixarEvolution(conta, origem.slice(4));
    bytes = r.bytes; mime = r.mime; nome = nome ?? r.nome;
  }
  const tipo = mime ?? msg.midia_mime ?? 'application/octet-stream';
  const path = `${msg.unidade}/${msg.conversa_id}/${msg.id}.${extensao(tipo, nome)}`;
  const { error } = await db.storage.from(BUCKET).upload(path, bytes, { contentType: tipo, upsert: true });
  if (error) throw error;
  await db.from('crm_wa_mensagens').update({ midia_path: path, midia_mime: tipo }).eq('id', msg.id);
  return { path, mime: tipo };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ erro: 'method not allowed' }, 405);

  let b: J;
  try { b = await req.json(); } catch { return json({ erro: 'json invalido' }, 400); }

  let s: J;
  try { s = await sessao(b.token, 1); } catch (e) {
    const m = String((e as Error).message);
    return json({ erro: m, detalhe: m === 'sem_permissao' ? 'Seu acesso a Conversas não permite ver mídia.' : 'Sessão expirada. Entre de novo.' }, m === 'sem_permissao' ? 403 : 401);
  }
  if (typeof b.mensagem_id !== 'string' || !/^[0-9a-f-]{36}$/i.test(b.mensagem_id)) return json({ erro: 'informe mensagem_id' }, 400);

  try {
    const { data: msg } = await db.from('crm_wa_mensagens')
      .select('id, conversa_id, unidade, midia_path, midia_mime, midia_nome')
      .eq('id', b.mensagem_id).eq('unidade', s.unidade).maybeSingle();
    if (!msg) return json({ erro: 'mensagem_de_outra_unidade', detalhe: 'Mensagem não encontrada nesta unidade.' }, 404);
    if (!msg.midia_path) return json({ erro: 'mensagem sem midia' }, 400);

    let path = String(msg.midia_path);
    let mime = msg.midia_mime as string | null;
    if (path.startsWith('meta:') || path.startsWith('evo:')) {
      const { data: conv } = await db.from('crm_wa_conversas').select('conta_id').eq('id', msg.conversa_id).single();
      const { data: conta } = await db.from('crm_wa_contas').select('*').eq('id', conv!.conta_id).eq('unidade', s.unidade).maybeSingle();
      if (!conta) return json({ erro: 'conta_de_outra_unidade' }, 404);
      ({ path, mime } = await ingerir(msg, conta));
    }

    const { data: assinada, error } = await db.storage.from(BUCKET).createSignedUrl(path, EXPIRA);
    if (error) throw error;
    return json({ ok: true, url: assinada.signedUrl, mime, expira_em: EXPIRA });
  } catch (e) {
    const m = String((e as Error)?.message ?? e);
    if (m === 'conta_sem_token') return json({ erro: m, detalhe: 'O token deste número não está configurado no servidor.' }, 500);
    return json({ erro: m.slice(0, 300) }, 500);
  }
});
