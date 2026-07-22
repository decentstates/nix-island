{ lib, config, houseContext, pkgs, ... }:

{
  options.simple = {
    enable = {
      type = lib.types.bool;
      default = true;
      description = ''
        Simple configuration.
        Denies all files, networking and other scopes by default.

        Limitations from Landlock config:
        - No way to specify UDP ports yet.
      '';
    };

    bindTcpPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      description = "
      Bindable TCP ports.

      Adding 0 will allow dynamic ephemerable ports to be used.
      ";
    };

    connectTcpPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      description = "Connectable TCP ports";
    };

    readPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ 
        # id
        "/etc/passwd"
        "/etc/group"
        "/etc/nsswitch.conf"

        # networking
        "/etc/hosts"
        "/etc/resolv.conf"
        "/etc/host.conf"
        "/etc/hostname"
        "/etc/services"
        "/etc/protocols"
        "/etc/gai.conf"

        # dyn linking
        "/etc/ld.so.cache"
        "/etc/ld.so.conf"
        "/etc/ld.so.conf.d/"

        # locale
        "/etc/localtime"
        "/etc/locale.conf"
        "/etc/locale.alias"

        # env
        "/etc/os-release"
        "/etc/machine-id"
        "/etc/mime.types"
        "/etc/profile"
        "/etc/profile.d/"
        "/etc/environment"
        "/etc/environment.d/"

        # proc
        "/proc/self"
        "/proc/cpuinfo"
      ];
      description = "Hierarchies readable inside.";
    };

    readExecutePaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ 
        "/bin"
        "/usr/bin"
        "/nix/store"
      ];
      description = "Hierarchies readable/executable inside.";
    };

    readWritePaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "/dev/full"
        "/dev/null"
        "/dev/random"
        "/dev/urandom"
        "/dev/zero"

        "/dev/tty"
        "/dev/pts"
        "/dev/ptmx"

        houseContext.houseHomeDir
        houseContext.tmpDir
        houseContext.runDir
      ];
      description = "Hierarchies read/writable inside.";
    };
  };


  config = lib.mkIf config.simple.enable {
    landlockConfigs.simple =
      let
        tomlFormat = pkgs.formats.toml { };

        netPort =
          (lib.optional (config.simple.connectTcpPorts != [ ]) {
            allowed_access = [ "connect_tcp" ];
            port = config.simple.connectTcpPorts;
          })
          ++ (lib.optional (config.simple.bindTcpPorts != [ ]) {
            allowed_access = [ "bind_tcp" ];
            port = config.simple.bindTcpPorts;
          });

        pathBeneath = 
          (lib.optional (config.simple.readWritePaths != [ ]) {
              allowed_access = [ "abi.read_write" ];
              parent = config.simple.readWritePaths;
          })
          ++
          (lib.optional (config.simple.readExecutePaths != [ ]) {
              allowed_access = [ "abi.read_execute" ];
              parent = config.simple.readExecutePaths;
          })
          ++
          (lib.optional (config.simple.readOnlyPaths != [ ]) {
              allowed_access = [
                "read_dir"
                "read_file"
                "refer"
                ];
              parent = config.simple.readOnlyPaths;
          });

        housingRules = {
          abi = 6;
          ruleset = [{
            handled_access_fs = [ "abi.all" ];
            handled_access_net = [ "abi.all" ];
            scoped = [ "abi.all" ];
          }];
        } // lib.optionalAttrs (pathBeneath != [ ]) { path_beneath = pathBeneath; }
          // lib.optionalAttrs (netPort != [ ]) { net_port = netPort; };
      in 
      tomlFormat.generate "20-simple.toml" housingRules;
  };
}
