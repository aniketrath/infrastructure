{ config, ... }:
{
  # Only imported by the REAL nixosConfigurations.homelab — never by the
  # Docker test build, which has no password at all and only needs
  # `docker exec` to get in.
  age.secrets.homelab-admin-password.file = ../secrets/homelab-admin-password.age;
  users.users.homelab-admin.hashedPasswordFile =
  config.age.secrets.homelab-admin-password.path;
}
