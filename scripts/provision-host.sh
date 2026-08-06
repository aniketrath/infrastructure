#!/usr/bin/env bash
set -euo pipefail

# One-shot bare-metal install & post-deploy automation for ANY host defined in flake.nix
#
# Usage:
#   Install:      ./provision-host.sh archer root@192.168.1.50
#   Post-deploy:  ./provision-host.sh --post-deploy archer 192.168.1.5
#   Debug mode:   DEBUG=1 ./provision-host.sh ... or ./provision-host.sh --debug ...

# ANSI Color Definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

DEBUG="${DEBUG:-0}"
POST_DEPLOY=0
ARGS=()

for arg in "$@"; do
  case "$arg" in
    --debug) DEBUG=1 ;;
    --post-deploy) POST_DEPLOY=1 ;;
    *) ARGS+=("$arg") ;;
  esac
done
set -- "${ARGS[@]:-}"

if [[ "$DEBUG" == "1" ]]; then
  set -x
fi

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# =========================================================================
# POST-DEPLOY MODE
# =========================================================================
if [[ "$POST_DEPLOY" == "1" ]]; then
  if [[ $# -ne 2 ]]; then
    echo -e "${RED}Usage: $0 --post-deploy <hostname> <target-ip>${NC}" >&2
    echo -e "${YELLOW}  e.g. $0 --post-deploy archer 192.168.1.5${NC}" >&2
    exit 1
  fi
  HOST="$1"
  TARGET_IP="$2"

  echo -e "${BLUE}${BOLD}==> Running post-deployment automation for ${HOST} at ${TARGET_IP}...${NC}"

  # 1. Commit facter.json if it exists and is untracked/changed
  if [[ -f "hosts/${HOST}/facter.json" ]]; then
    git add "hosts/${HOST}/facter.json"
    if ! git diff --cached --quiet; then
      git commit -m "Add hardware report for ${HOST}"
      echo -e "${GREEN}==> Committed hosts/${HOST}/facter.json${NC}"
    else
      echo -e "${CYAN}==> Hardware report already committed.${NC}"
    fi
  fi

  # 2. Extract SSH host public key from the newly provisioned node
  echo -e "${BLUE}==> Fetching new host's SSH ed25519 public key...${NC}"
  SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=5"
  REMOTE_PUBKEY=""

  if REMOTE_PUBKEY=$(ssh -p 2222 $SSH_OPTS homelabadmin@$TARGET_IP 'cat /etc/ssh/ssh_host_ed25519_key.pub' 2>/dev/null); then
    PORT=2222
  elif REMOTE_PUBKEY=$(ssh -p 22 $SSH_OPTS root@$TARGET_IP 'cat /etc/ssh/ssh_host_ed25519_key.pub' 2>/dev/null); then
    PORT=22
  else
    echo -e "${RED}ERROR: Could not fetch SSH host key from ${TARGET_IP}. Is the machine up and accessible?${NC}" >&2
    exit 1
  fi

  echo -e "    Found key: ${GREEN}$REMOTE_PUBKEY${NC}"

  echo ""
  echo -e "${YELLOW}${BOLD}IMPORTANT: Ensure this SSH public key is added to your secrets/secrets.nix file under keys for ${HOST}:${NC}"
  echo -e "    ${HOST} = \"${GREEN}${REMOTE_PUBKEY}${NC}\";"
  echo ""
  read -p "$(echo -e "${BOLD}Have you updated secrets/secrets.nix with this key? (y/N) ${NC}")" -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Aborted. Update secrets/secrets.nix manually and run:${NC}"
    echo -e "    cd secrets && nix run github:ryantm/agenix -- --rekey"
    exit 1
  fi

  # 3. Rekey secrets
  echo -e "${BLUE}==> Re-keying agenix secrets...${NC}"
  (
    cd secrets
    RULES="./secrets.nix" nix run github:ryantm/agenix -- --rekey
  )

  # 4. Push final deployment switch
  echo -e "${BLUE}==> Applying final nixos-rebuild switch to ${HOST}...${NC}"
  NIX_SSHOPTS="-p ${PORT} -i ~/.ssh/id_ed25519" nix run nixpkgs#nixos-rebuild -- switch \
    --flake ".#${HOST}" \
    --target-host "homelabadmin@${TARGET_IP}" \
    --use-remote-sudo

  echo -e "${GREEN}${BOLD}==> Post-deployment complete successfully for ${HOST}!${NC}"
  exit 0
fi

# =========================================================================
# STANDARD PROVISIONING MODE (nixos-anywhere)
# =========================================================================
if [[ $# -ne 2 ]]; then
  echo -e "${RED}Usage: $0 [--debug] <hostname> root@<live-installer-ip>${NC}" >&2
  echo -e "${YELLOW}  e.g. $0 archer root@192.168.1.50${NC}" >&2
  echo -e "${YELLOW}       $0 --post-deploy archer 192.168.1.5${NC}" >&2
  exit 1
fi
HOST="$1"
TARGET="$2"
TARGET_IP="${TARGET#*@}"

LOG_DIR="$REPO_ROOT/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/provision-host-${HOST}-$(date +%Y%m%d-%H%M%S).log"
SUMMARY_FILE="$LOG_DIR/provision-host-${HOST}-SUMMARY-$(date +%Y%m%d-%H%M%S).md"

if [[ "$DEBUG" == "1" ]]; then
  echo -e "${CYAN}DEBUG mode on${NC}"
  echo -e "host      : $HOST"
  echo -e "target    : $TARGET"
  echo -e "repo root : $REPO_ROOT"
  echo -e "log file  : $LOG_FILE"
fi

if [[ ! -f "$REPO_ROOT/hosts/${HOST}/disko.nix" ]]; then
  echo -e "${RED}ERROR: hosts/${HOST}/disko.nix not found — add this host to flake.nix's${NC}" >&2
  echo -e "${RED}       'hosts' attrset and create hosts/${HOST}/disko.nix first.${NC}" >&2
  exit 1
fi

echo -e "${BLUE}${BOLD}==> Generating hosts/${HOST}/facter.json from ${TARGET} and installing...${NC}"
nix run github:nix-community/nixos-anywhere -- \
  --flake ".#${HOST}" \
  --generate-hardware-config nixos-facter "./hosts/${HOST}/facter.json" \
  --target-host "$TARGET" 2>&1 | tee -a "$LOG_FILE"

echo -e "${GREEN}==> Install finished. Generating post-install summary...${NC}"

cat > "$SUMMARY_FILE" << EOF
# Post-install checklist: ${HOST}

Installed: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Target IP at install time: ${TARGET_IP}

To finish setting up secrets trust and complete deployment automatically, run:

    ./provision-host.sh --post-deploy ${HOST} ${TARGET_IP}
EOF

echo ""
echo -e "${GREEN}${BOLD}==> ${HOST} is now running the initial system.${NC}"
echo -e "${YELLOW}==> To finish setup automatically, run:${NC}"
echo ""
echo -e "    ${BOLD}./provision-host.sh --post-deploy ${HOST} ${TARGET_IP}${NC}"
echo ""
