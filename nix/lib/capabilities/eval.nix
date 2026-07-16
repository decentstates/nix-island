# evalCapabilities { house, module } — evaluate a house's capability
# module against the schema plus the shipped, flag-gated capabilities.
# Compose several capability modules via `imports` within `module`.
#
# `house` is the frozen per-house identity attrset made available to
# capability modules as a specialArg:
#   { profileName, runnerName, houseHomeDir, tmpDir, runDir, realHomeDir, username }
{ pkgs, lib }:

{ house, module ? { } }:

lib.evalModules {
  specialArgs = { inherit pkgs house; };
  modules = [
    ./schema.nix
    ./defaults.nix
    ./dbus.nix
    ./gpu.nix
    ./wayland.nix
  ] ++ [ module ];
}
