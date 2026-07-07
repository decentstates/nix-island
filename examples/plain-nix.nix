# Islands with their own home-manager configurations — plain Nix, no flakes.
# Install with:  nix-env -if ./examples/plain-nix.nix
let
  pkgs = import <nixpkgs> { };

  # Any home-manager source works: a channel...
  #   home-manager = <home-manager>;
  # ...or a pinned tarball:
  home-manager = builtins.fetchTarball {
    url = "https://github.com/nix-community/home-manager/archive/master.tar.gz";
    # pin it: sha256 = "...";
  };

  island = pkgs.callPackage ../nix/island-package.nix { };

  mkHolm = import ../nix/mk-holm.nix {
    inherit pkgs island home-manager;
  };
in
{
  work-shell = mkHolm {
    name = "work-shell";
    directory = "/home/alice/islands/work"; # absolute; becomes the holm's $HOME
    landlock.tcpConnectPorts = [ 443 22 ];
    homeManager = {
      username = "alice";
      stateVersion = "25.05";
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
  };

  # A sandboxed runner without home-manager: `untrusted-run npx sketchy-tool`
  untrusted-run = mkHolm {
    name = "untrusted-run";
    profileName = "untrusted";
    directory = "/home/alice/islands/untrusted";
    logAudit = true;
  };
}
