# Holms with their own home-manager configurations — flake usage.
#
# In your own flake:
#
#   inputs = {
#     nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
#     home-manager.url = "github:nix-community/home-manager";
#     home-manager.inputs.nixpkgs.follows = "nixpkgs";
#     nix-holm.url = "github:youruser/nix-holm";
#   };
#
# then build shells like below and install them wherever you like
# (environment.systemPackages, home.packages of your *real* home-manager,
# nix profile install, ...).
{ pkgs, home-manager, nix-holm }:

let
  mkHolm = nix-holm.lib.mkHolm {
    inherit pkgs home-manager;
    island = nix-holm.packages.${pkgs.system}.island;
  };
in
{
  # `work-shell`: its own $HOME at ~/islands/work with a work git identity
  # and work-only tools; TCP limited to HTTPS + SSH. Your real dotfiles are
  # neither used nor readable inside.
  work-shell = mkHolm {
    name = "work-shell";
    directory = "/home/alice/islands/work";
    username = "alice";
    tcpPorts = [ 443 22 ];
    modules = [
      ({ pkgs, ... }: {
        home.packages = with pkgs; [ ripgrep jq gh kubectl ];

        programs.bash.enable = true; # gives the holm its own .bashrc
        programs.starship.enable = true;

        programs.git = {
          enable = true;
          userName = "Alice @ Work";
          userEmail = "alice@corp.example";
        };

        programs.ssh = {
          enable = true;
          matchBlocks."git.corp.example".identityFile =
            "~/.ssh/id_work"; # ~ here = the HOLM's home
        };

        home.sessionVariables.KUBECONFIG = "$HOME/.kube/work.yaml";
      })
    ];
  };

  # `oss-shell`: same machine, completely different identity, toolset, and
  # shell — so you always know where you are.
  oss-shell = mkHolm {
    name = "oss-shell";
    directory = "/home/alice/islands/oss";
    username = "alice";
    tcpPorts = [ 443 22 ];
    shell = pkgs.zsh; # pair with programs.zsh.enable for its own zshrc
    modules = [
      ({ pkgs, ... }: {
        home.packages = with pkgs; [ ripgrep tokei ];
        programs.zsh.enable = true;
        programs.git = {
          enable = true;
          userName = "alicehacks";
          userEmail = "alice@personal.example";
        };
      })
    ];
  };

  # `untrusted-run`: a minimal offline holm for running sketchy things —
  # `untrusted-run npx some-tool`. No tcpPorts = no network.
  untrusted-run = mkHolm {
    name = "untrusted-run";
    directory = "/home/alice/islands/untrusted";
    username = "alice";
    modules = [ ({ pkgs, ... }: { home.packages = [ pkgs.nodejs ]; }) ];
  };
}
