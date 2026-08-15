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
- **NixOS**, pinned to the `nixos-26.05` **stable** release (not
  `nixos-unstable`) — deliberately, after unstable broke this repo more
  than once mid-project (a QEMU option restructured under us, a
  disko/kernel-packaging incompatibility). Stable moves far less.
- **disko** — turns disk partitioning/ZFS layout into Nix config instead
  of a manual `fdisk`/`mkfs`/`zpool create` session.
- **impermanence** — the "erase your darlings" pattern: root rolls back
  to a blank ZFS snapshot every boot; only explicitly persisted paths
  survive. Forces system state to genuinely live in this repo.
- **ragenix** — encrypted secrets committed straight into git, decrypted
  only by keys explicitly trusted per-host.
- **nixos-facter** — scans a real machine's hardware into a report,
  instead of hand-writing `hardware-configuration.nix`.
- **nixos-anywhere** — one command: partition, install, reboot into the
  real system, from a stock installer ISO, no custom image needed.
- **k3s** — the actual workload orchestrator, single-node to start with
  a clear path to adding nodes later. Chosen over Docker Swarm
  specifically because k8s (via k3s as the lightweight on-ramp) is the
  explicit longer-term learning goal.

## Recent updates
This branch adds a more robust install workflow and first-boot automation:
- `scripts/provision-host.sh` now supports an install step followed by a
  `--post-deploy` step that fetches the host's SSH `ed25519` key,
  rekeys `ragenix` secrets, and applies the final remote `nixos-rebuild`
  switch.
- `hosts/<name>/facter.json` is generated during install so hardware
  can be committed and used in later host evaluations.
- `modules/core/first-boot.nix` collects the newly provisioned machine's real
  SSH host key, zpool/zfs status, and a `NEXT_STEPS.md` into the host's
  home directory on first boot.

## Repo layout

```
.
├── flake.nix                     # single source of truth
├── flake.lock                    # flake lock
├── Makefile
├── .gitlab-ci.yml
├── modules/                      # SYSTEM-level config (core, services, testing)
│   ├── core/
│   ├── services/
│   └── testing/
├── hosts/                        # per-host disk definitions and hardware reports
│   ├── midguard-01/
│   ├── midguard-02/
│   ├── midguard-03/
│   ├── midguard-04/
│   └── template/
├── secrets/                      # ragenix/age-encrypted secrets and recipients
├── scripts/                      # operational helpers (provisioning, results)
│   └── provision-host.sh
├── tests/                        # test fixtures and disposable helpers
└── CHANGELOG.md
```

`modules/core/` vs `modules/services/`: `modules/core/` is system-level plumbing
(users, disks, secrets, the machine's own identity) — the same on every
host regardless of what it's actually for. `modules/services/` is what the
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
that, the host evaluates fine without it (this is what lets a host entry
exist as a config today, with no real hardware yet, without breaking
anything).

## Local testing (Makefile)

Fastest path — run everything at once before pushing via the `Makefile`:
```bash
make test                # full suite: flake checks, evals, builds and boots
make test DEBUG=1        # verbose output (prints build logs)
```

Or run the two boot-relevant checks individually:

**1. General config (packages, users, services) — does it evaluate and boot?**
```bash
make vm                 # builds and boots the shared vm-test image
```
Builds `.#vm-test`, boots it headlessly under QEMU, and prints the SSH
command to hop in using your real key.

**2. A specific host's REAL disk layout — does it partition, format, and boot?**
```bash
make disko HOST=<hostname>
```
Builds `.#<hostname>-disko-image`, boots it under software-emulated QEMU
(works without `/dev/kvm`, so it runs on CI runners too, just slower),
verifies success over SSH (`systemctl is-system-running --wait`) using a
throwaway keypair in `tests/fixtures/disko-test-ssh-key[.pub]`. Pass/fail is
based on the machine reaching a running state over SSH.

**Important, current scope limitation:** the disko-test image is
deliberately self-contained — single ext4 partition, no ZFS, no
impermanence — NOT archer's real three-dataset ZFS layout. This is a
deliberate pivot after hitting a real upstream bug (disko's
`vmTools`-based image builder panicking on multi-dataset ZFS pools —
matches nix-community/disko#461/#503). What this proves: disko's
partitioning mechanism itself works, and the disk boots. What it does
NOT prove: that archer's actual ZFS+impermanence design works — that
still only gets genuinely validated by a real hardware install.

## Secrets Management & Host Keys (`ragenix`)

Managed via [ragenix](https://github.com/yosida95/ragenix) — encrypted at
rest in `secrets/*.age`, decrypted on the real machine using a permanent static SSH host key.

### 1. Generating a Static Host Key (Per Host)
To prevent host keys from changing on every re-image, generate a dedicated static host key on your laptop and convert it to an `age` public key format:

```bash
mkdir -p ~/.ssh/hosts/<hostname>
ssh-keygen -t ed25519 -N "" -C "host-<hostname>" -f ~/.ssh/hosts/<hostname>/ssh_host_ed25519_key
nix run nixpkgs#ssh-to-age -- < ~/.ssh/hosts/<hostname>/ssh_host_ed25519_key.pub
```

### 2. Updating `secrets/secrets.nix`
Add your laptop's `ssh-ed25519` public key and the host's `ssh-ed25519`
public key directly to `secrets/secrets.nix`:

```nix
let
  laptop = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICcEPHCU24dDL+IxHMU8djT199vQWvwNOt2RL1enWabl aniketrath1121@gmail.com";
  archer = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB0ZzOIWo0+cYCOzSiyQIN+39xujvV4Gv8ai5X7QpQjz root@archer";
  allKeys = [ laptop archer ];
in
{
  "usercreds_homelabadmin.age".publicKeys = allKeys;
  "clusrercreds_k3s.age".publicKeys       = allKeys;
}
```

If you have a static SSH host key on your laptop, extract the public key with:

```bash
ssh-keygen -y -f ~/.ssh/hosts/<hostname>/ssh_host_ed25519_key
```

Then paste the resulting `ssh-ed25519 ...` line into `secrets/secrets.nix`.

### 3. Creating & Encrypting Secrets
From the root directory, navigate to `secrets/` and use `ragenix` along with `mkpasswd` or `openssl`:

```bash
cd secrets

# User password hash
nix run nixpkgs#mkpasswd -- -m sha-512
nix run nixpkgs#ragenix -- -e usercreds_homelabadmin.age -i ~/.ssh/id_ed25519

# K3s token
openssl rand -hex 16
nix run nixpkgs#ragenix -- -e clusrercreds_k3s.age -i ~/.ssh/id_ed25519

# If adding new hosts later, rekey all secrets:
# nix run github:ryantm/agenix -- --rekey -i ~/.ssh/id_ed25519

cd ..
```

### 4. Injecting Host Keys & Deploying Hardware
1. Re-image or install NixOS on the host.
2. Copy the static private host key onto the remote machine:

```bash
scp ~/.ssh/hosts/<hostname>/ssh_host_ed25519_key homelabadmin@<HOST_IP>:/tmp/ssh_host_ed25519_key
ssh homelabadmin@<HOST_IP> "sudo mv /tmp/ssh_host_ed25519_key /etc/ssh/ssh_host_ed25519_key && sudo chmod 600 /etc/ssh/ssh_host_ed25519_key && sudo systemctl restart sshd"
```

3. Commit secrets and trigger a nixos-rebuild deployment:

```bash
git add secrets/
git commit -m "chore: update secrets and host keys"

nix run nixpkgs#nixos-rebuild -- switch \
  --flake .#<hostname> \
  --target-host homelabadmin@<HOST_IP> \
  --use-remote-sudo
```

## Provisioning real hardware (Alternative via `nixos-anywhere`)

```bash
scripts/provision-host.sh <hostname> root@<live-installer-ip>
```
One-shot install via `nixos-anywhere`: generates the hardware report,
partitions via that host's `disko.nix`, installs the closure, and reboots
into it. See the comments at the top of the script for the manual
prerequisites (real disk path, a real `hostId`) that need filling in per
host before running it.

After the install completes, finish the setup automatically with:

```bash
./provision-host.sh --post-deploy <hostname> <target-ip>
```

Right after this finishes, and before you do anything else on that
machine: `modules/core/first-boot.nix`'s `first-boot-setup` service runs
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

### ZFS Impermanence & Rollback Setup

#### Enable Systemd Initrd [Already enabled for now, Optional as per use case]
If you are using the ZFS root rollback feature for impermanence, ensure that systemd is explicitly enabled inside the initrd. Without this flag, NixOS will use the legacy initrd setup and **silently ignore** any custom systemd services required to execute the rollback.

Add this configuration to your base system settings or impermanence module:

```nix
{
  boot.initrd.systemd.enable = true;
}
```
**A Quick Tip for Future Maintenance**
If you ever intentionally change or update things directly inside the root filesystem (though with impermanence, you generally won't need to, since most config is in Nix and state is in /persist), those changes will disappear on reboot. If you ever want to update your baseline @blank snapshot to include new foundational layout changes, you would manually destroy the old snapshot and take a new one:
``` bash
# Optional: Only if you want to update your baseline state
sudo zfs destroy zroot/root@blank
sudo zfs snapshot zroot/root@blank
```

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

## Local branch snapshot: host/updatenames (unpublished)

Recent local work on branch `host/updatenames` (not yet pushed to `origin/main`):

- Backup branch created: `backup/host-updatenames-20260815-131626` (points at previous local state)

- Commits on this branch not present in `origin/main` (newest first):

  - `fd5a390` — docs(readme, changelog): record local branch snapshot and pending changelog temp file
    - Files changed: `README.md`, `CHANGELOG.md.tmp`
    - Notes: Captures working-tree edits and a temporary changelog file before further history operations.

  - `7afdccb` — chore: apply local uncommitted changes on host/updatenames
    - Files changed (high level): `Makefile`, `core.67584` (binary), `flake.nix`,
      `modules/core/common.nix`, `modules/core/impermanence.nix`,
      `modules/services/clustercreds.nix`, `scripts/test-disko.sh`,
      `scripts/test-suite.sh`, `scripts/test-vm.sh`, and `secrets/*` entries.
    - Notes: Consolidated a set of local changes across infra modules, tests, and secrets.

  - `ebfe03c` — fix(disko-test): updated the test script to use port 22 for deployed VMs and added gtk to help with local testing
    - Files changed: `scripts/test-disko.sh`
    - Notes: Adjusted the test harness for real-VM (port 22) SSH testing and added GTK helpers for local GUI debugging.

Notes:
- A safety backup branch (`backup/host-updatenames-20260815-131626`) was created before recording working-tree changes.
- If you want commit messages split or polished, I can create additional commits and perform a non-destructive reword (this may require a force-push to update remote history).
