{ lib, pkgs, house, config, ... }:

let
  setupWrapper = pkgs.writeShellScript "house-${house.profileName}-setup" ''
    set -euo pipefail

    # TODO: Check permissions on these dirs
    mkdir -p ${lib.escapeShellArg house.tmpDir}
    chmod 700 ${lib.escapeShellArg house.tmpDir}
    export ORIGINAL_TMPDIR="''${TMPDIR:-/tmp}"
    export TMPDIR=${lib.escapeShellArg house.tmpDir}

    mkdir -p ${lib.escapeShellArg house.runDir}
    chmod 700 ${lib.escapeShellArg house.runDir}
    export ORIGINAL_XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-}"
    export XDG_RUNTIME_DIR=${house.runDir}

    # Landlock doesn't make it easy to allow access to /proc/self, so we get a private /proc and allow that:
    exec ${pkgs.util-linux}/bin/unshare --user --map-current-user --mount --pid --fork --mount-proc -- ${pkgs.tini}/bin/tini -- "$@"
  '';
in
{
  options.defaults.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Default house capabilites.
    '';
  };

  config = lib.mkIf config.defaults.enable {
    passthroughEnv = [
      "TERM"
      "COLORTERM"
      "LC_ALL"
      "TZ"
      "USER"
      "LOGNAME"
      "XDG_DATA_HOME"
      "XDG_CONFIG_HOME"
      "XDG_STATE_HOME"
      "XDG_CACHE_HOME"
      "XDG_RUNTIME_DIR"
      "TMPDIR"
    ];

    readWritePaths = [
      "/proc"
      "/dev/tty"
      "/dev/pts"
      "/dev/ptmx"
      house.houseHomeDir
      house.tmpDir
      house.runDir
    ];

    execWrappers = lib.mkOrder 500 [ "${setupWrapper}" ];
  };
}
