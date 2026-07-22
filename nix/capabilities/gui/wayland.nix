{ lib, pkgs, houseContext, config, libDag, ... }:

let
  cfg = config.gui.wayland;
  securityContext = pkgs.callPackage ../../pkgs/wayland-security-context/package.nix { };
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
    # TODO: This shouldn't be a passthrough env thing but a second exec wrapper on the other side of the envFilter
    # WAYLAND_DISPLAY is rewritten by housing-security-context to the
    # restricted per-launch socket before the env filter runs.
    passthroughEnv = [
      "WAYLAND_DISPLAY"
      "XCURSOR_THEME"
      "XCURSOR_SIZE"
    ];

    execWrappers.wayland = libDag.entryBefore ["envFilter" "landlock"] ''
      exec ${securityContext}/bin/housing-security-context \
            --app-id ${lib.escapeShellArg "house-${houseContext.profileName}"} \
            --runtime-dir "$XDG_RUNTIME_DIR" \
            -- "$@"
    '';
  };
}
