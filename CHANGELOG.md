# Changelog

## Unreleased — k3s workload, automated first-boot setup

### Added
- **`application/k3s.nix`** — first actual workload on the fleet: k3s,
  single-node to start (`role = "server"`), with a `myK3s.controlPlaneOnly`
  option (currently commented off for `archer`) to later mark a node
  control-plane-only once agents exist. k3s's own state
  (`/var/lib/rancher/k3s`) is added to `impermanence`'s persisted
  directories — without this, every reboot would wipe the whole cluster.
  New top-level `application/` directory, distinct from `modules/`:
  `modules/` is system-level plumbing (users, disks, secrets — the same
  regardless of purpose), `application/` is what the machine is actually
  FOR (workloads). Firewall opened for k3s's API port (6443) only —
  deliberately not etcd's ports (2379-2380), which only matter for
  multi-server HA, irrelevant for single-node's embedded sqlite backend.
- **`modules/first-boot.nix`** — a one-shot systemd service, gated on a
  marker file under `/persist` (so it only ever runs once, surviving
  every subsequent rollback), that fires on the first real multi-user
  boot after install. Collects hostname, IP, SSH host key, ZFS pool/
  dataset/snapshot status, and disk usage into
  `~homelabadmin/first-boot-info.tar.gz`, and writes `NEXT_STEPS.md`
  with THIS host's real values already filled in — the exact
  `ssh-to-age`/`ragenix` commands to extend secrets trust, and the `git`
  commands to commit its hardware report. Replaces "remember to SSH in
  and run these commands" with "cat a file that already has them."

### Changed
- **`modules/impermanence.nix`'s rollback service is now
  self-bootstrapping on real hosts too**, not just the disposable test
  image. If `zroot/root@blank` doesn't exist yet, it's created instead
  of rolled back — safe specifically because this only matters on the
  very first boot after a fresh `nixos-anywhere` install, when root
  already has exactly the freshly-installed closure and nothing else.
  Removes the previous "SSH in and manually run `zfs snapshot` before
  the next reboot" race entirely — a real, easy-to-miss manual step is
  now automatic.
- `secrets/secrets.nix` and `modules/secrets.nix` comments clarified:
  these are two genuinely different files serving two different
  consumers (the `agenix`/`ragenix` CLI tool vs. NixOS itself at boot),
  not a duplicate — worth being explicit about given how easy this is to
  conflate when new to agenix.

### Known issues (not yet fixed)
- `scripts/provision-host.sh`'s generated post-install summary has a
  stale section header: "1. Create the impermanence blank snapshot" is
  followed by the facter.json-commit commands, not snapshot commands —
  left over from before the rollback service became self-bootstrapping
  (see Changed, above). The header needs updating to match what's
  actually underneath it, and the numbering (which currently skips
  straight from "1." to "3.") needs fixing to match.

---

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
- **`nixos-anywhere`**-based provisioning (`scripts/provision-host.sh`) —
  one-shot remote install (kexec + disko + facter + closure install) from
  a stock NixOS installer ISO, no custom image needed.
- **VM-based local/CI testing**, replacing Docker:
  - `modules/vm-test.nix` + `scripts/test-vm.sh` — fast general config
    smoke test via `nixos-rebuild build-vm`'s native machinery.
  - `modules/disko-test.nix` + `scripts/test-disko.sh` — builds and
    boot-tests each host's disk layout mechanism as a disposable image
    under software-emulated QEMU (no `/dev/kvm` needed, so it also runs
    on shared CI runners).
- **`flake.nix` restructured** around a single `hosts = { ... }` attrset.
  Adding a machine is one entry (plus its `hosts/<name>/disko.nix`); the
  real `nixosConfigurations.<name>`, its disposable `<name>-disko-test`
  twin, and the CI job that exercises it are all generated from that one
  list — nothing hand-duplicated per host.
- **Two-job GitLab CI**: `build-config` (fast, every push) +
  `disko-boot-test` (boot-tests every host, enumerated automatically
  from `flake.nix`).
- `hosts/template/` — scaffold to copy when adding a new host.
- `scripts/test-suite.sh` — runs every local check in roughly CI order
  (flake check, `flake.lock` committed, `hostNames` resolves, per-host
  eval, per-host disko-image eval, then both VM boots), with `--debug`
  and `--skip-boot` flags for faster iteration.
- `modules/disko-test-ssh-key[.pub]` — throwaway keypair, committed
  intentionally (unlocks nothing but the disposable disko-test image),
  so `scripts/test-disko.sh` can verify boot success over SSH the same
  way locally and in CI, with no shared secret required.

### Fixed
- Host renamed consistently to `archer` across `flake.nix`,
  `networking.hostName`, and the `hosts/` folder (previously mismatched
  across a few different names).
- `networking.hostName`/`hostId` moved out of the shared
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
- `hosts/archer/disko.nix`'s `networking.hostId` was still the literal
  `REPLACE_WITH_8_HEX_CHARS` placeholder, failing NixOS's hostId
  assertion and breaking eval for the real host entirely.
- `mkDiskoTest` no longer imports a host's real `hosts/<hostname>/disko.nix`
  at all — it previously did, which collided with `disko-test.nix`'s own
  partition definitions once `disko-test.nix` moved to overriding the
  whole `disko.devices` tree.
- `modules/disko-test.nix`'s `disko.devices` override changed from
  `lib.mkForce` on the whole tree to a plain assignment — forcing the
  whole tree collided with disko's own internal per-partition defaults.
- `modules/vm-test.nix` and `modules/disko-test.nix` were missing a root
  filesystem/bootloader declaration, failing `nix flake check`'s
  assertions even though the VM-only paths they're used for don't need
  either for real.
- `scripts/test-disko.sh` pointed OVMF at `OVMF_CODE.fd` (the
  pflash-only split firmware variant, invalid with `-bios`) instead of
  `OVMF.fd` — QEMU failed immediately with "could not load PC BIOS".
- `scripts/test-disko.sh` booted the Nix store output directly
  (read-only) instead of a writable copy — QEMU failed to open the
  drive for write. Now copies to a scratch file first.
- `scripts/test-disko.sh`'s pass/fail check replaced entirely: it used
  to `grep` a `-serial file:...` log for "Reached target Multi-User
  System", but QEMU buffers that output and doesn't flush it until the
  VM exits — a genuinely-booted VM could still fail the check. Now
  verifies via SSH (`systemctl is-system-running --wait`), more reliable
  and actually exercises the SSH path a real host would use.
- Scripts renamed for consistency: `deployment_local.sh` →
  `test-vm.sh`, `provision_host.sh` → `provision-host.sh`,
  `testingmodule_disko.sh` split into `test-disko.sh` + `test-suite.sh`.

### Known limitations
- `disko-boot-test` in CI is marked `allow_failure` — disko's
  image-building step requires an internal builder VM that needs
  `/dev/kvm` (a longstanding nixpkgs limitation, not specific to this
  repo), which standard GitLab shared runners don't expose. Verify
  locally via `./scripts/test-disko.sh <host>` until a self-hosted
  runner with KVM passthrough is set up.
- The disko-test image (see above) is a plain single-partition ext4
  layout, NOT any real host's actual ZFS design — see the "Local
  testing" section of README.md for what this does and doesn't prove.
