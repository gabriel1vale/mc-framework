# Multi-Client Workflow

How to manage multiple clients with the framework, including onboarding, context switching, and cleanup of prior contamination.

## Onboarding a new client

### Host prerequisites

- WSL2 installed (the `mc` CLI installs if missing)
- Chrome/Edge/Brave (any Chromium-based browser)
- (Optional but recommended) browser profile dedicated to the client

### Setup

```powershell
# 1. Create project folder
mkdir C:\Users\<user>\Projects\<client>
cd C:\Users\<user>\Projects\<client>

# 2. Copy the framework
# (option A: fresh clone)
git clone https://<framework-repo-url> mc-framework

# (option B: copy from existing folder)
# drag mc-framework/ into the folder

# 3. Create initial CLAUDE.md (manually)
# Minimum content:
#   # Project <Client>
#   ## Client: <Client>
#   ## Framework
#   @mc-framework/AGENTS.md

# 4. Open Claude Code here and say "set up the project"
# (Claude reads AGENTS.md, follows scripts/new-project.ps1)
```

OR directly via the framework's CLI:

```powershell
.\mc-framework\scripts\mc.cmd new <client>
```

Which does everything automated:
- Creates WSL distro
- Installs tools inside
- Launches device-code logins (`az` + `pac`)
- Scaffolds the code app
- Writes populated `.mcp.json` and `CLAUDE.md`

### First Claude session

After setup, you open Claude Code in the folder. The `CLAUDE.md` points to `@mc-framework/AGENTS.md`. Claude has full context. Say what you want to do (create features, read tables, etc.) and it follows.

## Context switching between clients

You have 3 active clients: client-A, client-B, client-C.

### Morning: working for client-A

```powershell
# Open VS Code Remote-WSL in client A's folder
mc open client-a

# OR if you prefer terminal:
mc shell client-a
cd /mnt/c/users/<user>/projects/client-a
```

Client-A's tokens are used. Client-B and client-C tokens sleep in their distros, without interfering.

### Afternoon: switch to client-B

You close VS Code (or open another window):

```powershell
mc open client-b
```

Same pattern. No cross-contamination.

### End of day

Logout in all clients you worked on (optional but recommended):

```powershell
mc logout client-a
mc logout client-b
```

To return tomorrow, new device-code login (5 seconds per client).

## Cleanup of prior contamination

Before adopting the framework, you likely already have client tokens on the Windows host. How to clean up:

### CLI cleanup

```powershell
pac auth clear              # delete all pac profiles
pac auth delete --index <N> # delete specific profile if it persists
az logout                   # logout from az
az account clear            # clear az cache
```

### Windows account cleanup

`Settings → Accounts → Access work or school`

For each client account listed:
- If "Disconnect" button is available → click, confirm, account leaves
- If greyed out → MDM enrollment, see mail template below

### Browser cleanup

In your personal browser profile (NOT in the dedicated client profile, which you'll use in next device-code flows):

**Brave**: `brave://settings/content/all` → search and remove cookies for:
- `microsoftonline.com`
- `live.com`
- `account.microsoft.com`
- `*.dynamics.com`
- `*.office.com`
- client domains

**Chrome**: `chrome://settings/content/all` (same)

OR Brave shortcut: visit `https://login.microsoftonline.com`, click the shield/padlock to the left of the URL, "Forget this site". Repeat for each domain.

### Microsoft account portal cleanup

`account.microsoft.com` → "Organizations" section → for each client org listed → "Leave organization".

### Verification

```powershell
# Should be empty:
pac auth list
az account list

# Should not exist:
Test-Path "$env:LOCALAPPDATA\.IdentityService"
```

If `.IdentityService` still exists and has client entries, it's because:
- An account is still in "Access work or school" (layer 4)
- Or another Microsoft app (Outlook, Teams desktop) is still logged in

Resolve those first, then re-verify.

## Mail template for client IT (MDM disenrollment)

If "Disconnect" is greyed out in Settings:

```
Subject: Request for MDM disenrollment of device <DeviceID>

Hello,

I am a consultant working on <Client> projects through <Lean>.
The <Client> tenant is enrolled on my personal laptop, likely from a
prior work session. As the laptop is not managed by <Client>
(it's personal hardware), I would like to request that the device
be removed from management (MDM disenrollment).

Details:
  Device name: <see in Settings → System → About>
  Device object ID: <see at account.microsoft.com → Devices>
  Tenant: <Client>

Going forward, I will align with <Lean> on the correct way to access
your resources without having my personal device enrolled (e.g. cloud
environment, service account, or corporate laptop).

Thank you,
<name>
```

## When to switch from framework to nothing

The framework is overhead. For projects where it's NOT justified:

- Client provides corporate laptop → use that
- Client pays for cloud environment (Codespaces, Dev Box) → use that
- Exploratory <1 day project → work fast in a temp folder, delete after
- Your own personal project (not client work) → no need for isolation

## When the framework is essential

- Multiple simultaneous clients on personal hardware
- Doubt about whether you'll continue with the client (you want flexibility for `wsl --unregister`)
- Audit/compliance is (or might become) a topic
- You want to coexist with different tooling versions (client A on .NET 8, client B on .NET 10) without conflicts
