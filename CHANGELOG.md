# Changelog

## Unreleased — migration off Docker-based testing

### Removed
- `nixos-generators`-based Docker image testing (`homelab-docker-test`)
  and its Dockerfile-adjacent test scripts. The upstream project is now
  archived, and its Docker format was never migrated to nixpkgs' native
  `nixos-rebuild build-image` — no supported path forward for it.

### Added
- **`disko`** — declarative disk partitioning/ZFS layout, per host
  (`hosts/<name>/disko.nix`), replacing manual `fdisk`/`mkfs`.
- **`impermanence`** — ephemeral root pattern: ZFS dataset rolled back to
  a blank snapshot on every boot, with explicit persisted paths (SSH
  host keys, Docker state, logs) surviving via bind mounts.
- **`nixos-facter`** — generates each host's hardware report by scanning
  the real machine, replacing hand-written `hardware-configuration.nix`.
- **`nixos-anywhere`**-based provisioning (`scripts/provision_host.sh`) —
  one-shot remote install (kexec + disko + facter + closure install) from
  a stock NixOS installer ISO, no custom image needed.
- **VM-based local/CI testing**, replacing Docker:
  - `modules/vm-test.nix` + `scripts/deployment_local.sh` — fast general
    config smoke test via `nixos-rebuild build-vm`'s native machinery.
  - `modules/disko-test.nix` + `scripts/testingmodule_disko.sh` — builds
    and boot-tests each host's REAL disk layout as a disposable image
    under software-emulated QEMU (no `/dev/kvm` needed, so it also runs
    on shared CI runners).
- **`flake.nix` restructured** around a single `hosts = { ... }` attrset.
  Adding a machine is one entry (plus its `hosts/<name>/disko.nix`); the
  real `nixosConfigurations.<name>`, its disposable `<name>-disko-test`
  twin, and the CI job that exercises it are all generated from that one
  list — nothing hand-duplicated per host.
- **Two-stage GitLab CI**: fast `build-config` (evaluates/builds on every
  push) + slower `disko-boot-test` (boot-tests every host's real disk
  layout, enumerated automatically from `flake.nix`).
- `hosts/template/` — scaffold to copy when adding a new host.

### Fixed
- Host renamed consistently to `archer` across `flake.nix`,
  `networking.hostName`, and the `hosts/` folder (previously mismatched
  across a few different names).
- `networking.hostName` and `networking.hostId` moved out of the shared
  `modules/common.nix` into per-host files — a hardcoded value there
  would have silently applied to every host once a second one existed.
- Stale hyphenated username (`homelab-admin` → `homelabadmin`) in
  `modules/secrets.nix`, which was creating a broken duplicate user
  account with no group/type set.
- `boot.initrd.postDeviceCommands` (unsupported under systemd-stage-1,
  now the NixOS default) replaced with a proper
  `boot.initrd.systemd.services.zfs-rollback` unit.
- `environment.persistence."/persist"` now sets
  `fileSystems."/persist".neededForBoot = true` — required so files like
  SSH host keys are available early enough in boot for sshd to use them.
- `modules/disko-test.nix`'s rollback service now self-bootstraps the
  `@blank` snapshot on a disposable test image's first boot (nothing
  else creates it there, unlike a real install) — real deploys still
  require the documented manual snapshot step.
