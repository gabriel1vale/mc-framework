# MC Framework

> **MC = Multi Client.** Framework para consultores Power Platform que trabalham em hardware pessoal para múltiplos clientes simultaneamente. Foco: **isolamento de autenticação, gestão de acesso e provisionamento de ambiente** via WSL2.

> 📘 README em PT-BR. Documentação técnica, scripts e código em inglês.

**Status:** v0.1.0

[Setup](#setup) · [Como usar](#como-usar) · [Documentação](#documentação) · [Construído sobre](#construído-sobre)

---

## O que faz

Resolve dois problemas de quem trabalha em vários clientes Power Platform:

| Problema | Consequência |
|---|---|
| Tokens (`pac`, `az`, cookies, MDM) acumulam no Windows host | Difícil limpar; MDM exige IT do cliente |
| AI agents (Claude/Copilot) sem contexto consistente entre projetos | Cada sessão começa explicando à IA "como fazemos aqui" |

**A solução:**

- 🔒 **Um distro WSL2 por cliente** — tokens isolados; `wsl --unregister` apaga tudo no fim do contrato
- 🛠️ **Provisionamento automático** — cria distro, instala Node/az/.NET/pac, autentica via device-code, popula `.mcp.json` e `CLAUDE.md`
- 🤖 **`AGENTS.md` único** — o agent lê uma vez por sessão e sabe os comandos `mc`, os protocols (deploy/wrapup/rollback), e onde procurar respostas

**O que NÃO faz:** padrões de desenvolvimento Power Platform / Dataverse (lookups, rollups, imports, etc.) **não estão aqui**. Esses são responsabilidade de:
- [Microsoft Learn MCP](https://learn.microsoft.com/api/mcp) — sempre ativo no `.mcp.json` template
- [microsoft/PowerAppsCodeApps](https://github.com/microsoft/PowerAppsCodeApps) — samples
- [microsoft/power-platform-skills](https://github.com/microsoft/power-platform-skills) — plugin Claude oficial
- O `CLAUDE.md` do próprio projeto (lessons aprendidas, gotchas específicos)

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
- **`dataverse`** via WSL bridge — schema queries, CRUD ad-hoc dentro do distro
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

### CLI `mc`

```powershell
mc new <client>          # setup novo (distro + tools + auth + scaffold)
mc adopt <client>        # migrar projeto existente para isolamento WSL
mc open <client>         # VS Code Remote-WSL no projeto
mc dev <client>          # npm run dev dentro do distro
mc shell <client>        # shell interativa no distro
mc deploy <client>       # protocolo DEPLOY
mc auth status <client>  # estado pac/az dentro do distro
mc logout <client>       # limpar tokens (fim do dia)
mc destroy <client>      # wsl --unregister (irreversível)
mc list                  # listar distros
```

### Cenário A — cliente novo do zero

```powershell
mkdir C:\Users\<user>\Projects\acme-corp
cd C:\Users\<user>\Projects\acme-corp

xcopy $env:USERPROFILE\mc-framework mc-framework\ /E /I

.\mc-framework\scripts\mc.cmd new acme-corp
```

O wizard pergunta tenant ID, env URL, solution name. Cria distro, instala tools, faz autenticação device-code (você confirma no Chrome), faz scaffolding via Microsoft starter, popula `.mcp.json` e `CLAUDE.md`.

### Cenário B — migrar projeto existente

```powershell
cd C:\caminho\para\projeto-existente
.\mc-framework\scripts\mc.cmd adopt my-client
```

Cria distro, autentica dentro, atualiza `.mcp.json` para WSL bridge, sugere cleanup de tokens no Windows.

### Cenário C — trabalhar com Claude Code

1. Abre Claude Code na pasta do projeto
2. O `CLAUDE.md` referencia `@mc-framework/AGENTS.md` automaticamente
3. Pede: *"faz setup do projeto"* / *"deploya"* / *"abre shell"*
4. Para questões Power Platform específicas (Dataverse, lookups, rollups), Claude consulta o **Microsoft Learn MCP** — fonte da verdade sempre atualizada

---

## Documentação

| Arquivo | Conteúdo |
|---|---|
| [`AGENTS.md`](AGENTS.md) | Manual para AI agents (Claude/Copilot) |
| [`PROTOCOLS.md`](PROTOCOLS.md) | DEPLOY, WRAPUP, ROLLBACK |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Camadas Windows ↔ WSL ↔ Dataverse |
| [`docs/AUTH_HYGIENE.md`](docs/AUTH_HYGIENE.md) | Princípios de isolamento por cliente |
| [`docs/MULTI_CLIENT.md`](docs/MULTI_CLIENT.md) | Onboarding, troca de contexto, template MDM |
| [`docs/MCP_SETUP.md`](docs/MCP_SETUP.md) | `.mcp.json` + WSL stdio bridge + debugging |

---

## Estrutura

```
mc-framework/
├── AGENTS.md, PROTOCOLS.md, README.md, LICENSE, CHANGELOG.md
├── docs/         (4 docs: arquitetura, auth, multi-client, MCP)
├── scripts/
│   ├── mc.ps1, mc.cmd          (CLI principal)
│   ├── new-project.ps1         (bootstrap projeto novo)
│   ├── adopt-existing.ps1      (migrar projeto existente)
│   └── distro-setup.sh         (instala tools dentro do WSL)
└── templates/    (.mcp.json, CLAUDE.md, .gitignore)
```

---

## Filosofia

- **Escopo apertado** — só auth, acesso e ambiente. Padrões de Power Platform development ficam no Microsoft Learn ou no `CLAUDE.md` do projeto, não aqui.
- **Arquivos estáticos > código compilado** — markdown e shell scripts. Sem build, sem deps extra.
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

- [`microsoft/PowerAppsCodeApps`](https://github.com/microsoft/PowerAppsCodeApps) — templates oficiais (`mc new` usa o `starter` via `npx degit`) e samples para referência
- [`microsoft/power-platform-skills`](https://github.com/microsoft/power-platform-skills) — plugin Claude Code oficial; instalável em paralelo para slash-commands `/deploy`, `/add-dataverse`, etc.
- **Microsoft Learn MCP** (`https://learn.microsoft.com/api/mcp`) — sempre ativa no `.mcp.json` template, fonte para perguntas técnicas Power Platform

A MC Framework adiciona o que essas ferramentas oficiais não cobrem:

- Auth-per-client isolada via WSL2
- Provisionamento automatizado de distros (criar, instalar tools, autenticar)
- CLI `mc` para multi-client orchestration
- Protocols opinated (DEPLOY/WRAPUP/ROLLBACK) com WSL bridge

---

## Contribuições

Issues e PRs bem-vindos. Áreas com mais valor:
- Suporte a outros workflows Power Platform (Power Automate, Power Pages, etc.)
- Otimizações da CLI `mc`
- Traduções para outros idiomas

---

## Licença

MIT — ver [LICENSE](LICENSE).
