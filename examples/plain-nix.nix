# Holms — plain Nix, no flakes. Install with:
#   nix-env -if ./examples/plain-nix.nix
let
  pkgs = import <nixpkgs> { };

  # Any home-manager source works: a channel (<home-manager>) or a tarball:
  home-manager = builtins.fetchTarball {
    url = "https://github.com/nix-community/home-manager/archive/master.tar.gz";
    # pin it: sha256 = "...";
  };

  mkHolm = import ../nix/mk-holm.nix { inherit pkgs home-manager; };
in
{
  work-shell = mkHolm {
    name = "work-shell";
    directory = "/home/alice/islands/work"; # absolute; the holm's $HOME
    username = "alice";
    tcpPorts = [ 443 22 ];
    modules = [
      ({ pkgs, ... }: {
        home.packages = with pkgs; [ ripgrep jq ];
        programs.bash.enable = true;
        programs.git = {
          enable = true;
          userName = "Alice @ Work";
          userEmail = "alice@corp.example";
        };
      })
    ];
  };
}
