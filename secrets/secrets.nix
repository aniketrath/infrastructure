let
  laptop = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICcEPHCU24dDL+IxHMU8djT199vQWvwNOt2RL1enWabl aniketrath1121@gmail.com";
  archer = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB0ZzOIWo0+cYCOzSiyQIN+39xujvV4Gv8ai5X7QpQjz root@archer";

  adminKeys = [ laptop archer ];
  clusterNodes = [ archer ];
  tokenKeys = [ laptop ] ++ clusterNodes;
in
{
  "usercreds_homelabadmin.age".publicKeys = adminKeys;
  "clusrercreds_k3s.age".publicKeys = tokenKeys;
}
