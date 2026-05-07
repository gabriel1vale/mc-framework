<#
.SYNOPSIS
  Migrate an existing Power Platform project to the MC Framework isolated model.

.DESCRIPTION
  For projects that already exist on disk (with or without auth on the Windows host).
  Does:
    1. Creates WSL distro with the client name
    2. Bootstraps dev tools inside
    3. Launches az login + pac auth (from inside the distro)
    4. Updates the project's .mcp.json to use the wsl.exe bridge
    5. Suggests the user run 'pac auth clear' on the Windows host (cleanup)

  Used when you already have a project folder and want to move only auth/dev runtime
  to WSL without touching the code.

.PARAMETER ClientName
  Client name (will be the WSL distro name).

.EXAMPLE
  .\adopt-existing.ps1 -ClientName acme-corp
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

# --- Step 0: Sanity ---

Write-Header "Adopt '$ClientName' in '$ProjectRoot'"

if (-not (Test-WslAvailable)) {
    Write-Err 'WSL2 is not available. Run first: wsl --install'
    exit 1
}

# Try to detect project config
$existingMcp = Test-Path (Join-Path $ProjectRoot '.mcp.json')
$existingClaude = Test-Path (Join-Path $ProjectRoot 'CLAUDE.md')
$existingPwrConfig = Get-ChildItem -Path $ProjectRoot -Recurse -Filter 'power.config.json' -ErrorAction SilentlyContinue | Select-Object -First 1

Write-Info "Current state:"
Write-Info "  .mcp.json: $existingMcp"
Write-Info "  CLAUDE.md: $existingClaude"
if ($existingPwrConfig) {
    Write-Info "  power.config.json: $($existingPwrConfig.FullName)"
}

# --- Step 1: gather info ---

Write-Header "Step 1/5: Client info"
$tenantId = Read-Host '  Tenant ID (GUID, optional)'
$envUrl   = Read-Host '  Env URL (e.g. https://example.crm4.dynamics.com/)'
$envId    = Read-Host '  Env ID (GUID, optional)'

if ($envUrl -and -not $envUrl.EndsWith('/')) { $envUrl += '/' }

# --- Step 2: create or reuse distro ---

Write-Header "Step 2/5: WSL distro"

if ((Get-Distros) -contains $ClientName) {
    Write-Info "Distro '$ClientName' already exists. Reusing."
} else {
    if (-not ((Get-Distros) -contains $BaseDistro)) {
        Write-Info "Base distro '$BaseDistro' missing. Installing..."
        & wsl.exe --install -d $BaseDistro --no-launch
        if ($LASTEXITCODE -ne 0) { Write-Err 'Ubuntu install failed.'; exit 1 }
        Write-Info "  - Open a separate shell: wsl -d $BaseDistro"
        Write-Info '  - Create unix user + password, then exit'
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
    }
    Write-Ok "Distro '$ClientName' created."
}

# --- Step 3: bootstrap dev tools ---

Write-Header "Step 3/5: Dev tools"

$setupScript = Join-Path $ScriptRoot 'distro-setup.sh'
$wslSetup = ConvertTo-WslPath $setupScript
& wsl.exe -d $ClientName --cd '~' -- bash $wslSetup
if ($LASTEXITCODE -ne 0) { Write-Warn 'Setup had errors.' }

# --- Step 4: auth ---

Write-Header "Step 4/5: Auth"
Write-Info 'Will open device-code flows (az + pac). Use the client Chrome profile.'

$az = "az login --use-device-code"
if ($tenantId) { $az += " --tenant $tenantId" }
& wsl.exe -d $ClientName -- bash -lc $az

$pac = "pac auth create --deviceCode"
if ($envId) { $pac += " --environment $envId" }
& wsl.exe -d $ClientName -- bash -lc $pac

# --- Step 5: update .mcp.json + suggest cleanup ---

Write-Header "Step 5/5: Update .mcp.json"

$templatesDir = Join-Path $FrameworkRoot 'templates'
$mcpTemplate = Join-Path $templatesDir '.mcp.json.template'
$mcpTarget   = Join-Path $ProjectRoot '.mcp.json'

if (Test-Path $mcpTemplate) {
    if (Test-Path $mcpTarget) {
        $backup = "$mcpTarget.backup-$(Get-Date -Format 'yyyyMMddHHmmss')"
        Copy-Item $mcpTarget $backup
        Write-Ok "Backup of existing .mcp.json at: $backup"
    }
    $content = Get-Content $mcpTemplate -Raw
    $content = $content.Replace('{{DISTRO}}', $ClientName).Replace('{{ENV_URL}}', $envUrl)
    $content | Out-File -FilePath $mcpTarget -Encoding utf8
    Write-Ok ".mcp.json updated with WSL bridge for '$ClientName'."
}

Write-Header 'Done'
Write-Info ''
Write-Info 'Recommended Windows host cleanup (optional but hygienic):'
Write-Info '  pac auth clear              # clears pac profiles on the host'
Write-Info '  az logout                   # logout from az host'
Write-Info '  az account clear            # az cache'
Write-Info ''
Write-Info 'Verify it is clean:'
Write-Info '  pac auth list               # should say "No profiles"'
Write-Info '  az account list             # should be empty'
Write-Info ''
Write-Info "From here on, use: mc open $ClientName, mc dev $ClientName, mc shell $ClientName"
Write-Ok 'Adopt complete.'
