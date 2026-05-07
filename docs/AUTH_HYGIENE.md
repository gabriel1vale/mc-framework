# Auth Hygiene

How to ensure client credentials don't contaminate the Windows host.

## The problem

By default, Microsoft tools (`pac`, `az`, browsers, Outlook, OneDrive) save tokens in Windows-wide locations:

- `%LOCALAPPDATA%\Microsoft\PowerAppsCli\` — pac CLI tokens
- `~/.azure/` — Azure CLI tokens
- `%LOCALAPPDATA%\.IdentityService\` — OS-level token broker (WAM / MSAL cache)
- Browser cookies in `*.dynamics.com`, `*.microsoftonline.com`, `*.office.com`

Worse: if an app asks "let other apps use this account?", Windows adds the account to the **Token Broker (WAM)**, and from then on any Microsoft tool uses silent SSO. Even worse: if the app requests management (MDM enrollment), the org's remote admin can manage your device — and you cannot "Disconnect" without their IT's help.

For a consultant working on personal hardware, this is a compliance failure mode.

## The solution: a WSL2 distro per client

Each client has its own Linux distro inside WSL2. **Everything** related to client auth lives there:

```
WSL2
├── distro: client-1
│    ├── ~/.azure/                              ← client-1 az tokens
│    ├── ~/.local/share/Microsoft/PowerAppsCli/ ← client-1 pac tokens
│    └── (npm packages, dev tools, MCP procs)
│
├── distro: client-2
│    └── ... (same for client-2)
│
```

The Linux distro has **no** WAM, **no** MDM enrollment from Windows, **does not share** Identity Service with the host. Tokens are sealed in the Linux filesystem.

When the contract with client-1 ends:

```powershell
mc destroy client-1
# OR manually:
wsl --unregister client-1
```

`unregister` deletes the entire distro filesystem. Tokens, refresh tokens, packages, everything. Zero traces on the Windows host.

## Layers of isolation (defense in depth)

### Layer 1: WSL distro (CLI tokens)

As described above. All CLI tokens live in the distro.

### Layer 2: Dedicated Chrome profile (browser sessions)

The `--device-code` flow needs the user to authorize via browser. Recommendation: each client has its own **Chrome/Edge/Brave profile**. Cookies for `*.dynamics.com` are contained in the profile. When the contract ends, delete the browser profile.

### Layer 3: Separate project folder

In `C:\Users\<user>\Projects\<client>\` (or any other consistent path). When the contract ends, delete the folder. Can be archived if there's legal/audit need.

### Layer 4: DO NOT use a work account on Windows

**Critical**: never accept "Add this account to other apps?" when logging into a Microsoft app. If indispensable (e.g. app requires it), do it on a separate Windows user account (multi-user) or in a VM.

If an account was added by mistake: `Settings → Accounts → Access work or school → Disconnect`.

If "Disconnect" is greyed out, it's MDM enrollment — only the organization's IT can remove (mail template in `MULTI_CLIENT.md`).

## Daily workflow

### Start working

```powershell
# If the distro doesn't exist yet (first time)
mc new <client>

# Otherwise
mc open <client>      # opens VS Code Remote-WSL
# OR
mc shell <client>     # interactive shell
```

The first time of the day, if tokens have expired, `pac` or `az` will ask for re-auth via device code. Repeat the flow in the client's Chrome profile.

### End of work (end of day)

```powershell
mc logout <client>
```

Equivalent to:
```bash
wsl -d <client> -- pac auth clear
wsl -d <client> -- az logout
wsl -d <client> -- az account clear
```

The refresh tokens inside the distro are invalidated. To resume, new device-code login.

### End of work (end of contract)

```powershell
mc destroy <client>
```

Asks for double confirmation (writing the client name). Runs `wsl --unregister`. **Irreversible.**

Additionally:
- Delete the client's Chrome profile
- Delete the project folder (or archive)
- Confirm at `account.microsoft.com` → "Organizations" → "Leave organization" (if applicable)

## Verify it's clean

At any time you can check the Windows host state:

```powershell
# CLIs
pac auth list                   # should be empty if you're not actively working
az account list                 # same

# OS-level caches
Test-Path "$env:LOCALAPPDATA\.IdentityService"   # should be False or only contain personal MS account

# Work accounts on Windows
# Settings → Accounts → Access work or school
# Only legitimate accounts (your own employer, if applicable) — no clients
```

And inside the distro:

```powershell
mc auth status <client>
```

Lists pac auth and az account specifically inside the distro.

## Typical scenarios

### "I just logged into a Microsoft app (Outlook, OneDrive, etc.) and it added the account to Windows"

1. Go to Settings → Accounts → Access work or school
2. Check if there are client entries
3. If yes and the "Disconnect" button is available → disconnect
4. If greyed out (MDM) → mail to the client's IT (template in `MULTI_CLIENT.md`)
5. In parallel, move work to the WSL distro — from that moment on, no new contamination

### "The client provided a corporate laptop"

Excellent — use their laptop for their work. The framework isn't needed in that case (isolation is already physical, machine by machine).

### "The client pays for Azure Dev Box / GitHub Codespaces"

Same — use their cloud environment. The framework is unnecessary overhead.

The framework is only necessary when working **on personal hardware** for multiple clients (typical consulting).

## Non-goals

The framework **does not solve**:

- Existing MDM enrollment — only the client's IT can remove
- Browser cookies already saved before adoption — need manual cleanup (one time)
- Microsoft account portal showing linked organizations — separate from CLI/MCP, managed at `account.microsoft.com`

For those situations, see `MULTI_CLIENT.md` section "Cleanup of prior contamination".
