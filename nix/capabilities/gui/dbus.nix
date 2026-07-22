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
    envPassthrough = [ "DBUS_SESSION_BUS_ADDRESS" ];
    simple.readWritePaths = [ proxySocket ];

    execWrappers.dbusProxy = libDag.entryBefore ["envFilter" "landlock"] ''
      set -euo pipefail

      ORIGINAL_DBUS_SESSION_BUS_ADDRESS="''${DBUS_SESSION_BUS_ADDRESS:-}"
      if [ -z "$ORIGINAL_DBUS_SESSION_BUS_ADDRESS" ] && [ -n "''${ORIGINAL_XDG_RUNTIME_DIR:-}" ]; then
        ORIGINAL_DBUS_SESSION_BUS_ADDRESS="unix:path=$ORIGINAL_XDG_RUNTIME_DIR/bus"
      fi
      unset DBUS_SESSION_BUS_ADDRESS

      if [ -n "$ORIGINAL_DBUS_SESSION_BUS_ADDRESS" ]; then
        # Emulate pipe(2) with a fifo: the proxy holds the write end and
        # exits when the read end closes. The read end survives the exec
        # below, tying the proxy's lifetime to the app's. The proxy writes
        # one byte once its socket is bound and filtering.
        fifo=$(${pkgs.coreutils}/bin/mktemp -u ${houseContext.tmpDir}/dbus-proxy.XXXXXX)
        ${pkgs.coreutils}/bin/mkfifo -m 600 "$fifo"
        exec {unblock}<>"$fifo" {wr}>"$fifo" {rd}<"$fifo" {unblock}>&-
        ${pkgs.coreutils}/bin/rm "$fifo"

        ${pkgs.xdg-dbus-proxy}/bin/xdg-dbus-proxy --fd="$wr" \
          "$ORIGINAL_DBUS_SESSION_BUS_ADDRESS" ${proxySocket} \
          --filter ${filterArgs} \
          {rd}<&- &
        exec {wr}>&-

        # Wait for the ready byte (a NUL, so count bytes instead of read -n1).
        if [ "$(${pkgs.coreutils}/bin/head -c1 <&"$rd" | ${pkgs.coreutils}/bin/wc -c)" -eq 1 ]; then
          export DBUS_SESSION_BUS_ADDRESS="unix:path=${proxySocket}"
        else
          echo "housing: dbus proxy failed to start; running without session bus" >&2
          exec {rd}<&-
        fi
      fi

      exec "$@"
    '';
  };
}
