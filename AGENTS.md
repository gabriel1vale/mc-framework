# AGENTS.md — Manual for AI Agents

> **Read this before any operation.** This file describes who you are when working in a project that uses MC Framework, what tools the framework gives you, and where to look for everything else.

## Scope

MC Framework is **strictly** about three things:

1. **Authentication** — per-client WSL2 distro where `pac` and `az` tokens live, isolated from the Windows host.
2. **Access** — CLI commands and conventions to enter, operate, and tear down the per-client environment.
3. **Environment provisioning** — distro creation, dev tools install (Node, az, .NET, pac), and MCP wiring (Dataverse via WSL bridge + Microsoft Learn HTTP).

**Everything else is out of scope.** When the user asks anything about:

- How to develop (deploy commands, build pipelines, code patterns)
- What to develop (features, schema design, business logic)
- What is covered (Dataverse capabilities, Code Apps features, Power Automate triggers, etc.)

…the answer comes from these sources, in this priority order:

1. **`microsoft-learn` MCP** (always-on in `.mcp.json`) — `microsoft_docs_search`, `microsoft_docs_fetch`, `microsoft_code_sample_search`. This is the source of truth for Power Platform / Dataverse / Code Apps / Power Automate / Canvas Apps / Power Pages and any Microsoft API.
2. **Microsoft repos** when concrete examples help: [`microsoft/PowerAppsCodeApps`](https://github.com/microsoft/PowerAppsCodeApps) (templates and samples), [`microsoft/power-platform-skills`](https://github.com/microsoft/power-platform-skills) (the official Claude plugin with skills like `/deploy`, `/add-dataverse`, `/add-sharepoint`).
3. **The project's own `CLAUDE.md`** for project-specific gotchas, business rules, conventions.
4. **Your own general knowledge / reasoning** as the AI agent.

## Mental model of the work environment

```
Windows host (user's PC)
├── Claude Code (runs here)
├── Project files (in Windows filesystem)
└── WSL2
    ├── distro <Client1>     ← tokens, dev tools, MCP processes for Client1
    ├── distro <Client2>     ← same for Client2
    └── ...
```

- **Files**: live on the Windows host (fast for Claude Edit/Read/Write).
- **Tokens, MCP servers, dev runtime**: live **inside** the client's WSL distro.
- **Connection**: Claude uses the Bash tool with `wsl.exe -d <Distro> -- <command>` or `.mcp.json` configured to spawn via `wsl.exe` (stdio bridge).

## What the framework does for you (and what it does NOT)

| Concern | Framework provides | What it does NOT |
|---|---|---|
| WSL distro per client | `mc new`, `mc adopt`, `mc destroy` | Distros for non-PP projects |
| Auth flow | `pac auth create --deviceCode` + `az login --use-device-code` inside the distro | Service principals, CI auth, federated identities |
| Dev tools | Node LTS, Azure CLI, .NET SDK 8, pac CLI inside the distro | App-specific deps (those go into your project's package.json) |
| MCP wiring | `dataverse` via WSL bridge + `microsoft-learn` HTTP in `.mcp.json` template | Other MCP servers (add them yourself) |
| Access shortcuts | `mc open` (VS Code Remote-WSL), `mc shell`, `mc dev` (npm run dev) | Build pipelines, deploy commands, scaffolding flows |
| Daily hygiene | `mc auth status`, `mc logout`, `mc destroy` | Backup, snapshot, archive of project work |

If the user asks for anything in the right column, you handle it via Microsoft Learn / Microsoft repos / general knowledge — NOT by extending the framework.

## When working in a project

### The user opens Claude Code in a folder. What you do:

1. **Read the project's `CLAUDE.md`** — describes the client, env URL, tenant, solution name, associated WSL distro, and any project-specific instructions.
2. **Read this AGENTS.md** (you're reading it now — via `@mc-framework/AGENTS.md` in the project's CLAUDE.md).
3. **Identify the case** (table below) and act.

### When the user asks "set up new project":

Run `scripts/new-project.ps1`. It does:

1. Creates WSL distro `<ClientName>` (clone of Ubuntu-24.04)
2. Installs node, az, dotnet, pac inside (via `distro-setup.sh`)
3. Launches `az login --use-device-code` — pauses for human auth
4. Launches `pac auth create --deviceCode` — pauses again
5. Writes `.mcp.json`, `CLAUDE.md`, `.gitignore` from `templates/`

It does NOT scaffold a Code App, a Power Automate solution, or any other artifact. That choice is the user's. Once the env is ready, the user (or you, if asked) decides what to scaffold.

Ask 2-3 essential questions max upfront (client name, tenant ID, env URL); confirm with y/n; execute.

### When the user asks "adopt existing project":

Run `scripts/adopt-existing.ps1`. Same as `new-project.ps1` but skips the new-folder/templates parts when they already exist; backs up an existing `.mcp.json` before replacing.

### When the user asks "deploy" / "build" / "scaffold a Code App" / "import data" / etc.

These are out of MC Framework's scope. Approach:

1. **Check `microsoft-learn` MCP** — `microsoft_docs_search` for the relevant operation.
2. **Check the project's `CLAUDE.md`** — there may be project-specific conventions.
3. **Check Microsoft repos** if concrete examples help.
4. **Use general knowledge** for filling gaps.
5. **Ask the user** if a meaningful decision is needed (e.g. "Code App or Power Automate?", "which solution?").
6. **Execute** with appropriate confirmations for destructive ops.

For example, "deploy a Code App" eventually translates to `wsl -d <Distro> --cd <project> -- bash -lc "pac code push --solutionName <X>"`. You know `pac code push` from Microsoft Learn / general knowledge, you know `wsl -d <Distro>` from this AGENTS.md, you know the solution name from the project's `CLAUDE.md`. Compose them.

## Tools available

### CLI — in any Windows terminal

```powershell
mc new <client>            # provision env (distro + tools + auth + templates)
mc adopt <client>          # provision env for existing project
mc open <client>           # VS Code Remote-WSL in current directory
mc shell <client>          # interactive shell in the distro
mc dev <client>            # convenience: npm install && npm run dev
mc auth status <client>    # pac/az state inside the distro
mc logout <client>         # pac auth clear + az logout inside
mc destroy <client>        # wsl --unregister (irreversible)
mc list                    # list distros
```

### Bash tool — for ad-hoc operations inside the distro

```bash
wsl.exe -d <Client> -- bash -lc "<command>"
wsl.exe -d <Client> --cd <wsl-path> -- <command>
```

This is how you run any Power Platform CLI command, build, deploy, npm script, anything Linux. The framework does not wrap them — you compose with `wsl.exe`.

### MCP servers (configured in project's `.mcp.json` via WSL bridge)

- `mcp__dataverse__*` — describe tables, CRUD records, search, fetch (runs inside the distro)
- `mcp__claude_ai_Microsoft_Learn__*` — search/fetch Microsoft Learn docs (HTTP, always available)

### Web tools

- `WebFetch` for specific URLs (GitHub raw files, Microsoft samples, etc.)
- `WebSearch` for general queries

## When to ask vs when to execute

### ALWAYS ask before:
- Destructive operations: `delete`, `reset`, `wsl --unregister`, `git push --force`, schema changes
- Auth changes: new `pac auth create`, switching tenant/env on a project
- Production operations: deploying, bulk operations >100 records
- Anything that affects the Windows host (registry, settings, account changes)

### Execute directly (without pre-confirmation):
- Light read operations: `describe_table`, `read_query`, `git log`, `git status`
- `npm install`, `npm run dev` (if the user asked to start)
- Code edits (Read/Edit/Write) — user sees them next time they look
- Microsoft Learn lookups

### For tasks that need 2-3 questions to scope:
**Ask the essential 2-3 questions max, then verify state autonomously, then execute.** Don't ask the user to "read §X first." If context is missing, go fetch it (read code, read docs via MCP) — only ask what you cannot discover yourself.

## Non-negotiable principles

1. **Explicit confirmation for destructive ops.** Always.
2. **Auth never on the Windows host.** If you see `pac auth create` or `az login` without `wsl.exe` in front, it is wrong.
3. **Microsoft Learn first for Power Platform questions.** Before inventing an answer about Dataverse, Code Apps, Power Automate, etc., consult `mcp__claude_ai_Microsoft_Learn__microsoft_docs_search`. Official docs change; training may be stale.
4. **Stay in scope.** If a request goes beyond auth + access + environment, do NOT extend the framework — use Microsoft Learn / Microsoft repos / general knowledge instead, and capture project-specific gotchas in the project's `CLAUDE.md`.

## To get started

| Case | Action |
|---|---|
| "set up new project" | `scripts/new-project.ps1` |
| "adopt project X" | `scripts/adopt-existing.ps1` |
| "open / shell / dev" | The matching `mc` command |
| "logout / destroy" | The matching `mc` command, with confirmation for destroy |
| Power Platform / Dataverse / Code Apps / Power Automate development | `microsoft-learn` MCP first, then domain knowledge |
| Project-specific gotcha | Project's `CLAUDE.md` first, then `microsoft-learn` MCP |
| Ambiguous | Ask 1-2 clarifying questions |
