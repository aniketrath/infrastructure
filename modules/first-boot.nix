{ config, pkgs, ... }:
{
  # ---------------------------------------------------------------------
  # Runs once, on the first real multi-user boot after a fresh install.
  # Collects what's needed to finish setup (mainly: the SSH host key, for
  # extending secrets.nix's trust list) into a tarball in homelabadmin's
  # home directory, plus a plain-language NEXT_STEPS.md, so nothing has
  # to be reconstructed from memory or scrollback after the fact.
  #
  # Gated by a marker file living directly under /persist — NOT under
  # any of impermanence's bind-mounted subdirectories, just the dataset
  # root itself, which is never touched by the rollback service. That's
  # what makes "only ever run once" actually stick across reboots.
  # ---------------------------------------------------------------------

  systemd.services.first-boot-setup = {
    description = "Collect first-boot info for finishing setup";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" "sshd.service" ];
    wants = [ "network-online.target" ];
    unitConfig.ConditionPathExists = "!/persist/.first-boot-setup-done";
    serviceConfig.Type = "oneshot";
    path = with pkgs; [ zfs iproute2 gnutar gzip ];

    script = ''
      set -euo pipefail

      OUT_DIR="$(mktemp -d)"
      HOME_DIR="/home/homelabadmin"
      HOSTNAME_VAL="$(hostname)"
      HOST_KEY="$(cat /etc/ssh/ssh_host_ed25519_key.pub)"

      # --- Collect ---
      echo "$HOSTNAME_VAL"                              > "$OUT_DIR/hostname.txt"
      ip -brief addr                                    > "$OUT_DIR/ip-addresses.txt"
      echo "$HOST_KEY"                                  > "$OUT_DIR/ssh_host_ed25519_key.pub"
      zpool status                                      > "$OUT_DIR/zpool-status.txt"       2>&1 || true
      zfs list                                          > "$OUT_DIR/zfs-datasets.txt"       2>&1 || true
      zfs list -t snapshot                              > "$OUT_DIR/zfs-snapshots.txt"      2>&1 || true
      df -h                                             > "$OUT_DIR/disk-usage.txt"

      # --- Next-steps file, in plain language, with this host's real
      #     values — built with printf/echo, not a heredoc, since a
      #     heredoc nested inside this Nix multi-line string is fragile
      #     against Nix's own indentation stripping.
      NS="$OUT_DIR/NEXT_STEPS.md"
      {
        printf '%s\n\n' "# ${HOSTNAME_VAL}: finish setup"
        printf 'Collected: %s\n\n' "$(date -u +"%Y-%m-%d %H:%M:%S UTC")"
        printf '%s\n\n' "## 1. Extend secrets trust to this machine"
        printf '%s\n\n' "Its SSH host key (also in ssh_host_ed25519_key.pub in this tarball):"
        printf '    %s\n\n' "$HOST_KEY"
        printf '%s\n\n' "On your laptop:"
        printf '    echo '"'"'%s'"'"' | ssh-to-age\n\n' "$HOST_KEY"
        printf '%s\n\n' "Paste the resulting age1... key into secrets/secrets.nix as a new entry, then re-encrypt:"
        printf '    ragenix -e secrets/homelab-admin-password.age\n\n'
        printf '%s\n\n' "## 2. Commit hosts/${HOSTNAME_VAL}/facter.json"
        printf '%s\n\n' "Already generated on your laptop by provision-host.sh — just needs committing:"
        printf '    git add hosts/%s/facter.json secrets/secrets.nix secrets/homelab-admin-password.age\n' "$HOSTNAME_VAL"
        printf '    git commit -m "Trust %s for secrets; add its hardware report"\n' "$HOSTNAME_VAL"
        printf '    git push\n\n'
        printf '%s\n' "## 3. Sanity checks (see the other files in this tarball)"
        printf '%s\n' "- zpool-status.txt   — pool should show ONLINE, no errors"
        printf '%s\n' "- zfs-datasets.txt   — should show root, nix, persist all mounted"
        printf '%s\n' "- zfs-snapshots.txt  — should show zroot/root@blank"
        printf '%s\n' "- disk-usage.txt     — general sanity check"
      } > "$NS"

      # --- Package and place where the operator will actually find it ---
      tar -czf "$HOME_DIR/first-boot-info.tar.gz" -C "$OUT_DIR" .
      cp "$NS" "$HOME_DIR/NEXT_STEPS.md"
      chown homelabadmin:users "$HOME_DIR/first-boot-info.tar.gz" "$HOME_DIR/NEXT_STEPS.md"

      rm -rf "$OUT_DIR"

      # --- Mark done, so this never runs again ---
      touch /persist/.first-boot-setup-done

      echo "First-boot info collected: $HOME_DIR/first-boot-info.tar.gz"
      echo "See also: $HOME_DIR/NEXT_STEPS.md"
    '';
  };
}
