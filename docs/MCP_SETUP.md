# MCP Setup

How to configure and debug MCP servers for a client project, including the WSL stdio bridge and the Microsoft Learn MCP.

## Standard `.mcp.json`

Each client project has an `.mcp.json` at the root with (at minimum) two servers:

```json
{
  "mcpServers": {
    "dataverse": {
      "type": "stdio",
      "command": "wsl.exe",
      "args": [
        "-d", "<DistroName>",
        "--",
        "npx", "-y", "@microsoft/dataverse",
        "mcp", "<env-url>"
      ],
      "env": {}
    },
    "microsoft-learn": {
      "type": "http",
      "url": "https://learn.microsoft.com/api/mcp"
    }
  }
}
```

Where:
- `<DistroName>` is the name of the client's WSL distro (e.g. `client-x`)
- `<env-url>` is the URL of the Dataverse environment (e.g. `https://example.crm4.dynamics.com/`)

## How the WSL bridge works

When Claude Code starts a session in a project:

1. Reads `.mcp.json`
2. For each `stdio` server, runs `spawn(command, args)` on the Windows host
3. `wsl.exe -d <Distro> -- npx ...` creates a Windows-side process that is just a proxy
4. That proxy invokes inside the WSL distro: `npx -y @microsoft/dataverse mcp <env-url>`
5. **stdin/stdout/stderr are preserved** across the Windows ↔ WSL boundary
6. Claude sends JSON-RPC via stdin → crosses to the process inside WSL → response comes back via stdout

For Claude it's indistinguishable from a local MCP server. For the MCP server it's as if Claude were on the same machine (Linux).

## Microsoft Learn MCP (always on)

```json
"microsoft-learn": {
  "type": "http",
  "url": "https://learn.microsoft.com/api/mcp"
}
```

- HTTP transport — no need for WSL or local process
- No auth — public
- Tools available: `microsoft_docs_search`, `microsoft_docs_fetch`, `microsoft_code_sample_search`

**When to use**: before answering any question about Power Platform / Dataverse / Code Apps when there is doubt about version, behavior, or pattern. The agent's training may be stale; Microsoft Learn is the current source of truth.

## Prerequisites

For the `dataverse` MCP to work, inside the WSL distro you need:

1. Node.js (installed via `scripts/distro-setup.sh`)
2. `pac` or `az` authenticated (the `@microsoft/dataverse` package uses the local token cache)

If the user just created the distro but hasn't done `pac auth create` / `az login` yet, the MCP server starts but fails on attempting API calls. Solution: complete authentication first.

## Debugging

### "MCP server failed to start"

Check:

```powershell
# 1. Distro exists?
wsl --list --quiet

# 2. wsl.exe can invoke commands in the distro?
wsl -d <Distro> -- echo "ok"

# 3. npx works inside the distro?
wsl -d <Distro> -- npx --version

# 4. Does the @microsoft/dataverse package install?
wsl -d <Distro> -- npx -y @microsoft/dataverse --version
```

### "Authentication failed" / "Token expired"

Tokens inside the distro have expired. Re-authenticate:

```powershell
wsl -d <Distro> -- pac auth list
wsl -d <Distro> -- az account show
```

If empty or error:

```powershell
wsl -d <Distro> -- az login --use-device-code --tenant <tenant-id>
wsl -d <Distro> -- pac auth create --deviceCode --environment <env-id>
```

Restart Claude Code to force MCP reconnection.

### "Server hangs / no response"

Probably the MCP process inside the distro is blocked waiting for interactive input (e.g. auth prompt). Check with:

```powershell
wsl -d <Distro> -- pgrep -af "@microsoft/dataverse"
```

Kill if needed and re-authenticate before restarting Claude.

### "WSL distro is in stopped state"

```powershell
wsl --list --verbose          # see state
wsl -d <Distro> -- echo "wake up"   # wake up
```

## Variants / extensions

### Microsoft Power Platform CLI plugin (official)

If you want to add the official plugin for slash-commands like `/deploy`, `/add-dataverse`:

```powershell
# Once in Claude Code:
/plugin marketplace add microsoft/power-platform-skills
/plugin install code-apps@power-platform-skills
```

The plugin's commands are additional to the tools/MCP described here — they don't replace.

### Other useful MCP servers

For specific projects you can add:

```json
"playwright": {
  "type": "stdio",
  "command": "wsl.exe",
  "args": ["-d", "<DistroName>", "--", "npx", "@playwright/mcp@latest"]
}
```

For E2E tests. Same WSL bridge pattern.

## Performance notes

- MCP via WSL bridge has ~50-100ms overhead per call vs. local — imperceptible for most operations
- HTTP MCP (Microsoft Learn) has normal network latency — depends on the link
- Dataverse MCP `read_query` has internal cap of 20 records — for large operations use direct Web API (see `BULK_OPS_PATTERNS.md`)
