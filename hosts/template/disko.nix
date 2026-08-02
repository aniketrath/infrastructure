# The disk layout itself — this is what disko reads to partition/format,
# and what nixos-anywhere hands off to during a fresh remote install.
# Single disk: EFI boot partition + one ZFS pool holding everything else.
{
  networking.hostName = "REPLACE_WITH_HOST_NAME";

  # Unique per host — generate with:
  #   head -c4 /dev/urandom | od -A none -t x4 | tr -d ' '
  # Must stay stable for this machine forever once set — changing it
  # after data exists on the pool can make ZFS refuse to import it.
  networking.hostId = "REPLACE_WITH_8_HEX_CHARS";

  disko.devices = {
    disk.main = {
      # REPLACE with the real device path once hardware exists, e.g.
      # /dev/nvme0n1 or /dev/sda — check with `lsblk` on the target first.
      device = "/dev/REPLACE_WITH_REAL_DISK";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
            };
          };

          zfs = {
            size = "100%";
            content = {
              type = "zfs";
              pool = "zroot";
            };
          };
        };
      };
    };

    zpool.zroot = {
      type = "zpool";

      # ZFS handles its own redundancy differently than partitioning —
      # single disk here, nothing to mirror against yet.
      options = {
        ashift = "12";
      };
      rootFsOptions = {
        compression = "zstd";
        "com.sun:auto-snapshot" = "false";
      };

      datasets = {
        # Rolled back to a blank snapshot every boot (see
        # modules/impermanence.nix) — anything not explicitly persisted
        # is gone on reboot.
        root = {
          type = "zfs_fs";
          mountpoint = "/";
          options.mountpoint = "legacy";
        };

        # The Nix store — deliberately NOT rolled back. Wiping this every
        # boot would mean re-fetching/rebuilding the entire system closure
        # on every single reboot.
        nix = {
          type = "zfs_fs";
          mountpoint = "/nix";
          options.mountpoint = "legacy";
        };

        # Explicit persistent storage — impermanence bind-mounts specific
        # paths from here back into the (otherwise ephemeral) root.
        persist = {
          type = "zfs_fs";
          mountpoint = "/persist";
          options.mountpoint = "legacy";
        };
      };
    };
  };
}
