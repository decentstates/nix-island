# Common import surface: the flake, the home-manager module, and plain
# Nix all take mkHolm from here.
{
  mkHolm = import ./mk-holm.nix;

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
}
