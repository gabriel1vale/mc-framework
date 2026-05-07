# AGENTS.md — Manual for AI Agents

> **Read this before any operation.** This file describes who you are when working in a project that uses MC Framework, what tools you have, and how to decide what to do.

## What MC Framework is

A framework for **multi-client Power Platform projects** focused on three concerns: **authentication**, **access**, and **environment**.

It does NOT prescribe Power Platform / Dataverse development patterns — those come from Microsoft Learn (consult via `microsoft-learn` MCP), Microsoft samples (`microsoft/PowerAppsCodeApps`), the official Microsoft Claude plugin (`microsoft/power-platform-skills`), and the project's own `CLAUDE.md`.

What MC Framework provides:

1. **Per-client credential isolation** — each client has its own WSL2 distro where `pac` and `az` tokens live, along with MCP server processes. The Windows host never holds client credentials.
2. **Per-client environment provisioning** — distro creation, dev tools install (Node, az, .NET, pac), MCP wiring (Dataverse via WSL bridge + Microsoft Learn HTTP).
3. **Multi-client orchestration via the `mc` CLI** — `new`, `adopt`, `open`, `dev`, `shell`, `deploy`, `auth status`, `logout`, `destroy`.

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

1. **Read the project's `CLAUDE.md`** — describes the client, env URL, tenant, solution name, associated WSL distro, and any project-specific instructions.
2. **Read this AGENTS.md** (you're reading it now — via `@mc-framework/AGENTS.md` in the project's CLAUDE.md).
3. **For Power Platform / Dataverse questions**: consult the `microsoft-learn` MCP (always-on in `.mcp.json`) before answering. Microsoft docs are the source of truth.

### When the user asks "set up new project":

Follow the protocol in `scripts/new-project.ps1`:

1. **Ask only the essentials**: client name, tenant ID, env URL, solution name. If info is missing, ask — don't invent.
2. **Confirm the plan** with y/n before creating distro / installing tools.
3. **Execute** `scripts/new-project.ps1` with the gathered parameters. That script:
   - Creates WSL distro `<ClientName>` (clone of Ubuntu-24.04)
   - Installs node, az, dotnet, pac inside
   - Launches `az login --use-device-code` — pauses for human auth
   - Launches `pac auth create --deviceCode` — pauses again
   - Scaffolds the code app via `npx degit microsoft/PowerAppsCodeApps/templates/starter`
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
5. Update the project's logs / version history per `PROTOCOLS.md` WRAPUP

### When the user asks domain-specific things ("import data", "edit lookup", "fix rollup", etc.)

These are **outside the framework's scope**. Use:

1. **`microsoft-learn` MCP** for Power Platform / Dataverse / Code Apps reference (always current)
2. **`mcp__dataverse__*`** for schema queries and ad-hoc CRUD inside the project's distro
3. The project's own **`CLAUDE.md`** for project-specific patterns and constraints
4. The official **Microsoft Claude plugin** if installed (`code-apps@power-platform-skills`)

If the user is consistently asking about a domain pattern that you find yourself re-explaining, capture it in the project's `CLAUDE.md` (not in MC Framework).

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

- `WebFetch` for specific URLs (e.g. GitHub raw files, Microsoft samples)
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

### For tasks that need 2-3 questions to scope:
**Ask the essential 2-3 questions max, then verify state autonomously, then execute.** Don't ask the user to "read §X first." If context is missing, go fetch it (read code, read docs via MCP) — only ask what you cannot discover yourself.

## Non-negotiable principles

1. **Explicit confirmation for destructive ops.** Always. Regardless of "I confirmed before."
2. **Auth never on the Windows host.** If you see `pac auth create` or `az login` without `wsl.exe` in front, it's wrong.
3. **Microsoft Learn first for Power Platform questions.** Before inventing an answer about Dataverse, Code Apps, Power Automate, etc., consult `mcp__claude_ai_Microsoft_Learn__microsoft_docs_search`. Official docs change; training may be stale.
4. **Confirmation explícita for destructive operations.** Always.

## Memory hooks

When you learn something project-specific (lessons from the session), write it to the project's `SESSION_HANDOFF.md` (or equivalent) under "Lessons" with:
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

These project-specific lessons stay in the project, not in MC Framework.

## To get started

When the user says what they want to do:

| Case | Action |
|---|---|
| "create new project" / "set up from scratch" | `scripts/new-project.ps1` (with 2-3 initial questions) |
| "adopt project X" / "migrate to framework" | `scripts/adopt-existing.ps1` |
| "deploy" / "wrap up" / "rollback" | `PROTOCOLS.md` |
| "edit/read/change code" | Read/Edit/Write tools |
| Power Platform / Dataverse / Code Apps questions | `microsoft-learn` MCP first, then domain knowledge |
| Project-specific gotcha not in MC Framework docs | Project's `CLAUDE.md` + `microsoft-learn` MCP |
| Ambiguous | Ask 1-2 clarifying questions |
