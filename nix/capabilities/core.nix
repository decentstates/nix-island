{ lib, pkgs, island, houseContext, config, libDag, dagOfType, ... }:
let
  tomlFormat = pkgs.formats.toml { };
in
{
  options = {
    execWrappers = lib.mkOption {
      type = dagOfType lib.types.str;
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

    envPassthrough = lib.mkOption {
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

  config = {
    execWrappers.dirSetup = libDag.entryBefore ["landlock" "dirEnvVars"] ''
      set -eu

      # Ensures no symlink along path, mkdir, permissions
      ensure_dir() {
        d=$1
        case $d in
          /*) ;;
          *) echo "housing: refusing $d: not an absolute path" >&2; exit 1 ;;
        esac
        cur=
        IFS=/
        set -f
        for comp in $d; do
          [ -n "$comp" ] || continue
          cur="$cur/$comp"
          if [ -L "$cur" ]; then
            echo "housing: refusing $cur: is a symlink" >&2
            exit 1
          fi
          if [ ! -e "$cur" ]; then
            mkdir "$cur"
          elif [ ! -d "$cur" ]; then
            echo "housing: refusing $cur: not a directory" >&2
            exit 1
          fi
        done
        set +f
        unset IFS
        if [ "$(${pkgs.coreutils}/bin/stat -c %u "$d")" != "$(${pkgs.coreutils}/bin/id -u)" ]; then
          echo "housing: refusing $d: not owned by the current user" >&2
          exit 1
        fi
        chmod 700 "$d"
      }

      ensure_dir ${lib.escapeShellArg houseContext.houseHomeDir}
      ensure_dir ${lib.escapeShellArg houseContext.tmpDir}
      ensure_dir ${lib.escapeShellArg houseContext.runDir}

      exec "$@"
      '';

    execWrappers.dirEnvVars = libDag.entryAfter ["envFilter"] ''
      export HOME=${lib.escapeShellArg houseContext.houseHomeDir}
      export TMPDIR=${lib.escapeShellArg houseContext.tmpDir}
      export XDG_RUNTIME_DIR=${lib.escapeShellArg houseContext.runDir}

      exec "$@"
      '';

    execWrappers.profile = libDag.entryAfter ["dirEnvVars"] ''
      . /etc/profile
      [ -f "''${XDG_STATE_HOME:-$HOME/.local/state}/nix/profile/etc/profile.d/hm-session-vars.sh" ] && \
        . "''${XDG_STATE_HOME:-$HOME/.local/state}/nix/profile/etc/profile.d/hm-session-vars.sh"
      exec "$@"
      '';

    execWrappers.final = libDag.entryAfter [ "profile" ] ''
      [ "$#" -gt 0 ] && exec "$@" || exec "''${SHELL:-/bin/sh}" -l
      '';

    execWrappers.namespacing = libDag.entryBetween ["final"] ["landlock"] ''
      # Rudimentary PID namespacing to hide other processes
      # TODO: Find out if landlock can show /proc/self successfully...
      # TODO: LIMITATION: This doesn't hide other /proc files.
      exec ${pkgs.util-linux}/bin/unshare --user --map-current-user --mount --pid --fork --mount-proc -- ${pkgs.tini}/bin/tini -- "$@"
    '';
    

    landlockConfigs = {};

    # TODO: fix island or replace.
    execWrappers.landlock =
      let
        profileName = "the-profile";
        profileToml = tomlFormat.generate "profile.toml" {
          workspace = false;
          context = [];
        };
        profileDir = "island/profiles/${profileName}";
        xdgConfigDir = pkgs.runCommand "xdgConfig" { } (''
          mkdir -p "$out/${profileDir}"
          cp ${profileToml} "$out/${profileDir}/profile.toml"
        '' + lib.concatStrings (lib.mapAttrsToList (n: p: ''
          mkdir -p "$out/${profileDir}/landlock"
          cp ${p} "$out/${profileDir}/landlock/${n}.toml"
        '') config.landlockConfigs));
      in
      libDag.entryAnywhere ''
          # temporarily set XDG_CONFIG_HOME for the island profile we've created.
          if [ -n "''${XDG_CONFIG_HOME+x}" ]; then 
            restore=(env "XDG_CONFIG_HOME=$XDG_CONFIG_HOME"); 
          else 
            restore=(env -u XDG_CONFIG_HOME); 
          fi
          exec env XDG_CONFIG_HOME=${xdgConfigDir} ${island}/bin/island run -p ${lib.escapeShellArg profileName} -- \
            "''${restore[@]}" "$@"
        '';

    envPassthrough = [
      "TERM"
      "COLORTERM"
      "LC_ALL"
      "TZ"
      "USER"
      "LOGNAME"
    ];

    execWrappers.envFilter = (
      assert lib.assertMsg (lib.all (v: builtins.match "^[A-Za-z_][A-Za-z0-9_]*$" v != null) config.envPassthrough)
        "envPassthrough contains an invalid environment variable name";
      libDag.entryAfter ["landlock"] ''
        keep=()
        for v in ${toString config.envPassthrough}; do
          if [ -n "''${!v+x}" ]; then 
            keep+=("$v=''${!v}"); 
          fi
        done
        exec ${pkgs.coreutils}/bin/env -i "''${keep[@]}"  "$@"
        ''
    );
  };
}
