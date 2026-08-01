#!/usr/bin/env bash
set -euo pipefail

# One-shot bare-metal install for ANY host defined in flake.nix's `hosts`
# attrset. Boot the target machine from the official NixOS installer ISO
# (ships with sshd on and kexec-tools preinstalled — no custom image
# needed), then run this pointed at its IP. It generates a hardware
# report and installs NixOS in one pass.
#
# Re-run this same script any time that host's hardware changes (new
# disk, new NIC, etc.) to refresh hosts/<hostname>/facter.json — that's
# the whole point of using nixos-facter instead of a hand-maintained
# hardware-configuration.nix.
#
# ---- One-time manual steps BEFORE running this, per host: ----
#   1. Add the host to flake.nix's `hosts` attrset if it isn't there yet.
#   2. Boot the target from the NixOS installer ISO. Set a root password
#      or add your SSH key (`sudo -i` then `passwd`), then note its IP
#      (shown on the installer's login screen / `ip a`).
#   3. `ssh root@<ip> lsblk` to find the real disk device path (e.g.
#      /dev/nvme0n1), and put it into hosts/<hostname>/disko.nix in
#      place of REPLACE_WITH_REAL_DISK.
#   4. Generate a real hostId ONCE for this machine and put it in
#      hosts/<hostname>/disko.nix in place of REPLACE_WITH_8_HEX_CHARS:
#        head -c4 /dev/urandom | od -A none -t x4 | tr -d ' '
#      This must never change again once real data exists on the ZFS
#      pool — changing it later can make ZFS refuse to import the pool.
# ----------------------------------------------------------------

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <hostname> root@<live-installer-ip>" >&2
  echo "  e.g. $0 archer root@192.168.1.50" >&2
  exit 1
fi
HOST="$1"
TARGET="$2"

if [[ ! -f "hosts/${HOST}/disko.nix" ]]; then
  echo "ERROR: hosts/${HOST}/disko.nix not found — add this host to flake.nix's" >&2
  echo "       'hosts' attrset and create hosts/${HOST}/disko.nix first." >&2
  exit 1
fi

echo "==> Generating hosts/${HOST}/facter.json from ${TARGET} and installing"
# --generate-hardware-config nixos-facter <path>:
#   SSHes into $TARGET, runs the nixos-facter tool there to produce a
#   hardware report, and writes it to the given local path.
# nixos-anywhere then kexecs the target into a NixOS installer kernel
# over the network, runs disko against hosts/<hostname>/disko.nix to
# partition/format, installs that host's closure, and reboots into it —
# all automatically, no further manual steps.
nix run github:nix-community/nixos-anywhere -- \
  --flake ".#${HOST}" \
  --generate-hardware-config nixos-facter "./hosts/${HOST}/facter.json" \
  --target-host "$TARGET"

echo "==> Done. ${HOST} should reboot into the real system."
echo "    Once it's up, get its age public key so secrets/secrets.nix"
echo "    can be re-encrypted for it (see secrets/secrets.nix comments):"
echo "      ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub   # run ON the machine"
