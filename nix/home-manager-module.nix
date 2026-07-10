{ config, lib, pkgs, modulesPath, ... }:

let
  cfg = config.island;
  islandLib = import ./lib.nix { inherit pkgs; island = config.island.package; };

  islandModule = { name, ... }: {
    options = {
      profileName = lib.mkOption {
        type = lib.types.strMatching "[a-zA-Z0-9_-]+";
        default =  "${name}";
        description = "Island profile name";
      };
      runnerName = lib.mkOption {
        type = lib.types.strMatching "[a-zA-Z0-9_-]+";
        default =  "island-${name}";
        description = "Island runner executable name";
      };
      workspaceRoot = lib.mkOption {
        type = lib.types.str;
        default = "islands/${name}";
        description = "The island workspace root.";
      };
      modules = lib.mkOption {
        type = lib.types.listOf lib.types.deferredModule;
        default = [ ];
        description = "The island's home-manager modules.";
      };
      passthroughEnv = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = islandLib.defaultPassthroughEnv;
        description = "Variables to pass into the island environment";
      };
      readOnlyPaths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Extra hierarchies readable inside.";
      };
      readWritePaths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Extra hierarchies read/writable inside.";
      };
      bindTcpPorts = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        default = [ ];
        description = "TCP ports binable inside.";
      };
      connectTcpPorts = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        default = [ ];
        description = "TCP ports connectable to inside.";
      };
    };
  };
in
{
  options.island = {
    enable = lib.mkEnableOption "Enable island.";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./island/island-package.nix { };
      description = "Island package.";
    };
    islands = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule islandModule);
      default = { };
      description = "Island sandbox profiles";
    };
  };

  config = lib.mkIf config.island.enable (
    let
      cfg = config.island;
      islandLib = import ./lib.nix { inherit pkgs; island = cfg.package; };

      mkRunner = i: islandLib.mkIslandRunner {
        inherit (i) runnerName profileName passthroughEnv;
      };
      mkProfile = i: islandLib.mkIslandProfile {
        inherit (i) profileName passthroughEnv
                    readOnlyPaths readWritePaths bindTcpPorts connectTcpPorts;
        # Requires an absolute root
        workspaceRoot = "${config.home.homeDirectory}/${i.workspaceRoot}";
      }; 
      mkIslandHm = i: import modulesPath {
        inherit pkgs;
        check = true;
        configuration = { ... }: {
          imports = i.modules;
          home = {
            inherit (config.home) username stateVersion homeDirectory;
          };
        };
      };
    in
    {
      home.packages =
        [ cfg.package ] ++ lib.mapAttrsToList (_: i: mkRunner i) cfg.islands;

      xdg.configFile = lib.mapAttrs' (_: i:
        lib.nameValuePair "island/profiles/${i.profileName}" {
          source = mkProfile i;
          recursive = true;
        }) cfg.islands;

      home.file = lib.mapAttrs' (_: i:
        lib.nameValuePair "${i.workspaceRoot}/.keep" { text = ""; }) cfg.islands;

      home.activation = lib.mapAttrs' (_: i:
        lib.nameValuePair "island-nested-home-manager-activate-${i.profileName}"
          (lib.hm.dag.entryAfter [ "writeBoundary" "linkGeneration" "installPackages"] (
          let 
            activate = pkgs.writeShellScript "activate" ''
            export PATH="$PATH:${pkgs.nix}/bin"
            exec ${(mkIslandHm i).activationPackage}/activate
            '';
          in
          ''
            run ${mkRunner i}/bin/${(mkRunner i).name} \
              ${activate}
          ''))) cfg.islands;
    });
}
