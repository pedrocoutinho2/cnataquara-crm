# CLAUDE.md · cnataquara-crm

Instruções permanentes para sessões do Claude neste repo.
Última verificação contra o código: 31/08/2026.

## O que é

CRM comercial do CNA Taquara. Funil B2C, escolas e empresas, ações comerciais,
conversas de WhatsApp, calculadora de preços, mapa de turmas, calendário, mural,
atas de reunião, demandas e relatórios por consultor.

Usuários reais: duas consultoras comerciais, duas pessoas na secretaria e a
coordenação pedagógica. É sistema em produção, usado todo dia.

- Produção: https://crm.cnataquara.com.br
- Supabase: projeto `cnataquara-comercial`, ref `gpnwmsnayrqjcmhqrtpx`,
  compartilhado com o Escape Room e o Teste de Nível
- Nome do repo segue o padrão da unidade: `cnataquara-{subdomínio}`

## Stack

Decidida em 06/2026, não sugira trocar: HTML single-file + Supabase com RLS +
GitHub Pages. Sem build, sem framework, sem `package.json`.

## Arquitetura

Monólito de arquivo único. `index.html` com **10.880 linhas e 570 KB**,
**um único bloco `<script>`** (linhas 1661 a 10878) e **um único bloco
`<style>`** (linhas 9 a 1376). HTML, CSS e JS vanilla inline.

Arquivos do repo hoje: `CLAUDE.md`, `CNAME` e `index.html`. As pastas `sql/` e
`supabase/functions/` são a convenção acordada e ainda estão pendentes de
criação (ver as duas seções no fim deste arquivo).

Acesso a dados via REST direto no PostgREST, sem `supabase-js`:

```js
const SUPA='https://gpnwmsnayrqjcmhqrtpx.supabase.co/rest/v1';   // 1665
const KEY='eyJhbGciOi...';                                        // 1666, chave anon
const FUNCS='https://gpnwmsnayrqjcmhqrtpx.supabase.co/functions/v1'; // 3385
async function api(path,opt)   // 1668, helper único de request REST
function waFn(nome,body)       // 3388, helper das Edge Functions
```

`api()` derruba o cache dos relatórios (`REL.ts=0`) em qualquer escrita que
toque `/crm_leads` ou `/crm_interacoes`. Escrita nova no funil que precise
invalidar relatório deve passar por ele, não por `fetch` solto.

### Navegação

Abas em `NAVMOD` (4422), agrupadas no menu lateral:

- **Comercial**: Clientes B2C (`leads`), Escolas, Empresas, Ações comerciais
- **Atendimento**: Conversas (WhatsApp), Calculadora
- **Operação**: Turmas, Calendário, Mural de avisos, Dúvidas frequentes,
  Atas de reunião, Demandas
- **Gestão**: Relatórios, Equipe

Mais a tela de Início. Cada aba mapeia para um módulo de permissão; a aba
`relatorios` é liberada por qualquer um entre `rel_meudia`, `rel_funil` e
`rel_unidade` (`tabLiberada`, 4459).

## Login e permissões

**Login é por e-mail e senha**, com bcrypt server-side. O front manda as duas
coisas para a RPC e não faz hash nenhum no cliente:

```js
await api('/rpc/crm_login',{method:'POST',
  body:JSON.stringify({p_email:email,p_senha:senha})});   // 4021
```

Usuário sem e-mail não entra, e isso é proposital. Se `r.senha_temporaria`, o
sistema força a troca antes de deixar entrar (`abrirTrocaObrigatoria`, 4026).
Regra de senha em `SENHAREGRA` (4088): mínimo 8 caracteres, com pelo menos uma
letra e um número. RPCs relacionadas: `crm_trocar_senha`, `crm_definir_senha`.

**Não existe mais login por PIN.** `sha256()` (3987) e `sha256js()` (3945)
sobraram da versão antiga e são **código morto**: nenhuma chamada no arquivo.
O `id="pin"` do campo de senha (1551) também é resíduo de nome, não de
mecanismo. Não reintroduza hash no cliente.

### Três camadas de permissão

`nivelDe(mod,user)` (4441) resolve nesta ordem, parando na primeira que responde:

1. **Exceção individual** — `u.permissoes[mod]`, JSON na linha do usuário
2. **Padrão do papel** — `PAPELPERM[papelDe(u)][mod]`, de `crm_papel_permissoes`
3. **Fallback** — `total` se `u.admin`, senão `nenhum`

Papéis (`PAPEIS`, 4417): `secretaria`, `comercial`, `pedagogico`, `coordenacao`,
`admin`. Níveis (`PERMNIVEIS`, 4418): `nenhum`, `ver`, `editar`, `total`,
ordenados por `NIVORD` (4419).

Nunca compare nível por string. Use `pode(mod,min)`, `podeVer`, `podeEditar`,
`podeTotal` (4450-4453), que comparam pela ordem.

Módulos vêm de `crm_modulos`, não estão hardcoded. Módulo novo é linha no banco.

## Tabelas

Todas com prefixo `crm_`. As 35 que o `index.html` consulta hoje:

**Funil** — `crm_leads`, `crm_leads_interacoes`, `crm_leads_etapas`,
`crm_escolas`, `crm_empresas`, `crm_interacoes`, `crm_acoes`,
`crm_acoes_materiais`

**Operação** — `crm_turmas`, `crm_tarefas`, `crm_avisos`, `crm_faq`,
`crm_agenda_eventos`, `crm_agenda_categorias`, `crm_agenda_config`

**Demandas** — `crm_demandas`, `crm_demanda_itens`, `crm_demanda_anexos`

**Atas de reunião** — `crm_reunioes`, `crm_reuniao_participantes`,
`crm_reuniao_assinaturas`

**WhatsApp** — `crm_wa_contas`, `crm_wa_conversas`, `crm_wa_mensagens`,
`crm_wa_fila`, `crm_wa_templates`, `crm_wa_regras`

**Preços** — `crm_precos_niveis`, `crm_precos_materiais`,
`crm_precos_certificacoes`

**Sistema** — `crm_usuarios`, `crm_modulos`, `crm_papel_permissoes`,
`crm_configs`, `crm_relatorio_diario`

Não existem tabelas `crm_atas` nem `crm_metas`. Ata de reunião mora em
`crm_reunioes` e nas duas tabelas irmãs. Metas não estão modeladas.

### RPCs chamadas pelo front

`crm_login`, `crm_trocar_senha`, `crm_definir_senha`, `crm_relatorio_dia`,
`crm_fechar_dia`, `crm_painel_equipe`, `crm_ata_congelar`, `crm_ata_assinar`.

## Padrão de interface

**Todo cadastro, edição e detalhe abre em modal.** Nunca formulário inline.
Shell fixo: `.ov` (overlay, 253) > `.modal` (257) > `.mhead` (258) +
`.mbody` (259) + `.mfoot` (269). Tela nova de cadastro reaproveita esse shell.

## Regras de negócio que não são óbvias

### Etapa "Aguardando 27.1" é lateral

Definida em `stages` (1782) com `side:true`, cor `#0E7490`. Não é perda
(`off`) nem fechamento (`ok`): o lead segue contando como ativo e continua
entrando na fila de alertas. Não entra na progressão por seta.

Ao cair nessa etapa o **banco** carimba `proximo_atendimento` em 01/10/2026,
pelo trigger `crm_leads_aguarda_271_tg`, que dispara em
`BEFORE INSERT OR UPDATE`. O front não escreve essa data.

**Qualquer UPDATE em massa em `crm_leads` precisa excluir essa etapa no WHERE**,
senão o trigger reescreve o agendamento de todo mundo.

### Nível do aluno

No CRM, `teste_nivel` é um **canal de contato** (`CANAIS`, 1689), ao lado de
WhatsApp, ligação, e-mail, visita, reunião e aula experimental.

A partir das etapas `experimental`, `negociacao` e `fechado`
(`ETAPAS_NIVEL`, 2769), nome do aluno e nível viram obrigatórios: é quando o
nível deixa de ser chute. A lista de níveis depende do curso (`syncNivel`, 2774).

O comportamento de esconder o nível e mostrar só a pontuação é do **app do
Teste de Nível**, repo `cnataquara-testedenivel`, não deste aqui.

### O sistema cobra, mas nem sempre deixa passar

A regra geral é cobrar sem impedir: fechamento de dia é convite, não trava
(`dfechar`, 5822 e 5869); alertas e sugestões geram aviso (`buildSugestoes`, 5330).

Mas há **bloqueios reais** no salvamento de lead, que não são bugs:

- **Duplicidade de WhatsApp na criação** (3151): se já existe lead com o mesmo
  número, `toast` e `return`. Não salva.
- **Nome e nível obrigatórios** a partir de `experimental` (3107 e 3114).
- **Hora do agendamento** faltando (3147).
- **Motivo da perda** ausente quando a etapa é `perdido` (3122).

Se for mexer nisso, saiba que está mexendo em trava, não em aviso.

## Armadilhas conhecidas

### Normalização de telefone está fragmentada

Existem **três** normalizações diferentes no arquivo e elas não concordam:

- `phone()` (2008) — só `replace(/\D/g,'')`
- `dig()` (3152), usada na checagem de duplicidade — só `replace(/\D/g,'')`
- `waFmtNum()` (3404) — `replace(/\D/g,'')` **e** `replace(/^55/,'')`

Consequência real: um lead salvo com DDI 55 não colide com o mesmo número
salvo sem DDI, porque a checagem de duplicidade não remove o 55. Antes de
escrever uma quarta variante, unifique as três. No banco a chave canônica é
`crm_wa_chave()` (DDD + últimos 8 dígitos).

### Data

`CURRENT_DATE` no Supabase vira o dia às 21h de Brasília, porque o servidor
está em UTC. Isso quebra o turno que vai até 22h. Em query sensível a data use
`crm_hoje_br()`.

### Snapshot vs consulta ao vivo

`proximo_atendimento` é sobrescrito de forma destrutiva no reagendamento: não
dá para reconstruir o histórico a partir dele. Número histórico de relatório
diário sai de `crm_relatorio_diario`, nunca de recontagem ao vivo.

### RLS

Padrão atual é policy permissiva `anon_all`
(`for all to anon using (true) with check (true)`). Tabela nova precisa de
`enable row level security` + policy explícita. RPC nova precisa de
`grant execute ... to anon` e `notify pgrst, 'reload schema'`.

**UPDATE exige SELECT no RLS.** Se `anon` não tem SELECT na tabela, o UPDATE
falha em silêncio: retorna sucesso e não altera linha nenhuma. A saída é RPC
`security definer`, **não** abrir policy pública de UPDATE.

**`auth.uid()` é NULL no SQL Editor.** Função que dependa dele não dá para
testar por lá; teste pelo PostgREST.

**DDL junto com CREATE FUNCTION no mesmo SQL às vezes executa só o DDL.**
Separe em dois envios e confirme que a função existe depois.

### Patch de CSS em arquivo único

Substituição de hex roda **só dentro do bloco `<style>`** (linhas 9 a 1376).
Rodar contra o arquivo inteiro atinge string de JS: há hex literais em
`PALETA` (1685), em `<input type="color">` (7968, 8784) e um `<style>` inteiro
montado dentro de string na impressão do mapa de turmas (8433). Substituição
global já quebrou um `<input type="color">` neste repositório.

## SQL versionado

**SQL aplicado no SQL Editor vira arquivo em `sql/` no mesmo ciclo.**
Versionar faz parte do "done"; não é etapa separada para depois.

Nome do arquivo: `<version>_<name>.sql`, com a version completa do Supabase
(`YYYYMMDDHHMMSS`), igual à linha em `supabase_migrations.schema_migrations`.

A pasta `sql/` ainda não existe: em 31/08/2026 havia 46 migrations aplicadas no
projeto e nenhuma versionada.

Para extrair o que já está aplicado, use `../extrair-migrations.sh`, que
confere o md5 de cada arquivo contra o banco e aborta o lote se algum divergir.
A connection string mora em `~/.config/cna/pguri.env`, fora do repositório, e
nunca entra em commit, log ou chat.

## Edge Functions

Devem ficar versionadas em `supabase/functions/`. **Ainda não estão**: as
quatro rodam no projeto e não existem em repositório nenhum. Baixe com o
Supabase CLI (`supabase functions download <nome>`) antes de mexer em qualquer
uma. As quatro ativas:

- `wa-webhook` — recebe da Meta Cloud API. **Não pode ser renomeada**: a URL
  está registrada na Meta e renomear derruba o webhook em produção.
- `wa-send` — envio de mensagem (chamada em 3682 e 3815)
- `wa-media` — resolve mídia de mensagem (3702)
- `ata-analisar` — análise da ata de reunião (9270)

## Dívida de segurança nº 1

A chave anon está no HTML (1666) e a RLS é permissiva (`anon_all`). Quem tiver
a URL e a chave **lê e escreve as tabelas direto pelo PostgREST**, sem passar
pelo app e sem respeitar as três camadas de permissão, que são checagem de
front. Login e senha estão protegidos por bcrypt dentro de RPC; o resto não.

Toda permissão descrita acima é **conveniência de interface, não fronteira de
segurança**. Não trate como controle de acesso.

## Deploy

Nunca entregue arquivo para upload manual. Sempre via API do GitHub.

1. Extraia o `<script>` com `re.findall`, salve no scratchpad e rode `node --check`
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
- `index.html` é gravado por substituição do arquivo inteiro. Outra sessão pode
  estar editando o mesmo arquivo: releia antes de gravar.
- Confirme com o Pedro antes de qualquer operação destrutiva no banco.
- Não commite segredo: senha, API key, token, connection string ou dado pessoal
  de aluno.
- Padrão visual compartilhado com adm e ponto: ver `assets/PADRAO.md` no repo
  `cnataquara-ponto`. Este repo é a referência de origem dos tokens.
