{ config, lib, pkgs, ... }:
{
  options.myK3s = {
    controlPlaneOnly = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Control-plane only — disables the kubelet, no workloads scheduled here.";
    };
    isFirstNode = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        True only on the single node that bootstraps the cluster.
        Setting this on more than one node can split-brain etcd.
      '';
    };
    serverAddr = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "https://archer:6443";
      description = "First node's address. Required on every node except isFirstNode = true.";
    };
  };
  config = {
    assertions = [
      {
        assertion = config.myK3s.isFirstNode || config.myK3s.serverAddr != null;
        message = "application/k3s.nix: set myK3s.isFirstNode = true, or myK3s.serverAddr pointing at the first node.";
      }
    ];
    users.groups.kubectl = { };

    services.k3s = lib.mkMerge [
      {
        enable = true;
        role = "server";
        tokenFile = config.age.secrets.k3s-token.path;
        clusterInit = config.myK3s.isFirstNode;
        extraFlags = toString ([
          "--write-kubeconfig-group=kubectl"
          "--write-kubeconfig-mode=0640"
        ] ++ lib.optional config.myK3s.controlPlaneOnly "--disable-agent");
      }
      (lib.mkIf (config.myK3s.serverAddr != null) {
        serverAddr = config.myK3s.serverAddr;
      })
    ];
    networking.firewall = {
      allowedTCPPorts = [
        80    # Ingress HTTP
        443   # Ingress HTTPS
        6443  # Kubernetes API
        2379  # etcd client
        2380  # etcd peer
        10250 # Kubelet
      ];
      allowedUDPPorts = [ 8472 ]; # Flannel VXLAN
      allowedTCPPortRanges = [ { from = 30000; to = 32767; } ]; # NodePort services
    };
    environment.etc."profile.d/kubeconfig.sh".text = ''
      export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    '';
  };
}