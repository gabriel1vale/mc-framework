# MC Framework

> **MC = Multi Client.** Framework para consultores Power Platform que trabalham em hardware pessoal para múltiplos clientes simultaneamente. Resolve isolamento de credenciais via WSL2 e codifica padrões de Power Platform / Dataverse / Code Apps em docs e scripts reutilizáveis entre projetos.

**Status:** v0.1.0 — primeiro release público. Estável para uso pessoal; suporte para outros consultores em iteração.

> 📘 **Idioma:** este README está em PT-BR. Toda a documentação técnica, scripts, templates e código estão em **inglês**, conforme convenção padrão para projetos open source.

---

## O problema que resolve

Como consultor Power Platform trabalhando para múltiplos clientes:

1. **Tokens de cliente acumulam-se no Windows host.** `pac auth`, `az`, cookies de browser, MSAL token broker, MDM enrollments. Cada cliente novo deixa rastro. Limpar é trabalhoso, frequentemente impossível (MDM precisa do IT do cliente).
2. **Padrões Power Platform se repetem entre projetos** mas o conhecimento fica espalhado. O bug do empty-source nos rollups, FormattedValue para lookups, bulk ops via Web API, parser de import — descobrir, codificar, e re-aplicar em cada cliente é desperdício.
3. **AI agents (Claude, Copilot) precisam de contexto consistente.** Sem framework, cada projeto começa do zero a explicar à IA "como fazemos as coisas aqui".

A MC Framework ataca os três:

- **Isolamento via distros WSL2** — um distro por cliente, tokens lá dentro, `wsl --unregister` apaga tudo no fim do contrato.
- **Padrões codificados em docs** — leitura única, aplicação em qualquer projeto.
- **`AGENTS.md` como fonte de verdade para AI agents** — o agent lê uma vez por sessão e tem todas as ferramentas e protocols na ponta dos dedos.

---

## Como funciona

### Arquitetura em três camadas

```
┌─ Windows host ──────────────────────────────────────────────────┐
│  Claude Code / Copilot / VS Code                                │
│  Project files (C:\Users\<user>\Projects\<client>\)             │
│  mc CLI (scripts\mc.cmd)                                        │
└─────────────┬───────────────────────────────────────────────────┘
              │  wsl.exe -d <Distro> -- <command>
              ▼
┌─ WSL2 ──────────────────────────────────────────────────────────┐
│  ┌─ <Client1> distro ────┐  ┌─ <Client2> distro ────┐           │
│  │  pac/az tokens        │  │  pac/az tokens        │  ...      │
│  │  Node, .NET, dev tools│  │  Node, .NET, dev tools│           │
│  │  MCP server processes │  │  MCP server processes │           │
│  └───────────────────────┘  └───────────────────────┘           │
└─────────────┬───────────────────────────────────────────────────┘
              │  HTTPS (com tokens isolados por distro)
              ▼
┌─ Power Platform / Dataverse APIs ───────────────────────────────┐
│  Por tenant cliente                                             │
└─────────────────────────────────────────────────────────────────┘
```

**Princípios:**

1. **Arquivos do projeto vivem no Windows.** Edits rápidos, git natural, VS Code Explorer normal.
2. **Tokens, dev runtime, MCP servers vivem no distro WSL do cliente.** Filesystem Linux contido. `wsl --unregister` evapora tudo.
3. **Cliente = distro WSL = perfil do Chrome** — três compartimentos paralelos, um por cliente. Cross-contamination zero.
4. **MCP via stdio bridge.** `.mcp.json` faz `wsl.exe -d <Distro> -- npx ...`. O agent fala com o servidor MCP dentro do distro como se fosse local.

### MCP servers default

Cada projeto cliente tem `.mcp.json` com:

- **`dataverse`** — `@microsoft/dataverse` MCP via WSL bridge para o distro do cliente. Schema queries, CRUD ad-hoc, exploration.
- **`microsoft-learn`** — HTTP MCP em `https://learn.microsoft.com/api/mcp`. Documentação Microsoft sempre atual, no contexto do agent.

### CLI `mc`

Uma frente única para operações multi-cliente:

```powershell
mc new <client>          # setup novo (distro + tools + auth + scaffold)
mc adopt <client>        # migrar projeto existente para o modelo
mc open <client>         # VS Code Remote-WSL no projeto
mc shell <client>        # shell interativa
mc dev <client>          # npm run dev dentro do distro
mc deploy <client>       # protocolo DEPLOY (precisa de PP_SOLUTION env)
mc auth status <client>  # ver pac/az auth dentro do distro
mc logout <client>       # limpa tokens dentro do distro
mc destroy <client>      # wsl --unregister (irreversível)
mc list                  # listar distros
```

---

## Setup (uma vez)

### Pré-requisitos

- Windows 10/11
- WSL2 (a CLI `mc` instala se faltar)
- Git
- Chrome / Edge / Brave (para fluxos de auth device-code)

### Instalar a framework

```powershell
# Clone para o seu user (uma vez)
git clone https://github.com/gabriel1vale/mc-framework $env:USERPROFILE\mc-framework

# (Opcional) adicionar ao PATH para acesso global
$env:Path += ";$env:USERPROFILE\mc-framework\scripts"
```

A partir daqui, `mc` está disponível em qualquer terminal.

---

## Usar para um projeto cliente

### Cenário A: cliente novo do zero

```powershell
mkdir C:\Users\<user>\Projects\acme-corp
cd C:\Users\<user>\Projects\acme-corp

# Drop the framework into the project (escolha uma):
git clone https://github.com/gabriel1vale/mc-framework
# OU
xcopy $env:USERPROFILE\mc-framework mc-framework\ /E /I

# Bootstrap completo (cria distro, instala tools, autentica, faz scaffolding)
.\mc-framework\scripts\mc.cmd new acme-corp
```

O wizard pergunta tenant ID, env URL, nome da solution, e cuida do resto. Quando termina:

- Distro WSL `acme-corp` criado e configurado
- `az login` + `pac auth create` feitos lá dentro (via device-code, você abriu a URL no perfil Chrome do cliente)
- Code App starter scaffolded em `./code-app/`
- `.mcp.json` e `CLAUDE.md` populados

A partir daí:

```powershell
mc open acme-corp     # VS Code Remote-WSL
mc dev acme-corp      # npm run dev
```

### Cenário B: migrar projeto existente

Você tem uma pasta de projeto com auth no Windows host. Quer mover para o modelo isolado:

```powershell
cd C:\caminho\para\projeto-existente
.\mc-framework\scripts\mc.cmd adopt my-client
```

Cria distro, faz auth dentro, atualiza `.mcp.json` para usar WSL bridge. Sugere cleanup de tokens no Windows host.

### Cenário C: trabalhar com Claude Code

Em qualquer pasta com a framework:

1. Editar `CLAUDE.md` para descrever o cliente + o que quer fazer
2. Garantir `@mc-framework/AGENTS.md` está referenciado
3. Abrir Claude Code (extensão VS Code ou CLI)
4. Pedir: "faça setup do projeto" / "edite X" / "faça deploy" / "importe Y"

Claude lê o CLAUDE.md, segue o `@`, carrega o AGENTS.md e tem todas as ferramentas, padrões e protocols na cabeça. Sabe quais comandos `mc` usar, sabe como autenticar dentro do distro, sabe quais padrões aplicar (rollup workarounds, bulk ops, imports).

---

## Estrutura

```
mc-framework/
├── README.md                    Este arquivo (humanos)
├── AGENTS.md                    Manual para AI agents (Claude/Copilot leem)
├── PROTOCOLS.md                 DEPLOY, WRAPUP, IMPORT, ROLLBACK
├── LICENSE                      MIT
├── CHANGELOG.md                 Histórico de versões
├── docs/
│   ├── ARCHITECTURE.md          Camadas Windows ↔ WSL ↔ Dataverse
│   ├── DATAVERSE_PATTERNS.md    FormattedValue, OData bind, autonumber, custom APIs
│   ├── ROLLUP_PATTERNS.md       Bug do empty-source + dummy-anchor pattern
│   ├── BULK_OPS_PATTERNS.md     az + Web API direta, paralelismo, paginação
│   ├── IMPORT_PIPELINE.md       RFC-4180 CSV, exceljs, header mapping, validação
│   ├── MCP_SETUP.md             .mcp.json + WSL stdio bridge + Microsoft Learn HTTP
│   ├── AUTH_HYGIENE.md          Defesa em profundidade, cleanup, anti-contaminação
│   └── MULTI_CLIENT.md          Onboarding, troca de contexto, template de mail MDM
├── scripts/
│   ├── mc.ps1, mc.cmd           CLI principal
│   ├── new-project.ps1          Bootstrap projeto novo
│   ├── adopt-existing.ps1       Migrar projeto existente
│   ├── distro-setup.sh          Tools install dentro do WSL
│   └── lib/
│       ├── token-from-az.mjs    Bearer token do az + Web API helpers
│       ├── import-template.mjs  Skeleton de bulk import parametrizável
│       └── reset-template.mjs   Skeleton de bulk delete + recalc
└── templates/
    ├── .mcp.json.template       Com placeholders {{DISTRO}}, {{ENV_URL}}
    ├── CLAUDE.md.template       Com placeholders {{CLIENT}}, {{TENANT_ID}}, etc.
    └── .gitignore.template      Defaults Power Platform
```

---

## Padrões cobertos

### Power Platform / Dataverse

- **FormattedValue para lookups e choices** ([DATAVERSE_PATTERNS.md](docs/DATAVERSE_PATTERNS.md)) — os types autogen mentem; usar `_field_value@OData.Community.Display.V1.FormattedValue` via bracket notation.
- **OData bind para escrita de lookups** — `'<field>@odata.bind': '/<entityset>(<guid>)'`, schema name é case-sensitive.
- **Lookup tracking via lookup, não string** — engine de rollup só vê child records que tenham o lookup populado (não basta a string equivalente).
- **Autonumber columns em bulk imports** — sem passar valor explícito, plugins geram caracteres aleatórios em vez de sequenciais.
- **Custom API runtime registration** — `dataSourcesInfo` é singleton; muta o objeto original (não cópias) para registar APIs como `CalculateRollupField`.

### Rollup columns

- **Empty-source bug + dummy-anchor pattern** ([ROLLUP_PATTERNS.md](docs/ROLLUP_PATTERNS.md)) — `CalculateRollupField` em fonte vazia mantém o valor cacheado. Workaround: criar anchor qty=0 com lookup populado, esperar 2s, recalc com verify-and-retry, apagar anchor.
- **Recalc após bulk import** — sem dummy se a source não está vazia; sequencial (não paralelo).
- **Mapping território/região → coluna rollup** — função reutilizável.

### Bulk operations

- **`az` + Web API direta** ([BULK_OPS_PATTERNS.md](docs/BULK_OPS_PATTERNS.md)) — para >100 records, escrever script Node.js. MCP é caro em context tokens.
- **Paralelo de 10 com `Promise.allSettled`** — sweet spot; >10 começa a ter 429.
- **Paginação automática** — `@odata.nextLink` loop até null.
- **Token refresh em operações longas** — re-chamar `az account get-access-token` a cada 45min.

### Import pipeline

- **Parser CSV RFC-4180** ([IMPORT_PIPELINE.md](docs/IMPORT_PIPELINE.md)) — não usar `split(',')`, falha com vírgulas embutidas.
- **Header mapping tolerante** — case/acento/espaços insensível, mapeamento canônico.
- **Pre-resolve lookups** — uma query por lookup table, index em memória.
- **Per-row validation** — separar valid/invalid, reportar erros antes de submeter.
- **Preview + confirmação para >100 rows** — UX consistente.

### MCP

- **WSL stdio bridge** ([MCP_SETUP.md](docs/MCP_SETUP.md)) — `wsl.exe -d <Distro> -- npx ...` no `.mcp.json`. Servidor roda dentro do distro, comunica via stdio transparente.
- **Microsoft Learn HTTP MCP** sempre on — fonte da verdade para docs Microsoft, sempre atual.
- **Debugging** — comandos para verificar distro, package install, auth state.

### Auth hygiene

- **Defesa em profundidade** ([AUTH_HYGIENE.md](docs/AUTH_HYGIENE.md)) — distro WSL (camada 1) + perfil Chrome (camada 2) + pasta projeto (camada 3) + nunca aceitar work account no Windows (camada 4).
- **Cleanup de contaminação anterior** — passos para apagar tokens já gravados no Windows host.
- **MDM disenrollment template** — mail pronto para IT do cliente.

---

## Protocols (operações standard)

Em [PROTOCOLS.md](PROTOCOLS.md):

- **DEPLOY** — pre-validation (tsc + build + auth) → confirmação y/n → push → verify → update logs
- **WRAPUP** — cleanup, build, version bump, lessons capture, git commit (sem auto-push)
- **IMPORT** — info, schema, lookups, parse+validate, preview+confirm, bulk create, recalc rollups
- **ROLLBACK** — identify good state → confirm → revert → verify → document

---

## Dependências

### Em runtime do projeto cliente
Todas instaladas dentro do distro WSL (não no Windows host) por `scripts/distro-setup.sh`:

- Node.js LTS (NodeSource)
- Azure CLI
- .NET SDK 8
- pac CLI (`Microsoft.PowerApps.CLI.Tool` via dotnet tool)

### Para rodar o `mc` CLI
Apenas no Windows host:

- PowerShell 5.1+ (incluído com Windows)
- WSL2 (instalado on-demand pela própria CLI)

---

## Filosofia

1. **Arquivos estáticos > código compilado.** A framework é majoritariamente Markdown e shell scripts. Sem build step, sem dependencies extra. Lê-se em qualquer editor.
2. **Documentação > automação para coisas raras.** Operações que faço uma vez por mês ficam documentadas (não scriptadas). Operações que faço várias vezes por dia ficam scriptadas.
3. **Auth nunca toca o host.** Não-negociável. Isto é o problema que motiva tudo.
4. **Microsoft Learn é fonte da verdade.** Não copio docs Microsoft (envelhecem); referencio links e o agent consulta via MCP em runtime.
5. **Confirmação explícita para destrutivo.** Sempre. `wsl --unregister`, `git push --force`, `pac code push` em produção, `delete` em massa — y/n explícito antes de cada um.

---

## Quando NÃO usar

- Projetos não-Power Platform (web apps puros, APIs back-end) — overhead desnecessário
- Cliente fornece laptop corporativa — usa essa, isolamento já é físico
- Cliente paga ambiente cloud (Codespaces, Dev Box) — usa esse
- Projetos exploratórios <1 dia — overhead de criar distro WSL não compensa

---

## Roadmap (não comprometido)

- [ ] **Plugin Claude Code marketplace** — empacotar como plugin para `claude /plugin install` em vez de drag-and-drop manual
- [ ] **Power Pages support** — por agora foca em Code Apps + Dataverse
- [ ] **Sample projects** — exemplos `samples/<scenario>/` para learners
- [ ] **Tests** — Pester para PowerShell scripts, vitest para `.mjs` libs
- [ ] **CI** — GitHub Actions para lint + sample integration tests

---

## Contribuições

Issues e PRs são bem-vindos. Especialmente:
- Padrões adicionais (custom workflows, plugins, advanced rollup scenarios)
- Suporte a outros connectors (SharePoint, SQL, Power Automate)
- Traduções para outros idiomas

---

## Licença

MIT — ver [LICENSE](LICENSE).

---

## Créditos

Inspirações:
- [microsoft/PowerAppsCodeApps](https://github.com/microsoft/PowerAppsCodeApps) — templates e samples oficiais Microsoft
- [microsoft/power-platform-skills](https://github.com/microsoft/power-platform-skills) — plugin Claude Code oficial Microsoft (a MC Framework complementa, não substitui)

A MC Framework adiciona:
- Auth-per-client isolada via WSL2 (não coberto pelo oficial)
- Padrões de bulk ops via `az` + Web API direta
- Workaround do empty-source bug em rollup columns
- Pipeline de import xlsx/csv com preview UI
- AGENTS.md unificado para AI agents
