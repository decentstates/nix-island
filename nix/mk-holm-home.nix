# Evaluates a *per-holm* home-manager configuration: a full HM home
# (packages, dotfiles, programs.*) whose home directory is the holm's
# directory, giving each sandboxed shell its own self-contained $HOME.
#
# Works with either:
#   - a home-manager flake input        (has .lib.homeManagerConfiguration)
#   - a home-manager source path/channel (e.g. <home-manager>, fetchTarball)
{ pkgs, lib ? pkgs.lib }:

{ home-manager # flake input or source path
, username # must match $USER at runtime (activation checks it)
, homeDirectory # the holm's home; absolute
, modules ? [ ] # the holm's home-manager modules
, stateVersion ? "25.05" # overridable inside modules
, extraSpecialArgs ? { }
}:

let
  baseModule = { lib, ... }: {
    home.username = lib.mkDefault username;
    home.homeDirectory = lib.mkDefault homeDirectory;
    home.stateVersion = lib.mkDefault stateVersion;

    # This home lives inside a sandboxed shell, not a login session:
    # don't let activation poke the user's real systemd/D-Bus session.
    systemd.user.startServices = lib.mkDefault false;

    # The holm home is not the user's primary home; nixpkgs release
    # mismatch warnings are just noise here.
    home.enableNixpkgsReleaseCheck = lib.mkDefault false;
  };

  allModules = [ baseModule ] ++ modules;

  configuration =
    if home-manager ? lib.homeManagerConfiguration then
    # Flake-style input
      home-manager.lib.homeManagerConfiguration
        {
          inherit pkgs extraSpecialArgs;
          modules = allModules;
        }
    else
    # Channel / source path (e.g. <home-manager> or a fetchTarball)
      import "${home-manager}/modules" {
        inherit pkgs extraSpecialArgs;
        configuration = { imports = allModules; };
      };
in
{
  inherit configuration;
  inherit (configuration) activationPackage;
  # Convenience paths inside the activation package:
  #   home-path  -> buildEnv of home.packages + programs
  #   home-files -> the dotfile tree linked into the holm's $HOME
  homePath = "${configuration.activationPackage}/home-path";
  homeFiles = "${configuration.activationPackage}/home-files";
}
