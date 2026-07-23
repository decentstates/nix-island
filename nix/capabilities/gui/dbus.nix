{ lib, pkgs, houseContext, config, libDag, ... }:

let
  cfg = config.gui.dbus;

  proxySocket = "${houseContext.runDir}/bus";

  filterArgs = lib.escapeShellArgs
    (map (n: "--talk=${n}") cfg.talk
      ++ map (n: "--own=${n}") cfg.own);

in
{
  options.gui.dbus = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Session D-Bus access through a filtering xdg-dbus-proxy;
        `DBUS_SESSION_BUS_ADDRESS` points at the proxy socket.
      '';
    };
    talk = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "org.freedesktop.portal.*"
        "org.freedesktop.Notifications"
      ];
      description = "Well-known names the house may talk to (see xdg-dbus-proxy --talk).";
    };
    own = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Well-known names the house may own (see xdg-dbus-proxy --own).";
    };
  };

  config = lib.mkIf cfg.enable {
    simple.readWritePaths = [ proxySocket ];

    # TODO: review
    execWrappers.dbusProxy = libDag.entryBetween ["envFilter" "landlock"] ["dirSetup"] ''
      set -euo pipefail

      if [ -z "''${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ -n "''${XDG_RUNTIME_DIR:-}" ]; then
        DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
      fi

      if [ -n "''${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
        fifo=$(${pkgs.coreutils}/bin/mktemp -u ${houseContext.tmpDir}/dbus-proxy.XXXXXX)
        ${pkgs.coreutils}/bin/mkfifo -m 600 "$fifo"
        exec {unblock}<>"$fifo" {wr}>"$fifo" {rd}<"$fifo" {unblock}>&-
        ${pkgs.coreutils}/bin/rm "$fifo"

        ${pkgs.xdg-dbus-proxy}/bin/xdg-dbus-proxy --fd="$wr" \
          "$DBUS_SESSION_BUS_ADDRESS" ${lib.escapeShellArg proxySocket} \
          --filter ${filterArgs} \
          {rd}<&- &
        exec {wr}>&-

        # Wait for the ready byte (a NUL, so count bytes instead of read -n1).
        if ! [ "$(${pkgs.coreutils}/bin/head -c1 <&"$rd" | ${pkgs.coreutils}/bin/wc -c)" -eq 1 ]; then
          echo "housing: dbus proxy failed to start; running without session bus" >&2
          exec {rd}<&-
        fi
      fi

      exec "$@"
    '';

  execWrappers.dbusProxyEnv = libDag.entryBetween ["final"] ["envFilter"] ''
      export DBUS_SESSION_BUS_ADDRESS="unix:path="${lib.escapeShellArg proxySocket}
      exec "$@"
    '';
  };
}
