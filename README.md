# nix-homelab

Declarative NixOS config for the homelab machine, with a Docker-testable
path for CI so config changes get validated before touching real hardware.

## Layout

- `flake.nix` — defines the real system (`nixosConfigurations.homelab`)
  and a Docker-testable image (`packages.homelab-docker-test`) from the
  same shared config.
- `modules/common.nix` — shared config: packages, zsh, docker, the
  `homelab-admin` user, SSH. Safe for both real hardware and the
  Docker test.
- `modules/container-test.nix` — container-only overrides (no
  bootloader, no DHCP). Only used by the Docker test build, never the
  real system.
- `modules/secrets.nix` — wires the agenix-encrypted password into
  `homelab-admin`. Only used by the real system.
- `secrets/secrets.nix` — agenix manifest: which age public keys can
  decrypt which secret.
- `hosts/homelab/` — empty for now; drop `hardware-configuration.nix`
  here once real hardware exists (generate it with
  `nixos-generate-config` run on the machine), then uncomment the
  import in `flake.nix`.

## First-time setup on your machine

```bash
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
sudo systemctl enable --now nix-daemon.service   # skip if single-user install

# If /nix/store doesn't exist yet (known gap in the Arch pacman package):
sudo mkdir -p /nix/store
sudo chown root:nixbld /nix/store
sudo chmod 1775 /nix/store
sudo systemctl restart nix-daemon.service
```

## Set the real password (once, before deploying to real hardware)

```bash
nix shell nixpkgs#age nixpkgs#ssh-to-age nixpkgs#agenix

ssh-to-age < ~/.ssh/id_ed25519.pub
# paste the age1... output into secrets/secrets.nix as `laptop`

mkpasswd -m yescrypt
# paste the resulting hash when prompted below

cd secrets
agenix -e homelab-admin-password.age
```

Also paste your real SSH public key into
`modules/common.nix` → `homelab-admin.openssh.authorizedKeys.keys`.

## Build and test in Docker

```bash
nix build .#homelab-docker-test
docker import result/*.tar.xz homelab-test:latest
docker run --rm -it --privileged --network none \
  --tmpfs /tmp --tmpfs /run --tmpfs /run/lock \
  -e container=docker homelab-test:latest /init
```

In another terminal:
```bash
docker exec -it <container_name> /nix/var/nix/profiles/system/sw/bin/bash
```

## CI/CD

See `.gitlab-ci.yml` — every branch builds and boot-tests the Docker
image; merges to `prod` build the real system closure and deploy it to
the machine over SSH via `nixos-rebuild switch`.
