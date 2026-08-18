{ config, lib, pkgs, ... }:
{
  boot = {
    supportedFilesystems = [ "zfs" ];
    zfs.forceImportRoot = false;
    initrd.systemd.enable = true;
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    initrd.systemd.services.zfs-rollback = {
      description = "Roll back root dataset to blank snapshot";
      wantedBy = [ "initrd.target" ];
      after = [ "zfs-import-zroot.service" "persist.mount" ];
      requires = [ "persist.mount" ];
      before = [ "sysroot.mount" ];
      path = [ pkgs.zfs ];
      unitConfig.DefaultDependencies = "no";
      serviceConfig.Type = "oneshot";
      script = ''
        MARKER="/persist/.zfs-bootstrap-done"
        SNAP_EXISTS=0
        zfs list -t snapshot zroot/root@blank >/dev/null 2>&1 && SNAP_EXISTS=1

        if [[ ! -f "$MARKER" && "$SNAP_EXISTS" -eq 0 ]]; then
          echo "First boot: creating @blank snapshot"
          zfs snapshot zroot/root@blank
          touch "$MARKER"
        elif [[ -f "$MARKER" && "$SNAP_EXISTS" -eq 0 ]]; then
          echo "ERROR: @blank snapshot missing but bootstrap marker exists." >&2
          echo "       Refusing to auto-recreate it from current disk state." >&2
          exit 1
        else
          zfs rollback -r zroot/root@blank
        fi
      '';
    };
  };
  fileSystems."/persist".neededForBoot = true;
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/var/lib"
      "/var/log"
      "/var/lib/systemd/coredump"
      "/etc/rancher"
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
  systemd.services.systemd-tmpfiles-setup.unitConfig.RequiresMountsFor = [
    "/persist"
    "/home/homelabadmin"
    "/root"
  ];
  services.journald.storage = "persistent";
}