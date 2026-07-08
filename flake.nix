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
          (self.lib.mkHolm { inherit pkgs island; }) {
            name = "demo-shell";
            directory = "/tmp/holm-demo";
            packages = [ pkgs.ripgrep ];
            holmFiles = pkgs.writeTextDir ".gitconfig" ''
              [user]
                name = Demo
            '';
            tcpPorts = [ 443 ];
          };

      });

      checks = forAllSystems (pkgs: {
        inherit (self.packages.${pkgs.system}) island demo-shell;
        # building the outer home transitively builds the holm wrapper
        hm-module = (home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            self.homeManagerModules.holm
            {
              home = {
                username = "demo";
                homeDirectory = "/tmp/holm-demo-home";
                stateVersion = "25.05";
              };
              holm.holms.demo-home-shell.modules =
                [{ programs.bash.enable = true; }];
            }
          ];
        }).activationPackage;
      });

      formatter = forAllSystems (pkgs: pkgs.nixpkgs-fmt);

      lib = import ./nix/lib.nix; # { mkHolm, defaultPassEnv }

      homeManagerModules = rec {
        holm = import ./nix/home-manager-module.nix; # holm.holms.<name>
        default = holm;
      };
    };
}
