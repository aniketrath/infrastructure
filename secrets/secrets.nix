let
  # Your personal key: lets YOU (re-)encrypt secrets from your laptop.
  laptop = "age1d334zq8p7ufc0cy2e9xshnsjje7fj9a0kqd65daxa345m79g939svcf9va";

  # Real per-node keys: ssh-to-age against each node's own
  # /etc/ssh/ssh_host_ed25519_key.pub, once that node has booted at
  # least once. Add one line here per real machine as it comes online.
  # archer = "age1...";

  # Who can decrypt the admin password — just you, plus (eventually)
  # whichever specific machine needs to log in as that user.
  adminKeys = [ laptop ];

  # Every k3s cluster node needs to decrypt the SAME token — that's what
  # lets them join each other. As real nodes get keys above, add them
  # here too. Currently empty since only `archer` exists and its key
  # isn't generated yet.
  clusterNodes = [ ];
  tokenKeys = [ laptop ] ++ clusterNodes;
in
{
  "usercreds_homelabadmin.age".publicKeys = adminKeys;
  "clusrercreds_k3s.age".publicKeys = tokenKeys;
}
