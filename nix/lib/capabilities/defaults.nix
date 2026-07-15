{ lib, pkgs, island, config, ... }:

let
  setupWrapper = pkgs.writeShellScript "island-${island.profileName}-setup" ''
    set -euo pipefail

    # TODO: Check permissions on these dirs
    mkdir -p ${lib.escapeShellArg island.tmpDir}
    chmod 700 ${lib.escapeShellArg island.tmpDir}
    export ORIGINAL_TMPDIR="''${TMPDIR:-/tmp}"
    export TMPDIR=${lib.escapeShellArg island.tmpDir}

    mkdir -p ${lib.escapeShellArg island.runDir}
    chmod 700 ${lib.escapeShellArg island.runDir}
    export ORIGINAL_XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-}"
    export XDG_RUNTIME_DIR=${island.runDir}

    exec "$@"
  '';
in
{
  options.defaults.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Default island capabilites.
    '';
  };

  config = lib.mkIf config.defaults.enable {
    passthroughEnv = [
      "TERM"
      "COLORTERM"
      "LANG"
      "LC_ALL"
      "TZ"
      "TZDIR"
      "LOCALE_ARCHIVE"
      "USER"
      "LOGNAME"
      "HOME"
      "XDG_DATA_HOME"
      "XDG_CONFIG_HOME"
      "XDG_STATE_HOME"
      "XDG_CACHE_HOME"
      "XDG_RUNTIME_DIR"
      "TMPDIR"
    ];

    readWritePaths = [
      "/dev/tty"
      "/dev/pts"
      "/dev/ptmx"
      island.islandHomeDir
      island.tmpDir
      island.runDir
    ];

    execWrappers = lib.mkOrder 500 [ "${setupWrapper}" ];
  };
}
