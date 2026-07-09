{ pkgs
, lib ? pkgs.lib
, island ? pkgs.callPackage ./island/island-package.nix { }
} @ libArgs:

rec {
  defaultPassthroughEnv = [
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

  mkIslandRunner = import ./lib/mk-island-runner.nix libArgs;
  mkIslandProfile = import ./lib/mk-island-profile.nix libArgs;
}
