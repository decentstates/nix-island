# Shared between mk-holm.nix and home-manager-module.nix.
{
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
