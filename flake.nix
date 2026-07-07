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

        # Demo holm — try: nix run .#demo-shell
        demo-shell =
          (import ./nix/mk-holm.nix { inherit pkgs island home-manager; }) {
            name = "demo-shell";
            directory = "/tmp/holm-demo";
            username = "demo";
            tcpPorts = [ 443 ];
            modules = [ ({ pkgs, ... }: {
              home.packages = [ pkgs.ripgrep ];
              programs.bash.enable = true;
            }) ];
          };
      });

      checks = forAllSystems (pkgs: {
        island = self.packages.${pkgs.system}.island;
        demo-shell = self.packages.${pkgs.system}.demo-shell;
      });

      formatter = forAllSystems (pkgs: pkgs.nixpkgs-fmt);

      lib.mkHolm = import ./nix/mk-holm.nix;
    };
}
