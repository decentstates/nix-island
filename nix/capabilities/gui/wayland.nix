{ lib, pkgs, houseContext, config, libDag, ... }:

let
  cfg = config.gui.wayland;
  securityContext = pkgs.callPackage ../../pkgs/wayland-security-context/package.nix { };
  waylandDisplayPath = "${houseContext.runDir}/wayland-security-context";
in
{
  options.gui.wayland = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Wayland access via a security-contect.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    envPassthrough = [
      "XCURSOR_THEME"
      "XCURSOR_SIZE"
    ];

    execWrappers.wayland = libDag.entryBetween ["envFilter" "landlock"] ["dirSetup"] ''
      exec ${securityContext}/bin/wayland-security-context \
            --app-id ${lib.escapeShellArg "house-${houseContext.houseName}"} \
            --socket ${lib.escapeShellArg waylandDisplayPath} \
            -- "$@"
    '';

    execWrappers.waylandEnv = libDag.entryBetween ["final"] ["envFilter"] ''
      export WAYLAND_DISPLAY=${lib.escapeShellArg waylandDisplayPath}
      exec "$@"
    '';
  };
}
