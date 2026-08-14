{ lib, pkgs, config, ... }:

{
  # Boot settings
  boot.loader.systemd-boot.configurationLimit = 2;

  # Nix Store & GC settings
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  nix.settings.auto-optimise-store = true;

  # Nix & System Configuration
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "homelabadmin" ];
  };
  # Systemd Journal Configuration
  services.journald.extraConfig = ''
    Storage=persistent
    SystemMaxUse=4G
    SystemKeepFree=20%
    MaxRetentionSec=14day
    Compress=yes
  '';
  # 2. Non-Journald Log Rotation (Plain Text Logs)
  services.logrotate = {
    enable = true;
    settings = {
    # Default global settings for all log rotations
      header = {
        global = true;
        dateext = true;
        compress = true;
        delaycompress = true;
        missingok = true;
        notifempty = true;
      };

    # Rule for raw text logs in /var/log
      "/var/log/*.log" = {
        frequency = "daily";
        rotate = 7;
        maxsize = "50M";
      };
    };
  };

  system.stateVersion = "26.05";
  environment.enableAllTerminfo = true;

  # Users & Security
  users.mutableUsers = false;
  users.defaultUserShell = pkgs.zsh;
  users.users.root.shell = pkgs.zsh;

  security.sudo.wheelNeedsPassword = false;

  users.groups.libvirtd.members = [ "homelabadmin" ];

  users.users.homelabadmin = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [ "wheel" "libvirtd" "kvm" "qemu" ];
    hashedPasswordFile = config.age.secrets.homelabadmin-password.path;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICcEPHCU24dDL+IxHMU8djT199vQWvwNOt2RL1enWabl aniketrath1121@gmail.com"
    ];
  };
  # Virtualization & Kernel
  boot.kernelModules = [ "kvm-amd" "kvm-intel" ];
  programs.virt-manager.enable = true;
  virtualisation.spiceUSBRedirection.enable = true;
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu;
      swtpm.enable = true;
    };
  };
  # Services (SSH & Avahi)
  services.openssh = {
    enable = true;
    ports = [ 22 ];
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  services.tailscale.enable = true;
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      domain = true;
      hinfo = true;
      workstation = true;
    };
  };

  environment.systemPackages = with pkgs; [
    curl nvim vim wget eza bat jdk21_headless traceroute bind nettools iputils glances lsof
    strace tcpdump ncdu jq iproute2 procps psmisc tree unzip zip cacert gnupg git
    qemu virt-manager virtiofsd kubernetes-helm gnumake git tailscale
  ];

  # Zsh Shell Configuration
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;

    ohMyZsh = {
      enable = true;
      theme = "robbyrussell";
      plugins = [ "git" "sudo" "systemd" ];
    };

    shellAliases = {
      ls = "eza --icons";
      ll = "eza -lh --icons --git --group-directories-first";
      la = "eza -lah --icons --git --group-directories-first";
      cat = "bat --paging=never";
      ".." = "cd ..";

      # Nix Shortcuts
      nos = "sudo nixos-rebuild switch --flake .";
      noc = "sudo nix-env --profile /nix/var/nix/profiles/system --delete-generations +3 && sudo nix-collect-garbage -d";
      nfn = "nix flake update";
    };
  };
}
