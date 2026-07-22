# GPU access: render nodes plus what Mesa needs to pick a driver.
{ lib, config, ... }:

{
  options.gpu.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Grant GPU access: `/dev/dri` read/write (incl. ioctl),
      `/run/opengl-driver` and `/sys` read-only.
    '';
  };

  config = lib.mkIf config.gpu.enable {
    readOnlyPaths = [
      # Mesa: driver lookup (usually a /nix/store symlink; kept explicit
      # for non-symlink setups) and PCI device probing under /sys.
      "/run/opengl-driver"
      "/sys"
    ];

    # GPU render nodes; abi.read_write includes ioctl_dev since ABI 5.
    readWritePaths = [ "/dev/dri" ];
  };
}
