{
  description = "Homelab NixOS Flake Configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence.url = "github:nix-community/impermanence";
    nixos-facter-modules.url = "github:nix-community/nixos-facter-modules";
  };

  outputs = { self, nixpkgs, agenix, disko, impermanence, nixos-facter-modules, ... }:
    let
      lib = nixpkgs.lib;
      ciSystem = "x86_64-linux";

      # Central list of physical/virtual hosts and host-specific options
      # # { myK3s.controlPlaneOnly = true; }  # flip when other nodes exist
      hosts = {
        archer = { extraModules = [ ./modules/core/impermanence.nix ./modules/core/first-boot.nix ./modules/services/k3s.nix { myK3s.isFirstNode = true; } ]; };
        lancer = { extraModules = [ ./modules/core/impermanence.nix ./modules/core/first-boot.nix ./modules/services/k3s.nix { myK3s.serverAddr = "https://archer.local:6443"; } ]; };
        ruler = { extraModules = [ ./modules/core/impermanence.nix ./modules/core/first-boot.nix ./modules/services/k3s.nix { myK3s.serverAddr = "https://archer.local:6443"; } ]; };
        caster = { extraModules = [ ./modules/core/impermanence.nix ./modules/core/first-boot.nix ./modules/services/k3s.nix { myK3s.serverAddr = "https://archer.local:6443"; } ]; };
      };

      # Builder function for production host system closures
      mkHost = hostname: { system ? "x86_64-linux", extraModules ? [ ] }:
        let
          facterPath = ./hosts/${hostname}/facter.json;
          hasFacter = builtins.pathExists facterPath;
        in
        nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            agenix.nixosModules.default
            disko.nixosModules.disko
            impermanence.nixosModules.impermanence
            ./modules/core/common.nix
            ./modules/core/secrets.nix
            ./hosts/${hostname}/disko.nix
          ]
          # Auto-enable hardware facter report if it exists
          ++ lib.optionals hasFacter [
            nixos-facter-modules.nixosModules.facter
            { config.facter.reportPath = facterPath; }
          ]
          ++ extraModules;
        };

      # Builder function for isolated Disko partition test environments
      mkDiskoTest = hostname: { system ? "x86_64-linux", ... }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            agenix.nixosModules.default
            ./modules/core/secrets.nix
            disko.nixosModules.disko
            ./modules/core/common.nix
            ./modules/testing/disko-test.nix
          ];
        };
    in
    {
      # Exported NixOS system configurations
      nixosConfigurations =
        # Real production host systems
        (lib.mapAttrs (hostname: cfg: mkHost hostname cfg) hosts)
        //
        # Disko test twin configurations (<hostname>-disko-test)
        (lib.mapAttrs' (hostname: cfg: {
          name = "${hostname}-disko-test";
          value = mkDiskoTest hostname cfg;
        }) hosts)
        //
        {
          # Non-host-specific smoke test VM
          vm-test = nixpkgs.lib.nixosSystem {
            system = ciSystem;
            modules = [
              agenix.nixosModules.default
              ./modules/core/secrets.nix
              ./modules/core/common.nix
              ./modules/testing/vm-test.nix
            ];
          };
        };

      # Build artifacts and runnable CI packages
      packages.${ciSystem} =
        { vm-test = self.nixosConfigurations.vm-test.config.system.build.vm; }
        // (lib.mapAttrs' (hostname: _: {
          name = "${hostname}-disko-image";
          value = self.nixosConfigurations."${hostname}-disko-test".config.system.build.diskoImages;
        }) hosts);

      # Helper attribute exposing all active hostnames
      hostNames = builtins.attrNames hosts;
    };
}
