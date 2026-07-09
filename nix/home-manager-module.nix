# home-manager module: declare holms inside your home-manager
# configuration. Each holm.holms.<name> evaluates a nested HM home — via
# this home-manager's own modulesPath, so no separate input — and
# installs an executable of the same name. username/stateVersion come
# from the outer home; packages come from the holm's home.packages.
{ config, lib, pkgs, modulesPath, ... }:

let
  cfg = config.island;
  islandLib = import ./lib.nix { inherit pkgs; island = cfg.package; };

  evalHome = i: import modulesPath {
    inherit pkgs;
    configuration = {
      imports = i.modules;
      home = {
        inherit (config.home) username stateVersion;
        homeDirectory = i.workspaceRoot;
      };
    };
  };

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
        default = "${config.home.homeDirectory}/islands/${name}";
        description = "The island workspace root.";
      };
      modules = lib.mkOption {
        type = lib.types.listOf lib.types.deferredModule;
        default = [ ];
        description = "The holm's home-manager modules.";
      };
      passthroughEnv = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = islandLib.defaultPassEnv;
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

  config = lib.mkIf config.myModule.enable (
    lib.mkMerge [
      { home.packages = [ cfg.island ]; }
      (lib.mapAttrsToList
       (name: i: 
          let
            runner = islandLib.mkIslandRunner 
              { name = i.runnerName; inherit (i) profileName passthroughEnv; };
            profile = islandLib.mkIslandProfile
              { inherit (i) name;
                inherit (i) workspaceRoot passthroughEnv readOnlyPaths readWritePaths bindTcpPorts connectTcpPorts;
              };
            islandHomeManagerConfig = lib.homeManagerConfiguration (i: {
              imports = i.modules;
              home = {
                inherit (config.home) username stateVersion;
                # TODO: Check
                # homeDirectory = i.workspaceRoot;
              };
            });
          in
            {
              home.packages = [ runner ];
              xdg.configFile."island/profiles/${i.profileName}" = {
                source = profile;
                recursive = true;
              };

              home.activation."island-nested-home-manager-activate-${i.profileName}" =
                lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                  run ${runner}/bin/${runner.name} \
                    ${islandHomeManagerConfig.activationPackage}/activate
                '';
            }
       )
       cfg.islands)
   ]);
}
