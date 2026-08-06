{ config, ... }:
{
  # Only imported by the REAL nixosConfigurations.<any real host> — never by the
  # Docker test build, which has no password at all and only needs
  # `docker exec` to get in.
  age.secrets.homelab-admin-password.file = ../secrets/usercreds_homelabadmin.age;
  age.secrets.k3s-token.file = ../secrets/clusrercreds_k3s.age;
  users.users.homelabadmin.hashedPasswordFile =
    config.age.secrets.homelab-admin-password.path;
}
