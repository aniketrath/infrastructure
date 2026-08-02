{ config, lib, pkgs, ... }:
{
  # Real system only — the Docker test has no disks/ZFS at all.

  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = false;

  # ZFS requires a unique 8-hex-char host ID. This is set per-host, not
  # here — see hosts/<n>/disko.nix, alongside networking.hostName.

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # The "erase your darlings" pattern: roll the root dataset back to a
  # blank snapshot on every boot, before anything mounts on top of it.
  # Nothing written to `/` outside of what's explicitly persisted below
  # survives a reboot.
  #
  # Self-bootstrapping: if @blank doesn't exist yet, create it instead of
  # rolling back. This is safe specifically because it only ever matters
  # on the very first boot after a fresh nixos-anywhere install — at that
  # point root already has exactly the freshly-installed closure and
  # nothing else, so "blank" correctly means "freshly installed," not
  # "truly empty disk." No manual `zfs snapshot` step needed anymore.
  #
  # Written as a systemd-initrd service rather than the old
  # boot.initrd.postDeviceCommands hook — modern NixOS uses a
  # systemd-based initrd by default, which doesn't support that
  # script-hook style anymore.
  boot.initrd.systemd.services.zfs-rollback = {
    description = "Roll back root dataset to blank snapshot";
    wantedBy = [ "initrd.target" ];
    after = [ "zfs-import-zroot.service" ];
    before = [ "sysroot.mount" ];
    path = [ pkgs.zfs ];
    unitConfig.DefaultDependencies = "no";
    serviceConfig.Type = "oneshot";
    script = ''
      if ! zfs list -t snapshot zroot/root@blank >/dev/null 2>&1; then
        echo "First boot: no @blank snapshot yet, creating one now"
        zfs snapshot zroot/root@blank
      else
        zfs rollback -r zroot/root@blank
      fi
    '';
  };

  # Required by impermanence: files like the SSH host keys below need to
  # exist very early in boot (before sshd starts), so the filesystem
  # backing /persist must be guaranteed mounted that early. This overrides
  # the fileSystems."/persist" entry disko.nix already generates.
  fileSystems."/persist".neededForBoot = true;

  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/var/lib/docker"
      "/var/lib/nixos"
      "/var/log"
      "/var/lib/systemd/coredump"
      # add more here as real workloads land, e.g.:
      # "/var/lib/k3s"
      # "/var/lib/rancher"
    ];
    # SSH host keys specifically — regenerating these every boot would
    # mean every reboot changes the host's identity and breaks
    # known_hosts for everyone connecting to it.
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
    ];
  };
}
