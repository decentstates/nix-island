{
  description = "holm — named, Landlock-sandboxed shells, each furnished by its own home-manager configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems
        (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: rec {
        island = pkgs.callPackage ./nix/island-package.nix { };
        default = island;

        # Hand-built holm (nix-holm core, no home-manager) — try:
        #   nix run .#demo-shell
        demo-shell =
          (import ./nix/mk-holm.nix { inherit pkgs island; }) {
            name = "demo-shell";
            directory = "/tmp/holm-demo";
            packages = [ pkgs.ripgrep ];
            holmFiles = pkgs.writeTextDir ".gitconfig" ''
              [user]
                name = Demo
            '';
            tcpPorts = [ 443 ];
          };

        # Same idea via nix-holm-manager (home-manager inside):
        demo-manager-shell =
          (import ./nix/mk-holm-manager.nix { inherit pkgs island home-manager; }) {
            name = "demo-manager-shell";
            directory = "/tmp/holm-manager-demo";
            username = "demo";
            tcpPorts = [ 443 ];
            modules = [ ({ pkgs, ... }: {
              home.packages = [ pkgs.ripgrep ];
              programs.bash.enable = true;
              programs.git = { enable = true; userName = "Demo"; };
            }) ];
          };
      });

      checks = forAllSystems (pkgs: {
        inherit (self.packages.${pkgs.system}) island demo-shell demo-manager-shell;
      });

      formatter = forAllSystems (pkgs: pkgs.nixpkgs-fmt);

      # nix-holm core: hand-built holms, no home-manager involved.
      # nix-holm core: packages on PATH + a dotfiles derivation
      lib.mkHolm = import ./nix/mk-holm.nix;
      # nix-holm-manager: holms furnished by a home-manager configuration.
      lib.mkHolmManager = import ./nix/mk-holm-manager.nix;
    };
}
