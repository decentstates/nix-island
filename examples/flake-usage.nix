# Islands with their own home-manager configurations — flake usage.
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
  # `work-shell`: its own $HOME at ~/islands/work with a work git identity,
  # work-only tools, and network limited to HTTPS + SSH. Your real dotfiles
  # are neither used nor readable inside.
  work-shell = mkHolm {
    name = "work-shell";
    directory = "/home/alice/islands/work";
    landlock.tcpConnectPorts = [ 443 22 ];
    homeManager = {
      username = "alice"; # your real login name
      stateVersion = "25.05";
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
              "~/.ssh/id_work"; # ~ here = the ISLAND's home
          };

          home.sessionVariables.KUBECONFIG = "$HOME/.kube/work.yaml";
        })
      ];
    };
  };

  # `oss-shell`: same machine, completely different identity and toolset,
  # different prompt so you always know where you are.
  oss-shell = mkHolm {
    name = "oss-shell";
    directory = "/home/alice/islands/oss";
    landlock.tcpConnectPorts = [ 443 22 ];
    # Strict mode: only this holm's declared environment (its HM closure)
    # is readable/executable — no blanket /nix/store grant.
    confineToClosure = true;
    homeManager = {
      username = "alice";
      modules = [
        ({ pkgs, ... }: {
          home.packages = with pkgs; [ ripgrep tokei ];
          programs.zsh.enable = true;
          programs.git = {
            enable = true;
            userName = "alicehacks";
            userEmail = "alice@personal.example";
            signing.signByDefault = false;
          };
        })
      ];
    };
    # Enter with zsh instead of the default bash login shell:
    command = [ "${pkgs.zsh}/bin/zsh" "-l" ];
  };

  # `scratch-shell`: no home-manager at all — just a jailed throwaway shell
  # (Island's own workspace isolation is used instead).
  scratch-shell = mkHolm {
    name = "scratch-shell";
    directory = "/home/alice/islands/scratch";
  };
}
