let
  laptop = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICcEPHCU24dDL+IxHMU8djT199vQWvwNOt2RL1enWabl aniketrath1121@gmail.com";
  midguard-01 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO7amCnWmLmYCVbnNt/LYQ2jYcxlFCdQLLyo7k9UW4Z6 root@midguard-01";
  midguard-02 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEUrqUKpQuKEtqHUjCDQNYQ/4OdYgZC+3++Gd0ZzO0BJ root@midguard-02";

  adminKeys = [ laptop midguard-01 midguard-02 ];
  clusterNodes = [ midguard-01 midguard-02 ];
  tokenKeys = clusterNodes;
in
{
  "usercreds_homelabadmin.age".publicKeys = adminKeys;
  "clustercreds_k3s.age".publicKeys = clusterNodes;
  "clustercreds_postgres.age".publicKeys = clusterNodes;
  "clustercreds_tailscale.age".publicKeys = clusterNodes;
  "clustercreds_infisical.age".publicKeys = clusterNodes;
  
  __access_keys = adminKeys;
}