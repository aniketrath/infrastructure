# stackcraft-infra

Declarative NixOS config for a homelab fleet, built as a personal
SRE/DevOps portfolio project. Disk layout, ephemeral root with explicit
persistence, secrets, workloads, and CI/CD — all as code, tested locally
and in CI before anything touches real hardware.

## What this actually is, and why

Every machine in the fleet is defined entirely in this repo — packages,
users, disk partitioning, secrets, and workloads (currently: k3s). A
change gets validated two ways before it's trusted: a fast general
config check (does it evaluate/boot at all), and a per-host disk-layout
boot test (does THIS host's real disko/ZFS config actually partition,
format, and boot). Only after both pass does a change get merged and,
eventually, deployed to a real machine — one-shot, via `nixos-anywhere`.

The stack, and why each piece is here:
- **NixOS**, pinned to the `nixos-25.05` **stable** release (not
  `nixos-unstable`) — deliberately, after unstable broke this repo more
  than once mid-project (a QEMU option restructured under us, a
  disko/kernel-packaging incompatibility). Stable moves far less.
- **disko** — turns disk partitioning/ZFS layout into Nix config instead
  of a manual `fdisk`/`mkfs`/`zpool create` session.
- **impermanence** — the "erase your darlings" pattern: root rolls back
  to a blank ZFS snapshot every boot; only explicitly persisted paths
  survive. Forces system state to genuinely live in this repo.
- **agenix** — encrypted secrets committed straight into git, decrypted
  only by keys explicitly trusted per-host.
- **nixos-facter** — scans a real machine's hardware into a report,
  instead of hand-writing `hardware-configuration.nix`.
- **nixos-anywhere** — one command: partition, install, reboot into the
  real system, from a stock installer ISO, no custom image needed.
- **k3s** — the actual workload orchestrator, single-node to start with
  a clear path to adding nodes later. Chosen over Docker Swarm
  specifically because k8s (via k3s as the lightweight on-ramp) is the
  explicit longer-term learning goal.

## Repo layout

```
.
├── flake.nix                    # single source of truth — see below
├── application/
│   └── k3s.nix                  # the actual workload: k3s, single-node
├── modules/                      # SYSTEM-level config (not workloads)
│   ├── common.nix                # shared packages/users/ssh — safe on any host
│   ├── secrets.nix                # wires the agenix-encrypted admin password in
│   ├── impermanence.nix           # ZFS rollback-on-boot + explicit persistence
│   ├── first-boot.nix              # one-time post-install data collection
│   ├── vm-test.nix                 # TEST-ONLY: headless VM smoke test
│   ├── disko-test.nix               # TEST-ONLY: disposable disk-image overrides
│   └── disko-test-ssh-key[.pub]      # TEST-ONLY: throwaway keypair so
│                                      # test-disko.sh can SSH into the
│                                      # disposable image locally/in CI —
│                                      # unlocks nothing but that image
├── hosts/
│   ├── archer/disko.nix          # real disk layout for the archer host
│   └── template/disko.nix         # starting point for adding a new host
├── secrets/
│   ├── secrets.nix                # agenix recipients (who can decrypt what)
│   └── *.age                       # encrypted secrets, safe to commit
├── scripts/
│   ├── test-vm.sh                 # build + boot the vm-test image, print SSH cmd
│   ├── test-disko.sh               # build + boot-test one host's real disk layout
│   ├── test-suite.sh                # runs every local check, roughly in CI order
│   └── provision-host.sh             # one-shot real install via nixos-anywhere
└── .gitlab-ci.yml
```

`application/` vs `modules/`: `modules/` is system-level plumbing
(users, disks, secrets, the machine's own identity) — the same on every
host regardless of what it's actually for. `application/` is what the
machine is FOR — actual workloads like k3s. This split keeps "is this
machine set up correctly" separate from "is this machine running the
right software," which matters more once there's more than one workload.

## `flake.nix`: the `hosts` attrset

Every real machine is one entry in a single `hosts = { ... }` attrset
near the top of `flake.nix`. From that one entry, `flake.nix`
automatically generates: the real `nixosConfigurations.<name>`, its
disposable `<name>-disko-test` twin, the buildable `<name>-disko-image`
package, and CI coverage for all of it — nothing hand-duplicated per
host. To add a machine: one entry in `hosts`, plus `hosts/<name>/disko.nix`
(copy `hosts/template/disko.nix` as a starting point).

A host's real config only gets `nixos-facter`'s hardware module wired in
once `hosts/<name>/facter.json` actually exists and is committed — before
that, the host evaluates fine without it (this is what lets `archer`
exist as a config today, with no real hardware yet, without breaking
anything).

## Local testing

Fastest path — run everything at once before pushing:
```bash
./scripts/test-suite.sh              # every check, including both VM boots
./scripts/test-suite.sh --skip-boot  # fast: eval/flake-check only, no QEMU
./scripts/test-suite.sh --debug      # verbose, for actually diagnosing a failure
```

Or run the two boot-relevant checks individually:

**1. General config (packages, users, services) — does it evaluate and boot?**
```bash
./scripts/test-vm.sh
```
Builds `.#vm-test`, boots it headlessly under QEMU, prints the SSH
command to hop in using your real key (`modules/common.nix`).

**2. A specific host's REAL disk layout — does it partition, format, and boot?**
```bash
bash scripts/test-disko.sh <hostname>
```
Builds `.#<hostname>-disko-image`, boots it under software-emulated QEMU
(works without `/dev/kvm`, so it also runs on plain CI shared runners —
just slower), verifies success over SSH (`systemctl is-system-running
--wait`) using a throwaway keypair committed specifically for this
(`modules/disko-test-ssh-key[.pub]` — unlocks nothing but this
disposable image). Pass/fail is based on the machine actually reaching a
running state, not just `nix build` succeeding.

**Important, current scope limitation:** the disko-test image is
deliberately self-contained — single ext4 partition, no ZFS, no
impermanence — NOT archer's real three-dataset ZFS layout. This is a
deliberate pivot after hitting a real upstream bug (disko's
`vmTools`-based image builder panicking on multi-dataset ZFS pools —
matches nix-community/disko#461/#503). What this proves: disko's
partitioning mechanism itself works, and the disk boots. What it does
NOT prove: that archer's actual ZFS+impermanence design works — that
still only gets genuinely validated by a real hardware install.

## Secrets

Managed via [agenix](https://github.com/ryantm/agenix) — encrypted at
rest in `secrets/*.age`, decrypted on the real machine using its own SSH
host key.

There are two, deliberately separate, `secrets.nix` files:
- **`secrets/secrets.nix`** — read only by the `agenix`/`ragenix`
  command-line tool, when you're authoring/updating a secret. Defines
  WHO can decrypt WHAT (a recipients list of age-format public keys).
- **`modules/secrets.nix`** — read by NixOS itself, at boot. Defines
  WHAT the running system does with the decrypted result (wires it into
  `homelabadmin`'s password).

The age keys in `secrets/secrets.nix` are NOT new keys — they're your
existing SSH keys, translated into `age`'s format with `ssh-to-age`
(`ssh-to-age -i ~/.ssh/id_ed25519.pub` for yours; the same command run
against `/etc/ssh/ssh_host_ed25519_key.pub` ON a real host for its own).
Add a new host's converted key to the list, then re-encrypt:
```bash
ragenix -e secrets/homelab-admin-password.age
```
One shared `.age` file for the whole fleet — you're not creating a new
encrypted file per host, only growing the recipients list.

## Provisioning real hardware

```bash
scripts/provision-host.sh <hostname> root@<live-installer-ip>
```
One-shot install via `nixos-anywhere`: generates the hardware report,
partitions via that host's `disko.nix`, installs the closure, reboots
into it. See the comments at the top of the script for the manual
prerequisites (real disk path, a real `hostId`) that need filling in per
host before running it.

Right after this finishes, and before you do anything else on that
machine: `modules/first-boot.nix`'s `first-boot-setup` service runs
automatically, once, on the first real boot — it collects the host's
SSH key, ZFS pool status, and disk info into
`~homelabadmin/first-boot-info.tar.gz`, and writes a `NEXT_STEPS.md`
right there with this specific host's real values already filled in
(the exact `ssh-to-age`/`ragenix` commands to extend secrets trust, and
the `git` commands to commit its hardware report). SSH in and start
there — no need to reconstruct these steps from memory.

Note: the impermanence rollback service is self-bootstrapping — it
creates the `@blank` snapshot itself, automatically, on that same first
boot. There's no longer a manual "snapshot before the first reboot"
race to worry about.

## CI/CD

Two jobs in `.gitlab-ci.yml`, same stage, run in parallel:
- **`build-config`** — `nix build .#vm-test`. Fast, no KVM needed.
- **`disko-boot-test`** — runs `test-disko.sh` against every host in
  `flake.nix`'s `hosts` attrset automatically (via the `hostNames` flake
  output) — adding a host needs no CI file changes.

**Known limitation:** `disko-boot-test` is currently marked
`allow_failure: true`. disko's image-building step needs an internal
builder VM requiring `/dev/kvm`, which standard GitLab shared runners
don't expose — a longstanding nixpkgs limitation, not specific to this
repo. Until a self-hosted runner with KVM passthrough exists, verify
this locally (`./scripts/test-disko.sh <host>` or `./scripts/test-suite.sh`)
before merging, rather than trusting this job's CI result alone.
