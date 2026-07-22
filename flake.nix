{
  description = "nix-housing — island: data-based sandboxing for nix, with home-manager module provided.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, home-manager }@inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages.island = pkgs.callPackage ./nix/pkgs/island/package.nix { };
        formatter = pkgs.nixpkgs-fmt;
      }
    ) //
    {
      lib = import ./nix/lib.nix;
      homeManagerModules.default = import ./nix/home-manager-module.nix;
    };
}
