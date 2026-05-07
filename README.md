# MC Framework

> **MC = Multi Client.** Framework para consultores Power Platform que trabalham em hardware pessoal para múltiplos clientes simultaneamente. **Escopo estrito: autenticação, acesso e provisionamento de ambiente.** Tudo o que envolve desenvolvimento (deploy, build, scaffolding, padrões Power Platform) vem do Microsoft Learn (via MCP), dos repos oficiais Microsoft e do próprio AI agent.

> 📘 README em PT-BR. Documentação técnica, scripts e código em inglês.

**Status:** v0.1.0

[Setup](#setup) · [Como usar](#como-usar) · [Documentação](#documentação) · [Construído sobre](#construído-sobre)

---

## O que faz (e o que não faz)

Resolve dois problemas de quem trabalha em vários clientes Power Platform:

| Problema | Consequência |
|---|---|
| Tokens (`pac`, `az`, cookies, MDM) acumulam no Windows host | Difícil limpar; MDM exige IT do cliente |
| AI agents (Claude/Copilot) sem contexto consistente entre projetos | Cada sessão começa explicando à IA "como fazemos aqui" |

**Faz:**

- 🔒 **Um distro WSL2 por cliente** — tokens isolados; `wsl --unregister` apaga tudo no fim do contrato
- 🛠️ **Provisionamento automático** — cria distro, instala Node/az/.NET/pac, autentica via device-code, popula `.mcp.json` e `CLAUDE.md`
- 🤖 **`AGENTS.md` único** — o agent lê uma vez por sessão e sabe os comandos `mc`, como acessar o distro, como autenticar

**NÃO faz:**

- ❌ Padrões de desenvolvimento Power Platform (Dataverse lookups, rollups, imports, Code App scaffolding, etc.)
- ❌ Workflows de deploy / build / test (varia por tipo de projeto: Code App, Power Automate, Canvas App, Power Pages)
- ❌ Convenções de pasta de projeto, version history, session logs

Para tudo isso o agent consulta:

| Fonte | Para quê |
|---|---|
| `microsoft-learn` MCP (sempre ativa no `.mcp.json`) | Documentação Microsoft sempre atualizada (Dataverse, Code Apps, Power Automate, etc.) |
| [microsoft/PowerAppsCodeApps](https://github.com/microsoft/PowerAppsCodeApps) | Templates oficiais e samples |
| [microsoft/power-platform-skills](https://github.com/microsoft/power-platform-skills) | Plugin Claude Code oficial (slash-commands `/deploy`, `/add-dataverse`, etc.) |
| `CLAUDE.md` do projeto | Gotchas, regras, convenções específicas do projeto |
| Conhecimento geral do agent | Como fallback |

A framework deliberadamente NÃO tenta cobrir esses domínios — eles mudam, dependem do tipo de projeto, e já têm fontes oficiais melhores.

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
mc new <client>          # provisionar ambiente (distro + tools + auth + templates)
mc adopt <client>        # provisionar ambiente para projeto existente
mc open <client>         # VS Code Remote-WSL no projeto
mc shell <client>        # shell interativa no distro
mc dev <client>          # conveniência: npm install && npm run dev no distro
mc auth status <client>  # estado pac/az dentro do distro
mc logout <client>       # limpar tokens (fim do dia)
mc destroy <client>      # wsl --unregister (irreversível)
mc list                  # listar distros
```

Note que **não há `mc deploy` nem `mc build`** — esses são desenvolvimento, fora do escopo. Para deployar, abre `mc shell <client>` e usa o comando que se aplica (`pac code push`, `pac solution import`, ou outro), guiado pelo Microsoft Learn / Claude.

### Cenário A — cliente novo do zero

```powershell
mkdir C:\Users\<user>\Projects\acme-corp
cd C:\Users\<user>\Projects\acme-corp

xcopy $env:USERPROFILE\mc-framework mc-framework\ /E /I

.\mc-framework\scripts\mc.cmd new acme-corp
```

O wizard pergunta tenant ID, env URL, solution name (opcional). Cria distro, instala tools, faz autenticação device-code (você confirma no Chrome), e escreve `.mcp.json` + `CLAUDE.md` + `.gitignore` populados. Pronto.

A partir daí, o que você quiser construir (Code App, Power Automate solution, etc.) é decisão sua — peça ao Claude para fazer scaffolding via Microsoft starter, `pac solution clone`, ou outra forma.

### Cenário B — migrar projeto existente

```powershell
cd C:\caminho\para\projeto-existente
.\mc-framework\scripts\mc.cmd adopt my-client
```

Cria distro, autentica dentro, atualiza `.mcp.json` para WSL bridge, sugere cleanup de tokens no Windows.

### Cenário C — trabalhar com Claude Code

1. Abre Claude Code na pasta do projeto
2. O `CLAUDE.md` referencia `@mc-framework/AGENTS.md` automaticamente
3. Pede: *"abre shell"*, *"deploya o projeto"*, *"importa este xlsx"*, etc.
4. Claude usa os comandos `mc` para acesso, e consulta o **Microsoft Learn MCP** + repos Microsoft + conhecimento geral para a parte de desenvolvimento

---

## Documentação

| Arquivo | Conteúdo |
|---|---|
| [`AGENTS.md`](AGENTS.md) | Manual para AI agents — escopo, ferramentas, onde procurar respostas fora do escopo |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Camadas Windows ↔ WSL ↔ Dataverse |
| [`docs/AUTH_HYGIENE.md`](docs/AUTH_HYGIENE.md) | Princípios de isolamento por cliente |
| [`docs/MULTI_CLIENT.md`](docs/MULTI_CLIENT.md) | Onboarding, troca de contexto, template de mail MDM |
| [`docs/MCP_SETUP.md`](docs/MCP_SETUP.md) | `.mcp.json` + WSL stdio bridge + debugging |

---

## Estrutura

```
mc-framework/
├── AGENTS.md, README.md, LICENSE, CHANGELOG.md
├── docs/         (4 docs: arquitetura, auth, multi-client, MCP)
├── scripts/
│   ├── mc.ps1, mc.cmd          (CLI principal)
│   ├── new-project.ps1         (provisionamento de ambiente novo)
│   ├── adopt-existing.ps1      (migrar projeto existente)
│   └── distro-setup.sh         (instala tools dentro do WSL)
└── templates/    (.mcp.json, CLAUDE.md, .gitignore)
```

---

## Filosofia

- **Escopo apertado** — só auth, acesso e ambiente. Tudo de desenvolvimento Power Platform vem de fontes oficiais (Microsoft Learn / repos Microsoft / agent).
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

- [`microsoft/PowerAppsCodeApps`](https://github.com/microsoft/PowerAppsCodeApps) — templates e samples; quando precisares de scaffolding de Code App, é daí que sai
- [`microsoft/power-platform-skills`](https://github.com/microsoft/power-platform-skills) — plugin Claude Code oficial; instalável em paralelo para slash-commands `/deploy`, `/add-dataverse`, etc.
- **Microsoft Learn MCP** (`https://learn.microsoft.com/api/mcp`) — sempre ativa no `.mcp.json` template, fonte para perguntas Power Platform

A MC Framework adiciona o que essas ferramentas não cobrem:

- Auth-per-client isolada via WSL2
- Provisionamento automatizado de distros (criar, instalar tools, autenticar)
- CLI `mc` para multi-client orchestration

---

## Contribuições

Issues e PRs bem-vindos. Áreas com mais valor:
- Suporte a outros workflows de auth (service principals, federated identity)
- Otimizações da CLI `mc`
- Traduções para outros idiomas

---

## Licença

MIT — ver [LICENSE](LICENSE).
