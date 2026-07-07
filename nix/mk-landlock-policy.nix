# Landlock policy generation in the landlockconfig TOML schema
# (https://github.com/landlock-lsm/landlockconfig).
# Returns { defaults, mkPolicy }: deny-by-default with NixOS-friendly rules.
{ lib }:

rec {
  # Exposed so callers (e.g. closure confinement) can filter them.
  defaults = {
    # Read + execute: what a shell needs on NixOS.
    # Note: /run/wrappers (setuid binaries) is intentionally NOT included.
    readExecutePaths = [
      "/nix/store"
      "/run/current-system"
      "/run/booted-system"
      "/run/opengl-driver"
      "/bin" # /bin/sh
      "/usr/bin" # /usr/bin/env
    ];

    readOnlyPaths = [
      "/etc"
      "/proc/self"
      "/proc/cpuinfo"
    ];

    # Character devices an interactive shell needs.
    writableDevices = [
      "/dev/null"
      "/dev/zero"
      "/dev/full"
      "/dev/random"
      "/dev/urandom"
      "/dev/tty"
      "/dev/pts"
      "/dev/ptmx"
    ];
  };

  mkPolicy =
    { abi ? 6

      # Deny everything the kernel supports by default; allow-list below.
    , handledAccessFs ? [ "abi.all" ]
    , handledAccessNet ? [ "abi.all" ]
      # Scopes abstract unix sockets and signals to the sandbox domain.
    , scoped ? [ "abi.all" ]

    , readExecutePaths ? defaults.readExecutePaths
    , readOnlyPaths ? defaults.readOnlyPaths
      # Full read/write (everything except execute).
    , readWritePaths ? [ ]
    , writableDevices ? defaults.writableDevices

      # TCP ports (Landlock network restrictions). Empty = all denied
      # (because handledAccessNet handles them).
    , tcpConnectPorts ? [ ]
    , tcpBindPorts ? [ ]

      # Escape hatch: raw attrs merged into the config, e.g.
      # { path_beneath = [ { allowed_access = [ "refer" ]; parent = [ "/tmp" ]; } ]; }
    , extraRules ? { }
    }:

    let
      inherit (lib) optional;

      pathRules =
        optional (readExecutePaths != [ ]) {
          allowed_access = [ "abi.read_execute" ];
          parent = readExecutePaths;
        }
        ++ optional (readOnlyPaths != [ ]) {
          allowed_access = [ "read_dir" "read_file" ];
          parent = readOnlyPaths;
        }
        ++ optional (readWritePaths != [ ]) {
          allowed_access = [ "abi.read_write" ];
          parent = readWritePaths;
        }
        ++ optional (writableDevices != [ ]) {
          allowed_access = [ "abi.read_write" ];
          parent = writableDevices;
        }
        ++ (extraRules.path_beneath or [ ]);

      netRules =
        optional (tcpConnectPorts != [ ]) {
          allowed_access = [ "connect_tcp" ];
          port = tcpConnectPorts;
        }
        ++ optional (tcpBindPorts != [ ]) {
          allowed_access = [ "bind_tcp" ];
          port = tcpBindPorts;
        }
        ++ (extraRules.net_port or [ ]);

      base = {
        inherit abi;
        ruleset = [
          {
            handled_access_fs = handledAccessFs;
            handled_access_net = handledAccessNet;
            inherit scoped;
          }
        ];
      };
    in
    base
    // lib.optionalAttrs (pathRules != [ ]) { path_beneath = pathRules; }
    // lib.optionalAttrs (netRules != [ ]) { net_port = netRules; }
    // builtins.removeAttrs extraRules [ "path_beneath" "net_port" ];
}
