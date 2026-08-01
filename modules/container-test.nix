{ lib, ... }:
{
  # This is what makes the config buildable/runnable as an OCI container
  # instead of requiring a disk + bootloader. Only reachable via
  # `homelab-docker-test` in flake.nix — the real `nixosConfigurations.homelab`
  # never imports this file, so none of this reaches actual hardware.
  boot.isContainer = true;
  boot.loader.grub.enable = lib.mkForce false;
  boot.loader.systemd-boot.enable = lib.mkForce false;
  networking.useDHCP = lib.mkForce false;
  systemd.network.enable = lib.mkForce false;
  # No real disks to schedule fstrim against inside a container
  services.fstrim.enable = lib.mkForce false;
}
