{ config, lib, pkgs, ... }:
{
  options.myK3s = {
    controlPlaneOnly = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "If true, --disable-agent is set — this node runs control-plane only, no kubelet, no scheduled workloads.";
    };
    isFirstNode = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        True ONLY for the single node that bootstraps the cluster
        (maps to services.k3s.clusterInit). Exactly one node in the
        whole cluster should ever set this — setting it on more than
        one node risks a split-brain etcd cluster.
      '';
    };
    serverAddr = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "https://archer:6443";
      description = "Address of the first/bootstrap node. Required on every node except the one with isFirstNode = true.";
    };
  };
  config = {
    assertions = [
      {
        assertion = config.myK3s.isFirstNode || config.myK3s.serverAddr != null;
        message = "application/k3s.nix: this host must set either myK3s.isFirstNode = true, or myK3s.serverAddr pointing at the first node.";
      }
    ];
    # Shared cluster join secret — same ciphertext decrypts identically
    # on every node (see secrets/secrets.nix: clusrercreds_k3s.age is encrypted
    # for every cluster node's key, not just one host).
    services.k3s = lib.mkMerge [
      {
        enable = true;
        role = "server";
        tokenFile = config.age.secrets.k3s-token.path;
        clusterInit = config.myK3s.isFirstNode;
        extraFlags = toString (
          lib.optional config.myK3s.controlPlaneOnly "--disable-agent"
        );
      }
      (lib.mkIf (config.myK3s.serverAddr != null) {
        serverAddr = config.myK3s.serverAddr;
      })
    ];
    networking.firewall.allowedTCPPorts = [ 6443 10250 ];
    networking.firewall.allowedUDPPorts = [ 8472 ];
    environment.persistence."/persist".directories = [
      "/var/lib/rancher/k3s"
    ];
  };
}
