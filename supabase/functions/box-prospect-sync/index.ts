// box-prospect-sync: envia a fila crm_box_fila do CRM para o CNA Box com o login de cada consultor.
// Base gpnwmsnayrqjcmhqrtpx (rede). Ver vault: 10-cna/sistemas/integracao-crm-box.md
//
// Acesso (verify_jwt desligado, checagem própria, falha fechada):
//   - header x-box-cron com o segredo 'crm_box_cron' do Vault (agendamento), ou
//   - body.token = token de sessão do CRM com nível total no módulo leads.
// Modo: por padrão SIMULA (monta payload, faz login e busca só se pedir). Envio real exige body.enviar === true.
// Senhas: lidas do Vault pela RPC crm_box_credencial_ler (só service_role). Nunca vão para log ou resposta.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { DOMParser, Element } from "jsr:@b-fuze/deno-dom";

const BOX = "https://www.cnabox.com.br";
const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type, x-box-cron, apikey, authorization",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...CORS, "content-type": "application/json" } });

// ---------- mapeamentos CRM -> Box (decisões de 05/11/2026) ----------
const MIDIA: Record<string, string> = {
  "Google": "16", "Instagram": "14", "Facebook": "14", "Indicação": "17", "Ação comercial": "1",
  "Flyer": "50", "Presencial": "52", "Matriz": "43",
};
const IDIOMA: Record<string, string> = { "Inglês": "1", "Espanhol": "2", "Proficiência": "3", "Robótica": "6" };
// Box: 1 Não atende, 2 Telefone errado, 3 Outros, 6 Não estava, 8 Não pode falar agora
const MOTIVO_INEFETIVO: Record<string, string> = {
  nao_atendeu: "1", caixa_postal: "1", numero_errado: "2", nao_leu: "3", recusou: "3", ausente: "6", pediu_retorno: "8",
};
const MOTIVO_REPIQUE: Record<string, string> = { vai_pesquisar: "1", sem_tempo: "3", desempregado: "4", nao_quer_agora: "7" };

const dataBR = (iso?: string | null) => (iso ? iso.slice(0, 10).split("-").reverse().join("/") : "");
const digitos = (s?: string | null) => (s || "").replace(/\D/g, "");
function foneBox(s?: string | null) {
  let d = digitos(s);
  if (d.length > 11 && d.startsWith("55")) d = d.slice(2);
  if (d.length === 11) return `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}`;
  if (d.length === 10) return `(${d.slice(0, 2)}) ${d.slice(2, 6)}-${d.slice(6)}`;
  return d;
}

// deno-lint-ignore no-explicit-any
type Item = any;

export function atendimento(it: Item, pessoaId: string) {
  const i = it.interacao;
  const tipo = i.tipo === "ligacao" ? "1" : i.tipo === "visita" ? "3" : "2";
  const eletronico = tipo === "2" ? (i.tipo === "email" ? "2" : "4") : "";
  let acao = "6";
  if (i.proximo_canal === "visita" || i.proximo_canal === "reuniao") acao = "1";
  else if (i.proximo_canal === "teste_nivel" || i.proximo_canal === "experimental") acao = "5";
  else if (i.proximo_contato) acao = "2";
  const hora = (i.proximo_contato_hora || "09:00").slice(0, 5);
  const desc = (i.nota || "").trim() || "Contato registrado no CRM.";
  // deno-lint-ignore no-explicit-any
  const a: any = {
    Agenda: i.proximo_contato ? { DataInicio: `${dataBR(i.proximo_contato)} ${hora}`, Descricao: desc } : null,
    CollectionSolicitacaoSuspensao: null,
    Efetivo: i.efetivo !== false,
    Receptivo: !!i.receptivo, // no JSON do Box, true = receptivo (o rádio da tela é invertido)
    Descricao: desc,
    PessoaEscolaId: pessoaId,
    CategoriaAtendimentoId: 1,
    TipoAtendimentoId: tipo,
    TipoAcaoAtendimentoId: acao,
    MotivoNaoAgendamentoPessoalId: i.efetivo !== false && acao === "2" ? (MOTIVO_REPIQUE[i.motivo_repique] || "") : "",
    MotivoAtendimentoInefetivoId: i.efetivo === false ? (MOTIVO_INEFETIVO[i.motivo_nao_efetivo] || "3") : "",
    MotivoNaoMatriculaId: null,
  };
  if (eletronico) a.TipoAtendimentoEletronicoId = eletronico;
  return a;
}

export function payloadNovo(it: Item) {
  const l = it.lead;
  const idioma = IDIOMA[l.curso];
  return {
    CollectionAlunoTag: [],
    CollectionAlunoDisponibilidadePeriodo: (l.disponibilidade || []).map((p: number) => ({ DisponibilidadePeriodoId: String(p) })),
    CollectionAlunoIdioma: idioma ? [{ IdiomaId: idioma, EstagioInteresseId: "", ModalidadeInteresseId: "" }] : [],
    CollectionPessoaResponsavel: null,
    PessoaEscola: {
      CollectionAtendimento: [atendimento(it, "0")],
      CollectionPessoaInteresse: [],
      Endereco: { EnderecoId: "0", CEP: "", Rua: "", Numero: "", Complemento: "", Cidade: "", EstadoId: "", Bairro: "" },
      EnderecoId: "0",
      DataNascimento: dataBR(l.data_nascimento),
      Sexo: l.sexo === "M" ? "1" : l.sexo === "F" ? "2" : "",
      Nome: (l.nome || "").toUpperCase(),
      Apelido: (l.nome || "").toUpperCase(),
      Email: l.email || "",
      EmailSecundario: null,
      Telefone: "",
      Celular: foneBox(l.whatsapp),
      PessoaEscolaId: "0",
      CPF_CNPJ: "",
      RG_IE: "",
      PessoaCNAId: null,
    },
    MidiaId: MIDIA[l.origem] || "",
    AcaoComercialId: null,
    CampanhaId: " ",
    AlunoIndicacaoId: "0",
    EmpresaEscola: " ",
    Escola: " ",
    Observacoes: " ",
    Diagnostico: " ",
    NaoReceberEmail: false,
    NaoReceberSMS: false,
    NaoReceberLigacoes: false,
    NaoReceberWhatsapp: false,
    AlunoId: "0",
    InstituicaoEnsinoId: null,
    ConfirmationResponseBehavior: " ",
    AlunoValidacaoDados: {
      AlunoValidacaoDadosId: "0", EnviarEmail: false, EnviarSms: false, EnviarComprovanteAutorizacao: false,
      EmailEnviado: "", CelularEnviado: "", ComprovanteEnviado: "", CodigoEnviado: "", CodigoValidado: "False",
    },
    AttributeBehavior: "SaveProspect",
  };
}

// Prospect que já existe: a ficha vai inteira no Save, então parte do que está no Box hoje
// e só acrescenta o atendimento novo (e campos que estavam vazios lá). Nunca apaga dado do Box.
export function payloadExistente(it: Item, html: string, boxId: string) {
  const doc = new DOMParser().parseFromString(html, "text/html");
  const f = doc?.querySelector("#frmProspectCreate") as Element | null;
  if (!f) throw new Error("ficha_do_box_nao_carregou");
  const val = (n: string) => (f.querySelector(`[name="${n}"]`) as Element | null)?.getAttribute("value") ?? "";
  const txt = (n: string) => (f.querySelector(`[name="${n}"]`) as Element | null)?.textContent ?? "";
  const sel = (n: string) => {
    const s = f.querySelector(`select[name="${n}"]`) as Element | null;
    const o = s?.querySelector("option[selected]") as Element | null;
    return o?.getAttribute("value") ?? "";
  };
  const radio = (n: string) => (f.querySelector(`input[name="${n}"][checked]`) as Element | null)?.getAttribute("value") ?? "";
  const checks = (n: string) =>
    [...f.querySelectorAll(`input[name="${n}"][checked]`)].map((e) => (e as Element).getAttribute("value") || "");
  const tags = [...f.querySelectorAll('select[name="TagNome"] option[selected]')];
  if (tags.length) throw new Error("ficha_com_tags_revisar_formato");

  const l = it.lead;
  const idiomas = checks("IdiomaId").map((id) => ({
    IdiomaId: id, EstagioInteresseId: sel(`EstagioInteresseId_${id}`), ModalidadeInteresseId: sel(`ModalidadeInteresseId_${id}`),
  }));
  const idiomaCrm = IDIOMA[l.curso];
  if (!idiomas.length && idiomaCrm) idiomas.push({ IdiomaId: idiomaCrm, EstagioInteresseId: "", ModalidadeInteresseId: "" });
  let disp = checks("DisponibilidadePeriodoId");
  if (!disp.length) disp = (l.disponibilidade || []).map(String);
  const end = (k: string) => val(`Endereco.${k}`);
  const nasc = val("DataNascimento") || dataBR(l.data_nascimento);
  const vazio = (s: string) => (s && s.trim() ? s : " ");
  return {
    CollectionAlunoTag: [],
    CollectionAlunoDisponibilidadePeriodo: disp.map((p) => ({ DisponibilidadePeriodoId: p })),
    CollectionAlunoIdioma: idiomas,
    CollectionPessoaResponsavel: null,
    PessoaEscola: {
      CollectionAtendimento: [atendimento(it, boxId)],
      CollectionPessoaInteresse: [],
      Endereco: {
        EnderecoId: end("EnderecoId") || val("EnderecoId"), CEP: end("CEP"), Rua: end("Rua"), Numero: end("Numero"),
        Complemento: end("Complemento"), Cidade: end("Cidade"), EstadoId: sel("Endereco.EstadoId"), Bairro: end("Bairro"),
      },
      EnderecoId: val("EnderecoId"),
      DataNascimento: nasc,
      Sexo: radio("Sexo") || (l.sexo === "M" ? "1" : l.sexo === "F" ? "2" : ""),
      Nome: val("Nome"),
      Apelido: val("Nome"),
      Email: val("Email") || l.email || "",
      EmailSecundario: null,
      Telefone: val("Telefone"),
      Celular: val("Celular") || foneBox(l.whatsapp),
      PessoaEscolaId: boxId,
      CPF_CNPJ: val("CPF_CNPJ"),
      RG_IE: val("RG_IE"),
      PessoaCNAId: null,
    },
    MidiaId: sel("MidiaId") || MIDIA[l.origem] || "",
    AcaoComercialId: null,
    CampanhaId: vazio(sel("CampanhaId")),
    AlunoIndicacaoId: val("AlunoIndicacaoId") || "0",
    EmpresaEscola: vazio(val("EmpresaEscola")),
    Escola: vazio(val("Escola")),
    Observacoes: vazio(txt("Observacoes")),
    Diagnostico: vazio(txt("Diagnostico")),
    NaoReceberEmail: !!f.querySelector('input[type="checkbox"][name="NaoReceberEmail"][checked]'),
    NaoReceberSMS: !!f.querySelector('input[type="checkbox"][name="NaoReceberSMS"][checked]'),
    NaoReceberLigacoes: !!f.querySelector('input[type="checkbox"][name="NaoReceberLigacoes"][checked]'),
    NaoReceberWhatsapp: !!f.querySelector('input[type="checkbox"][name="NaoReceberWhatsapp"][checked]'),
    AlunoId: boxId,
    InstituicaoEnsinoId: null,
    ConfirmationResponseBehavior: " ",
    AlunoValidacaoDados: {
      AlunoValidacaoDadosId: boxId, EnviarEmail: false, EnviarSms: false, EnviarComprovanteAutorizacao: false,
      EmailEnviado: "", CelularEnviado: "", ComprovanteEnviado: "", CodigoEnviado: "", CodigoValidado: "False",
    },
    AttributeBehavior: "SaveProspect",
  };
}

// ---------- sessão HTTP no Box ----------
class Box {
  jar = new Map<string, string>();
  guarda(r: Response) {
    for (const c of r.headers.getSetCookie()) {
      const [kv] = c.split(";");
      const i = kv.indexOf("=");
      if (i > 0) this.jar.set(kv.slice(0, i).trim(), kv.slice(i + 1).trim());
    }
  }
  cookie() {
    return [...this.jar].map(([k, v]) => `${k}=${v}`).join("; ");
  }
  async req(path: string, init: RequestInit = {}) {
    const h = new Headers(init.headers);
    h.set("cookie", this.cookie());
    h.set("user-agent", "CRM-CNA-integracao/1.0");
    if (!h.has("x-requested-with")) h.set("x-requested-with", "XMLHttpRequest");
    const r = await fetch(BOX + path, { ...init, headers: h, redirect: "manual" });
    this.guarda(r);
    return r;
  }
  async login(email: string, senha: string) {
    await (await this.req("/Account/Login", { headers: { "x-requested-with": "" } })).arrayBuffer();
    const r = await this.req("/Account/Login", {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded", "x-requested-with": "" },
      body: new URLSearchParams({ Localization: "", Email: email, Password: senha }),
    });
    await r.arrayBuffer();
    const loc = r.headers.get("location") || "";
    const ok = (r.status === 302 || r.status === 301) && !/Account\/Login/i.test(loc);
    if (!ok) throw new Error("login_recusado");
  }
  async buscar(email?: string | null, fone?: string | null) {
    const tentativas: Array<[string, string]> = [];
    if (email) tentativas.push([email, ""]);
    const d = digitos(fone);
    if (d.length >= 10) tentativas.push(["", foneBox(fone)]);
    for (const [e, t] of tentativas) {
      const q = new URLSearchParams({
        PageIndex: "1", AtendimentoNome: "", AtendimentoEmail: e, AtendimentoTelefone: t,
        RGl2dWxnYWRvcklk_ActualDataItemType: "Divulgador", RGl2dWxnYWRvcklk_FirstDataItemType: "Divulgador",
        RGl2dWxnYWRvcklk_SecondDataItemType: "DivulgadorInativo", IdToggle: "true", DivulgadorId: "",
        _: String(Date.now()),
      });
      const r = await this.req(`/Atendimento/Load?${q}`);
      const html = await r.text();
      const ids = [...new Set([...html.matchAll(/popup-prospect[^>]*data-value="(\d+)"/g)].map((m) => m[1]))];
      if (ids.length === 1) return ids[0];
      if (ids.length > 1) throw new Error("mais_de_um_cadastro_no_box");
    }
    return null;
  }
  async ficha(id: string) {
    const r = await this.req(`/Prospect/Edit/${id}?_=${Date.now()}`);
    return await r.text();
  }
  async salvar(payload: unknown) {
    const r = await this.req("/Prospect/Save", {
      method: "POST",
      headers: { "content-type": "application/json; charset=utf-8" },
      body: JSON.stringify(payload),
    });
    const t = await r.text();
    let j: Record<string, unknown> = {};
    try { j = JSON.parse(t); } catch { throw new Error(`resposta_nao_json_${r.status}`); }
    return j;
  }
}

// ---------- handler ----------
if (import.meta.main) Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  if (req.method !== "POST") return json({ erro: "metodo" }, 405);
  // deno-lint-ignore no-explicit-any
  let body: any = {};
  try { body = await req.json(); } catch { /* corpo vazio */ }

  // autenticação própria, falha fechada
  let origem = "";
  const cron = req.headers.get("x-box-cron");
  if (cron) {
    const { data } = await sb.rpc("crm_box_cron_valida", { p_segredo: cron });
    if (data === true) origem = "cron";
  } else if (body.token) {
    const { data, error } = await sb.rpc("crm_box_sessao", { p_token: body.token, p_min: 3 });
    if (!error && data) origem = `gestao:${data.nome}`;
  }
  if (!origem) return json({ erro: "nao_autorizado" }, 401);

  const enviar = body.enviar === true;
  const simularLogin = body.login === true; // em simulação, só faz login e busca se pedido
  const limite = Math.min(Number(body.limite) || 30, 100);

  const { data: itens, error } = await sb.rpc("crm_box_fila_proximos", { p_limite: limite });
  if (error) return json({ erro: "fila", detalhe: error.message }, 500);

  // agrupa por unidade + consultor (um login por consultor)
  const grupos = new Map<string, Item[]>();
  for (const it of itens as Item[]) {
    const k = `${it.unidade}|${it.consultor}`;
    if (!grupos.has(k)) grupos.set(k, []);
    grupos.get(k)!.push(it);
  }

  const relatorio: Array<Record<string, unknown>> = [];
  for (const [k, lista] of grupos) {
    const [unidade, consultor] = k.split("|");
    let box: Box | null = null;
    if (enviar || simularLogin) {
      const { data: cred } = await sb.rpc("crm_box_credencial_ler", { p_unidade: unidade, p_consultor: consultor });
      const c = Array.isArray(cred) ? cred[0] : null;
      if (!c) {
        for (const it of lista) relatorio.push({ fila_id: it.fila_id, ok: false, erro: "consultor_sem_box" });
        continue;
      }
      box = new Box();
      try {
        await box.login(c.email_box, c.senha);
        await sb.rpc("crm_box_credencial_resultado", { p_unidade: unidade, p_consultor: consultor, p_ok: true, p_erro: null });
      } catch (e) {
        const msg = (e as Error).message;
        await sb.rpc("crm_box_credencial_resultado", { p_unidade: unidade, p_consultor: consultor, p_ok: false, p_erro: msg });
        for (const it of lista) relatorio.push({ fila_id: it.fila_id, ok: false, erro: msg });
        continue;
      }
    }

    for (const it of lista) {
      const pend: string[] = (it.pendencias || []).filter((p: string) => p !== "consultor_sem_box" || !box);
      if (pend.length) {
        relatorio.push({ fila_id: it.fila_id, ok: false, erro: `pendencias:${pend.join(",")}` });
        continue;
      }
      try {
        let boxId: string | null = it.lead.box_id ? String(it.lead.box_id) : null;
        if (!boxId && box) boxId = await box.buscar(it.lead.email, it.lead.whatsapp);
        let payload: unknown;
        if (boxId && box) payload = payloadExistente(it, await box.ficha(boxId), boxId);
        else if (boxId) payload = { simulacao: "prospect_existente_requer_login_para_ler_ficha", box_id: boxId };
        else payload = payloadNovo(it);

        if (!enviar) {
          relatorio.push({ fila_id: it.fila_id, ok: true, simulacao: true, box_id: boxId, payload });
          continue;
        }
        const resp = await box!.salvar(payload);
        // deno-lint-ignore no-explicit-any
        const r: any = resp;
        const ok = r.StatusCode === 200 && !(r.Errors && r.Errors.length);
        const novoId = r?.Data?.AlunoId ? Number(r.Data.AlunoId) : boxId ? Number(boxId) : null;
        await sb.rpc("crm_box_fila_resultado", {
          p_fila_id: it.fila_id, p_ok: ok, p_box_id: novoId, p_payload: payload, p_resposta: resp,
          p_erro: ok ? null : (r.Errors || []).join(" | ") || "erro_box",
        });
        relatorio.push({ fila_id: it.fila_id, ok, box_id: novoId, erro: ok ? null : r.Errors });
      } catch (e) {
        const msg = (e as Error).message;
        if (enviar) {
          await sb.rpc("crm_box_fila_resultado", {
            p_fila_id: it.fila_id, p_ok: false, p_box_id: null, p_payload: null, p_resposta: null, p_erro: msg,
          });
        }
        relatorio.push({ fila_id: it.fila_id, ok: false, erro: msg });
      }
    }
  }

  return json({ origem, modo: enviar ? "envio" : "simulacao", itens: relatorio.length, relatorio });
});
