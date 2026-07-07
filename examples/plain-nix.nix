# Plain Nix, no flakes: nix-env -if ./examples/plain-nix.nix
let
  pkgs = import <nixpkgs> { };

  # a channel (<home-manager>) or a pinned tarball both work
  home-manager = builtins.fetchTarball {
    url = "https://github.com/nix-community/home-manager/archive/master.tar.gz";
    # pin it: sha256 = "...";
  };

  # core instead: import ../nix/mk-holm.nix, pass packages + holmFiles
  mkHolmManager = import ../nix/mk-holm-manager.nix {
    inherit pkgs home-manager;
  };
in
{
  work-shell = mkHolmManager {
    name = "work-shell";
    directory = "/home/alice/islands/work";
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
