#!/usr/bin/env bash
set -euo pipefail

# Local dev loop: builds the vm-test config, boots it under QEMU, and
# prints the SSH command to hop in and poke around.
# Requires QEMU installed locally (the generated VM script execs
# qemu-system-* itself — this script doesn't invoke qemu directly).
# Not host-specific — vm-test is a single shared config, not per-host.
#
# Debug mode: `DEBUG=1 ./test-vm.sh` or `./test-vm.sh --debug`
# (flag can appear anywhere) — turns on shell tracing and full nix build logs.

SSH_PORT=2222       # matches modules/common.nix's services.openssh.ports
SSH_USER="homelabadmin"

DEBUG="${DEBUG:-0}"
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --debug) DEBUG=1 ;;
    *) ARGS+=("$arg") ;;
  esac
done
set -- "${ARGS[@]:-}"

NIX_FLAGS=()
if [[ "$DEBUG" == "1" ]]; then
  set -x
  NIX_FLAGS+=(-L --print-build-logs)
fi

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
LOG_DIR="$REPO_ROOT/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/test-vm-$(date +%Y%m%d-%H%M%S).log"

if [[ -t 1 ]]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'
  BLUE=$'\033[0;34m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; BLUE=""; BOLD=""; RESET=""
fi

_ts() { date +"%H:%M:%S"; }
log_info()    { echo "${BLUE}[$(_ts)] ==>${RESET} $*"       | tee -a "$LOG_FILE"; }
log_success() { echo "${GREEN}[$(_ts)] OK  ${RESET} $*"     | tee -a "$LOG_FILE"; }
log_warn()    { echo "${YELLOW}[$(_ts)] WARN${RESET} $*"    | tee -a "$LOG_FILE"; }
log_error()   { echo "${RED}[$(_ts)] ERROR${RESET} $*" >&2  | tee -a "$LOG_FILE" >&2; }

trap 'log_error "Failed at line $LINENO. See $LOG_FILE for the full run."' ERR

if [[ "$DEBUG" == "1" ]]; then
  log_info "DEBUG mode on"
  log_info "repo root : $REPO_ROOT"
  log_info "log file  : $LOG_FILE"
  log_info "nix       : $(nix --version)"
fi

log_info "Building .#vm-test (this can take a while on first build)"
if nix build .#vm-test "${NIX_FLAGS[@]}" 2>&1 | tee -a "$LOG_FILE"; then
  log_success "Build finished"
else
  log_error "Build failed"
  exit 1
fi

VM_SCRIPT=$(find result/bin -maxdepth 1 -name 'run-*-vm' | head -n1)
if [[ ! -x "$VM_SCRIPT" ]]; then
  log_error "No VM runner script found in result/bin/"
  exit 1
fi
log_success "Found: $VM_SCRIPT"

log_info "Booting VM headlessly, forwarding host:${SSH_PORT} -> guest:${SSH_PORT}"
QEMU_NET_OPTS="hostfwd=tcp::${SSH_PORT}-:${SSH_PORT}" "$VM_SCRIPT" >>"$LOG_FILE" 2>&1 &
VM_PID=$!
log_success "VM started (pid $VM_PID)"

log_info "Waiting for sshd to come up..."
sleep 10

echo ""
echo "${BOLD}${GREEN}Ready. Connect with:${RESET}"
echo ""
echo "  ${BOLD}ssh -p ${SSH_PORT} ${SSH_USER}@localhost${RESET}"
echo ""
echo "Stop it afterward with:"
echo ""
echo "  kill ${VM_PID}"
echo ""
echo "Full run log: $LOG_FILE"
