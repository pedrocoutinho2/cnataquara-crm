# CLAUDE.md · cnataquara-crm

Instruções permanentes para sessões do Claude neste repo.

## O que é

CRM comercial do CNA Taquara. Funil de leads B2C, escolas e empresas, relatórios
por consultor, mapa de turmas e integração WhatsApp.

- Produção: https://crm.cnataquara.com.br
- Supabase: `gpnwmsnayrqjcmhqrtpx` (compartilhado com o escape room)
- Nome do repo segue o padrão da unidade: `cnataquara-{subdomínio}`

## Arquitetura

Monólito de arquivo único. `index.html` com ~4.500 linhas, **um único bloco
`<script>`**, HTML + CSS + JS vanilla inline. Sem build, sem `package.json`,
sem framework.

O repo tem só dois arquivos: `index.html` e `CNAME`.

Acesso a dados via REST direto, sem `supabase-js`:

```js
const SUPA='https://gpnwmsnayrqjcmhqrtpx.supabase.co/rest/v1';
async function api(...)   // helper único de request
```

Tabelas: `crm_leads`, `crm_leads_interacoes`, `crm_leads_etapas`, `crm_escolas`,
`crm_empresas`, `crm_interacoes`, `crm_usuarios`, `crm_turmas`, `crm_tarefas`,
`crm_avisos`, `crm_faq`, `crm_relatorio_diario`, `crm_precos_niveis`,
`crm_precos_materiais`, `crm_precos_certificacoes`.

Abas: Mural, Conversão, Calculadora, Turmas, Relatórios, Equipe (só admin).

Login por PIN com SHA-256 via `crypto.subtle.digest`, função `sha256()`.

## Armadilhas conhecidas

**Data.** `CURRENT_DATE` no Supabase vira o dia às 21h de Brasília, porque o
servidor está em UTC. Isso quebra o turno da Camila (13h às 22h). Em qualquer
query sensível a data use `crm_hoje_br()`.

**Snapshot vs consulta ao vivo.** Campos como `proximo_atendimento` são
sobrescritos de forma destrutiva no reagendamento. Número histórico de relatório
diário sai de `crm_relatorio_diario`, nunca de recontagem ao vivo.

**Duplicidade.** Comparação de WhatsApp usa só dígitos, removendo o DDI 55.
`crm_wa_chave()` normaliza (DDD + últimos 8 dígitos). Reaproveite essa função,
não escreva outra normalização.

**RLS.** Padrão atual é policy permissiva `anon all`
(`for all to anon using (true) with check (true)`). Tabela nova precisa de
`enable row level security` + policy explícita. RPC nova precisa de
`grant execute ... to anon` e `notify pgrst, 'reload schema'`.

**Patch de CSS.** Substituição de hex roda **só dentro do bloco `<style>`**.
Rodar contra o arquivo inteiro quebra nomes de variável no `<script>`.

## Deploy

Nunca entregue arquivo para upload manual. Sempre via API do GitHub.

1. Extraia o `<script>` com `re.findall`, salve em `/tmp/` e rode `node --check`
2. `GET` do arquivo para pegar o `sha`
3. `PUT` em `contents` com `sha` + conteúdo em base64
4. Poll em `pages/builds/latest` até `built` (~60 a 90s)
5. Confirme lendo via API com `Accept: application/vnd.github.raw`.
   A URL do Pages pode servir cache.

Em substituição com regex use `re.subn` com lambda, para não quebrar em escapes
de barra invertida. Antes de escrever, garanta a contagem esperada
(`assert s.count(old) == n`).

## Regras

- Busque o arquivo atual antes de editar. Nunca escreva de memória.
- Confirme com o Pedro antes de qualquer operação destrutiva no banco.
- Padrão visual compartilhado com adm e ponto: ver `assets/PADRAO.md` no repo
  `cnataquara-ponto`. Este repo é a referência de origem dos tokens.
