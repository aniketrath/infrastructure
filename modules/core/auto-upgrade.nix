{ config, pkgs, ... }:

{
  system.autoUpgrade = {
    enable = true;
    flake = "git+https://gitlab.com/stackcraft/infrastructure.git#${config.networking.hostName}";
    dates = "04:00";
    randomizedDelaySec = "5min";
    flags = [
      "--refresh"
    ];
    allowReboot = true;
  };
}


