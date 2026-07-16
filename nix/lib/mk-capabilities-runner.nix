{ pkgs
, lib
, island
}:

let
  mkHouseRunner = import ./mk-house-runner.nix { inherit pkgs lib island; };
  evalCapabilities = import ./capabilities/eval.nix { inherit pkgs lib; };
in

{ house
, capabilitiesModule ? { }
}:

let
  capabilityConfig = (evalCapabilities {
    inherit house;
    module = capabilitiesModule;
  }).config;

  houseRunner = mkHouseRunner {
    inherit (house) runnerName profileName;
    inherit (capabilityConfig) passthroughEnv;
  };
in
pkgs.writeShellApplication {
  name = house.runnerName;
  text = ''
    exec ${toString capabilityConfig.execWrappers} \
      ${houseRunner}/bin/${house.runnerName} "$@"
  '';
}
