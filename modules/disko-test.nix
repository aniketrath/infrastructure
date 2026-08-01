{ lib, modulesPath, ... }:
{
  # ---------------------------------------------------------------------
  # TEST-ONLY MODULE. Layered on top of a REAL host's hosts/<hostname>/
  # disko.nix (see flake.nix's mkDiskoTest) purely to make that layout
  # buildable as a disposable QEMU image. Never touches the real deploy
  # for any host. Applies uniformly to every host in flake.nix's `hosts`
  # attrset — nothing here is specific to any one machine's name.
  #
  # Each hosts/<hostname>/disko.nix typically has placeholder values
  # (REPLACE_WITH_REAL_DISK, REPLACE_WITH_8_HEX_CHARS) until real
  # hardware exists for that host — this file's `lib.mkForce` overrides
  # let the test build run anyway, without needing fake values in the
  # real disko.nix files.
  # ---------------------------------------------------------------------

  # qemu-guest.nix pulls in virtio drivers etc. so the image boots cleanly
  # inside QEMU — real hardware doesn't need this, a live VM test does.
  imports = [ "${modulesPath}/profiles/qemu-guest.nix" ];

  # Real hardware: an actual /dev/nvme0n1 or similar, with a real fixed size.
  # Here: a virtual disk file that disko itself creates for the test image.
  disko.devices.disk.main.device = lib.mkForce "/dev/vda";
  disko.devices.disk.main.imageSize = "8G"; # only meaningful for image builds —
                                              # real disks don't need a declared size
  # Must be a real 8-hex-character value on the actual machine (see
  # hosts/<hostname>/disko.nix comments) — this dummy is only for the
  # throwaway test image and is never reused anywhere real.
  networking.hostId = lib.mkForce "deadbeef";

  # Real hardware: the @blank snapshot must exist BEFORE first boot (see
  # modules/impermanence.nix's comments — created manually during install).
  # For this disposable test image there's no separate "install" step to
  # hook into, so bootstrap it on first boot instead: if @blank doesn't
  # exist yet, create it (this IS the equivalent moment, since nothing
  # else writes to root between image build and first boot here); on
  # every boot after that, actually roll back as normal. This only
  # applies to the test image — real deploys keep requiring the manual
  # snapshot step, since a real install DOES write files before reboot.
  boot.initrd.systemd.services.zfs-rollback.script = lib.mkForce ''
    if ! zfs list -t snapshot zroot/root@blank >/dev/null 2>&1; then
      echo "TEST IMAGE: no @blank snapshot yet, creating one now (first boot only)"
      zfs snapshot zroot/root@blank
    else
      zfs rollback -r zroot/root@blank
    fi
  '';

  # No agenix/secrets wiring in any disko-test config (see flake.nix), so
  # there's no real password to log in with — this just lets `root` in
  # for anyone poking at the test image manually.
  users.users.root.initialPassword = "root";
}
