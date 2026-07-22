{ lib, libDag, dagOfType, ... }:

{
  options = {
    execWrappers = lib.mkOption {
      type = dagOfType lib.types.package;
      default = [ ];
      description = ''
        Scripts that exec each other.

        Ordered by home-manager's dagOf type, with hm.dag exposed as libDag, e.g.:
        - libDag.entryBefore
        - libDag.entryAfter
        - libDag.entryAnywhere
        - libDag.entryBetween
      '';
    };
  };
}
