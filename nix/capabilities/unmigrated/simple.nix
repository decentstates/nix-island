{ lib, ... }:

{
  options = {
    execWrappers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Store paths of self-contained scripts that perform their setup and
        then `exec "$@"`. Composed left-to-right, outermost first, around the
        sandbox entry:

            exec <w1> <w2> ... <house-runner> <cmd...>

        Wrappers run *outside* the sandbox. Order across capabilities with
        `lib.mkOrder` (the defaults setup wrapper sits at 500).
      '';
    };

    passthroughEnv = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Environment variables preserved across the house boundary; everything
        else is stripped by the runner's env filter.
      '';
    };

    bindTcpPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      description = "TCP ports bindable inside.";
    };

    connectTcpPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      description = "TCP ports connectable to inside.";
    };

    readOnlyPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Hierarchies readable/executable inside.";
    };

    readWritePaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Hierarchies read/writable inside.";
    };
  };
}
