<#
.SYNOPSIS
  MC Framework CLI: management of multi-client Power Platform projects with WSL isolation.

.DESCRIPTION
  Single front-end to create, open, operate, and destroy client projects that use
  MC Framework. Each client has its own dedicated WSL2 distro where auth tokens,
  dev tools, and MCP server processes live.

.EXAMPLE
  mc new acme-corp
  mc open acme-corp
  mc dev acme-corp
  mc deploy acme-corp
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
    # Resolve project = current working dir (assumed)
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
    Write-Info 'Ctrl+C to stop.'
    & wsl.exe -d $ClientName --cd $wslPath -- bash -lc 'npm install --no-audit --no-fund && npm run dev'
}

function Invoke-Deploy {
    param([string]$ClientName)
    if (-not $ClientName) { Write-Err 'Usage: mc deploy <client-name>'; exit 1 }
    Assert-Distro $ClientName
    Write-Header "DEPLOY '$ClientName'"
    Write-Info 'Follows PROTOCOLS.md DEPLOY:'
    Write-Info '  1. tsc --noEmit'
    Write-Info '  2. npm run build'
    Write-Info '  3. explicit y/n confirmation'
    Write-Info '  4. pac code push --solutionName <Solution>'
    Write-Info ''
    Write-Warn 'This command requires Solution name. Recommended: ask Claude to execute the protocol.'
    Write-Info 'Or set $env:PP_SOLUTION and re-run.'
    if (-not $env:PP_SOLUTION) {
        Write-Err 'No PP_SOLUTION defined. Aborting.'
        exit 1
    }
    $projectPath = Get-ProjectPath
    $wslPath = ConvertTo-WslPath $projectPath
    Write-Info "Pre-validation..."
    & wsl.exe -d $ClientName --cd $wslPath -- bash -lc 'npx tsc -b --noEmit'
    if ($LASTEXITCODE -ne 0) { Write-Err 'tsc failed.'; exit 1 }
    & wsl.exe -d $ClientName --cd $wslPath -- bash -lc 'npm run build'
    if ($LASTEXITCODE -ne 0) { Write-Err 'build failed.'; exit 1 }
    Write-Ok 'Pre-validation passed.'
    $confirm = Read-Host "  Push to solution '$env:PP_SOLUTION'? (y/n)"
    if ($confirm -ne 'y') { Write-Info 'Cancelled.'; return }
    & wsl.exe -d $ClientName --cd $wslPath -- bash -lc "pac code push --solutionName $env:PP_SOLUTION"
    if ($LASTEXITCODE -eq 0) { Write-Ok 'Deploy complete.' } else { Write-Err 'Push failed.' }
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

  Commands:
    mc new <client>              Full setup (distro + tools + auth + scaffold)
    mc adopt <client>            Migrate existing project to isolated model
    mc open <client>             Open VS Code Remote-WSL in current directory
    mc shell <client>            Interactive shell in the distro
    mc dev <client>              npm run dev inside the distro
    mc deploy <client>           DEPLOY protocol (requires PP_SOLUTION env var)
    mc auth status <client>      Authentication state inside the distro
    mc logout <client>           pac auth clear + az logout inside the distro
    mc destroy <client>          wsl --unregister (destructive)
    mc list                      List existing distros
    mc help                      This message

  The 'open', 'dev', 'shell' commands use the current directory as the project.

  More info: mc-framework/AGENTS.md, mc-framework/PROTOCOLS.md.

'@ -ForegroundColor Gray
}

# --- Dispatcher ---

switch ($Command.ToLower()) {
    'new'     { Invoke-New     $Rest[0] }
    'adopt'   { Invoke-Adopt   $Rest[0] }
    'open'    { Invoke-Open    $Rest[0] }
    'shell'   { Invoke-Shell   $Rest[0] }
    'dev'     { Invoke-Dev     $Rest[0] }
    'deploy'  { Invoke-Deploy  $Rest[0] }
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
