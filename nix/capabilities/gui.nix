{ lib, config, houseContext, pkgs, ... }:

{
  imports = [
    ./gui/dbus.nix
    ./gui/gpu.nix
    ./gui/wayland.nix
  ];

  options.gui = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable wayland gui access:
        - dbus proxy
        - wayland secure access
        - pulse-audio proxy
      '';
    };
  };

  config = lib.mkIf config.gui.enable {
    gui.dbus.enable = true;
    gui.wayland.enable = true;
  };
}
