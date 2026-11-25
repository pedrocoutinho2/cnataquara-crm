// wa-send v5 · envia mensagem de WhatsApp pela conta da unidade da sessão do CRM.
// Spec: 10-cna/sistemas/whatsapp-multinumero.md (W2). Dívida nº 3 fechada aqui:
//   - exige o token de sessão do CRM (crm_wa_sessao, nível 2 em 'conversas'); a chave anon sozinha não envia
//   - conversa e conta sempre da unidade da sessão; número avulso usa o número principal da unidade (v5)
//   - autor_id vem da sessão, nunca do cliente
//   - token do provedor lido do secret apontado por crm_wa_contas.token_ref (WA_TOKEN_* ou EVO_TOKEN_*)
//   - opt-out respeitado no ato (crm_wa_optout por unidade + wa_chave)
// v3 (16/11/2026, multiagente): consultor só envia em conversa dele (gestão em qualquer uma);
//   enviar não troca o dono; conversa nova aberta pelo CRM nasce com quem enviou.
// v4 (16/11/2026): quem acompanha a conversa (crm_wa_seguidores) também responde, sem virar dono.
//   Ações além do texto (só Evolution): { acao: 'reagir', mensagem_id, emoji } · { acao: 'editar', mensagem_id, texto }
//   · { acao: 'apagar', mensagem_id } (apaga para todos; no CRM a mensagem fica marcada, o texto não some)
//   · { acao: 'midia', conversa_id, base64, mime, nome?, legenda? } (imagem, vídeo, documento; áudio vai como nota de voz).
//   Editar e apagar só em mensagem enviada pela escola.
// v5 (25/11/2026): conversa NOVA (por número) sai sempre pelo número principal da unidade
//   (crm_wa_contas.principal); conta_id do cliente é ignorado. Os outros números só continuam conversas existentes.
// Transporte por conta: 'cloud' (Meta Cloud API, janela de 24h e template) ou 'evolution' (sessão por QR).
import { createClient } from 'jsr:@supabase/supabase-js@2';

const db = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

const GRAPH = Deno.env.get('WA_GRAPH_VERSION') ?? 'v21.0';
const EVO_URL = (Deno.env.get('EVO_URL') ?? 'https://evo.cnataquara.com.br').replace(/\/+$/, '');

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

// Mesma chave canônica de crm_wa_chave: DDD + 8 últimos dígitos
function chave(num: string | null | undefined): string | null {
  let d = (num ?? '').replace(/\D/g, '');
  if (d.length >= 12 && d.startsWith('55')) d = d.slice(2);
  if (d.length < 10) return null;
  return d.slice(0, 2) + d.slice(-8);
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

async function conversaPorNumero(conta: J, waId: string, autor: string): Promise<J> {
  const { data: existente } = await db.from('crm_wa_conversas')
    .select('*').eq('conta_id', conta.id).eq('wa_id', waId).maybeSingle();
  if (existente) return existente;
  const k = chave(waId);
  let leadId: string | null = null;
  let ambiguo = false;
  if (k) {
    const { data: leads } = await db.from('crm_leads')
      .select('id, created_at').eq('wa_chave', k).eq('unidade', conta.unidade)
      .order('created_at', { ascending: false });
    if (leads?.length) { leadId = leads[0].id; ambiguo = leads.length > 1; }
  }
  const { data: nova, error } = await db.from('crm_wa_conversas').insert({
    conta_id: conta.id, wa_id: waId, numero_e164: '+' + waId, wa_chave: k, lead_id: leadId, lead_ambiguo: ambiguo,
    atendente_id: autor, atribuicao: 'manual', atribuida_em: new Date().toISOString(),
  }).select('*').single();
  if (error?.code === '23505') {
    const { data: outra } = await db.from('crm_wa_conversas').select('*').eq('conta_id', conta.id).eq('wa_id', waId).single();
    return outra!;
  }
  if (error) throw error;
  return nova;
}

async function enviarCloud(conta: J, conversa: J, texto: string | null, tpl: { nome: string; idioma: string; vars: string[] } | null) {
  if (!conta.phone_number_id) throw new Error('conta_sem_phone_number_id');
  const payload: J = { messaging_product: 'whatsapp', recipient_type: 'individual', to: conversa.wa_id };
  if (tpl) {
    payload.type = 'template';
    payload.template = {
      name: tpl.nome, language: { code: tpl.idioma },
      ...(tpl.vars.length ? { components: [{ type: 'body', parameters: tpl.vars.map((t) => ({ type: 'text', text: t })) }] } : {}),
    };
  } else {
    payload.type = 'text';
    payload.text = { preview_url: true, body: texto };
  }
  const r = await fetch(`https://graph.facebook.com/${GRAPH}/${conta.phone_number_id}/messages`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${segredo(conta)}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
  const resp = await r.json().catch(() => ({}));
  if (!r.ok) {
    const err = resp?.error ?? {};
    return { ok: false, codigo: String(err.code ?? r.status), msg: err.error_user_msg ?? err.message ?? 'falha no envio' };
  }
  return { ok: true, id: resp?.messages?.[0]?.id ?? null };
}

async function enviarEvolution(conta: J, conversa: J, texto: string) {
  if (!conta.evolution_instancia) throw new Error('conta_sem_instancia');
  const r = await fetch(`${EVO_URL}/message/sendText/${encodeURIComponent(conta.evolution_instancia)}`, {
    method: 'POST',
    headers: { apikey: segredo(conta), 'Content-Type': 'application/json' },
    body: JSON.stringify({ number: conversa.wa_id, text: texto }),
  });
  const resp = await r.json().catch(() => ({}));
  if (!r.ok) {
    const m = resp?.response?.message ?? resp?.message ?? resp?.error ?? `HTTP ${r.status}`;
    return { ok: false, codigo: String(r.status), msg: (Array.isArray(m) ? JSON.stringify(m) : String(m)).slice(0, 300) };
  }
  return { ok: true, id: resp?.key?.id ?? null };
}

async function evo(conta: J, rota: string, corpo: J, metodo = 'POST') {
  const r = await fetch(`${EVO_URL}${rota}/${encodeURIComponent(conta.evolution_instancia)}`, {
    method: metodo, headers: { apikey: segredo(conta), 'Content-Type': 'application/json' }, body: JSON.stringify(corpo),
  });
  const resp = await r.json().catch(() => ({}));
  if (!r.ok) {
    const m = resp?.response?.message ?? resp?.message ?? resp?.error ?? `HTTP ${r.status}`;
    throw new Error('evolution:' + (Array.isArray(m) ? JSON.stringify(m) : String(m)).slice(0, 300));
  }
  return resp;
}

const EXT: Record<string, string> = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'video/mp4': 'mp4',
  'audio/ogg': 'ogg', 'audio/mpeg': 'mp3', 'audio/webm': 'webm', 'audio/mp4': 'm4a', 'application/pdf': 'pdf' };

async function acao(b: J, s: J, conta: J, conversa: J): Promise<Response> {
  if (conta.provider !== 'evolution') return json({ erro: 'nao_suportado', detalhe: 'Disponível só nos números conectados pela Evolution.' }, 409);
  const jid = `${conversa.wa_id}@s.whatsapp.net`;
  const tipo = String(b.acao);
  if (tipo === 'reagir' || tipo === 'editar' || tipo === 'apagar') {
    const { data: m } = await db.from('crm_wa_mensagens').select('*').eq('id', b.mensagem_id).eq('conversa_id', conversa.id).maybeSingle();
    if (!m?.wa_message_id) return json({ erro: 'mensagem_nao_encontrada', detalhe: 'Mensagem ainda sem confirmação do WhatsApp.' }, 404);
    const fromMe = m.direcao === 'saida';
    const key = { remoteJid: jid, fromMe, id: m.wa_message_id };
    if (tipo === 'reagir') {
      const emoji = String(b.emoji ?? '');
      await evo(conta, '/message/sendReaction', { key, reaction: emoji });
      const reacoes: J = { ...(m.reacoes ?? {}) };
      if (emoji) reacoes.nos = emoji; else delete reacoes.nos;
      await db.from('crm_wa_mensagens').update({ reacoes }).eq('id', m.id);
      return json({ ok: true, reacoes });
    }
    if (!fromMe) return json({ erro: 'so_mensagem_da_escola', detalhe: 'Só dá para editar ou apagar mensagem enviada pela escola.' }, 409);
    if (tipo === 'editar') {
      const texto = String(b.texto ?? '').trim();
      if (!texto) return json({ erro: 'mensagem vazia' }, 400);
      await evo(conta, '/chat/updateMessage', { number: conversa.wa_id, key, text: texto });
      await db.from('crm_wa_mensagens').update({ texto, editada: true }).eq('id', m.id);
      return json({ ok: true });
    }
    await evo(conta, '/chat/deleteMessageForEveryone', { id: m.wa_message_id, remoteJid: jid, fromMe: true }, 'DELETE');
    await db.from('crm_wa_mensagens').update({ apagada: true }).eq('id', m.id);
    return json({ ok: true });
  }
  if (tipo === 'midia') {
    const b64 = String(b.base64 ?? '').replace(/^data:[^,]+,/, '');
    const mime = String(b.mime ?? 'application/octet-stream');
    if (!b64) return json({ erro: 'arquivo vazio' }, 400);
    if (b64.length > 22_000_000) return json({ erro: 'arquivo_grande', detalhe: 'Arquivo acima de 16 MB.' }, 413);
    const audio = mime.startsWith('audio/');
    const mt = mime.startsWith('image/') ? 'image' : mime.startsWith('video/') ? 'video' : 'document';
    const tipoMsg = audio ? 'audio' : mt === 'image' ? 'imagem' : mt === 'video' ? 'video' : 'documento';
    const nome = String(b.nome ?? `arquivo.${EXT[mime] ?? 'bin'}`).slice(0, 120);
    const legenda = (b.legenda ?? '').toString().trim() || null;
    const { data: msg, error } = await db.from('crm_wa_mensagens').insert({
      conversa_id: conversa.id, direcao: 'saida', tipo: tipoMsg, texto: legenda, midia_mime: mime, midia_nome: audio ? null : nome,
      status: 'pendente', autor_id: s.usuario_id, wa_timestamp: new Date().toISOString(),
    }).select('*').single();
    if (error) throw error;
    // guarda no bucket antes de enviar: o CRM mostra a mídia mesmo se a API cair
    const path = `${conversa.unidade}/${conversa.id}/${msg.id}.${EXT[mime] ?? (nome.split('.').pop() || 'bin')}`;
    const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
    await db.storage.from('wa-media').upload(path, bytes, { contentType: mime, upsert: true });
    await db.from('crm_wa_mensagens').update({ midia_path: path }).eq('id', msg.id);
    try {
      const resp = audio
        ? await evo(conta, '/message/sendWhatsAppAudio', { number: conversa.wa_id, audio: b64 })
        : await evo(conta, '/message/sendMedia', { number: conversa.wa_id, mediatype: mt, mimetype: mime, media: b64, fileName: nome, ...(legenda ? { caption: legenda } : {}) });
      const id = resp?.key?.id ?? null;
      const { error: eu } = await db.from('crm_wa_mensagens').update({ status: 'enviado', wa_message_id: id }).eq('id', msg.id);
      if (eu?.code === '23505' && id) {
        // eco chegou antes: a linha do eco recebe o arquivo do bucket e o autor; a pendente sai
        await db.from('crm_wa_mensagens').update({ autor_id: s.usuario_id, midia_path: path }).eq('wa_message_id', id);
        await db.from('crm_wa_mensagens').delete().eq('id', msg.id);
      }
      await db.from('crm_wa_conversas').update({ atendente_id: conversa.atendente_id ?? s.usuario_id }).eq('id', conversa.id);
      return json({ ok: true, mensagem_id: msg.id, wa_message_id: id });
    } catch (e) {
      await db.from('crm_wa_mensagens').update({ status: 'falhou', erro_msg: String((e as Error).message).slice(0, 300) }).eq('id', msg.id);
      return json({ erro: 'falha_no_envio', detalhe: String((e as Error).message), mensagem_id: msg.id }, 502);
    }
  }
  return json({ erro: 'acao_invalida' }, 400);
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ erro: 'method not allowed' }, 405);

  let b: J;
  try { b = await req.json(); } catch { return json({ erro: 'json invalido' }, 400); }

  let s: J;
  try { s = await sessao(b.token, 2); } catch (e) {
    const m = String((e as Error).message);
    return json({ erro: m, detalhe: m === 'sem_permissao' ? 'Seu acesso a Conversas não permite enviar.' : 'Sessão expirada. Entre de novo.' }, m === 'sem_permissao' ? 403 : 401);
  }
  const unidade: string = s.unidade;

  const texto: string | null = (b.texto ?? '').toString().trim() || null;
  const templateNome: string | null = b.template ? String(b.template) : null;

  try {
    // 1. conversa e conta, sempre da unidade da sessão
    let conversa: J | null = null;
    let conta: J | null = null;
    if (b.mensagem_id && !b.conversa_id) {
      const { data: mm } = await db.from('crm_wa_mensagens').select('conversa_id').eq('id', b.mensagem_id).eq('unidade', unidade).maybeSingle();
      if (!mm) return json({ erro: 'mensagem_nao_encontrada' }, 404);
      b.conversa_id = mm.conversa_id;
    }
    if (b.conversa_id) {
      const { data } = await db.from('crm_wa_conversas').select('*').eq('id', b.conversa_id).eq('unidade', unidade).maybeSingle();
      if (!data) return json({ erro: 'conversa_de_outra_unidade', detalhe: 'Conversa não encontrada nesta unidade.' }, 404);
      conversa = data;
      const { data: c } = await db.from('crm_wa_contas').select('*').eq('id', data.conta_id).eq('unidade', unidade).maybeSingle();
      conta = c;
    } else if (b.wa_id || b.numero) {
      const { data: contas } = await db.from('crm_wa_contas').select('*').eq('unidade', unidade).eq('ativa', true);
      if (!contas?.length) return json({ erro: 'sem_conta', detalhe: 'Nenhum número de WhatsApp ativo nesta unidade.' }, 400);
      const principal = contas.find((c: J) => c.principal) ?? (contas.length === 1 ? contas[0] : null);
      if (!principal) return json({ erro: 'sem_principal', detalhe: 'Esta unidade não tem número principal ativo para começar conversa.' }, 409);
      conta = principal;
      let waId = String(b.wa_id ?? b.numero).replace(/\D/g, '');
      if (!waId.startsWith('55')) waId = '55' + waId;
      if (waId.length < 12) return json({ erro: 'numero_invalido', detalhe: 'Número de WhatsApp inválido.' }, 400);
      conversa = await conversaPorNumero(conta!, waId, s.usuario_id);
    } else {
      return json({ erro: 'informe conversa_id ou wa_id' }, 400);
    }
    if (!conta) return json({ erro: 'conta_de_outra_unidade' }, 404);
    // multiagente: conversa de outro consultor só a gestão ou quem acompanha responde
    if (conversa!.atendente_id && conversa!.atendente_id !== s.usuario_id) {
      const { data: seg } = await db.from('crm_wa_seguidores').select('usuario_id')
        .eq('conversa_id', conversa!.id).eq('usuario_id', s.usuario_id).maybeSingle();
      const { data: vt } = seg ? { data: true } : await db.rpc('crm_wa_ve_tudo', { p_usuario: s.usuario_id, p_unidade: unidade });
      if (!vt) return json({ erro: 'conversa_de_outro_agente', detalhe: 'Esta conversa é de outro consultor.' }, 403);
    }
    if (!conta.ativa) return json({ erro: 'conta_inativa', detalhe: 'Este número está desativado no CRM.' }, 409);

    // 2. opt-out
    const k = conversa!.wa_chave ?? chave(conversa!.wa_id);
    if (k) {
      const { data: oo } = await db.from('crm_wa_optout').select('wa_chave').eq('unidade', unidade).eq('wa_chave', k).maybeSingle();
      if (oo) return json({ erro: 'optout', detalhe: 'Este contato pediu para não receber mensagens.' }, 409);
    }

    if (b.acao) return await acao(b, s, conta, conversa!);

    // 3. regras do transporte
    const evo = conta.provider === 'evolution';
    let tpl: { nome: string; idioma: string; vars: string[] } | null = null;
    if (evo) {
      // Evolution não tem template nem janela: manda o texto (ou a prévia do template, já preenchida)
      if (!texto) return json({ erro: 'mensagem vazia' }, 400);
    } else {
      const janelaAberta = conversa!.janela_expira_em ? new Date(conversa!.janela_expira_em).getTime() > Date.now() : false;
      if (!janelaAberta && !templateNome) {
        return json({ erro: 'janela_fechada', detalhe: 'A janela de 24 horas expirou. Fora dela só é possível enviar template aprovado.', janela_expira_em: conversa!.janela_expira_em }, 409);
      }
      if (templateNome) {
        tpl = { nome: templateNome, idioma: String(b.template_idioma ?? 'pt_BR'), vars: Array.isArray(b.variaveis) ? b.variaveis.map(String) : [] };
      } else if (!texto) return json({ erro: 'mensagem vazia' }, 400);
    }

    // 4. grava como pendente antes de chamar o provedor, para nada sumir se a API falhar
    const previa = tpl ? (texto ?? `[template: ${tpl.nome}]`) : texto;
    const { data: msg, error: errIns } = await db.from('crm_wa_mensagens').insert({
      conversa_id: conversa!.id, direcao: 'saida', tipo: tpl ? 'template' : 'texto', texto: previa,
      template_nome: tpl?.nome ?? null, status: 'pendente', autor_id: s.usuario_id, wa_timestamp: new Date().toISOString(),
    }).select('*').single();
    if (errIns) throw errIns;

    // 5. envio
    const r = evo ? await enviarEvolution(conta, conversa!, texto!) : await enviarCloud(conta, conversa!, texto, tpl);
    if (!r.ok) {
      await db.from('crm_wa_mensagens').update({ status: 'falhou', erro_codigo: r.codigo, erro_msg: r.msg }).eq('id', msg.id);
      return json({ erro: 'falha_no_envio', detalhe: r.msg, mensagem_id: msg.id }, 502);
    }

    let mensagemId = msg.id;
    const { error: errUp } = await db.from('crm_wa_mensagens').update({ status: 'enviado', wa_message_id: r.id }).eq('id', msg.id);
    if (errUp?.code === '23505' && r.id) {
      // o eco do webhook da Evolution chegou antes: fica a linha do eco, com o autor; a pendente sai
      const { data: eco } = await db.from('crm_wa_mensagens').update({ autor_id: s.usuario_id }).eq('wa_message_id', r.id).select('id').maybeSingle();
      if (eco) { await db.from('crm_wa_mensagens').delete().eq('id', msg.id); mensagemId = eco.id; }
    } else if (errUp) throw errUp;

    await db.from('crm_wa_conversas').update({
      atendente_id: conversa!.atendente_id ?? s.usuario_id,
      status: conversa!.status === 'resolvida' ? 'pendente' : conversa!.status,
    }).eq('id', conversa!.id);

    return json({ ok: true, mensagem_id: mensagemId, wa_message_id: r.id, conversa_id: conversa!.id, provider: conta.provider });
  } catch (e) {
    const m = String((e as Error)?.message ?? e);
    if (m.startsWith('evolution:')) return json({ erro: 'falha_no_envio', detalhe: m.slice(10) }, 502);
    if (m === 'conta_sem_token') return json({ erro: m, detalhe: 'O token deste número não está configurado no servidor.' }, 500);
    return json({ erro: m }, 500);
  }
});
