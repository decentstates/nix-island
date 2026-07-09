{ pkgs
, lib
, island
}:

{ profileName
, workspaceRoot # absolute path
, passthroughEnv ? [ ] 
, readOnlyPaths ? [ ]
, readWritePaths ? [ ]
, bindTcpPorts ? [ ] 
, connectTcpPorts ? [ ]
}:

assert lib.assertMsg (lib.hasPrefix "/" (toString workspaceRoot))
  "mkIsland(${profileName}): `workspaceRoot` must be an absolute path";

assert builtins.match "^[A-Za-z0-9-_]+$" profileName != null;

let
  tomlFormat = pkgs.formats.toml { };

  holmRules = {
    abi = 6;
    ruleset = [{
      handled_access_fs = [ "abi.all" ];
      handled_access_net = [ "abi.all" ];
      scoped = [ "abi.all" ];
    }];
    path_beneath = [
      {
        allowed_access = [ "abi.read_write" ];
        parent = [ "/dev/tty" "/dev/pts" "/dev/ptmx" workspaceRoot ]
          ++ readWritePaths;
      }
      {
        allowed_access = [ "read_dir" "read_file" ];
        parent = readOnlyPaths;
      }
    ];
    net_port = [
      {
        allowed_access = [ "connect_tcp" ];
        port = connectTcpPorts;
      }
      {
        allowed_access = [ "bind_tcp" ];
        port = bindTcpPorts;
      } 
    ];
  };

  islandProfile = pkgs.runCommand "holm-${profileName}-island-profile" { } ''
    mkdir -p "$out/landlock"
    cp ${tomlFormat.generate "profile.toml" {
      workspace = false;
      context = [{ when_beneath = toString workspaceRoot; }];
    }} "$out/profile.toml"
    cp ${./island/island-default-base.toml} \
       "$out/landlock/island-default-base.toml"
    cp ${tomlFormat.generate "holm.toml" holmRules} \
       "$out/landlock/20-holm.toml"
  '';
in 
  islandProfile
