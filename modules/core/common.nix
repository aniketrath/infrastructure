{ lib, pkgs, config, ... }:

let
  secrets = import ../../secrets/secrets.nix;
in
{
  imports = [
    ./auto-upgrade.nix
  ];
  options.myNetwork = {
    staticIPv4 = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "192.168.1.101";
      description = "Static IPv4 address for this host. Leave null (default) to keep DHCP.";
    };
    prefixLength = lib.mkOption {
      type = lib.types.int;
      default = 24;
      description = "CIDR prefix length to pair with staticIPv4.";
    };
    gateway = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Default gateway address. Required when staticIPv4 is set.";
    };
    interface = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "enp1s0";
      description = "Network interface to assign staticIPv4 to. Required when staticIPv4 is set. Check with `ip a` on the target host.";
    };
    nameservers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "1.1.1.1" "9.9.9.9" ];
      description = "Resolver nameservers, used only when staticIPv4 is set.";
    };
  };

  config = lib.mkMerge [
    {
      boot = {
        loader.systemd-boot.configurationLimit = 2;
        kernelModules = [ "kvm-amd" "kvm-intel" ];
      };
      nix = {
        gc = {
          automatic = true;
          dates = "weekly";
          options = "--delete-older-than 14d";
        };
        settings = {
          auto-optimise-store = true;
          experimental-features = [ "nix-command" "flakes" ];
          trusted-users = [ "root" "homelabadmin" ];
        };
      };
      system.stateVersion = "26.05";
      environment = {
        enableAllTerminfo = true;
        systemPackages = with pkgs; [
          curl neovim vim wget eza bat jdk21_headless traceroute bind nettools iputils glances lsof
          strace tcpdump ncdu jq iproute2 procps psmisc tree unzip zip cacert gnupg git
          qemu virt-manager virtiofsd kubernetes-helm gnumake git tailscale
        ];
      };
      security.sudo.wheelNeedsPassword = false;
      users = {
        mutableUsers = false;
        defaultUserShell = pkgs.zsh;
        groups.libvirtd.members = [ "homelabadmin" ];
        users = {
          root.shell = pkgs.zsh;
          homelabadmin = {
            isNormalUser = true;
            shell = pkgs.zsh;
            extraGroups = [ "wheel" "libvirtd" "kvm" "qemu" "kubectl"];
            hashedPasswordFile = config.age.secrets.homelabadmin-password.path;
            openssh.authorizedKeys.keys = secrets.__access_keys;
          };
        };
      };
      # Virtualization
      programs.virt-manager.enable = true;
      virtualisation = {
        spiceUSBRedirection.enable = true;
        libvirtd = {
          enable = true;
          qemu = {
            package = pkgs.qemu;
            swtpm.enable = true;
          };
        };
      };
      # Services
      services = {
        journald.extraConfig = ''
          Storage=persistent
          SystemMaxUse=4G
          SystemKeepFree=20%
          MaxRetentionSec=14day
          Compress=yes
        '';
        logrotate = {
          enable = true;
          settings = {
            header = {
              global = true;
              dateext = true;
              compress = true;
              delaycompress = true;
              missingok = true;
              notifempty = true;
            };
            "/var/log/*.log" = {
              frequency = "daily";
              rotate = 7;
              maxsize = "50M";
            };
          };
        };
        openssh = {
          enable = true;
          ports = [ 22 ];
          settings = {
            PasswordAuthentication = false;
            PermitRootLogin = "no";
          };
        };
        tailscale.enable = true;
        avahi = {
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
      };
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
          c = "clear";
          e = "exit";
          ls = "eza --icons";
          ll = "eza -lh --icons --git --group-directories-first";
          la = "eza -lah --icons --git --group-directories-first";
          cat = "bat --paging=never";
          ".." = "cd ..";
          nos = "sudo nixos-rebuild switch --flake .";
          noc = "sudo nix-env --profile /nix/var/nix/profiles/system --delete-generations +3 && sudo nix-collect-garbage -d";
          nfn = "nix flake update";
        };
      };
    }
    (lib.mkIf (config.myNetwork.staticIPv4 != null) {
      assertions = [
        {
          assertion = config.myNetwork.interface != null;
          message = "modules/core/common.nix: myNetwork.interface must be set when myNetwork.staticIPv4 is set.";
        }
        {
          assertion = config.myNetwork.gateway != null;
          message = "modules/core/common.nix: myNetwork.gateway must be set when myNetwork.staticIPv4 is set.";
        }
      ];
      networking.interfaces.${config.myNetwork.interface} = {
        useDHCP = false;
        ipv4.addresses = [
          {
            address = config.myNetwork.staticIPv4;
            prefixLength = config.myNetwork.prefixLength;
          }
        ];
      };
      networking.defaultGateway = config.myNetwork.gateway;
      networking.nameservers = config.myNetwork.nameservers;
    })
  ];
}