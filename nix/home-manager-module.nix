hmArgs@{ config, inputs, lib, pkgs, modulesPath, ... }:

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

      tmpDir = i: "/tmp/island-${config.home.username}-${i.profileName}";

      mkRunner = i:
        let 
          inner = pkgs.writeShellScript "activate" ''
            set -e

            export HOME="${config.home.homeDirectory}/${i.workspaceRoot}"
            export TMPDIR="${tmpDir i}"
            # This enables everything else to work
            export XDG_STATE_HOME="${config.home.homeDirectory}/${i.workspaceRoot}/.local/state"

            # TODO: Which first?
            . ${(mkIslandHm i).activationPackage}/home-path/etc/profile.d/hm-session-vars.sh
            . /etc/profile

            [ "$#" -gt 0 ] && exec "$@" || exec "$SHELL" -l
          '';
          outer =
            islandLib.mkIslandRunner {
              inherit (i) runnerName profileName passthroughEnv;
            };
        in
        pkgs.writeShellApplication {
          name = outer.name;
          text = ''
          # HACK: This won't work for nested islands... maybe just don't support:
          # TODO: Block nested islands.
          mkdir -p ${tmpDir i}

          exec ${outer}/bin/${outer.name} ${inner} "$@"
          '';
        };
      
      mkProfile = i: islandLib.mkIslandProfile {
        inherit (i) profileName passthroughEnv
                    bindTcpPorts connectTcpPorts;
        readWritePaths = i.readWritePaths ++ [
            "${config.home.homeDirectory}/${i.workspaceRoot}"
            (tmpDir i)
        ];
      }; 
      mkIslandHm = i: import modulesPath {
        inherit pkgs;
        check = true;
        # HACK: But should be stable as HM adding extra args is a breaking
        #       change to their API, with nix used namespaces more...
        extraSpecialArgs = builtins.removeAttrs hmArgs.specialArgs [                                
         "modulesPath" "lib" "osConfig" "osClass"
        ];
        configuration = innerHomeManagerArgs:
          let
            innerConfig = innerHomeManagerArgs.config;
          in
          {
            imports = i.modules;
            home = {
              inherit (config.home) username stateVersion;
              homeDirectory = "${config.home.homeDirectory}/${i.workspaceRoot}";
              sessionVariables = {
                HOME = innerConfig.home.homeDirectory;
                TMPDIR = (tmpDir i);
                ISLAND_NAME = i.profileName;
                # Used directly in Fish shell, added into other shells below:
                SHELL_PROMPT_PREFIX = "⟦${i.profileName}⟧ ";
              };
            };
            programs.bash.initExtra = lib.mkAfter ''
              PS1="$SHELL_PROMPT_PREFIX$PS1"
            '';
            programs.zsh.initContent = lib.mkOrder 1500 ''
              PROMPT="$SHELL_PROMPT_PREFIX$PROMPT"
            '';
            xdg = {
              enable = true;
            };
          };
      };
    in
    {
      home.packages =
        [ cfg.package ] 
          ++ lib.mapAttrsToList (_: i: mkRunner i) cfg.islands;


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
           ''
             set -euo pipefail

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

             run ${mkRunner i}/bin/${(mkRunner i).name} ${(mkIslandHm i).activationPackage}/activate
           ''))) cfg.islands;
    });
}
