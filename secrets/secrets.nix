let
  # Your personal key: lets YOU (re-)encrypt secrets from your laptop.
  # Get this by converting your existing SSH ed25519 key with ssh-to-age
  # (see README below) — paste the age1... output here.
  laptop = "age1d334zq8p7ufc0cy2e9xshnsjje7fj9a0kqd65daxa345m79g939svcf9va";
  # The real machine's key: lets nixos-rebuild decrypt on the box itself,
  # using its own SSH host key. Get this the same way, but run ssh-to-age
  # against /etc/ssh/ssh_host_ed25519_key.pub ON the target machine once
  # it exists and has been SSH'd into at least once.
  allKeys = [ laptop ];
in
{
  "homelab-admin-password.age".publicKeys = allKeys;
}
