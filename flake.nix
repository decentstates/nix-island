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

        # Pure demo (no home-manager): a throwaway jailed shell — try:
        #   nix run .#demo-shell
        # For holms with their own home-manager configuration, see
        # examples/flake-usage.nix (those need your real username, so
        # they can't be a generic flake output).
        demo-shell =
          (import ./nix/mk-holm.nix { inherit pkgs island; }) {
            name = "demo-shell";
            directory = "/tmp/holm-demo";
            landlock.tcpConnectPorts = [ 443 ];
          };
      });

      checks = forAllSystems (pkgs: {
        island = self.packages.${pkgs.system}.island;
        demo-shell = self.packages.${pkgs.system}.demo-shell;
      });

      formatter = forAllSystems (pkgs: pkgs.nixpkgs-fmt);

      overlays.default = final: _prev: {
        island = final.callPackage ./nix/island-package.nix { };
      };

      # Plain-Nix API:
      #   let mkHolm = nix-holm.lib.mkHolm { inherit pkgs home-manager island; };
      #   in mkHolm { name = "work-shell"; homeManager = { ... }; ... }
      lib.mkHolm = import ./nix/mk-holm.nix;
      lib.mkHolmHome = import ./nix/mk-holm-home.nix;
      lib.landlockPolicy = import ./nix/mk-landlock-policy.nix; # { defaults, mkPolicy }
    };
}
