# Renders a complete Island profile directory in the Nix store:
#   result/profile.toml
#   result/landlock/00-nix-managed.toml
#   result/landlock/<extra files>
{ pkgs, lib ? pkgs.lib }:

{ name
, contexts ? [ ] # list of when_beneath paths (strings)
, env ? { } # attrset -> [[env]] name/literal entries
, workspace ? true # Island's per-profile isolated XDG dirs
, landlockPolicy ? null # attrset in landlockconfig schema (see mk-landlock-policy.nix)
, landlockPolicyFile ? null # OR: a prebuilt TOML file/derivation (takes precedence)
, extraLandlockFiles ? { } # filename -> attrset, layered as additional policies
}:

let
  tomlFormat = pkgs.formats.toml { };

  policyFile =
    if landlockPolicyFile != null then landlockPolicyFile
    else if landlockPolicy != null then
      tomlFormat.generate "00-nix-managed.toml" landlockPolicy
    else throw "mk-profile(${name}): need landlockPolicy or landlockPolicyFile";

  profile =
    { inherit workspace; }
    // lib.optionalAttrs (contexts != [ ]) {
      context = map (p: { when_beneath = toString p; }) contexts;
    }
    // lib.optionalAttrs (env != { }) {
      env = lib.mapAttrsToList (n: v: { name = n; literal = toString v; }) env;
    };

  extraFiles = lib.concatStrings (lib.mapAttrsToList
    (fn: attrs: ''
      cp ${tomlFormat.generate fn attrs} "$out/landlock/${fn}"
    '')
    extraLandlockFiles);
in
pkgs.runCommand "island-profile-${name}" { } ''
  mkdir -p "$out/landlock"
  cp ${tomlFormat.generate "profile.toml" profile} "$out/profile.toml"
  cp ${policyFile} "$out/landlock/00-nix-managed.toml"
  ${extraFiles}
''
