### Added
... (existing bullets unchanged) ...
- `hosts/template/` — scaffold to copy when adding a new host.
- `scripts/test-suite.sh` — runs every local check in roughly CI order
  (flake check, `flake.lock` committed, `hostNames` resolves, per-host
  eval, per-host disko-image eval, then both VM boots), with
  `--debug` and `--skip-boot` flags for faster iteration.
- `modules/disko-test-ssh-key[.pub]` — throwaway keypair, committed
  intentionally (unlocks nothing but the disposable disko-test image),
  so `scripts/test-disko.sh` can verify boot success over SSH the same
  way locally and in CI, with no shared secret required.

### Fixed
... (existing bullets unchanged) ...
- `hosts/archer/disko.nix`'s `networking.hostId` was still the literal
  `REPLACE_WITH_8_HEX_CHARS` placeholder, failing NixOS's hostId
  assertion and breaking eval for the real host entirely.
- `mkDiskoTest` (`flake.nix`) no longer imports a host's real
  `hosts/<hostname>/disko.nix` at all — it previously did, which
  collided with `disko-test.nix`'s own partition definitions
  (`disko.devices.disk.main.content.partitions.ESP.content.mountpoint`
  defined twice) once `disko-test.nix` moved to overriding the whole
  `disko.devices` tree.
- `modules/disko-test.nix`'s `disko.devices` override changed from
  `lib.mkForce` on the whole tree to a plain assignment — now that
  nothing else contributes to `disko.devices` for this config, forcing
  the whole tree collided with disko's own internal per-partition
  defaults instead of cleanly winning.
- `modules/vm-test.nix` and `modules/disko-test.nix` were missing a
  root filesystem/bootloader declaration, failing `nix flake check`'s
  `system.build.toplevel` assertions (`fileSystems` doesn't specify
  root; no `boot.loader.grub.devices`) even though the VM-only build
  paths they're actually used for don't need either.
- `scripts/test-disko.sh` pointed OVMF at `OVMF_CODE.fd` (the
  pflash-only split firmware variant, invalid with `-bios`) instead of
  `OVMF.fd` — QEMU failed immediately with "could not load PC BIOS".
- `scripts/test-disko.sh` booted the Nix store output directly
  (read-only, `0444`) instead of a writable copy — QEMU failed to open
  the drive for write. Now copies to a scratch file inside the repo
  (not `/tmp`, which may be a small tmpfs) before booting.
- `scripts/test-disko.sh`'s pass/fail check replaced entirely: it used
  to `grep` a `-serial file:...` log for "Reached target Multi-User
  System", but QEMU buffers that output and doesn't flush it until the
  VM exits — a genuinely-booted VM could still fail the check. Now
  verifies via SSH (`systemctl is-system-running --wait`), which is
  both more reliable and actually exercises the SSH path a real host
  would use.
- `scripts/deployment_local.sh`, `scripts/provision_host.sh`, and
  `scripts/testingmodule_disko.sh` renamed to `test-vm.sh`,
  `provision-host.sh`, and split into `test-disko.sh` + `test-suite.sh`
  respectively, for consistent naming; `.gitlab-ci.yml` updated to
  install `nixpkgs#openssh` alongside `qemu`/`jq` so the SSH-based
  disko boot check works on CI runners too.