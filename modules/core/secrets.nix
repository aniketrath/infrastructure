{ config, ... }:
{
  # Only imported by the REAL nixosConfigurations.<any real host> — never by the
  # Docker test build, which has no password at all and only needs
  # `docker exec` to get in.
  age.secrets.homelabadmin-password.file = ../../secrets/usercreds_homelabadmin.age;
  age.secrets.k3s-token.file = ../../secrets/clustercreds_k3s.age;

  # Force agenix to decrypt secrets BEFORE NixOS user account activation runs
  system.activationScripts.users.deps = [ "agenix" ];
}
