{ lib, config, houseContext, pkgs, ... }:

{
  options.gui = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable wayland gui access:
        - dbus proxy
        - wayland secure access
        - pulse-audio proxy
      '';
    };
  };

  imports = [
    ./gui/dbus.nix
    ./gui/gpu.nix
    ./gui/wayland.nix
  ];

  config = lib.mkIf config.gui.enable {
    gui.dbus.enable = true;
    gui.wayland.enable = true;
  };
}
