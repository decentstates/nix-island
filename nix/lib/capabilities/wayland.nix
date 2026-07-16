{ lib, pkgs, house, config, ... }:

let
  securityContext = pkgs.callPackage ../../security-context/package.nix { };

  waylandWrapper = pkgs.writeShellScript "house-${house.profileName}-wayland" ''
    set -euo pipefail

    exec env XDG_RUNTIME_DIR="''${ORIGINAL_XDG_RUNTIME_DIR:-}" \
      ${securityContext}/bin/housing-security-context \
      --app-id ${lib.escapeShellArg "house-${house.profileName}"} \
      --runtime-dir "$XDG_RUNTIME_DIR" \
      -- "$@"
  '';
in
{
  options.wayland.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Grant basic wayland access.
    '';
  };

  config = lib.mkIf config.wayland.enable {
    dbus.enable = lib.mkDefault true;
    gpu.enable = lib.mkDefault true;

    # WAYLAND_DISPLAY is rewritten by housing-security-context to the
    # restricted per-launch socket before the env filter runs.
    passthroughEnv = [
      "WAYLAND_DISPLAY"
      "XCURSOR_THEME"
      "XCURSOR_SIZE"
    ];

    execWrappers = [ "${waylandWrapper}" ];
  };
}
