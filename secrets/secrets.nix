let
  laptop = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICcEPHCU24dDL+IxHMU8djT199vQWvwNOt2RL1enWabl aniketrath1121@gmail.com";
  midguard-01 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINZhH6apiZ7YtHSRI7CKvCdhL6QzRbJm+vnfTsRTNR5V root@midguard-01";
  midguard-02 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFEiNJE3Yz3edUmgUdkMmzIg4KByOX3JsBEXcgRaKzIz root@midguard-02";

  adminKeys = [ laptop midguard-01 midguard-02 ];
  clusterNodes = [ midguard-01 midguard-02 ];
  tokenKeys = [ laptop ] ++ clusterNodes;
in
{
  "usercreds_homelabadmin.age".publicKeys = adminKeys;
  "clustercreds_k3s.age".publicKeys = tokenKeys;
  "clustercreds_postgres.age".publicKeys = tokenKeys;
  "clustercreds_tailscale.age".publicKeys = tokenKeys;
}
