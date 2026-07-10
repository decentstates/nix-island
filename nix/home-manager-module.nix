{ config, inputs, lib, pkgs, modulesPath, ... }:

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
        default = [ 
        ];
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
                    bindTcpPorts connectTcpPorts;
          # TODO: Determine these programatically:
        readOnlyPaths = i.readOnlyPaths ++ [
            "${config.home.homeDirectory}/.local/share/island-cache-profiles/${i.profileName}"
            "${config.home.homeDirectory}/.config/island-cache-profiles/${i.profileName}"
        ];
        readWritePaths = i.readWritePaths ++ [
            "${config.home.homeDirectory}/.local/state/island-cache-profiles/${i.profileName}"
            "${config.home.homeDirectory}/.cache/island-cache-profiles/${i.profileName}"
        ];
        # Requires an absolute root
        workspaceRoot = "${config.home.homeDirectory}/${i.workspaceRoot}";
      }; 
      mkIslandHm = i: import modulesPath {
        inherit pkgs;
        check = true;
        # TODO: make this an option
        extraSpecialArgs = {
          inherit inputs;
        };
        configuration = { ... }: {
          imports = i.modules;
          home = {
            inherit (config.home) username stateVersion;
            homeDirectory = "${config.home.homeDirectory}/${i.workspaceRoot}";
          };
          xdg = {
            enable = true;
            # TODO: Determine these programatically:
            dataHome = "/.local/share/island-data-profiles/${i.profileName}";
            configHome = "/.config/island-config-profiles/${i.profileName}";
            stateHome = "/.local/state/island-state-profiles/${i.profileName}";
            cacheHome = "/.cache/island-cache-profiles/${i.profileName}";
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
            export HOME="${config.home.homeDirectory}/${i.workspaceRoot}"
            exec ${(mkIslandHm i).activationPackage}/activate
            '';
          in
          ''
            if [ -e "$HOME/.nix-profile" ]; then
                warnEcho "nix-island: WARNING: ~/.nix-profile exists."
                warnEcho "nix-island: Home-manager now stores profiles under XDG dirs allowing isolation."
                warnEcho "nix-island: You still have the legacy profile link, this will prevent environment isolation."
                warnEcho "nix-island: It should be safe to delete it AFAIK:"
                warnEcho "nix-island:    rm ~/.nix-profile"
            fi

            # HACK: Island requires this variable but it is only present if the user is logged in.
            export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/tmp/run/user/$(id -u)}"
            mkdir -p $XDG_RUNTIME_DIR
            run ${mkRunner i}/bin/${(mkRunner i).name} \
              ${activate}
          ''))) cfg.islands;
    });
}
