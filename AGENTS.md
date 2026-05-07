# AGENTS.md — Manual for AI Agents

> **Read this before any operation.** This file describes who you are when working in a project that uses MC Framework, what tools you have, and how to decide what to do.

## What MC Framework is

A framework for **multi-client Power Platform projects**. Solves three problems:

1. **Per-client credential isolation** — each client has its own WSL2 distro where `pac` and `az` tokens live, along with MCP server processes. The Windows host never holds client credentials.
2. **Documented Power Platform patterns** — Dataverse lookup gotchas, rollup empty-source workaround, bulk ops via Web API, import pipelines.
3. **Operation patterns** (DEPLOY, WRAPUP, IMPORT, ROLLBACK) consistent across clients.

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

## When working in a project

### The user opens Claude Code in a folder. What you do:

1. **Read the project's `CLAUDE.md`** — describes the client, env URL, tenant, solution name, associated WSL distro.
2. **Read this AGENTS.md** (you're reading it now — via `@mc-framework/AGENTS.md` in the project's CLAUDE.md).
3. **Load relevant patterns** when needed — follow the `@` references below.

### When the user asks "set up new project":

Follow the protocol in `scripts/new-project.ps1`:

1. **Ask only the essentials**: client name, tenant ID, env URL, solution name. If info is missing, ask — don't invent.
2. **Confirm the plan** with y/n before creating distro / installing tools.
3. **Execute** `scripts/new-project.ps1` with the gathered parameters. That script:
   - Creates WSL distro `<ClientName>` (clone of Ubuntu-24.04)
   - Installs node, az, dotnet, pac inside
   - Launches `az login --use-device-code` — pauses for human auth
   - Launches `pac auth create --deviceCode` — pauses again
   - Scaffolds the code app from `templates/code-app-starter/` (or via `npx degit microsoft/PowerAppsCodeApps/templates/starter`)
   - Writes `.mcp.json` in the project from `templates/.mcp.json.template`
   - Writes `CLAUDE.md` from `templates/CLAUDE.md.template`
4. **Report** the final state: project path, distro name, next steps.

### When the user asks "adopt existing project":

Follow `scripts/adopt-existing.ps1`. Migrates a project that already exists (with auth on the Windows host) to the isolated WSL model:

1. Ask for the distro name to create
2. Create distro, install tools
3. Run `pac auth create` + `az login` inside the distro
4. Update the project's `.mcp.json` to use the `wsl.exe` bridge
5. Suggest the user run `pac auth clear` on the Windows host (cleanup of older contamination)

### When the user asks "deploy":

Follow `PROTOCOLS.md` section **DEPLOY**. Summary:

1. Pre-validation (TS check + build) — automatic, failure blocks deploy
2. Explicit y/n confirmation
3. `wsl -d <Distro> -- bash -lc "cd <project> && pac code push --solutionName <Solution>"`
4. Post-deploy verification via `pac code list`
5. Update logs, version history, session handoff

### When the user asks "bulk import":

Follow `docs/IMPORT_PIPELINE.md`. Standard pattern:

1. Ask for source file (xlsx/csv) and target table
2. Inspect table schema via MCP `dataverse__describe_table`
3. Adapt `scripts/lib/import-template.mjs` to the client's schema
4. Auth: `az account get-access-token --resource <env-url>` (from inside the WSL distro)
5. Web API direct with `Promise.allSettled` in batches of 10
6. Recalc rollups afterwards (if applicable — see `ROLLUP_PATTERNS.md`)

### When the user asks "read table X":

1. Use MCP `dataverse__describe_table` to obtain the schema
2. For simple queries: `dataverse__read_query` (limit 20 records per call)
3. For large queries: use the pattern in `BULK_OPS_PATTERNS.md` (Web API direct)

## Critical patterns (read when relevant)

@docs/DATAVERSE_PATTERNS.md
@docs/ROLLUP_PATTERNS.md
@docs/BULK_OPS_PATTERNS.md
@docs/IMPORT_PIPELINE.md
@docs/MCP_SETUP.md

## Tools available

### CLI — in any Windows terminal

```powershell
mc new <client>            # create new project from scratch
mc adopt <client>          # migrate existing project to framework
mc open <client>           # open VS Code with Remote-WSL in project
mc dev <client>            # run npm run dev inside the distro
mc shell <client>          # interactive shell in the distro
mc deploy <client>         # execute DEPLOY protocol
mc auth status <client>    # check pac/az auth inside the distro
mc logout <client>         # pac auth clear + az logout inside the distro
mc destroy <client>        # wsl --unregister <client> (destructive!)
```

### Bash tool — for ad-hoc operations inside the distro

```bash
wsl.exe -d <Client> -- bash -lc "<command>"
wsl.exe -d <Client> --cd <wsl-path> -- <command>
```

### MCP servers (configured in project's `.mcp.json` via WSL bridge)

- `mcp__dataverse__*` — describe tables, CRUD records, search, fetch (runs inside the distro)
- `mcp__claude_ai_Microsoft_Learn__*` — search/fetch Microsoft Learn docs (HTTP, always available)

### Web tools

- `WebFetch` for specific URLs (e.g. GitHub raw files)
- `WebSearch` for general queries

## When to ask vs when to execute

### ALWAYS ask before:
- Destructive operations: `delete`, `reset`, `wsl --unregister`, `git push --force`, schema changes
- Auth changes: new `pac auth create`, switching tenant/env on a project
- Production operations: deploy, bulk imports >100 records
- Anything that affects the Windows host (registry, settings, account changes)

### Execute directly (without pre-confirmation):
- Light read operations: `describe_table`, `read_query`, `git log`, `git status`
- `npm install`, `npm run dev` (if the user asked to start)
- Code edits (Read/Edit/Write) — user sees them next time they look
- Microsoft Learn lookups

### For Power Platform / Code Apps tasks:
**Ask 2-3 essential questions max, then verify state autonomously, then execute.** Don't ask the user to "read §X first." If context is missing, go fetch it (read code, read docs via MCP) — only ask what you cannot discover yourself.

## Non-negotiable principles

1. **Explicit confirmation for destructive ops.** Always. Regardless of "I confirmed before."
2. **Auth never on the Windows host.** If you see `pac auth create` or `az login` without `wsl.exe` in front, it's wrong.
3. **Microsoft Learn first.** Before inventing an answer about Power Platform/Dataverse, consult `mcp__claude_ai_Microsoft_Learn__microsoft_docs_search`. Official docs change; my training may be stale.
4. **Logs in `dataverse/logs/YYYY-MM-DD/session.md`** for any significant operation in live systems (deploy, bulk import, schema change).
5. **Immutable version history.** `VERSION_HISTORY.md` entries marked `COMPLETE - DO NOT MODIFY` are not re-edited. New releases go as new entries at the top.

## Memory hooks (memory bank format)

When you learn something project-specific (lessons from the session), write it to the project's `SESSION_HANDOFF.md` under "Lessons" with:
- **Rule**: single, actionable rule
- **Why**: concrete reason (incident, constraint)
- **How to apply**: when/where to apply

Example:
```markdown
### L<N> — <Short title>
**Rule:** <rule>
**Why:** <reason>
**How to apply:** <when/where>
```

## To get started

When the user says what they want to do, identify the case:

| Case | Action |
|---|---|
| "create new project" / "set up from scratch" | `scripts/new-project.ps1` (with 2-3 initial questions) |
| "adopt project X" / "migrate to framework" | `scripts/adopt-existing.ps1` |
| "edit/read/change code" | Read/Edit/Write tools as usual |
| "deploy" | `PROTOCOLS.md` DEPLOY |
| "wrap up" | `PROTOCOLS.md` WRAPUP |
| "import data" | `docs/IMPORT_PIPELINE.md` + adapt `scripts/lib/import-template.mjs` |
| "read table X" / "explore schema" | MCP `dataverse__describe_table` + `read_query` |
| Ambiguous | Ask 1-2 clarifying questions |

Don't try to remember everything from here — use `@` references to specific docs when you need them.
