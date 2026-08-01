{ ... }:
{
  # ---------------------------------------------------------------------
  # TEST-ONLY MODULE. Reached only via `nixosConfigurations.vm-test` in
  # flake.nix. Never imported by any real host's config, and not
  # specific to any host's name.
  #
  # WHY THIS EXISTS: we used to smoke-test config changes by building a
  # Docker image (via the now-deprecated `nixos-generators` project).
  # nixpkgs' native replacement does NOT include a docker format, so
  # instead we boot a real (if minimal) VM using nixpkgs' built-in
  # `config.system.build.vm` — the same machinery behind the
  # `nixos-rebuild build-vm` command. It's arguably a better test
  # anyway: a real init/boot instead of a container.
  # ---------------------------------------------------------------------

  networking.hostName = "automation-test"; # also determines the generated run script's
                                    # name: result/bin/run-vm-automation-test

  # Headless, passed straight through as a raw QEMU flag rather than via
  # virtualisation.graphics — that option's exact availability/behavior
  # has moved around across recent nixpkgs revisions, whereas passing
  # -nographic directly is stable regardless of which NixOS option wraps
  # it this month.

  virtualisation.diskSize = 2048;  # MB. Ephemeral: thrown away after every run,
                                    # never persisted anywhere.
}
