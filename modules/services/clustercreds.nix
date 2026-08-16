{ config, lib, pkgs, ... }:
let
  # One entry per Kubernetes Secret you want auto-applied into the cluster
  # for ArgoCD-deployed apps to consume.
  #
  # name = the Kubernetes Secret's own name (what `metadata.name` inside
  #         the decrypted YAML should be, and what shows up in `kubectl`).
  # file = the age file under secrets/, following this repo's existing
  #        naming convention (clustercreds_*.age, usercreds_*.age, ...).
  #
  # For each entry you need:
  #   1. The age file created/edited with:
  #        agenix -e secrets/<file>
  #      whose *decrypted plaintext* is a complete `kind: Secret` manifest
  #      (not raw key=value).
  #   2. A matching recipients entry in secrets/secrets.nix:
  #        "<file>".publicKeys = adminKeys;  # or tokenKeys, etc.
  secrets = [
    { name = "clustercreds-postgres"; file = "clustercreds_postgres.age"; }
    { name = "operator-oauth"; file = "clustercreds_tailscale.age"; }
    { name = "operator-infisical"; file = "clustercreds_infisical.age"; }
  ];
  toManifestPath = name: "/var/lib/rancher/k3s/server/manifests/${name}-secret.yaml";
in
{
  age.secrets = lib.listToAttrs (map
    (s: {
      name = s.name;
      value = { file = ../../secrets/${s.file}; };
    })
    secrets);

  systemd.services = lib.listToAttrs (map
    (s: {
      name = "k3s-manifest-${s.name}";
      value = {
        description = "Deploy decrypted ${s.name} Secret into k3s auto-apply manifests";
        after = [ "k3s.service" ];
        wants = [ "k3s.service" ];
        wantedBy = [ "multi-user.target" ];
        restartTriggers = [ config.age.secrets.${s.name}.file ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          mkdir -p /var/lib/rancher/k3s/server/manifests
          install -m 0600 ${config.age.secrets.${s.name}.path} ${toManifestPath s.name}
        '';
      };
    })
    secrets);
}