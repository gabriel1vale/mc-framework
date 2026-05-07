<#
.SYNOPSIS
  Provision a new client environment for MC Framework.

.DESCRIPTION
  Orchestrates:
    1. Verifies WSL2 installed (installs if missing)
    2. Gathers client info (tenant, env, optional solution)
    3. Creates WSL distro <ClientName> (clone of Ubuntu-24.04)
    4. Bootstraps dev tools inside (node, az, dotnet, pac) via distro-setup.sh
    5. Launches az login --use-device-code (waits for human auth)
    6. Launches pac auth create --deviceCode (waits for human auth)
    7. Writes .mcp.json, CLAUDE.md, .gitignore from templates
    8. Reports next steps

  Scope: authentication + access + environment only.
  Project scaffolding (Code App, Power Automate solution clone, etc.)
  is the user's choice and happens AFTER this script - typically by
  asking the agent to do it via the project's CLAUDE.md.

  Prerequisites: PowerShell 5.1+, WSL2 (installed on-demand), Chrome/Edge/Brave.

.PARAMETER ClientName
  Client name (will be the WSL distro name and may be referenced in the project).
  Alphanumeric + hyphens only. E.g. 'acme-corp', 'beta-inc'.

.EXAMPLE
  .\new-project.ps1 -ClientName acme-corp
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-zA-Z][a-zA-Z0-9-]{1,30}$')]
    [string]$ClientName,

    [string]$BaseDistro = 'Ubuntu-24.04'
)

$ErrorActionPreference = 'Stop'
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$FrameworkRoot = Split-Path -Parent $ScriptRoot
$ProjectRoot = (Get-Location).Path

function Write-Header($t) {
    $line = '=' * 70
    Write-Host ''
    Write-Host $line -ForegroundColor DarkCyan
    Write-Host "  $t" -ForegroundColor Cyan
    Write-Host $line -ForegroundColor DarkCyan
}
function Write-Info($t) { Write-Host "  $t" -ForegroundColor Gray }
function Write-Ok($t)   { Write-Host "  [OK] $t" -ForegroundColor Green }
function Write-Warn($t) { Write-Host "  [!] $t" -ForegroundColor Yellow }
function Write-Err($t)  { Write-Host "  [X] $t" -ForegroundColor Red }

function ConvertTo-WslPath([string]$winPath) {
    $drive = $winPath.Substring(0, 1).ToLower()
    $rest  = $winPath.Substring(2) -replace '\\', '/'
    return "/mnt/$drive$rest"
}

function Test-WslAvailable {
    try { $null = wsl.exe --status 2>$null; return $LASTEXITCODE -eq 0 }
    catch { return $false }
}

function Get-Distros {
    if (-not (Test-WslAvailable)) { return @() }
    $raw = & wsl.exe --list --quiet 2>$null
    if ($LASTEXITCODE -ne 0) { return @() }
    return $raw | Where-Object { $_ -and $_.Trim().Length -gt 0 } | ForEach-Object { $_.Trim() }
}

# --- Step 1: WSL2 ---

Write-Header "Setup '$ClientName' - Step 1/8: WSL2"

if (-not (Test-WslAvailable)) {
    Write-Warn 'WSL2 not installed.'
    $ok = Read-Host '  Run "wsl --install --no-launch" now? Will request UAC + reboot. (y/n)'
    if ($ok -ne 'y') { Write-Err 'Aborted.'; exit 1 }
    & wsl.exe --install --no-launch
    Write-Ok 'WSL installed. Reboot Windows and re-run this script.'
    exit 0
}
Write-Ok 'WSL2 available.'

# --- Step 2: gather info ---

Write-Header "Step 2/8: Client info"
$tenantId = Read-Host '  Tenant ID (GUID)'
$envUrl   = Read-Host '  Env URL (e.g. https://example.crm4.dynamics.com/)'
$envId    = Read-Host '  Env ID (GUID, optional - blank to skip pac auth env binding)'
$solution = Read-Host '  Solution name (optional - just stored in CLAUDE.md for reference)'

if (-not $envUrl.EndsWith('/')) { $envUrl += '/' }

Write-Info "Collected:"
Write-Info "  Tenant: $tenantId"
Write-Info "  Env:    $envUrl"
if ($envId)    { Write-Info "  EnvID:  $envId" }
if ($solution) { Write-Info "  Solution: $solution" }
$proceed = Read-Host '  Continue? (y/n)'
if ($proceed -ne 'y') { Write-Info 'Aborted.'; exit 0 }

# --- Step 3: create distro ---

Write-Header "Step 3/8: Create distro '$ClientName'"

if ((Get-Distros) -contains $ClientName) {
    Write-Warn "Distro '$ClientName' already exists. Skipping."
} else {
    if (-not ((Get-Distros) -contains $BaseDistro)) {
        Write-Info "Base distro '$BaseDistro' missing. Installing..."
        & wsl.exe --install -d $BaseDistro --no-launch
        if ($LASTEXITCODE -ne 0) { Write-Err 'Ubuntu install failed.'; exit 1 }
        Write-Ok "$BaseDistro installed. FIRST TIME:"
        Write-Info "  - Open a separate shell: wsl -d $BaseDistro"
        Write-Info '  - Create unix user + password'
        Write-Info '  - exit'
        Read-Host "  Press Enter when $BaseDistro has user created"
    }

    $tempDir = Join-Path $env:TEMP "wsl-export-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    $tarPath = Join-Path $tempDir 'ubuntu.tar'
    $distroPath = Join-Path $env:LOCALAPPDATA "WSL\$ClientName"
    New-Item -ItemType Directory -Path $distroPath -Force | Out-Null

    Write-Info "Export $BaseDistro -> tar..."
    & wsl.exe --export $BaseDistro $tarPath
    if ($LASTEXITCODE -ne 0) { Write-Err 'Export failed.'; exit 1 }

    Write-Info "Import as '$ClientName'..."
    & wsl.exe --import $ClientName $distroPath $tarPath --version 2
    if ($LASTEXITCODE -ne 0) { Write-Err 'Import failed.'; exit 1 }
    Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue

    $unixUser = Read-Host "  Unix username inside the distro (e.g. dev)"
    if ($unixUser) {
        $createUser = "id -u $unixUser >/dev/null 2>&1 || (useradd -m -s /bin/bash $unixUser && passwd -d $unixUser && usermod -aG sudo $unixUser)"
        & wsl.exe -d $ClientName -u root bash -c $createUser
        & wsl.exe -d $ClientName -u root bash -c "printf '[user]\ndefault=$unixUser\n' > /etc/wsl.conf"
        & wsl.exe --terminate $ClientName
        Write-Ok "User '$unixUser' set as default in '$ClientName'."
    }
    Write-Ok "Distro '$ClientName' ready."
}

# --- Step 4: bootstrap dev tools ---

Write-Header "Step 4/8: Bootstrap dev tools"

$setupScript = Join-Path $ScriptRoot 'distro-setup.sh'
if (-not (Test-Path $setupScript)) {
    Write-Err "Could not find $setupScript."
    exit 1
}
$wslSetup = ConvertTo-WslPath $setupScript
Write-Info "Running distro-setup.sh inside '$ClientName' (will ask for sudo password)..."
& wsl.exe -d $ClientName --cd '~' -- bash $wslSetup
if ($LASTEXITCODE -ne 0) { Write-Warn 'Setup had errors - review output.' }
Write-Ok 'Dev tools installed.'

# --- Step 5: az login ---

Write-Header "Step 5/8: az login"
Write-Info 'Will open device-code flow. Open the URL in the client Chrome profile.'
$az = "az login --use-device-code"
if ($tenantId) { $az += " --tenant $tenantId" }
& wsl.exe -d $ClientName -- bash -lc $az
if ($LASTEXITCODE -ne 0) { Write-Err 'az login failed.'; exit 1 }
Write-Ok 'az authenticated inside the distro.'

# --- Step 6: pac auth ---

Write-Header "Step 6/8: pac auth"
Write-Info 'New device-code flow. Same Chrome profile.'
$pac = "pac auth create --deviceCode"
if ($envId) { $pac += " --environment $envId" }
& wsl.exe -d $ClientName -- bash -lc $pac
if ($LASTEXITCODE -ne 0) { Write-Warn 'pac auth failed - you can retry manually later.' }
else { Write-Ok 'pac authenticated inside the distro.' }

# --- Step 7: write .mcp.json + CLAUDE.md ---

Write-Header "Step 7/8: Templates"
$templatesDir = Join-Path $FrameworkRoot 'templates'

# .mcp.json
$mcpTemplate = Join-Path $templatesDir '.mcp.json.template'
$mcpTarget   = Join-Path $ProjectRoot '.mcp.json'
if (Test-Path $mcpTemplate) {
    $content = Get-Content $mcpTemplate -Raw
    $content = $content.Replace('{{DISTRO}}', $ClientName).Replace('{{ENV_URL}}', $envUrl)
    $content | Out-File -FilePath $mcpTarget -Encoding utf8
    Write-Ok "Wrote .mcp.json"
}

# CLAUDE.md
$claudeTemplate = Join-Path $templatesDir 'CLAUDE.md.template'
$claudeTarget   = Join-Path $ProjectRoot 'CLAUDE.md'
if (Test-Path $claudeTemplate) {
    if (Test-Path $claudeTarget) {
        Write-Warn 'CLAUDE.md already exists. Skipping to avoid overwrite.'
    } else {
        $content = Get-Content $claudeTemplate -Raw
        $content = $content.Replace('{{CLIENT}}', $ClientName)
        $content = $content.Replace('{{TENANT_ID}}', $tenantId)
        $content = $content.Replace('{{ENV_URL}}', $envUrl)
        $content = $content.Replace('{{ENV_ID}}', $envId)
        $content = $content.Replace('{{SOLUTION}}', $solution)
        $content = $content.Replace('{{DISTRO}}', $ClientName)
        $content | Out-File -FilePath $claudeTarget -Encoding utf8
        Write-Ok "Wrote CLAUDE.md"
    }
}

# .gitignore
$gitignoreTemplate = Join-Path $templatesDir '.gitignore.template'
$gitignoreTarget   = Join-Path $ProjectRoot '.gitignore'
if ((Test-Path $gitignoreTemplate) -and (-not (Test-Path $gitignoreTarget))) {
    Copy-Item $gitignoreTemplate $gitignoreTarget
    Write-Ok "Wrote .gitignore"
}

# --- Step 8: report ---

Write-Header "Step 8/8: Done"
Write-Info "Environment ready at: $ProjectRoot"
Write-Info ''
Write-Info 'You now have:'
Write-Info "  - WSL distro '$ClientName' with Node, az, .NET, pac installed"
Write-Info '  - az + pac authenticated to the client tenant (inside the distro)'
Write-Info '  - .mcp.json wired to use the WSL bridge for Dataverse + Microsoft Learn HTTP'
Write-Info '  - CLAUDE.md with client info, ready for the agent to read'
Write-Info ''
Write-Info 'Next steps:'
Write-Info '  1. Open the project:'
Write-Info "       mc open $ClientName"
Write-Info '     OR plain VS Code: code ."'
Write-Info ''
Write-Info '  2. Ask the agent (or run yourself) to scaffold what you need:'
Write-Info '       - Code App: npx degit microsoft/PowerAppsCodeApps/templates/starter <subfolder>'
Write-Info '       - Power Automate: pac solution clone --name <SolutionName>'
Write-Info '       - Other: see Microsoft Learn (microsoft-learn MCP is already wired)'
Write-Info ''
Write-Ok 'Setup complete.'
