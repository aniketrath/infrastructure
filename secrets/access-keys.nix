let
  laptop = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICcEPHCU24dDL+IxHMU8djT199vQWvwNOt2RL1enWabl aniketrath1121@gmail.com";
  midguard-01 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO7amCnWmLmYCVbnNt/LYQ2jYcxlFCdQLLyo7k9UW4Z6 root@midguard-01";
  midguard-02 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEUrqUKpQuKEtqHUjCDQNYQ/4OdYgZC+3++Gd0ZzO0BJ root@midguard-02";
in
[ laptop midguard-01 midguard-02 ]