import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANTHROPIC    = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
const MODELO       = Deno.env.get("ATA_MODELO") ?? "claude-sonnet-5";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

async function rest(path: string, init: RequestInit = {}) {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      "Content-Type": "application/json",
      Prefer: "return=representation",
      ...(init.headers ?? {}),
    },
  });
  const txt = await r.text();
  if (!r.ok) throw new Error(`${path}: ${r.status} ${txt.slice(0, 300)}`);
  return txt ? JSON.parse(txt) : null;
}

/* soma dias a uma data ISO sem cair em fuso */
function addDias(iso: string, n: number) {
  const [y, m, d] = iso.split("-").map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  dt.setUTCDate(dt.getUTCDate() + n);
  return dt.toISOString().slice(0, 10);
}

const SISTEMA = `Você analisa atas de reunião do CNA Taquara, uma escola de idiomas no Rio de Janeiro, e transforma o texto corrido em estrutura acionável.

Responda SOMENTE com um objeto JSON válido. Sem markdown, sem crases, sem texto antes ou depois.

Formato exato:
{
  "resumo": "3 a 5 frases em português do Brasil, direto, sem jargão corporativo",
  "decisoes": [{"texto": "decisão tomada", "responsavel": "Nome ou null"}],
  "tarefas": [{
    "titulo": "até 60 caracteres, começando com verbo no infinitivo",
    "descricao": "o que precisa ser feito e por quê",
    "responsavel": "Nome exato da lista ou null",
    "prazo": "YYYY-MM-DD",
    "prazo_inferido": true,
    "prioridade": "alta|media|baixa",
    "trecho_origem": "a frase da ata que gerou esta tarefa, copiada literalmente"
  }],
  "pendencias": [{"texto": "assunto que ficou em aberto", "bloqueador": "o que trava ou null"}],
  "riscos": ["risco percebido"],
  "proxima_reuniao": {"sugerida": true, "quando": "YYYY-MM-DD ou null", "pauta": ["item"]}
}

Regras obrigatórias:
- "responsavel" só pode ser um nome EXATO da lista de participantes fornecida. Se a ata não deixar claro quem faz, use null.
- Prazos relativos ("até sexta", "semana que vem", "amanhã") resolvem contra a DATA DA REUNIÃO informada, nunca contra a data de hoje.
- Se a ata não indica prazo, use a data padrão fornecida e marque "prazo_inferido": true. Se a ata indica prazo, marque false.
- "trecho_origem" é obrigatório em toda tarefa e precisa ser texto que realmente aparece na ata.
- Não invente tarefa, decisão ou pendência que não esteja no texto. Ata vaga gera poucas tarefas, e isso está correto.
- Assunto que foi citado mas não teve encaminhamento vira pendência, nunca tarefa.
- Nunca use travessão no texto que você escrever.
- Arrays vazios são válidos. Prefira omitir a inventar.`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ erro: "use POST" }, 405);

  if (!ANTHROPIC) {
    return json({ erro: "ANTHROPIC_API_KEY nao configurada nos secrets do projeto" }, 503);
  }

  let reuniao_id = "";
  try {
    ({ reuniao_id } = await req.json());
  } catch {
    return json({ erro: "corpo invalido" }, 400);
  }
  if (!reuniao_id) return json({ erro: "reuniao_id obrigatorio" }, 400);

  try {
    const rs = await rest(`crm_reunioes?id=eq.${reuniao_id}&select=*`);
    const r = rs?.[0];
    if (!r) return json({ erro: "reuniao nao encontrada" }, 404);
    if (!r.ata_bruta || r.ata_bruta.trim().length < 40) {
      return json({ erro: "a ata esta muito curta para analisar" }, 400);
    }
    if (r.status !== "rascunho" && r.status !== "analisada") {
      return json({ erro: "ata ja congelada, nao pode ser reanalisada" }, 409);
    }

    const parts = await rest(
      `crm_reuniao_participantes?reuniao_id=eq.${reuniao_id}&select=nome,presente`,
    );
    const presentes = (parts ?? []).filter((p: any) => p.presente).map((p: any) => p.nome);
    const nomes = presentes.length ? presentes : (parts ?? []).map((p: any) => p.nome);
    const prazoPadrao = addDias(r.data, 7);

    const prompt =
      `DATA DA REUNIÃO: ${r.data}\n` +
      `TÍTULO: ${r.titulo}\n` +
      `TIPO: ${r.tipo}\n` +
      `PARTICIPANTES (nomes válidos para o campo responsavel): ${nomes.join(", ") || "nenhum informado"}\n` +
      `PRAZO PADRÃO quando a ata não disser nada: ${prazoPadrao}\n\n` +
      `ATA:\n"""\n${r.ata_bruta}\n"""`;

    const ia = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": ANTHROPIC,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: MODELO,
        max_tokens: 4000,
        system: SISTEMA,
        messages: [{ role: "user", content: prompt }],
      }),
    });

    if (!ia.ok) {
      const t = await ia.text();
      let detalhe = t.slice(0, 300);
      try { detalhe = JSON.parse(t)?.error?.message ?? detalhe; } catch { /* texto cru */ }
      if (/credit balance/i.test(detalhe)) {
        return json({ erro: "A conta da Anthropic esta sem creditos. Adicione saldo em Plans & Billing no console." }, 402);
      }
      if (ia.status === 401) {
        return json({ erro: "A chave da Anthropic foi recusada. Confira o secret ANTHROPIC_API_KEY." }, 401);
      }
      if (ia.status === 429) {
        return json({ erro: "Limite de uso da IA atingido. Tente de novo em alguns minutos." }, 429);
      }
      return json({ erro: `API da Anthropic: ${detalhe}` }, 502);
    }

    const data = await ia.json();
    const bruto = (data.content ?? [])
      .filter((b: any) => b.type === "text")
      .map((b: any) => b.text)
      .join("\n")
      .trim();

    let parsed: any;
    try {
      const limpo = bruto.replace(/^```(?:json)?/i, "").replace(/```$/i, "").trim();
      parsed = JSON.parse(limpo);
    } catch {
      const i = bruto.indexOf("{"), j = bruto.lastIndexOf("}");
      if (i < 0 || j <= i) return json({ erro: "a IA nao devolveu JSON valido", bruto: bruto.slice(0, 500) }, 502);
      parsed = JSON.parse(bruto.slice(i, j + 1));
    }

    /* saneamento: responsavel invalido vira null, prazo fora do formato vira o padrao */
    const validos = new Set(nomes);
    parsed.tarefas = (parsed.tarefas ?? []).map((t: any) => ({
      titulo: String(t.titulo ?? "").slice(0, 120),
      descricao: t.descricao ?? "",
      responsavel: validos.has(t.responsavel) ? t.responsavel : null,
      prazo: /^\d{4}-\d{2}-\d{2}$/.test(t.prazo ?? "") ? t.prazo : prazoPadrao,
      prazo_inferido: t.prazo_inferido !== false,
      prioridade: ["alta", "media", "baixa"].includes(t.prioridade) ? t.prioridade : "media",
      trecho_origem: t.trecho_origem ?? "",
    })).filter((t: any) => t.titulo);
    parsed.decisoes = (parsed.decisoes ?? []).map((d: any) => ({
      texto: String(d.texto ?? d),
      responsavel: validos.has(d.responsavel) ? d.responsavel : null,
    })).filter((d: any) => d.texto);
    parsed.pendencias = (parsed.pendencias ?? []).map((p: any) => ({
      texto: String(p.texto ?? p),
      bloqueador: p.bloqueador ?? null,
    })).filter((p: any) => p.texto);

    await rest(`crm_reunioes?id=eq.${reuniao_id}`, {
      method: "PATCH",
      body: JSON.stringify({
        resumo: parsed.resumo ?? null,
        decisoes: parsed.decisoes,
        pendencias: parsed.pendencias,
        analise_payload: parsed,
        analise_em: new Date().toISOString(),
        analise_modelo: MODELO,
        status: "analisada",
        atualizado_em: new Date().toISOString(),
      }),
    });

    return json({ ok: true, analise: parsed, modelo: MODELO, uso: data.usage ?? null });
  } catch (e) {
    return json({ erro: String((e as Error).message ?? e) }, 500);
  }
});
