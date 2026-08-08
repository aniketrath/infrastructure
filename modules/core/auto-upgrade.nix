{ config, pkgs, ... }:

{
  system.autoUpgrade = {
    enable = true;.
    flake = "git+https://gitlab.com/aniketrath/stackcraft-infra.git#${config.networking.hostName}";
    dates = "04:00";
    randomizedDelaySec = "45min";
    flags = [
      "--refresh"
    ];
    allowReboot = true;
  };
}
