{ pkgs
, lib
, island
}:

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
  houseProfile
