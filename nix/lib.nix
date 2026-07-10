{ pkgs
, lib ? pkgs.lib
, island ? pkgs.callPackage ./island/island-package.nix { }
}:

{
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
    "HOME"
  ];

  mkIslandRunner = import ./lib/mk-island-runner.nix { inherit pkgs lib island; };
  mkIslandProfile = import ./lib/mk-island-profile.nix { inherit pkgs lib island; };
}
