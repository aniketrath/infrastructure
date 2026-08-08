{ lib, modulesPath, ... }:
{
  # ---------------------------------------------------------------------
  # TEST-ONLY MODULE. Purpose changed from "boot-test this host's exact
  # ZFS/multi-dataset layout" to "does the disko module correctly
  # partition, format, and produce a working image at all" — we are NOT
  # trying to validate the real partition scheme here, just that disko
  # itself functions. A real host's own hosts/<hostname>/disko.nix stays
  # completely untouched; this file overrides disko.devices entirely for
  # the disposable test image only.
  #
  # Bonus: dropping ZFS from this test also sidesteps a known disko/
  # nixpkgs vmTools incompatibility with ZFS kernel modules in the
  # image-builder VM (nix-community/disko#1114) — that bug only
  # triggers when ZFS is present, so a plain ext4 layout never hits it.
  #
  # NOTE: plain assignment, not lib.mkForce — nothing else contributes to
  # disko.devices here anymore (mkDiskoTest no longer imports the real
  # host's disko.nix), so forcing the whole tree just collides with
  # disko's own internal per-partition defaults instead of cleanly
  # winning.
  # ---------------------------------------------------------------------
  imports = [ "${modulesPath}/profiles/qemu-guest.nix" ];
  disko.devices = {
    disk.main = {
      device = "/dev/vda";
      type = "disk";
      imageSize = "20G";
      content = {
        type = "gpt";
        partitions = {
          # EFI System Partition — required for the image to actually
          # boot; not the thing under test, just plumbing to get there.
          ESP = {
            size = "256M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
            };
          };
          # The ONE partition this test actually cares about: does disko
          # correctly create, format, and mount a filesystem at all.
          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
      };
    };
  };
  networking.hostId = lib.mkForce "deadbeef";
  users.users.root.initialPassword = "root";
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.consoleLogLevel = 7;
  boot.kernelParams = [ "console=ttyS0,115200n8" "console=tty1" "boot.shell_on_fail" ];
  # Throwaway keypair committed alongside this file (see
  # disko-test-ssh-key[.pub]) — trusted in ADDITION to whatever real key
  # modules/common.nix already grants homelabadmin, so scripts/test-disko.sh
  # can SSH in and run `systemctl is-system-running --wait` to verify boot,
  # both locally and in CI (which has no access to anyone's real private
  # key). Only ever unlocks this disposable, self-destructing test image —
  # never a real host.
  users.users.root.openssh.authorizedKeys.keyFiles = [
    ../../tests/fixtures/disko-test-ssh-key.pub
  ];
}
