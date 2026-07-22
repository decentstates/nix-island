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
      sorted = home-manager.lib.hm.dag.topoSort execWrappers;
      ordered =
        if sorted ? result then sorted.result
        else throw "composeExecWrappers: execWrappers '${name}' contain a dependency cycle";
      # Each wrapper must hand off to the next command; a wrapper that forgets
      # to `exec ... "$@"` would silently drop the rest of the chain.
      checkHandoff = entry:
        lib.assertMsg (lib.hasInfix "exec" entry.data && lib.hasInfix ''"$@"'' entry.data)
          "execWrapper '${entry.name}' must exec the next command (needs `exec` and `\"$@\"`)";
      execWrappersD =
        pkgs.symlinkJoin {
          name = "exec-wrappers.d";
          paths = lib.imap0
            (i: entry:
              assert checkHandoff entry;
              pkgs.writeShellScriptBin "${lib.fixedWidthNumber 3 i}-${entry.name}" entry.data)
            ordered;
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
    composeExecWrappers { name = houseContext.runnerName; inherit execWrappers; };
in
{ inherit mkCapabilities mkCapabilitiesRunner; }
