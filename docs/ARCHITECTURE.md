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
│  │   ├── CLAUDE.md   (client info + project notes)              │  │
│  │   ├── .mcp.json   (WSL bridge config)                        │  │
│  │   ├── mc-framework/  (this framework, copied)                │  │
│  │   └── (whatever you scaffold for this project)               │  │
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

If the overhead is unacceptable on a specific project (heavy build systems, huge monorepos), only that project can be moved to WSL native FS without affecting the framework.

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

**Microsoft Learn MCP** is public HTTP — no auth, no WSL bridge needed. It is the agent's source-of-truth for any Power Platform / Dataverse / Code Apps / Power Automate question.

### Framework as drop-in folder

Each client project receives a copy of `mc-framework/`. Tradeoffs:

- ✅ Self-contained: the entire project zipped works on any machine
- ✅ Fixed version per project — no "framework upgrade" that breaks old projects
- ❌ Multiple copies of the same framework — update management is on the user

For v0.1 this is the chosen option. Future: Claude Code marketplace plugin for centralized auto-update.

### Strict scope

The framework prescribes **only** authentication, access, and environment. Development workflows (deploy, build, test, scaffold, import, etc.) are NOT in scope. They come from:

- **Microsoft Learn MCP** (always-on in `.mcp.json`) for any official Microsoft API/feature
- **Microsoft repos** for examples ([`microsoft/PowerAppsCodeApps`](https://github.com/microsoft/PowerAppsCodeApps) samples, [`microsoft/power-platform-skills`](https://github.com/microsoft/power-platform-skills) plugin)
- **The project's own `CLAUDE.md`** for project-specific gotchas
- **General agent reasoning** as fallback

This keeps the framework small, stable, and platform-agnostic within Power Platform (works for Code Apps, Power Automate, Canvas Apps, Power Pages, and pure Dataverse work).

## Components

### `mc` CLI (`scripts/mc.ps1`)

Consistent front-end for per-client environment ops:

| Command | Action |
|---|---|
| `mc new <client>` | Provision env (distro + tools + auth + templates) |
| `mc adopt <client>` | Provision env for an existing project |
| `mc open <client>` | VS Code Remote-WSL in the current directory |
| `mc dev <client>` | Convenience: `npm install && npm run dev` inside the distro |
| `mc shell <client>` | Interactive shell |
| `mc auth status <client>` | pac + az state inside the distro |
| `mc logout <client>` | `pac auth clear` + `az logout` inside |
| `mc destroy <client>` | `wsl --unregister` (destructive) |
| `mc list` | List existing distros |

### Auxiliary scripts (`scripts/`)

- `new-project.ps1` — orchestrates `mc new` (creates distro, installs tools, authenticates, writes templates)
- `adopt-existing.ps1` — orchestrates `mc adopt` for an existing folder
- `distro-setup.sh` — runs inside the freshly-created distro to install Node, az, dotnet, pac

### Templates (`templates/`)

- `.mcp.json.template` — with placeholders `{{DISTRO}}`, `{{ENV_URL}}`
- `CLAUDE.md.template` — with placeholders `{{CLIENT}}`, `{{TENANT_ID}}`, `{{ENV_URL}}`, `{{SOLUTION}}`, `{{DISTRO}}`
- `.gitignore.template` — standard exclusions

### Docs (`docs/`)

- `ARCHITECTURE.md` — this file
- `MCP_SETUP.md` — WSL bridge config, debugging
- `AUTH_HYGIENE.md` — per-client isolation policy, defense in depth
- `MULTI_CLIENT.md` — onboarding guide, context switching, MDM cleanup

## When NOT to use the framework

- Non-Power-Platform projects (pure web apps, back-end APIs)
- Projects where the client provides a cloud environment (Codespaces, Dev Box) — isolation is already guaranteed
- Exploratory <1-day projects where WSL distro creation overhead doesn't pay off
