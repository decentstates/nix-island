# evalCapabilities { island, module } — evaluate an island's capability
# module against the schema plus the shipped, flag-gated capabilities.
# Compose several capability modules via `imports` within `module`.
#
# `island` is the frozen per-island identity attrset made available to
# capability modules as a specialArg:
#   { profileName, runnerName, islandHomeDir, tmpDir, runDir, realHomeDir, username }
{ pkgs, lib }:

{ island, module ? { } }:

lib.evalModules {
  specialArgs = { inherit pkgs island; };
  modules = [
    ./schema.nix
    ./defaults.nix
    ./dbus.nix
    ./gpu.nix
    ./wayland.nix
  ] ++ [ module ];
}
