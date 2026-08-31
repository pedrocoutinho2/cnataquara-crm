import { createClient } from 'jsr:@supabase/supabase-js@2';

const db = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

const TOKEN = Deno.env.get('WA_TOKEN') ?? '';
const GRAPH = Deno.env.get('WA_GRAPH_VERSION') ?? 'v21.0';

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

// Mesma chave canonica de crm_wa_chave: DDD + 8 ultimos digitos
function chave(num: string | null | undefined): string | null {
  let d = (num ?? '').replace(/\D/g, '');
  if (d.length >= 12 && d.startsWith('55')) d = d.slice(2);
  if (d.length < 10) return null;
  return d.slice(0, 2) + d.slice(-8);
}

// Abre (ou reaproveita) a conversa de um numero avulso, sem esperar mensagem de entrada
async function conversaPorNumero(contaId: string, waId: string) {
  const { data: existente } = await db.from('crm_wa_conversas')
    .select('*').eq('conta_id', contaId).eq('wa_id', waId).maybeSingle();
  if (existente) return existente;

  const k = chave(waId);
  let leadId: string | null = null;
  let ambiguo = false;
  if (k) {
    const { data: leads } = await db.from('crm_leads')
      .select('id, created_at').eq('wa_chave', k).order('created_at', { ascending: false });
    if (leads?.length) { leadId = leads[0].id; ambiguo = leads.length > 1; }
  }
  const { data: nova, error } = await db.from('crm_wa_conversas').insert({
    conta_id: contaId,
    wa_id: waId,
    numero_e164: '+' + waId.replace(/\D/g, ''),
    wa_chave: k,
    lead_id: leadId,
    lead_ambiguo: ambiguo,
  }).select('*').single();
  if (error) throw error;
  return nova;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ erro: 'method not allowed' }, 405);
  if (!TOKEN) return json({ erro: 'WA_TOKEN nao configurado' }, 500);

  let b: Record<string, any>;
  try { b = await req.json(); } catch { return json({ erro: 'json invalido' }, 400); }

  const texto: string | null = (b.texto ?? '').toString().trim() || null;
  const templateNome: string | null = b.template ?? null;
  const templateIdioma: string = b.template_idioma ?? 'pt_BR';
  const templateVars: string[] = Array.isArray(b.variaveis) ? b.variaveis.map(String) : [];
  const autorId: string | null = b.autor_id ?? null;

  try {
    // 1. Resolver conversa e conta
    let conversa: Record<string, any> | null = null;
    if (b.conversa_id) {
      const { data } = await db.from('crm_wa_conversas').select('*').eq('id', b.conversa_id).maybeSingle();
      conversa = data;
      if (!conversa) return json({ erro: 'conversa nao encontrada' }, 404);
    } else if (b.wa_id || b.numero) {
      const { data: conta } = await db.from('crm_wa_contas')
        .select('id').eq('ativa', true).order('created_at').limit(1).maybeSingle();
      if (!conta) return json({ erro: 'nenhuma conta de WhatsApp ativa em crm_wa_contas' }, 400);
      let waId = (b.wa_id ?? b.numero).toString().replace(/\D/g, '');
      if (!waId.startsWith('55')) waId = '55' + waId;
      conversa = await conversaPorNumero(conta.id, waId);
    } else {
      return json({ erro: 'informe conversa_id ou wa_id' }, 400);
    }

    const { data: conta } = await db.from('crm_wa_contas')
      .select('*').eq('id', conversa!.conta_id).single();
    if (!conta?.phone_number_id) return json({ erro: 'conta sem phone_number_id' }, 400);

    // 2. Regra da janela de 24h: fora dela, so template aprovado
    const janelaAberta = conversa!.janela_expira_em
      ? new Date(conversa!.janela_expira_em).getTime() > Date.now()
      : false;
    if (!janelaAberta && !templateNome) {
      return json({
        erro: 'janela_fechada',
        detalhe: 'A janela de 24 horas expirou. Fora dela so e possivel enviar template aprovado.',
        janela_expira_em: conversa!.janela_expira_em,
      }, 409);
    }
    if (!templateNome && !texto) return json({ erro: 'mensagem vazia' }, 400);

    // 3. Grava como pendente antes de chamar a Meta, para nada sumir se a API falhar
    const previa = templateNome ? (texto ?? `[template: ${templateNome}]`) : texto;
    const { data: msg, error: errIns } = await db.from('crm_wa_mensagens').insert({
      conversa_id: conversa!.id,
      direcao: 'saida',
      tipo: templateNome ? 'template' : 'texto',
      texto: previa,
      template_nome: templateNome,
      status: 'pendente',
      autor_id: autorId,
      wa_timestamp: new Date().toISOString(),
    }).select('*').single();
    if (errIns) throw errIns;

    // 4. Envio
    const payload: Record<string, any> = {
      messaging_product: 'whatsapp',
      recipient_type: 'individual',
      to: conversa!.wa_id,
    };
    if (templateNome) {
      payload.type = 'template';
      payload.template = {
        name: templateNome,
        language: { code: templateIdioma },
        ...(templateVars.length
          ? { components: [{ type: 'body', parameters: templateVars.map((t) => ({ type: 'text', text: t })) }] }
          : {}),
      };
    } else {
      payload.type = 'text';
      payload.text = { preview_url: true, body: texto };
    }

    const r = await fetch(`https://graph.facebook.com/${GRAPH}/${conta.phone_number_id}/messages`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${TOKEN}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    const resp = await r.json().catch(() => ({}));

    if (!r.ok) {
      const err = resp?.error ?? {};
      await db.from('crm_wa_mensagens').update({
        status: 'falhou',
        erro_codigo: String(err.code ?? r.status),
        erro_msg: err.error_user_msg ?? err.message ?? 'falha no envio',
      }).eq('id', msg.id);
      return json({ erro: 'falha_no_envio', detalhe: err.message ?? null, mensagem_id: msg.id }, 502);
    }

    const waMessageId = resp?.messages?.[0]?.id ?? null;
    await db.from('crm_wa_mensagens').update({
      status: 'enviado',
      wa_message_id: waMessageId,
    }).eq('id', msg.id);

    // Envio nao reabre a janela; ela so conta a partir da resposta do cliente
    await db.from('crm_wa_conversas').update({
      ultima_mensagem_em: new Date().toISOString(),
      atendente_id: autorId ?? conversa!.atendente_id,
      status: conversa!.status === 'resolvida' ? 'pendente' : conversa!.status,
    }).eq('id', conversa!.id);

    return json({ ok: true, mensagem_id: msg.id, wa_message_id: waMessageId, conversa_id: conversa!.id });
  } catch (e) {
    return json({ erro: String(e) }, 500);
  }
});
