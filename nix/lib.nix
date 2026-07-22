{ pkgs
, lib ? pkgs.lib
# Required for home-manager.lib.dag:
# TODO: vendor lib.dag?
, home-manager
, island ? pkgs.callPackage ./pkgs/island/package.nix { }
}:
let
  libDag = home-manager.lib.hm.dag;
  dagOfType = home-manager.lib.hm.types.dagOf;
  mkCapabilities = { houseContext, modules ? [] }:
    lib.evalModules {
      # TODO extraSpecialArgs?...
      specialArgs = { 
        inherit pkgs island houseContext libDag dagOfType;
      };
      modules = [
        ./capabilities/core.nix
        ./capabilities/simple.nix
        ./capabilities/gui.nix
      ] ++ modules;
    };
  composeExecWrappers = { name, execWrappers }:
    let
      execWrappersD =
        pkgs.symlinkJoin {
          name = "exec-wrappers.d";
          paths = lib.imap0
            (i: { name, data }: pkgs.writeShellScriptBin "${lib.fixedWidthNumber 3 i}-${name}" data) 
            (home-manager.lib.hm.dag.topoSort execWrappers);
        };
    in
    pkgs.writeShellApplication {
      inherit name;
      text = ''
      set -euo pipefail

      wrappers=()
      for w in ${lib.escapeShellArg execWrappersD}/*; do
          [[ -f $w && -x $w ]] || continue
          wrappers+=("$w")
      done

      exec "''${wrappers[@]}" "$@"
      '';
    };
  mkCapabilitiesRunner = { houseContext , capabilitiesModule ? { } }:
    let
      execWrappers = (mkCapabilities {
        inherit houseContext;
        modules = [capabilitiesModule];
      }).config.execWrappers;
    in
    composeExecWrappers houseContext.runnerName execWrappers;
in
{ inherit mkCapabilities mkCapabilitiesRunner; }
