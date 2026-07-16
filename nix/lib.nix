{ pkgs
, lib ? pkgs.lib
, island ? pkgs.callPackage ./island/island-package.nix { }
}:

{
  mkHouseRunner = import ./lib/mk-house-runner.nix { inherit pkgs lib island; };
  mkHouseProfile = import ./lib/mk-house-profile.nix { inherit pkgs lib island; };
  evalCapabilities = import ./lib/capabilities/eval.nix { inherit pkgs lib; };
  mkCapabilitiesRunner = import ./lib/mk-capabilities-runner.nix { inherit pkgs lib island; };
}
