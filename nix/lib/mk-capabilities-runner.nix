{ pkgs
, lib
, island
}:

let
  mkIslandRunner = import ./mk-island-runner.nix { inherit pkgs lib island; };
  evalCapabilities = import ./capabilities/eval.nix { inherit pkgs lib; };
in

{ island
, capabilitiesModule ? { }
}:

let
  capabilityConfig = (evalCapabilities {
    inherit island;
    module = capabilitiesModule;
  }).config;

  islandRunner = mkIslandRunner {
    inherit (island) runnerName profileName;
    inherit (capabilityConfig) passthroughEnv;
  };
in
pkgs.writeShellApplication {
  name = island.runnerName;
  text = ''
    exec ${toString capabilityConfig.execWrappers} \
      ${islandRunner}/bin/${island.runnerName} "$@"
  '';
}
