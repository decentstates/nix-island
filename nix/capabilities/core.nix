{ lib, pkgs, island, house, config, libDag, dagOfType, ... }:
let
  tomlFormat = pkgs.formats.toml { };
in
{
  options = {
    # TODO: Add assertion that the last line contains exec and "$@" maybe
    execWrappers = lib.mkOption {
      type = dagOfType lib.types.string;
      default = [];
      description = ''
        Shell script text, that exec each other.

        Should end with something like `exec "$@"`.

        Ordered by home-manager's dagOf type, with hm.dag exposed as libDag, e.g.:
        - libDag.entryBefore
        - libDag.entryAfter
        - libDag.entryAnywhere
        - libDag.entryBetween
      '';
    };

    # TODO: Rename to envVarPassthrough or better
    passthroughEnv = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = ''
        Environment variables preserved across the boundary.
      '';
    };

    landlockConfigs = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = {};
      description = ''
        Store paths of island profile files.
      '';
    };
  };

  execWrappers.dirSetup = lib.entryBefore ["landlock"] ''
    # TODO: Check permissions, don't allow symlinks.
    mkdir -p ${lib.escapeShellArg house.tmpDir}
    chmod 700 ${lib.escapeShellArg house.tmpDir}

    # TODO: Check permissions, don't allow symlinks.
    mkdir -p ${lib.escapeShellArg house.runDir}
    chmod 700 ${lib.escapeShellArg house.runDir}
    
    exec "$@"
    '';

  execWrappers.dirEnvVars = lib.entryAfter ["env-filter"] ''
    export HOME="${lib.escapeShellArg house.houseHomeDir}"
    export TMPDIR=${lib.escapeShellArg house.tmpDir}
    export XDG_RUNTIME_DIR=${lib.escapeShellArg house.runDir}

    exec "$@"
    '';

  execWrappers.profile = lib.entryAfter ["dirEnvVars"] ''
  . /etc/profile
  [ -f "${XDG_STATE_DIR:-~/.local/state}/nix/profile/etc/profile.d/hm-session-vars.sh" ] && \
    . "${XDG_STATE_DIR:-~/.local/state}/nix/profile/etc/profile.d/hm-session-vars.sh"
  '';

  execWrappers.final = lib.entryAfter [ "profile" ] ''
  [ "$#" -gt 0 ] && exec "$@" || exec "$SHELL" -l
  '';
  

  landlockConfigs = {};

  # TODO: fix island or replace.
  execWrappers.landlock =
    let
      profileName = "the-profile";
      islandProfile = pkgs.linkFarm "islandProfile" (
            [{ 
                name = "profile.toml"; 
                path = tomlFormat.generate "profile.toml" {
                  workspace = false;
                  context = [];
                };
            }]
            ++ pkgs.lib.mapAttrsToList (n: p: { name = "landlock/${n}"; path = p; }) config.landlockConfigs
          );

      xdgConfigDir = pkgs.linkFarm "xdgConfig" [ 
          {
            name = "island/profiles/${profileName}";
          }
        ];
    in
    libDag.entryAnywhere ''
        # temporarily set XDG_CONFIG_DIR for the island profile we've created.
        if [ -n "''${XDG_CONFIG_DIR+x}" ]; then 
          restore=(env "XDG_CONFIG_DIR=$XDG_CONFIG_DIR"); 
        else 
          restore=(env -u XDG_CONFIG_DIR); 
        fi
        exec env XDG_CONFIG_DIR=${xdgConfigDir} ${island}/bin/island run -p ${lib.escapeShellArg profileName} -- \
          "''${restore[@]}" "$@"
      '';

  passthroughEnv = [
    "TERM"
    "COLORTERM"
    "LC_ALL"
    "TZ"
    "USER"
    "LOGNAME"
  ];

  execWrappers.envFilter = libDag.entryAfter ["landlock"] ''
    keep=()
    for v in ${toString config.passthroughEnv}; do
      if [ -n "''${!v+x}" ]; then 
        keep+=("$v=''${!v}"); 
      fi
    done
    exec ${pkgs.coreutils}/bin/env -i "''${keep[@]}"  "$@"
    '';
}
