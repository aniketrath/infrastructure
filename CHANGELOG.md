# Changelog

## [2026-08-06] - k3s workload, automated first-boot setup

- Added `scripts/provision-host.sh` post-deploy mode to fetch the host's
  `ssh-ed25519` key, rekey `ragenix` secrets, and apply a final remote
  `nixos-rebuild` switch.
- Added `hosts/<name>/facter.json` hardware report generation on install
  to support per-host evaluation and commit-driven hardware-aware config.
- Added first-boot collection via `modules/core/first-boot.nix`, producing
  `~/first-boot-info.tar.gz` and `~/NEXT_STEPS.md` on the new host.
- Updated secrets management to use native SSH host keys and a more
  explicit trust/rekey workflow.
- Reorganized module layout: moved host-independent config into
  `modules/core/`, moved workload config into `modules/services/`, and
  moved test-only support into `modules/testing/` / `tests/fixtures/`.
- Added new host disk definitions for `caster`, `lancer`, and `ruler`.

### Added
- **`modules/services/k3s.nix`** — first actual workload on the fleet: k3s, single-node to start (`role = "server"`), with a `myK3s.controlPlaneOnly` option (currently commented off for `archer`) to later mark a node control-plane-only once agents exist. k3s's own state (`/var/lib/rancher/k3s`) is added to `impermanence`'s persisted directories — without this, every reboot would wipe the whole cluster. Workload config now lives under `modules/services/` instead of a top-level `application/` directory.
- **`modules/core/first-boot.nix`** — a one-shot systemd service, gated on a marker file under `/persist` (so it only ever runs once, surviving every subsequent rollback), that fires on the first real multi-user boot after install. Collects hostname, IP, SSH host key, ZFS pool/dataset/snapshot status, and disk usage into `~homelabadmin/first-boot-info.tar.gz`, and writes `NEXT_STEPS.md` with THIS host's real values already filled in — the exact `ssh-to-age`/`ragenix` commands to extend secrets trust, and the `git` commands to commit its hardware report. Replaces "remember to SSH in and run these commands" with "cat a file that already has them."
- **Post-Deployment Automation**: Added `--post-deploy` handler to `provision-host.sh` to automatically fetch host SSH keys, re-key secrets, and trigger final `nixos-rebuild` deployment.

### Changed
- **`modules/impermanence.nix`'s rollback service is now self-bootstrapping on real hosts too**, not just the disposable test image. If `zroot/root@blank` doesn't exist yet, it's created instead of rolled back — safe specifically because this only matters on the very first boot after a fresh `nixos-anywhere` install, when root already has exactly the freshly-installed closure and nothing else. Removes the previous "SSH in and manually run `zfs snapshot` before the next reboot" race entirely — a real, easy-to-miss manual step is now automatic.
- **Native Agenix/Ragenix Key Format**: Simplified key configurations by transitioning to raw `ssh-ed25519` public keys natively supported by `age`, removing the requirement for `ssh-to-age` conversion.
- **Node Configuration**: Finalized hardware profile (`facter.json`) and `disko.nix` parameters for the `archer` host.
- `secrets/secrets.nix` and `modules/secrets.nix` comments clarified: these are two genuinely different files serving two different consumers (the `agenix`/`ragenix` CLI tool vs. NixOS itself at boot), not a duplicate — worth being explicit about given how easy this is to conflate when new to agenix.

### Fixed
- `scripts/provision-host.sh` generated post-install summary now correctly points to the hardware report/facter.json commit instructions.

### Known issues (not yet fixed)
- `disko-boot-test` in CI is marked `allow_failure` — disko's image-building step requires an internal builder VM that needs `/dev/kvm`, which standard GitLab shared runners don't expose. Verify locally via `./scripts/test-disko.sh <host>` until a self-hosted runner with KVM passthrough is set up.
- The disko-test image is a plain single-partition ext4 layout, NOT any real host's actual ZFS design — see the "Local testing" section of README.md for what this does and doesn't prove.

---

## [2026-06-01] - migration off Docker-based testing

### Removed
- `nixos-generators`-based Docker image testing (`homelab-docker-test`) and its Dockerfile-adjacent test scripts.

### Added
- **`disko`** — declarative disk partitioning/ZFS layout.
- **`impermanence`** — ephemeral root pattern.
- **`nixos-facter`** — generates each host's hardware report.
- **`nixos-anywhere`**-based provisioning (`scripts/provision-host.sh`).
- **VM-based local/CI testing**, replacing Docker.
- **`flake.nix` restructured** around a single `hosts = { ... }` attrset.
- **Two-job GitLab CI**: `build-config` + `disko-boot-test`.
- `hosts/template/` — scaffold.
- `scripts/test-suite.sh` — runs every local check.
- `modules/disko-test-ssh-key[.pub]` — throwaway keypair.
