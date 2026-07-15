{ pkgs
, lib ? pkgs.lib
, island ? pkgs.callPackage ./island/island-package.nix { }
}:

{
  mkIslandRunner = import ./lib/mk-island-runner.nix { inherit pkgs lib island; };
  mkIslandProfile = import ./lib/mk-island-profile.nix { inherit pkgs lib island; };
  evalCapabilities = import ./lib/capabilities/eval.nix { inherit pkgs lib; };
  mkCapabilitiesRunner = import ./lib/mk-capabilities-runner.nix { inherit pkgs lib island; };
}
