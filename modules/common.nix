{ lib, pkgs, config, ... }:
{
  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;
  users.users.root.shell = pkgs.zsh;
  nix.settings.trusted-users = [ "root" "homelabadmin" ];

# virtualisation.docker.enable = true;
  boot.kernelModules = [ "kvm-amd" "kvm-intel" ];

  programs.virt-manager.enable = true;
  virtualisation.spiceUSBRedirection.enable = true;

  users.groups.libvirtd.members = ["homelabadmin"];
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu;
      swtpm.enable = true; # Required for Windows 11 / vTPM
      ovmf.packages = [ pkgs.OVMFFull.fd ]; # UEFI support
    };
  };
  security.sudo.wheelNeedsPassword = false;
  users.users.homelabadmin = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [ "wheel" "libvirtd" "kvm" "qemu" ];
    hashedPasswordFile = config.age.secrets.homelabadmin-password.path;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICcEPHCU24dDL+IxHMU8djT199vQWvwNOt2RL1enWabl aniketrath1121@gmail.com"
    ];
  };
  services.openssh = {
    enable = true;
    ports = [ 2222 ];
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  services.avahi = {
    enable = true;
    nssmdns4 = true;       # Enables local resolution via multicast DNS
    publish = {
      enable = true;
      addresses = true;    # Broadcast your IP address(es)
      domain = true;       # Publish the local domain
      hinfo = true;        # Publish hardware info
      workstation = true;  # Broadcast as a workstation
    };
  };

  environment.systemPackages = with pkgs; [
    curl wget eza bat jdk21_headless traceroute bind nettools iputils glances lsof strace tcpdump ncdu jq
    iproute2 procps psmisc tree unzip zip cacert gnupg git qemu virt-manager virtiofsd
  ];
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  system.stateVersion = "24.05";
}
