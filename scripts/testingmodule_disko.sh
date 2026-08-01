#!/usr/bin/env bash
set -euo pipefail

# Usage: scripts/test-disko-boot.sh <hostname>
#
# Builds that host's REAL disk layout (hosts/<hostname>/disko.nix, ZFS,
# impermanence — via nixosConfigurations.<hostname>-disko-test in
# flake.nix) as a disposable disk image, then boots it under
# software-emulated QEMU (no /dev/kvm required, so this also works on
# plain shared CI runners — just slower than hardware-accelerated
# virtualization).
#
# Pass/fail is decided by grepping the serial console log for evidence
# the system actually reached a normal multi-user boot, not just that
# `nix build` succeeded (a successful build says nothing about whether
# the disk actually partitions/mounts/boots correctly).

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <hostname>   e.g. $0 archer" >&2
  exit 1
fi
HOST="$1"

BOOT_TIMEOUT=180   # seconds — generous, since TCG (software) emulation is slow
LOG_FILE="logs/disko-boot-${HOST}-$(date +%Y%m%d-%H%M%S).log"
mkdir -p logs

echo "==> Building .#${HOST}-disko-image"
nix build ".#${HOST}-disko-image"

IMG="result/main.raw"
if [[ ! -f "$IMG" ]]; then
  echo "ERROR: expected image at $IMG — check result/ for the actual output name" >&2
  exit 1
fi

echo "==> Booting ${HOST} under QEMU (TCG software emulation, headless)"
# The disk layout has an EFI System Partition + systemd-boot, so we need
# UEFI firmware (OVMF) rather than QEMU's default legacy BIOS.
OVMF_CODE="$(nix build --no-link --print-out-paths nixpkgs#OVMF.fd)/FV/OVMF_CODE.fd"

timeout "$BOOT_TIMEOUT" qemu-system-x86_64 \
  -machine q35,accel=tcg \
  -m 2048 \
  -bios "$OVMF_CODE" \
  -drive file="$IMG",if=virtio,format=raw \
  -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
  -nographic \
  -serial file:"$LOG_FILE" || true
  # `|| true`: qemu may exit non-zero on timeout/forced shutdown — we
  # decide pass/fail ourselves below by reading its console output,
  # not by trusting qemu's own exit code.

if grep -q "Reached target Multi-User System" "$LOG_FILE"; then
  echo "OK: ${HOST} booted to multi-user target"
else
  echo "ERROR: ${HOST} never reached multi-user target — see $LOG_FILE" >&2
  exit 1
fi
