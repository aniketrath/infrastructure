#!/usr/bin/env bash
set -euo pipefail

# Usage: scripts/test-disko.sh [--debug] <hostname>
#
# Builds a disposable disk image using the disko module (see
# modules/disko-test.nix — a minimal single-partition layout, NOT this
# host's real partition scheme) and boots it under software-emulated
# QEMU. Purpose: prove disko itself works, not validate exact partitioning.
#
# Verifies boot success via SSH + `systemctl is-system-running --wait`,
# using the throwaway keypair committed at modules/disko-test-ssh-key —
# works identically locally and in CI. NOT a serial-console grep: QEMU's
# -serial file: output buffers and doesn't flush until the VM exits,
# which gives false negatives even on a genuinely-booted VM.
#
# Debug mode: `DEBUG=1 ./test-disko.sh archer` or
# `./test-disko.sh --debug archer` — shell tracing + full nix
# build logs.

SSH_PORT=2223  # deliberately different from test-vm.sh's 2222, so both
                # can run concurrently without colliding.
SSH_USER="homelabadmin"
BOOT_TIMEOUT=180

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

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 [--debug] <hostname>   e.g. $0 archer" >&2
  exit 1
fi
HOST="$1"

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
LOG_DIR="$REPO_ROOT/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/disko-boot-${HOST}-$(date +%Y%m%d-%H%M%S).log"
TEST_KEY="$REPO_ROOT/modules/disko-test-ssh-key"
chmod 600 "$TEST_KEY" 2>/dev/null || true  # git doesn't preserve this bit

if [[ "$DEBUG" == "1" ]]; then
  echo "DEBUG mode on"
  echo "host      : $HOST"
  echo "repo root : $REPO_ROOT"
  echo "log file  : $LOG_FILE"
  echo "nix       : $(nix --version)"
fi

echo "==> Building .#${HOST}-disko-image"
nix build ".#${HOST}-disko-image" "${NIX_FLAGS[@]}"

IMG="result/main.raw"
if [[ ! -f "$IMG" ]]; then
  echo "ERROR: expected image at $IMG — check result/ for the actual output name" >&2
  exit 1
fi

# Nix store outputs are read-only (0444); QEMU needs a writable disk to
# actually boot a real OS (journal, systemd state, etc.), so copy it to
# scratch first. Placed inside REPO_ROOT rather than /tmp, since /tmp
# may be a small tmpfs mount too small for a multi-GB image.
SCRATCH_IMG="$(mktemp --tmpdir="$REPO_ROOT" --suffix=.raw)"
trap 'kill "${QEMU_PID:-}" 2>/dev/null; rm -f "$SCRATCH_IMG"' EXIT
cp -f "$IMG" "$SCRATCH_IMG"
chmod +w "$SCRATCH_IMG"

echo "==> Booting ${HOST} under QEMU (TCG software emulation, background)"
# OVMF.fd, not OVMF_CODE.fd — the latter is the split pflash-only
# variant and fails to load via -bios ("could not load PC BIOS").
OVMF_CODE="$(nix build --no-link --print-out-paths nixpkgs#OVMF.fd)/FV/OVMF.fd"

qemu-system-x86_64 \
  -machine q35,accel=tcg \
  -m 2048 \
  -bios "$OVMF_CODE" \
  -drive file="$SCRATCH_IMG",if=virtio,format=raw \
  -netdev "user,id=n0,hostfwd=tcp::${SSH_PORT}-:2222" -device virtio-net-pci,netdev=n0 \
  -display none \
  >>"$LOG_FILE" 2>&1 &
QEMU_PID=$!
echo "QEMU started (pid $QEMU_PID)"

echo "==> Verifying boot via SSH (systemctl is-system-running --wait)"
SSH_READY=0
ATTEMPTS=$(( BOOT_TIMEOUT / 5 ))
for attempt in $(seq 1 "$ATTEMPTS"); do
  if ssh -p "$SSH_PORT" -i "$TEST_KEY" \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=5 -o BatchMode=yes \
    "${SSH_USER}@localhost" 'systemctl is-system-running --wait' 2>/dev/null; then
    SSH_READY=1
    break
  fi
  echo "   ... attempt ${attempt}/${ATTEMPTS}, not up yet, retrying"
  sleep 5
done

if [[ "$SSH_READY" == "1" ]]; then
  echo "OK: ${HOST}'s disko module produced a bootable, fully-running image"
else
  echo "ERROR: ${HOST} never reached a running state via SSH after ${BOOT_TIMEOUT}s — see $LOG_FILE" >&2
  exit 1
fi