#!/usr/bin/env bash
#
# MC Framework distro setup
# Run inside a freshly-created WSL distro (one-time).
# Idempotent — safe to re-run.
#
# Installs:
#   - build-essential, curl, git, unzip
#   - Node.js LTS (NodeSource)
#   - Azure CLI
#   - .NET SDK 8
#   - pac CLI (Microsoft.PowerApps.CLI.Tool via dotnet tool)
#
set -euo pipefail

GREEN='\033[32m'
YELLOW='\033[33m'
NC='\033[0m'

info() { printf "  %s\n" "$1"; }
ok()   { printf "${GREEN}  [OK] %s${NC}\n" "$1"; }
warn() { printf "${YELLOW}  [!] %s${NC}\n" "$1"; }
header() {
  printf "\n"
  printf '%s\n' "===================================================================="
  printf "  %s\n" "$1"
  printf '%s\n' "===================================================================="
}

header "[1/6] System update"
sudo apt-get update -y
sudo apt-get upgrade -y

header "[2/6] Build tools + curl + git + unzip"
sudo apt-get install -y \
  build-essential curl git unzip ca-certificates \
  apt-transport-https lsb-release gnupg wget

header "[3/6] Node.js LTS via NodeSource"
if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
  sudo apt-get install -y nodejs
else
  info "node already installed"
fi
node --version
npm --version

header "[4/6] Azure CLI"
if ! command -v az >/dev/null 2>&1; then
  curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
else
  info "az already installed"
fi
az --version | head -1

header "[5/6] .NET SDK 8"
if ! command -v dotnet >/dev/null 2>&1; then
  source /etc/os-release
  wget -q "https://packages.microsoft.com/config/ubuntu/${VERSION_ID}/packages-microsoft-prod.deb" -O /tmp/packages-microsoft-prod.deb
  sudo dpkg -i /tmp/packages-microsoft-prod.deb
  rm /tmp/packages-microsoft-prod.deb
  sudo apt-get update -y
  sudo apt-get install -y dotnet-sdk-8.0
else
  info ".NET already installed"
fi
dotnet --version

header "[6/6] pac CLI"
# Ensure dotnet tools dir on PATH
if ! grep -q '.dotnet/tools' "$HOME/.bashrc" 2>/dev/null; then
  echo 'export PATH="$PATH:$HOME/.dotnet/tools"' >> "$HOME/.bashrc"
fi
export PATH="$PATH:$HOME/.dotnet/tools"

if ! command -v pac >/dev/null 2>&1; then
  dotnet tool install --global Microsoft.PowerApps.CLI.Tool
else
  info "pac already installed"
fi
pac --version | head -1 || warn "pac --version returned error - normal before pac auth"

header "Done"
info ""
info "Tools installed. Reload PATH:"
info "  source ~/.bashrc"
info ""
info "Next steps (from the calling script):"
info "  az login --use-device-code"
info "  pac auth create --deviceCode"
info ""
ok "distro-setup.sh complete."
