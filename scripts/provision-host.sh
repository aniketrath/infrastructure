#!/usr/bin/env bash
set -euo pipefail

# One-shot bare-metal install for ANY host defined in flake.nix's `hosts`
# attrset. Boot the target machine from the official NixOS installer ISO
# (ships with sshd on and kexec-tools preinstalled), then run this
# pointed at its IP. Generates a hardware report and installs NixOS in
# one pass.
#
# Debug mode: `DEBUG=1 ./provision-host.sh archer root@<ip>` or
# `./provision-host.sh --debug archer root@<ip>` — shell tracing (be
# aware this will echo the full nixos-anywhere command including the
# target host).
#
# ---- One-time manual steps BEFORE running this, per host: ----
#   1. Add the host to flake.nix's `hosts` attrset if it isn't there yet.
#   2. Boot the target from the NixOS installer ISO. Set a root password
#      or add your SSH key (`sudo -i` then `passwd`), then note its IP.
#   3. `ssh root@<ip> lsblk` to find the real disk device path, and put
#      it into hosts/<hostname>/disko.nix in place of REPLACE_WITH_REAL_DISK.
#   4. Generate a real hostId ONCE and put it in hosts/<hostname>/disko.nix
#      in place of REPLACE_WITH_8_HEX_CHARS:
#        head -c4 /dev/urandom | od -A none -t x4 | tr -d ' '
#      Must never change again once real data exists on the ZFS pool.
# ----------------------------------------------------------------

DEBUG="${DEBUG:-0}"
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --debug) DEBUG=1 ;;
    *) ARGS+=("$arg") ;;
  esac
done
set -- "${ARGS[@]:-}"

if [[ "$DEBUG" == "1" ]]; then
  set -x
fi

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 [--debug] <hostname> root@<live-installer-ip>" >&2
  echo "  e.g. $0 archer root@192.168.1.50" >&2
  exit 1
fi
HOST="$1"
TARGET="$2"
TARGET_IP="${TARGET#*@}"

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
LOG_DIR="$REPO_ROOT/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/provision-host-${HOST}-$(date +%Y%m%d-%H%M%S).log"

# Everything worth having on hand afterward — pulled together into one
# file at the end, so there's no scrolling back through terminal history
# to reconstruct what to do next or who to tell.
SUMMARY_FILE="$LOG_DIR/provision-host-${HOST}-SUMMARY-$(date +%Y%m%d-%H%M%S).md"

if [[ "$DEBUG" == "1" ]]; then
  echo "DEBUG mode on"
  echo "host      : $HOST"
  echo "target    : $TARGET"
  echo "repo root : $REPO_ROOT"
  echo "log file  : $LOG_FILE"
  echo "nix       : $(nix --version)"
fi

if [[ ! -f "$REPO_ROOT/hosts/${HOST}/disko.nix" ]]; then
  echo "ERROR: hosts/${HOST}/disko.nix not found — add this host to flake.nix's" >&2
  echo "       'hosts' attrset and create hosts/${HOST}/disko.nix first." >&2
  exit 1
fi

echo "==> Generating hosts/${HOST}/facter.json from ${TARGET} and installing"
nix run github:nix-community/nixos-anywhere -- \
  --flake ".#${HOST}" \
  --generate-hardware-config nixos-facter "./hosts/${HOST}/facter.json" \
  --target-host "$TARGET" 2>&1 | tee -a "$LOG_FILE"

echo "==> Install finished. Writing post-install summary to $SUMMARY_FILE"

cat > "$SUMMARY_FILE" << EOF
# Post-install checklist: ${HOST}

Installed: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Target IP at install time: ${TARGET_IP}
Full nixos-anywhere log: ${LOG_FILE}

Note: the impermanence blank snapshot (zroot/root@blank) is created
automatically on ${HOST}'s first real boot — see
modules/impermanence.nix's self-bootstrapping rollback service. No
manual snapshot step needed here anymore.

Also: modules/first-boot.nix runs once on that same first boot and
drops ~homelabadmin/first-boot-info.tar.gz + NEXT_STEPS.md on the
machine itself, with ${HOST}'s real values already filled in. SSH in
and read that first — the steps below are the same information,
available here in case you'd rather not wait for/rely on that step.

## 1. Commit the hardware report

    ls -la hosts/${HOST}/facter.json
    git add hosts/${HOST}/facter.json
    git commit -m "Add hardware report for ${HOST}"

## 2. Extend secrets trust to this machine (it can't decrypt its own
##    admin password on future rebuilds until this is done)

    ssh -p 2222 homelabadmin@${TARGET_IP} 'cat /etc/ssh/ssh_host_ed25519_key.pub' | ssh-to-age

    # paste the resulting age1... key into secrets/secrets.nix as a new
    # entry (see that file's comments), then re-encrypt from your laptop:
    ragenix -e secrets/homelab-admin-password.age

## 3. Confirm you can actually reach it going forward

    ssh -p 2222 homelabadmin@${TARGET_IP}

## 4. Commit everything from steps 1–2 together, same branch -> CI ->
##    merge flow as any other change.
EOF

echo ""
echo "==> ${HOST} should now be running the real system. Next steps:"
echo ""
cat "$SUMMARY_FILE"
