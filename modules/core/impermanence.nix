{ config, lib, pkgs, ... }:
{
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = false;

  boot.initrd.systemd.enable = true;
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

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

  fileSystems."/persist".neededForBoot = true;

  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/var/lib"
      "/var/log"
      "/var/lib/systemd/coredump"
      "/etc/rancher/node"
      {
        directory = "/home/homelabadmin";
        user = "homelabadmin";
        group = "users";
        mode = "0700";
      }
      "/root"
    ];
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
    ];
  };

  # Ensures impermanence's ownership/mode tmpfiles rules apply to the actual
  # persisted data rather than firing before the bind mounts exist.
  systemd.services.systemd-tmpfiles-setup.unitConfig.RequiresMountsFor = [
    "/persist"
    "/home/homelabadmin"
    "/root"
  ];

  services.journald.storage = "persistent";
}