# Flake usage. Inputs: nixpkgs, home-manager (follows nixpkgs),
# nix-holm.url = "github:youruser/nix-holm". Install the results anywhere
# (systemPackages, your real HM's home.packages, nix profile install).
{ pkgs, home-manager, nix-holm }:

let
  island = nix-holm.packages.${pkgs.system}.island;

  mkHolm = nix-holm.lib.mkHolm { inherit pkgs island; };
  mkHolmManager = nix-holm.lib.mkHolmManager {
    inherit pkgs island home-manager;
  };
in
{
  # Hand-built (core): `holmFiles` is any derivation.
  plain-shell = mkHolm {
    name = "plain-shell";
    directory = "/home/alice/islands/plain";
    packages = with pkgs; [ ripgrep jq ];
    environment.EDITOR = "vi";
    holmFiles = pkgs.runCommand "plain-dotfiles" { } ''
      mkdir -p "$out"
      printf '[user]\n  name = Alice\n  email = alice@example.invalid\n' \
        > "$out/.gitconfig"
    '';
  };

  work-shell = mkHolmManager {
    name = "work-shell";
    directory = "/home/alice/islands/work";
    username = "alice";
    tcpPorts = [ 443 22 ];
    modules = [
      ({ pkgs, ... }: {
        home.packages = with pkgs; [ ripgrep jq gh kubectl ];

        programs.bash.enable = true;
        programs.starship.enable = true;

        programs.git = {
          enable = true;
          userName = "Alice @ Work";
          userEmail = "alice@corp.example";
        };

        programs.ssh = {
          enable = true;
          # ~ = the HOLM's home
          matchBlocks."git.corp.example".identityFile = "~/.ssh/id_work";
        };

        home.sessionVariables.KUBECONFIG = "$HOME/.kube/work.yaml";
      })
    ];
  };

  oss-shell = mkHolmManager {
    name = "oss-shell";
    directory = "/home/alice/islands/oss";
    username = "alice";
    tcpPorts = [ 443 22 ];
    shell = pkgs.zsh; # pair with programs.zsh.enable
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

  # no tcpPorts = offline
  untrusted-run = mkHolmManager {
    name = "untrusted-run";
    directory = "/home/alice/islands/untrusted";
    username = "alice";
    modules = [ ({ pkgs, ... }: { home.packages = [ pkgs.nodejs ]; }) ];
  };
}
