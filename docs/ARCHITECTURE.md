# Architecture

Overview of how the framework composes and the rationale for each piece.

## Layers

```
┌────────────────────────────────────────────────────────────────────┐
│ Windows host                                                       │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ Claude Code (VS Code extension or CLI)                       │  │
│  │  • Read/Edit/Write tools → Windows filesystem direct         │  │
│  │  • Bash tool → Git Bash + invokes wsl.exe                    │  │
│  │  • MCP tools → spawned via wsl.exe (stdio bridge)            │  │
│  └──────────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ Project files                                                │  │
│  │   C:\Users\<user>\Projects\<client>\                         │  │
│  │   ├── CLAUDE.md   (client-specific config)                   │  │
│  │   ├── .mcp.json   (WSL bridge config)                        │  │
│  │   ├── mc-framework/  (this framework, copied)                │  │
│  │   └── code-app/   (the actual app)                           │  │
│  └──────────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ mc.cmd / mc.ps1 in PATH (or directly via .\mc-framework\...) │  │
│  └──────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────┘
                              │
                              │  wsl.exe -d <Distro> -- ...
                              ▼
┌────────────────────────────────────────────────────────────────────┐
│ WSL2                                                               │
│  ┌────────────────────┐  ┌────────────────────┐                    │
│  │ Distro: <Client1>  │  │ Distro: <Client2>  │   ...              │
│  │                    │  │                    │                    │
│  │ tokens (pac, az)   │  │ tokens (pac, az)   │                    │
│  │ dev tools          │  │ dev tools          │                    │
│  │ MCP server procs   │  │ MCP server procs   │                    │
│  │ /mnt/c/... mount   │  │ /mnt/c/... mount   │                    │
│  └────────────────────┘  └────────────────────┘                    │
└────────────────────────────────────────────────────────────────────┘
                              │
                              │  HTTPS direct (with isolated tokens)
                              ▼
┌────────────────────────────────────────────────────────────────────┐
│ Power Platform / Dataverse APIs (cloud, per client tenant)         │
└────────────────────────────────────────────────────────────────────┘
```

## Foundational decisions

### Files on the Windows host, not in WSL

Tradeoff: Vite hot-reload via /mnt/c has ~200ms overhead vs. Linux native filesystem. Accepted because:

- Claude's Read/Edit/Write tools operate ~10× faster on Windows native
- VS Code (UI) loads on Windows; opening WSL filesystem via UNC is slower
- Git/Explorer workflow more natural

If the overhead is unacceptable on a specific project (e.g. heavy build systems, huge monorepos), only that project can be moved to WSL native FS without affecting the framework.

### Auth isolated per WSL distro

**Principle**: each client is a sealed cube. WSL distro → its tokens. Chrome profile → its cookies. Project folder → its code.

When the client contract ends:
```powershell
mc destroy <client>          # wsl --unregister
# (manually: remove Chrome profile + delete project folder)
```

Tokens, MFA cache, MSAL caches, refresh tokens — all evaporate with `unregister`.

### MCP servers run INSIDE the distro

Project's `.mcp.json`:
```json
{
  "mcpServers": {
    "dataverse": {
      "type": "stdio",
      "command": "wsl.exe",
      "args": ["-d", "<DistroName>", "--", "npx", "-y", "@microsoft/dataverse", "mcp", "<env-url>"]
    },
    "microsoft-learn": {
      "type": "http",
      "url": "https://learn.microsoft.com/api/mcp"
    }
  }
}
```

Claude on Windows spawns `wsl.exe`. wsl.exe is a stdin/stdout proxy to the process inside the distro. The MCP server runs there, uses the tokens there, communicates via stdio that crosses transparently.

**Microsoft Learn MCP** is public HTTP — no auth, no WSL bridge needed.

### Framework as drop-in folder

Each client project receives a copy of `mc-framework/`. Tradeoffs:

- ✅ Self-contained: the entire project zipped works on any machine
- ✅ Fixed version per project — no "framework upgrade" that breaks old projects
- ❌ Multiple copies of the same framework — update management is on the user

For v1 this is the chosen option. Future: Claude Code marketplace plugin for centralized auto-update.

## Components

### `mc` CLI (`scripts/mc.ps1`)

Consistent front-end for all multi-client operations:

| Command | Action |
|---|---|
| `mc new <client>` | Full setup (distro + tools + auth + scaffold) |
| `mc adopt <client>` | Migrate existing project to the model |
| `mc open <client>` | VS Code Remote-WSL in the project |
| `mc dev <client>` | `npm run dev` inside the distro |
| `mc shell <client>` | Interactive shell |
| `mc deploy <client>` | Execute DEPLOY protocol |
| `mc auth status <client>` | pac + az state inside |
| `mc logout <client>` | `pac auth clear` + `az logout` inside |
| `mc destroy <client>` | `wsl --unregister` (destructive) |

### Auxiliary scripts (`scripts/`)

- `new-project.ps1` — orchestrates `mc new` (creates distro, installs tools, authenticates, scaffolds)
- `adopt-existing.ps1` — orchestrates `mc adopt`
- `distro-setup.sh` — runs inside the freshly-created distro to install Node, az, dotnet, pac
- `lib/import-template.mjs` — parameterizable template for bulk imports
- `lib/reset-template.mjs` — template for wipe + recalc

### Templates (`templates/`)

- `.mcp.json.template` — with placeholders `{{DISTRO}}`, `{{ENV_URL}}`
- `CLAUDE.md.template` — with placeholders `{{CLIENT}}`, `{{TENANT_ID}}`, `{{ENV_URL}}`, `{{SOLUTION}}`, `{{DISTRO}}`
- `.gitignore.template` — standard exclusions for Power Platform projects

### Patterns docs (`docs/`)

Codified knowledge:
- `DATAVERSE_PATTERNS.md` — gotchas (FormattedValue, lookup binding)
- `ROLLUP_PATTERNS.md` — empty-source workaround, dummy-anchor pattern
- `BULK_OPS_PATTERNS.md` — `az` + Web API direct for scale
- `IMPORT_PIPELINE.md` — xlsx/csv parser + validation + preview UI
- `MCP_SETUP.md` — WSL bridge config, debugging
- `AUTH_HYGIENE.md` — per-client isolation policy
- `MULTI_CLIENT.md` — onboarding guide

## When NOT to use the framework

- Non-Power-Platform projects (pure web apps, back-end APIs, etc.)
- Projects where the client provides cloud environment (Codespaces, Dev Box) — isolation is already guaranteed
- Exploratory <1-day projects where WSL distro creation overhead doesn't pay off
