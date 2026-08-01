#!/usr/bin/env bash
set -euo pipefail

# Local dev loop: builds the vm-test config, boots it under QEMU, and
# prints the SSH command to hop in and poke around. Run from the repo root.
# Requires QEMU installed locally (the generated VM script execs
# qemu-system-* itself — this script doesn't invoke qemu directly).
# Not host-specific — vm-test is a single shared config, not per-host.

SSH_PORT=2222       # matches modules/common.nix's services.openssh.ports
SSH_USER="homelabadmin"

mkdir -p logs
LOG_FILE="logs/test-local-$(date +%Y%m%d-%H%M%S).log"

# Skip ANSI colors when output isn't going to an interactive terminal
# (e.g. redirected to a file) — avoids garbled escape codes in logs.
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

# Print a clear pointer to the log file if anything fails partway through.
trap 'log_error "Failed at line $LINENO. See $LOG_FILE for the full run."' ERR

log_info "Building .#vm-test (this can take a while on first build)"
if nix build .#vm-test 2>&1 | tee -a "$LOG_FILE"; then
  log_success "Build finished"
else
  log_error "Build failed"
  exit 1
fi

# nixpkgs names the generated VM runner script "run-<hostName>-vm" —
# modules/vm-test.nix sets networking.hostName = "vm-test", hence this path.
VM_SCRIPT=$(find result/bin -maxdepth 1 -name 'run-*-vm' | head -n1)
if [[ -z "$VM_SCRIPT" || ! -x "$VM_SCRIPT" ]]; then
  log_error "No VM runner script found in result/bin/"
  exit 1
fi
log_success "Found: $VM_SCRIPT"

log_info "Booting VM headlessly, forwarding host:${SSH_PORT} -> guest:${SSH_PORT}"
# QEMU_NET_OPTS is read by the generated VM script itself and appended to
# its `-netdev user,...` line — this is how we get SSH into the guest
# without any custom QEMU invocation of our own.
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
