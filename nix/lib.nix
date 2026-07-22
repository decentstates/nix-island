{ pkgs
, lib ? pkgs.lib
, island ? pkgs.callPackage ./island/island-package.nix { }
}:
let
  mkCapabilities = { house, module ? { } }:
    lib.evalModules {
      specialArgs = { inherit pkgs house; };
      modules = [
        ./capabilities/schema.nix
        ./capabilities/defaults.nix
        ./capabilities/dbus.nix
        ./capabilities/gpu.nix
        ./capabilities/wayland.nix
      ] ++ [ module ];
    };
  mkCapabilitiesRunner = { house , capabilitiesModule ? { } }:
    let
      capabilityConfig = (mkCapabilities {
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
    };
  mkHouseProfile = 
    { profileName
    , readOnlyPaths ? [ ]
    , readWritePaths ? [ ]
    , bindTcpPorts ? [ ] 
    , connectTcpPorts ? [ ]
    }:

    assert builtins.match "^[A-Za-z0-9_-]+$" profileName != null;

    let
      tomlFormat = pkgs.formats.toml { };

      netPort =
        (lib.optional (connectTcpPorts != [ ]) {
          allowed_access = [ "connect_tcp" ];
          port = connectTcpPorts;
        })
        ++ (lib.optional (bindTcpPorts != [ ]) {
          allowed_access = [ "bind_tcp" ];
          port = bindTcpPorts;
        });

      pathBeneath = 
        (lib.optional (readWritePaths != [ ]) {
            allowed_access = [ "abi.read_write" ];
            parent = readWritePaths;
        })
        ++
        (lib.optional (readOnlyPaths != [ ]) {
            allowed_access = [ "abi.read_execute" ];
            parent = readOnlyPaths;
        });

      housingRules = {
        abi = 6;
        ruleset = [{
          handled_access_fs = [ "abi.all" ];
          handled_access_net = [ "abi.all" ];
          scoped = [ "abi.all" ];
        }];
      } // lib.optionalAttrs (pathBeneath != [ ]) { path_beneath = pathBeneath; }
        // lib.optionalAttrs (netPort != [ ]) { net_port = netPort; };

      houseProfile = pkgs.runCommand "house-${profileName}-profile" { } ''
        mkdir -p "$out/landlock"
        cp ${tomlFormat.generate "profile.toml" {
          workspace = false;
          context = [];
        }} "$out/profile.toml"
        # TODO: Use the toml file from within the package.
        cp ${./../island/island-default-base.toml} \
           "$out/landlock/island-default-base.toml"
        cp ${tomlFormat.generate "island.toml" housingRules} \
           "$out/landlock/20-housing.toml"
      '';
    in 
      houseProfile;
  mkHouseRunner =
    { runnerName
    , profileName
    , passthroughEnv ? [ ] 
    }:


    assert builtins.match "^[A-Za-z0-9_-]+$" runnerName != null;

    assert lib.assertMsg (lib.all (v: builtins.match "^[A-Za-z_][A-Za-z0-9_]*$" v != null) passthroughEnv)
      "passthroughEnv contains an invalid environment variable name";

    let
      envFilterer = pkgs.writeShellScript "house-${profileName}-shell-filterer" ''
          keep=()
          for v in ${toString passthroughEnv}; do
            if [ -n "''${!v+x}" ]; then keep+=("$v=''${!v}"); fi
          done
          ${pkgs.coreutils}/bin/env -i "''${keep[@]}"  "$@"
      '';

      runner = pkgs.writeShellApplication {
        name = runnerName;
        text = ''
          exec ${island}/bin/island run -p ${lib.escapeShellArg profileName} -- \
            ${envFilterer} "$@"
        '';
      };
    in runner;
in
{
  inherit
  mkHouseRunner
  mkHouseProfile
  mkCapabilities 
  mkCapabilitiesRunner;
}
