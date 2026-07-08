# home-manager module: declare holms inside your home-manager
# configuration. Each holm.shells.<name> evaluates a nested HM home —
# via this home-manager's own modulesPath, so no separate input — and
# installs an executable of the same name.
{ config, lib, pkgs, modulesPath, ... }:

let
  cfg = config.holm;

  mkHolm = import ./mk-holm.nix { inherit pkgs; island = cfg.island; };

  evalHome = h: import modulesPath {
    inherit pkgs;
    configuration = {
      imports = h.modules;
      home = {
        inherit (h) username stateVersion;
        homeDirectory = h.directory;
      };
    };
  };

  mkWrapper = name: h:
    let home = evalHome h;
    in mkHolm {
      inherit name;
      inherit (h)
        directory shell environment passEnv
        readOnlyPaths readWritePaths tcpPorts;
      packages = h.packages ++ [ "${home.activationPackage}/home-path" ];
      holmFiles = "${home.activationPackage}/home-files";
    };

  shellModule = { name, ... }: {
    options = {
      directory = lib.mkOption {
        type = lib.types.str;
        default = "${config.home.homeDirectory}/holms/${name}";
        description = "The holm's $HOME; absolute.";
      };
      username = lib.mkOption {
        type = lib.types.str;
        default = config.home.username;
        description = "home.username of the nested evaluation.";
      };
      stateVersion = lib.mkOption {
        type = lib.types.str;
        default = config.home.stateVersion;
        description = "home.stateVersion of the nested evaluation.";
      };
      modules = lib.mkOption {
        type = lib.types.listOf lib.types.deferredModule;
        default = [ ];
        description = "The holm's home-manager modules.";
      };
      packages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        description = "Extra packages on PATH besides the holm's HM environment.";
      };
      shell = lib.mkOption {
        type = lib.types.package;
        default = pkgs.bashInteractive;
        description = "$SHELL inside; runs with no args, CLI args run instead.";
      };
      environment = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Env vars exported inside.";
      };
      passEnv = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        # keep in sync with mk-holm.nix
        default = [ "TERM" "COLORTERM" "LANG" "LC_ALL" "TZ" "TZDIR" "LOCALE_ARCHIVE" "USER" "LOGNAME" ];
        description = "Sole variables crossing from the session into the holm.";
      };
      readOnlyPaths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Extra hierarchies readable inside.";
      };
      readWritePaths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Extra hierarchies read/writable inside.";
      };
      tcpPorts = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        default = [ ];
        description = "TCP ports usable inside (connect + bind); empty = no TCP.";
      };
    };
  };
in
{
  options.holm = {
    island = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./island-package.nix { };
      defaultText = lib.literalExpression "nix-holm's island package";
      description = "Island package used by all holms.";
    };
    shells = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule shellModule);
      default = { };
      description = "Sandboxed shells; each attribute installs an executable of the same name.";
    };
  };

  config = lib.mkIf (cfg.shells != { }) {
    home.packages = [ cfg.island ] ++ lib.mapAttrsToList mkWrapper cfg.shells;
  };
}
