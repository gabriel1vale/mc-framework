<#
.SYNOPSIS
  MC Framework CLI: per-client WSL isolation for Power Platform consultants.

.DESCRIPTION
  Single front-end to create, open, and manage WSL distros that hold per-client
  authentication and dev tools. The framework's scope is strictly authentication,
  access, and environment provisioning - it does NOT prescribe development
  workflows (deploy, build, test, etc.). For those, the agent consults
  Microsoft Learn (via MCP), Microsoft samples and skills repos, or relies on
  general knowledge.

.EXAMPLE
  mc new acme-corp
  mc open acme-corp
  mc shell acme-corp
  mc logout acme-corp
  mc destroy acme-corp

.NOTES
  Prerequisites: Windows 10/11, WSL2 (installed on-demand), git.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command = '',

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$Rest = @()
)

$ErrorActionPreference = 'Stop'
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Color helpers (ASCII-only for PowerShell 5.1 compat)
function Write-Header($text) {
    $line = '=' * 70
    Write-Host ''
    Write-Host $line -ForegroundColor DarkCyan
    Write-Host "  $text" -ForegroundColor Cyan
    Write-Host $line -ForegroundColor DarkCyan
}
function Write-Info($t) { Write-Host "  $t" -ForegroundColor Gray }
function Write-Ok($t)   { Write-Host "  [OK] $t" -ForegroundColor Green }
function Write-Warn($t) { Write-Host "  [!] $t" -ForegroundColor Yellow }
function Write-Err($t)  { Write-Host "  [X] $t" -ForegroundColor Red }

# --- Utilities ---

function Test-WslAvailable {
    try {
        $null = wsl.exe --status 2>$null
        return $LASTEXITCODE -eq 0
    } catch { return $false }
}

function Get-Distros {
    if (-not (Test-WslAvailable)) { return @() }
    $raw = & wsl.exe --list --quiet 2>$null
    if ($LASTEXITCODE -ne 0) { return @() }
    return $raw | Where-Object { $_ -and $_.Trim().Length -gt 0 } | ForEach-Object { $_.Trim() }
}

function Test-DistroExists($name) {
    return (Get-Distros) -contains $name
}

function Assert-Distro($name) {
    if (-not (Test-DistroExists $name)) {
        Write-Err "Distro '$name' does not exist. Create with: mc new $name"
        exit 1
    }
}

function ConvertTo-WslPath([string]$winPath) {
    $drive = $winPath.Substring(0, 1).ToLower()
    $rest  = $winPath.Substring(2) -replace '\\', '/'
    return "/mnt/$drive$rest"
}

function Get-ProjectPath {
    return (Get-Location).Path
}

# --- Commands ---

function Invoke-New {
    param([string]$ClientName)
    if (-not $ClientName) {
        Write-Err 'Usage: mc new <client-name>'
        exit 1
    }
    & "$ScriptRoot\new-project.ps1" -ClientName $ClientName
}

function Invoke-Adopt {
    param([string]$ClientName)
    if (-not $ClientName) {
        Write-Err 'Usage: mc adopt <client-name>'
        exit 1
    }
    & "$ScriptRoot\adopt-existing.ps1" -ClientName $ClientName
}

function Invoke-Open {
    param([string]$ClientName)
    if (-not $ClientName) { Write-Err 'Usage: mc open <client-name>'; exit 1 }
    Assert-Distro $ClientName
    $projectPath = Get-ProjectPath
    $wslPath = ConvertTo-WslPath $projectPath
    Write-Info "Opening VS Code via Remote-WSL in the project..."
    & wsl.exe -d $ClientName --cd $wslPath -- bash -lc 'code .'
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "code-cli not found inside the distro. Install VS Code Remote-WSL extension."
    }
}

function Invoke-Shell {
    param([string]$ClientName)
    if (-not $ClientName) { Write-Err 'Usage: mc shell <client-name>'; exit 1 }
    Assert-Distro $ClientName
    $projectPath = Get-ProjectPath
    $wslPath = ConvertTo-WslPath $projectPath
    Write-Info "Shell in '$ClientName' (cd $wslPath). Type 'exit' to return."
    & wsl.exe -d $ClientName --cd $wslPath
}

function Invoke-Dev {
    param([string]$ClientName)
    if (-not $ClientName) { Write-Err 'Usage: mc dev <client-name>'; exit 1 }
    Assert-Distro $ClientName
    $projectPath = Get-ProjectPath
    $wslPath = ConvertTo-WslPath $projectPath
    Write-Header "npm run dev in '$ClientName'"
    Write-Info "cwd: $wslPath"
    Write-Info 'Ctrl+C to stop. (No-op if the project has no npm/dev script.)'
    & wsl.exe -d $ClientName --cd $wslPath -- bash -lc 'npm install --no-audit --no-fund && npm run dev'
}

function Invoke-AuthStatus {
    param([string]$ClientName)
    if (-not $ClientName) { Write-Err 'Usage: mc auth status <client-name>'; exit 1 }
    Assert-Distro $ClientName
    Write-Header "Auth status '$ClientName'"
    & wsl.exe -d $ClientName -- bash -lc 'echo "--- pac auth ---"; pac auth list 2>&1 | head -10; echo; echo "--- az account ---"; az account show 2>&1 | head -10'
}

function Invoke-Logout {
    param([string]$ClientName)
    if (-not $ClientName) { Write-Err 'Usage: mc logout <client-name>'; exit 1 }
    Assert-Distro $ClientName
    Write-Header "Logout '$ClientName'"
    & wsl.exe -d $ClientName -- bash -lc 'pac auth clear 2>&1; az logout 2>&1; az account clear 2>&1; echo "Done."'
    Write-Ok 'Tokens cleared inside the distro.'
}

function Invoke-Destroy {
    param([string]$ClientName)
    if (-not $ClientName) { Write-Err 'Usage: mc destroy <client-name>'; exit 1 }
    Assert-Distro $ClientName
    Write-Header "DESTROY '$ClientName'"
    Write-Warn 'IRREVERSIBLE OPERATION - deletes the entire distro and everything inside.'
    $confirm = Read-Host "  Type '$ClientName' to confirm"
    if ($confirm -ne $ClientName) { Write-Info 'Cancelled.'; return }
    & wsl.exe --unregister $ClientName
    if ($LASTEXITCODE -eq 0) { Write-Ok 'Distro deleted.' } else { Write-Err 'Failed.' }
}

function Invoke-List {
    Write-Header 'MC Framework distros'
    if (-not (Test-WslAvailable)) {
        Write-Warn 'WSL not installed.'
        return
    }
    $distros = Get-Distros
    if ($distros.Count -eq 0) {
        Write-Warn 'No WSL distros.'
        return
    }
    foreach ($d in $distros) {
        Write-Host "  - $d" -ForegroundColor Gray
    }
}

function Show-Help {
    Write-Host @'

  mc - MC Framework CLI

  Authentication, access, and environment provisioning for multi-client
  Power Platform consulting on personal hardware. Development workflows
  (deploy, build, test) are NOT in scope - use Microsoft Learn (via MCP),
  Microsoft samples, or general knowledge for those.

  Commands:
    mc new <client>              Create distro + install tools + authenticate + write templates
    mc adopt <client>            Migrate existing project to isolated WSL model
    mc open <client>             Open VS Code Remote-WSL in current directory
    mc shell <client>            Interactive shell in the distro
    mc dev <client>              Convenience: npm install && npm run dev inside the distro
    mc auth status <client>      Authentication state inside the distro
    mc logout <client>           pac auth clear + az logout inside the distro
    mc destroy <client>          wsl --unregister (destructive)
    mc list                      List existing distros
    mc help                      This message

  The 'open', 'shell', 'dev' commands operate on the current directory as the project.

  More info: mc-framework/AGENTS.md.

'@ -ForegroundColor Gray
}

# --- Dispatcher ---

switch ($Command.ToLower()) {
    'new'     { Invoke-New     $Rest[0] }
    'adopt'   { Invoke-Adopt   $Rest[0] }
    'open'    { Invoke-Open    $Rest[0] }
    'shell'   { Invoke-Shell   $Rest[0] }
    'dev'     { Invoke-Dev     $Rest[0] }
    'auth'    {
        if ($Rest[0] -eq 'status') { Invoke-AuthStatus $Rest[1] }
        else { Write-Err 'Usage: mc auth status <client>' }
    }
    'logout'  { Invoke-Logout  $Rest[0] }
    'destroy' { Invoke-Destroy $Rest[0] }
    'list'    { Invoke-List }
    'help'    { Show-Help }
    ''        { Show-Help }
    default   {
        Write-Err "Unknown command: $Command"
        Show-Help
        exit 1
    }
}
