{
  description = "Homelab NixOS config";

  # Every input is pinned via flake.lock, so `nix build`/`nix flake check`
  # stays fully reproducible until someone runs `nix flake update`.
  inputs = {
    # The package set and NixOS module collection everything else builds on.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    # agenix: lets us commit encrypted secrets (see secrets/) straight into
    # git and decrypt them on the target machine using its own SSH host key.
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs"; # reuse our nixpkgs, don't fetch a second copy
    };

    # disko: turns disk partitioning/formatting into declarative Nix config
    # (see hosts/<name>/disko.nix) instead of a manual fdisk/mkfs dance.
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # impermanence: the "erase your darlings" pattern — wipe root to a
    # blank snapshot every boot, keep only what's explicitly persisted.
    # Used by real hosts only (see modules/impermanence.nix, wired in per
    # host via the `hosts` attrset below) — the disposable disko-test
    # image has no impermanence story, so mkDiskoTest never imports this.
    impermanence.url = "github:nix-community/impermanence";

    # nixos-facter: generates a hardware report (facter.json) by scanning a
    # real machine, instead of us hand-writing hardware-configuration.nix
    # per host. This is what scripts/provision-host.sh relies on.
    nixos-facter-modules.url = "github:nix-community/nixos-facter-modules";
  };

  outputs = { self, nixpkgs, agenix, disko, impermanence, nixos-facter-modules, ... }:
    let
      lib = nixpkgs.lib;

      # ----------------------------------------------------------------
      # SINGLE SOURCE OF TRUTH for real hosts. To add a machine, add ONE
      # entry here — every real nixosConfiguration, disko-test twin, and
      # CI package output further down is generated FROM this list, not
      # hand-duplicated per host.
      #
      # Keys: hostname, your choice — must match a hosts/<hostname>/disko.nix.
      # Values:
      #   system       — defaults to x86_64-linux; override for e.g. a Pi.
      #   extraModules — host-specific modules on top of the shared base
      #                  (impermanence.nix, hardware quirks, etc).
      #
      # `archer` below is just this repo owner's own example host, named
      # after their actual machine — rename it, delete it, add your own;
      # nothing elsewhere in this flake assumes that specific name.
      # ----------------------------------------------------------------
      hosts = {
              archer = {
                extraModules = [
                  ./modules/impermanence.nix
                  ./modules/first-boot.nix
                  ./application/k3s.nix
                  { myK3s.isFirstNode = true; }
                  # { myK3s.controlPlaneOnly = true; }  # flip when other nodes exist
                ];
              };

              # A future second node joining archer's cluster:
              # some-worker-node = {
              #   extraModules = [
              #     ./modules/impermanence.nix
              #     ./application/k3s.nix
              #     { myK3s.serverAddr = "https://archer:6443"; }
              #   ];
              # };
            };

      # Builds one REAL host's system closure.
      mkHost = hostname: { system ? "x86_64-linux", extraModules ? [ ] }:
        let
          facterPath = ./hosts/${hostname}/facter.json;
          # Only wire up nixos-facter once that host's hardware report has
          # actually been generated (scripts/provision-host.sh) and
          # committed. Before then, evaluating this host would otherwise
          # hard-fail on a nonexistent facter.json — including breaking
          # `nix flake check` itself for every host until its hardware
          # exists. builtins.pathExists checks the flake's git-tracked
          # source, so this flips on automatically once facter.json is
          # committed — nothing to toggle by hand.
          hasFacter = builtins.pathExists facterPath;
        in
        nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            agenix.nixosModules.default
            disko.nixosModules.disko
            impermanence.nixosModules.impermanence
            ./modules/common.nix   # shared packages/users/ssh, safe on any host
            ./modules/secrets.nix  # wires the agenix-encrypted admin password in
            ./hosts/${hostname}/disko.nix
          ]
          ++ lib.optionals hasFacter [
            nixos-facter-modules.nixosModules.facter
            { config.facter.reportPath = facterPath; }
          ]
          ++ extraModules;
        };

      # Builds a disposable, boot-testable image using disko — proves the
      # disko module mechanism itself works (single ext4 partition, see
      # modules/disko-test.nix), not that any specific host's real
      # partition scheme is correct. Deliberately self-contained: does
      # NOT import a host's real hosts/<hostname>/disko.nix (that used to
      # collide with disko-test.nix's own partition definitions) and does
      # NOT import impermanence (no rollback story in this test at all).
      mkDiskoTest = hostname: { system ? "x86_64-linux", ... }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            disko.nixosModules.disko
            ./modules/common.nix
            ./modules/disko-test.nix
          ];
        };

      # System used for everything test/CI-related, independent of how
      # many/which architectures real hosts use.
      ciSystem = "x86_64-linux";
    in
    {
      nixosConfigurations =
        # One real nixosConfigurations.<hostname> per entry in `hosts`.
        (lib.mapAttrs (hostname: cfg: mkHost hostname cfg) hosts)
        //
        # One nixosConfigurations.<hostname>-disko-test twin per host.
        (lib.mapAttrs' (hostname: cfg: {
          name = "${hostname}-disko-test";
          value = mkDiskoTest hostname cfg;
        }) hosts)
        //
        {
          # Not host-specific — a single shared smoke test that just
          # proves modules/common.nix evaluates and boots, without any
          # disko/disk-layout involvement at all.
          vm-test = nixpkgs.lib.nixosSystem {
            system = ciSystem;
            modules = [
              ./modules/common.nix
              ./modules/vm-test.nix
            ];
          };
        };

      packages.${ciSystem} =
        { vm-test = self.nixosConfigurations.vm-test.config.system.build.vm; }
        //
        # One <hostname>-disko-image package per host, built from its
        # corresponding <hostname>-disko-test configuration above.
        (lib.mapAttrs' (hostname: _: {
          name = "${hostname}-disko-image";
          value = self.nixosConfigurations."${hostname}-disko-test".config.system.build.diskoImages;
        }) hosts);

      # Non-standard flake output (nix flake check may note it as
      # "unrecognized," which is harmless) purely so CI/scripts can
      # enumerate real hosts without a second hand-maintained list:
      #   nix eval --json .#hostNames
      hostNames = builtins.attrNames hosts;
    };
}
