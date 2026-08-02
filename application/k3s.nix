{ config, lib, pkgs, ... }:
{
  options.myK3s.controlPlaneOnly = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Controls ControlPlane / Worker status";
  };

  config = {
    services.k3s = {
      enable = true;
      role = "server";
      extraFlags = toString (
        lib.optional config.myK3s.controlPlaneOnly "--disable-agent"
      );
    };

    networking.firewall.allowedTCPPorts = [ 6443 10250 ];
    networking.firewall.allowedUDPPorts = [ 8472 ];

    environment.persistence."/persist".directories = [
      "/var/lib/rancher/k3s"
    ];
  };
}
