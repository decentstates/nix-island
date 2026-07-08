# home-manager module: declare holms inside your home-manager
# configuration. Each holm.holms.<name> evaluates a nested HM home — via
# this home-manager's own modulesPath, so no separate input — and
# installs an executable of the same name. username/stateVersion come
# from the outer home; packages and the shell from the holm's modules.
{ config, lib, pkgs, modulesPath, ... }:

let
  cfg = config.holm;
  holmLib = import ./lib.nix;

  mkHolm = holmLib.mkHolm { inherit pkgs; island = cfg.island; };

  evalHome = h: import modulesPath {
    inherit pkgs;
    configuration = {
      imports = h.modules;
      home = {
        inherit (config.home) username stateVersion;
        homeDirectory = h.directory;
      };
    };
  };

  # $SHELL = the shell the holm's own configuration enables.
  # home.sessionVariables.SHELL (sourced later) still overrides.
  shellOf = home:
    let c = home.config;
    in
    if c.programs.zsh.enable then c.programs.zsh.package
    else if c.programs.fish.enable then c.programs.fish.package
    else pkgs.bashInteractive;

  mkWrapper = name: h:
    let home = evalHome h;
    in mkHolm {
      inherit name;
      inherit (h)
        directory environment passEnv
        readOnlyPaths readWritePaths tcpPorts;
      shell = shellOf home;
      packages = [ "${home.activationPackage}/home-path" ];
      holmFiles = "${home.activationPackage}/home-files";
    };

  holmModule = { name, ... }: {
    options = {
      directory = lib.mkOption {
        type = lib.types.str;
        default = "${config.home.homeDirectory}/holms/${name}";
        description = "The holm's $HOME; absolute.";
      };
      modules = lib.mkOption {
        type = lib.types.listOf lib.types.deferredModule;
        default = [ ];
        description = "The holm's home-manager modules.";
      };
      environment = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Env vars exported inside.";
      };
      passEnv = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = holmLib.defaultPassEnv;
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
    holms = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule holmModule);
      default = { };
      description = "Sandboxed holms; each attribute installs an executable of the same name.";
    };
  };

  config = lib.mkIf (cfg.holms != { }) {
    home.packages = [ cfg.island ] ++ lib.mapAttrsToList mkWrapper cfg.holms;
  };
}
