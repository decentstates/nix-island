# Generation-aware dotfile linker — the useful core of home-manager's
# linkGeneration. The full HM activation script is deliberately not run:
# on a fresh home its profile step falls back to the SHARED
# /nix/var/nix/profiles/per-user/$USER (holms would clobber each other's
# and the real HM generation pointer), it needs the nix daemon, and its
# hooks assume a login home. Consequently home.activation.* / onChange
# hooks don't run.
{ pkgs, lib ? pkgs.lib }:

{ name, holmFiles, homeDirectory }:

let
  # LC_ALL=C so `comm` can diff old vs new manifests at runtime.
  manifest = pkgs.runCommand "holm-${name}-manifest" { } ''
    cd ${holmFiles}
    find . \( -type f -o -type l \) -print | sed 's|^\./||' | LC_ALL=C sort > "$out"
  '';
in
pkgs.writeShellApplication {
  name = "holm-${name}-link-home";
  runtimeInputs = [ pkgs.coreutils ];
  text = ''
    ihome=${lib.escapeShellArg homeDirectory}
    files=${holmFiles}
    manifest=${manifest}
    state="$ihome/.local/state/holm"
    marker="$state/home-files"

    old="$(readlink "$marker" 2>/dev/null || true)"
    [ "$old" = "$files" ] && exit 0
    echo "holm(${name}): linking dotfiles..." >&2
    mkdir -p "$state"

    # Only links into the current/previous/an HM generation may be
    # replaced; anything else aborts the launch.
    while IFS= read -r rel; do
      tgt="$ihome/$rel"
      if [ -e "$tgt" ] || [ -L "$tgt" ]; then
        link="$(readlink "$tgt" 2>/dev/null || true)"
        ok=false
        case "$link" in
          "$files"/* | /nix/store/*/home-files/*) ok=true ;;
        esac
        if [ -n "$old" ]; then
          case "$link" in
            "$old"/*) ok=true ;;
          esac
        fi
        if [ "$ok" = false ]; then
          echo "holm(${name}): refusing to clobber $tgt (not managed by holm)" >&2
          exit 1
        fi
      fi
    done < "$manifest"

    # Leaf-by-leaf, so directories in $HOME stay real and writable.
    while IFS= read -r rel; do
      mkdir -p "$ihome/$(dirname "$rel")"
      ln -sfT "$files/$rel" "$ihome/$rel"
    done < "$manifest"

    # Prune links that vanished between generations, then emptied dirs.
    if [ -n "$old" ] && [ -f "$state/manifest" ]; then
      comm -23 "$state/manifest" "$manifest" | while IFS= read -r rel; do
        tgt="$ihome/$rel"
        [ -L "$tgt" ] || continue
        case "$(readlink "$tgt")" in
          "$old"/*) rm -f "$tgt" ;;
          *) continue ;;
        esac
        d="$(dirname "$tgt")"
        while [ "$d" != "$ihome" ]; do
          rmdir "$d" 2>/dev/null || break
          d="$(dirname "$d")"
        done
      done
    fi

    # install, not cp: the source is a 0444 store file and cp would copy
    # those bits, breaking the NEXT generation change with EACCES.
    install -m 644 "$manifest" "$state/manifest"
    ln -sfT "$files" "$marker"
  '';
}
