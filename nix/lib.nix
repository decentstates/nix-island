# Common import surface: the flake, the home-manager module, and plain
# Nix all take mkHolm from here.
{ pkgs
, lib ? pkgs.lib
, island ? pkgs.callPackage ./island-package.nix { }
}:

rec {
  defaultPassEnv = [
    "TERM"
    "COLORTERM"
    "LANG"
    "LC_ALL"
    "TZ"
    "TZDIR"
    "LOCALE_ARCHIVE"
    "USER"
    "LOGNAME"
  ];

  mkHolm = args:
    import ./mk-holm.nix { inherit pkgs lib island; }
      ({ passEnv = defaultPassEnv; } // args);
}
