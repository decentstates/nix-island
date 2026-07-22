# GPU access: render nodes plus what Mesa needs to pick a driver.
{ lib, config, ... }:

{
  options.gui.gpu.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Grant GPU access: 
      - `/dev/dri`
      - `/run/opengl-driver` 
      - `/sys`
    '';
  };

  config = lib.mkIf config.gpu.enable {
    readExecutePaths = [
      "/run/opengl-driver"
      "/sys"
    ];

    readWritePaths = [ "/dev/dri" ];
  };
}
