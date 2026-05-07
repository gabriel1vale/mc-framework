# MC Framework

> **MC = Multi Client.** Framework para consultores Power Platform que trabalham em hardware pessoal para múltiplos clientes simultaneamente. Resolve isolamento de credenciais via WSL2 e codifica padrões Power Platform / Dataverse / Code Apps em docs e scripts reutilizáveis.

> 📘 README em PT-BR. Documentação técnica, scripts e código estão em inglês.

**Status:** v0.1.0

[Setup](#setup) · [Como usar](#como-usar) · [Documentação](#documentação) · [Construído sobre](#construído-sobre)

---

## O problema

Como consultor Power Platform trabalhando para múltiplos clientes:

| Problema | Consequência |
|---|---|
| Tokens (`pac`, `az`, cookies, MDM) acumulam no Windows host | Difícil limpar; MDM exige IT do cliente |
| Padrões Power Platform repetem-se entre projetos | Re-descobrir o mesmo bug, FormattedValue, parser CSV em cada cliente |
| AI agents sem contexto consistente | Toda sessão começa explicando à IA "como fazemos aqui" |

**A solução:**

- 🔒 **Um distro WSL2 por cliente** — tokens isolados; `wsl --unregister` apaga tudo no fim do contrato
- 📚 **Docs codificados** — leitura única, aplicação em qualquer projeto
- 🤖 **`AGENTS.md` único** — o agent lê uma vez por sessão e tem todas as ferramentas

---

## Como funciona

```
Windows host                                WSL2
├── Claude Code (VS Code)        wsl.exe   ├── Distro <Client1>
├── Project files            ──────────►   │    pac/az tokens
└── mc CLI                                 │    Node, .NET, dev tools
                                           │    MCP server processes
                                           ├── Distro <Client2> ...
                                           └── ...
```

- **Arquivos do projeto** vivem no Windows (rapidez para Claude editar)
- **Tokens, dev runtime, MCP servers** vivem **dentro** do distro WSL
- **MCP via stdio bridge** — `.mcp.json` faz `wsl.exe -d <Distro> -- npx ...`
- Cliente = **distro WSL = perfil Chrome = pasta projeto** — três compartimentos paralelos

Cada projeto cliente tem `.mcp.json` com dois servidores default:
- **`dataverse`** via WSL bridge — schema queries, CRUD ad-hoc
- **`microsoft-learn`** HTTP — docs Microsoft sempre atualizados

---

## Setup

```powershell
# Uma vez
git clone https://github.com/gabriel1vale/mc-framework $env:USERPROFILE\mc-framework
$env:Path += ";$env:USERPROFILE\mc-framework\scripts"
```

Pré-requisitos: Windows 10/11, Git, Chrome/Edge/Brave. WSL2 é instalado on-demand pelo `mc`.

---

## Como usar

### CLI `mc` — comandos disponíveis

```powershell
mc new <client>          # setup novo (distro + tools + auth + scaffold)
mc adopt <client>        # migrar projeto existente
mc open <client>         # VS Code Remote-WSL no projeto
mc dev <client>          # npm run dev dentro do distro
mc shell <client>        # shell interativa
mc deploy <client>       # protocolo DEPLOY
mc auth status <client>  # ver estado pac/az
mc logout <client>       # limpar tokens (fim do dia)
mc destroy <client>      # wsl --unregister (irreversível)
mc list                  # listar distros
```

### Cenário A — cliente novo do zero

```powershell
mkdir C:\Users\<user>\Projects\acme-corp
cd C:\Users\<user>\Projects\acme-corp

# Drop the framework into the project
xcopy $env:USERPROFILE\mc-framework mc-framework\ /E /I

# Bootstrap completo
.\mc-framework\scripts\mc.cmd new acme-corp
```

O wizard pergunta tenant ID, env URL, solution name. Cria distro, instala tools (Node, az, .NET, pac), faz autenticação device-code (você confirma no Chrome do cliente), faz scaffolding via Microsoft starter, popula `.mcp.json` e `CLAUDE.md`.

### Cenário B — migrar projeto existente

```powershell
cd C:\caminho\para\projeto-existente
.\mc-framework\scripts\mc.cmd adopt my-client
```

Cria distro, autentica dentro, atualiza `.mcp.json` para WSL bridge, sugere cleanup de tokens no Windows.

### Cenário C — trabalhar com Claude Code

1. Abre Claude Code na pasta do projeto
2. O `CLAUDE.md` referencia `@mc-framework/AGENTS.md` automaticamente
3. Pede: *"faz setup do projeto"* / *"edita X"* / *"deploya"* / *"importa Y"*
4. Claude segue os protocols, usa os comandos `mc`, aplica os padrões

---

## Documentação

| Arquivo | Conteúdo |
|---|---|
| [`AGENTS.md`](AGENTS.md) | Manual para AI agents (Claude/Copilot) |
| [`PROTOCOLS.md`](PROTOCOLS.md) | DEPLOY, WRAPUP, IMPORT, ROLLBACK |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Camadas Windows ↔ WSL ↔ Dataverse |
| [`docs/AUTH_HYGIENE.md`](docs/AUTH_HYGIENE.md) | Princípios de isolamento por cliente |
| [`docs/MULTI_CLIENT.md`](docs/MULTI_CLIENT.md) | Onboarding, troca de contexto, template MDM |
| [`docs/MCP_SETUP.md`](docs/MCP_SETUP.md) | `.mcp.json` + WSL stdio bridge + debugging |
| [`docs/DATAVERSE_PATTERNS.md`](docs/DATAVERSE_PATTERNS.md) | FormattedValue, OData bind, autonumber, custom APIs |
| [`docs/ROLLUP_PATTERNS.md`](docs/ROLLUP_PATTERNS.md) | Bug do empty-source + dummy-anchor pattern |
| [`docs/BULK_OPS_PATTERNS.md`](docs/BULK_OPS_PATTERNS.md) | `az` + Web API direta, paralelismo, paginação |
| [`docs/IMPORT_PIPELINE.md`](docs/IMPORT_PIPELINE.md) | RFC-4180 CSV, exceljs, validação, preview UI |

---

## Estrutura

```
mc-framework/
├── AGENTS.md, PROTOCOLS.md, README.md, LICENSE, CHANGELOG.md
├── docs/         (8 arquivos com padrões e arquitetura)
├── scripts/
│   ├── mc.ps1, mc.cmd          (CLI principal)
│   ├── new-project.ps1         (bootstrap projeto novo)
│   ├── adopt-existing.ps1      (migrar projeto existente)
│   ├── distro-setup.sh         (instala tools dentro do WSL)
│   └── lib/                    (helpers: token-from-az, import-template, reset-template)
└── templates/    (.mcp.json, CLAUDE.md, .gitignore)
```

---

## Filosofia

- **Arquivos estáticos > código compilado** — markdown e shell scripts. Sem build, sem deps extra.
- **Documentação > automação para coisas raras** — operações mensais ficam documentadas; diárias ficam scriptadas.
- **Auth nunca toca o host** — não-negociável.
- **Microsoft Learn é fonte da verdade** — não copio docs; o agent consulta via MCP em runtime.
- **Confirmação explícita para destrutivo** — sempre.

---

## Quando NÃO usar

- Projetos não-Power Platform (web apps puros, APIs back-end)
- Cliente fornece laptop corporativa — isolamento já é físico
- Cliente paga ambiente cloud (Codespaces, Dev Box) — usa esse
- Projetos exploratórios <1 dia — overhead não compensa

---

## Construído sobre

A MC Framework não substitui as ferramentas oficiais Microsoft — **complementa**:

- [`microsoft/PowerAppsCodeApps`](https://github.com/microsoft/PowerAppsCodeApps) — templates e samples; o `mc new` usa o starter via `npx degit`
- [`microsoft/power-platform-skills`](https://github.com/microsoft/power-platform-skills) — plugin Claude Code oficial; instalável em paralelo para slash-commands `/deploy`, `/add-dataverse`, etc.
- **Microsoft Learn MCP** (`https://learn.microsoft.com/api/mcp`) — sempre ativa no `.mcp.json` template

A MC Framework adiciona o que o oficial não cobre:

- Auth-per-client isolada via WSL2
- Padrões de bulk ops via `az` + Web API direta
- Workaround do empty-source bug em rollup columns
- Pipeline de import xlsx/csv com preview UI
- `AGENTS.md` unificado para AI agents

---

## Contribuições

Issues e PRs bem-vindos. Áreas com mais valor:
- Padrões adicionais (custom workflows, plugins, advanced rollup scenarios)
- Suporte a outros connectors (SharePoint, SQL, Power Automate)
- Traduções para outros idiomas

---

## Licença

MIT — ver [LICENSE](LICENSE).
