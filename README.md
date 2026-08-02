# stackcraft-infra

Declarative NixOS config for the homelab fleet — disk layout, ephemeral
root with explicit persistence, secrets, and CI/CD, all as code.

## Repo layout

├── flake.nix # single source of truth — see below
├── modules/
│ ├── common.nix # shared packages/users/ssh — safe on any host
│ ├── secrets.nix # wires the agenix-encrypted admin password in
│ ├── impermanence.nix # ZFS rollback-on-boot + explicit persistence
│ ├── vm-test.nix # TEST-ONLY: headless VM smoke test
│ ├── disko-test.nix # TEST-ONLY: disposable disk-image overrides
│ └── disko-test-ssh-key[.pub] # TEST-ONLY: throwaway keypair so
│ # scripts/test-disko.sh can SSH into
│ # the disposable image locally and in
│ # CI — unlocks nothing but this
│ # self-destructing test image
├── hosts/
│ ├── archer/disko.nix # real disk layout for the archer host
│ └── template/disko.nix # starting point for adding a new host
├── secrets/
│ ├── secrets.nix # agenix recipients (who can decrypt what)
│ └── *.age # encrypted secrets, safe to commit
├── scripts/
│ ├── test-vm.sh # build + boot the vm-test image, print SSH cmd
│ ├── test-disko.sh # build + boot-test one host's real disk layout
│ ├── test-suite.sh # runs every local check, roughly in CI order
│ └── provision-host.sh # one-shot real install via nixos-anywhere
└── .gitlab-ci.yml

## `flake.nix`: the `hosts` attrset

Every real machine is one entry in a single `hosts = { ... }` attrset near
the top of `flake.nix`. Everything else — the real `nixosConfigurations.<n>`,
its disposable `<n>-disko-test` twin, and the CI job that boot-tests it —
is generated FROM that list, not hand-duplicated per host. To add a
machine, add one entry there plus a `hosts/<name>/disko.nix` (copy
`hosts/template/disko.nix` as a starting point).

## Local testing

Fastest path: run everything at once before pushing —

```bash
./scripts/test-suite.sh              # every check, including both VM boots
./scripts/test-suite.sh --skip-boot  # fast: eval/flake-check only, no QEMU
```

Or run the two boot-relevant checks individually:

**1. Does the general config (packages, users, services) still evaluate
and boot?**
```bash
./scripts/test-vm.sh
```
Builds `.#vm-test`, boots it headlessly under QEMU, prints the SSH
command to hop in (your own real key, via `modules/common.nix`).

**2. Does a specific host's REAL disk layout (disko + ZFS + impermanence)
still partition, format, and boot correctly?**
```bash
bash scripts/test-disko.sh <hostname>
```
Builds `.#<hostname>-disko-image` from that host's actual `disko.nix`,
boots it under software-emulated QEMU (works on CI shared runners, no
`/dev/kvm` needed), and verifies success over SSH —
`systemctl is-system-running --wait` — using a throwaway keypair
committed at `modules/disko-test-ssh-key[.pub]` (works identically
locally and in CI; unlocks nothing but this disposable image). Pass/fail
is based on the machine actually reaching a running state, not just
`nix build` succeeding.

Note: this proves the disk layout is sound and boots. It does **not** by
itself prove the impermanence rollback/persistence *behavior* is
correct — that needs an interactive reboot-and-check pass (boot the same
`<hostname>-disko-image` interactively, touch a file on `/`, touch one
under a persisted path, `reboot`, confirm which one survived).

## Secrets

Managed via [agenix](https://github.com/ryantm/agenix) — encrypted at
rest in `secrets/*.age`, decrypted on the real machine using its own SSH
host key. See `secrets/secrets.nix` for the recipients list; add a new
host's age-converted SSH host key there once it's been provisioned, then
re-run `agenix -e`/`ragenix -e` to re-encrypt for the expanded set.

## Provisioning real hardware

```bash
scripts/provision-host.sh <hostname> root@<live-installer-ip>
```

One-shot install via `nixos-anywhere`: generates a hardware report with
`nixos-facter` (no hand-written `hardware-configuration.nix`), partitions
via that host's `disko.nix`, installs the closure, reboots into it. See
the comments at the top of the script for the manual prerequisites
(disk path, hostId) that need filling in per host before running it.

## CI/CD

Two stages in `.gitlab-ci.yml`:
- **`build-config`** (fast, every push) — `nix build .#vm-test`.
- **`disko-boot-test`** (slower, every push) — runs
  `test-disko.sh` against every host in `flake.nix`'s `hosts`
  attrset automatically; adding a host needs no CI file changes.