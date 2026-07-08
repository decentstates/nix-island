# Core, plain Nix, no home-manager: nix-env -if ./examples/plain-nix.nix
let
  pkgs = import <nixpkgs> { };
  mkHolm = import ../nix/mk-holm.nix { inherit pkgs; };
in
{
  work-shell = mkHolm {
    name = "work-shell";
    directory = "/home/alice/islands/work";
    packages = with pkgs; [ ripgrep jq git ];
    environment.EDITOR = "vi";
    tcpPorts = [ 443 22 ];
    holmFiles = pkgs.runCommand "work-dotfiles" { } ''
      mkdir -p "$out"
      printf '[user]\n  name = Alice\n  email = alice@corp.example\n' \
        > "$out/.gitconfig"
    '';
  };
}
