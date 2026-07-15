{ lib, pkgs, island, config, ... }:

let
  setupWrapper = pkgs.writeShellScript "island-${island.profileName}-setup" ''
    set -euo pipefail

    # Both levels live under world-writable sticky /tmp: refuse planted
    # symlinks/foreign dirs; 0700 on the validated base then protects
    # everything beneath it.
    create_owned_dir() {
      mkdir -p "$1" 2>/dev/null || true
      if [ -L "$1" ] || [ ! -O "$1" ]; then
        echo "island: refusing $1: symlink or not owned by us" >&2
        exit 1
      fi
      chmod 700 "$1"
    }
    base=$(${pkgs.coreutils}/bin/dirname ${island.tmpDir})
    [ "$base" = /tmp ] || create_owned_dir "$base"
    create_owned_dir ${island.tmpDir}
    export ORIGINAL_TMPDIR="''${TMPDIR:-/tmp}"
    export TMPDIR=${island.tmpDir}

    export ORIGINAL_XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-}"
    export XDG_RUNTIME_DIR=${island.runDir}
    mkdir -p $XDG_RUNTIME_DIR
    chmod 700 $XDG_RUNTIME_DIR

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
