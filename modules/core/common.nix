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
          curl wget git unzip zip tree cacert
          iproute2 iputils bind
          procps psmisc
          kubectl kubernetes-helm jq
          neovim
          eza bat fzf
        ];
      };

      fonts = {
        packages = with pkgs; [
          nerd-fonts.jetbrains-mono
        ];
        fontconfig.enable = true;
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
      programs = {
        virt-manager.enable = true;
        fzf = {
          fuzzyCompletion = true;
          keybindings = true;
        };
        zsh = {
          enable = true;
          enableCompletion = true;
          autosuggestions.enable = true;
          syntaxHighlighting.enable = true;
          ohMyZsh = {
            enable = true;
            theme = "agnoster";
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
            k = "kubectl";
            kgp = "kubectl get pods";
            kgpa = "kubectl get pods -A";
            kgs = "kubectl get svc";
            kgn = "kubectl get nodes";
            kgd = "kubectl get deployments";
            kgi = "kubectl get ingress";
            kaf = "kubectl apply -f";
            kdel = "kubectl delete";
            kdelf = "kubectl delete -f";
            kdesc = "kubectl describe";
            klog = "kubectl logs -f";
            kex = "kubectl exec -it";
            kctx = "kubectl config current-context";
            kns = "kubectl config set-context --current --namespace";
            kaml = "kubectl get -o yaml";
            ktop = "kubectl top pods";
          };
          interactiveShellInit = ''
            node-login() {
              local target="$1"
              if [[ -z "$target" ]]; then
                echo "Usage: node-login <midguard-01|midguard-02>"
                return 1
              fi
              sudo ssh -i /etc/ssh/ssh_host_ed25519_key homelabadmin@"$target"
            }
          '';
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
