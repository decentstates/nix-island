# Generation-aware dotfile linker — the useful core of home-manager's
# `linkGeneration` phase, extracted so launching a holm never runs the full
# activation script. Why not just run `activationPackage/activate`:
#
#   * Its nix-profile step picks `$HOME/.local/state/nix/profiles` only if
#     that directory already exists; on a FRESH island home it doesn't, so
#     it falls back to the SHARED /nix/var/nix/profiles/per-user/$USER —
#     holms would clobber each other's (and your real home-manager's)
#     generation pointer.
#   * It needs the nix daemon at launch; pure linking doesn't.
#   * Its module activation hooks are written for real login homes.
#
# What we keep, matching HM's semantics:
#   * leaf-by-leaf symlinks into home-files, so directories in $HOME stay
#     real and writable;
#   * refuse to clobber files we don't manage;
#   * on generation change, prune links that vanished and directories that
#     became empty.
{ pkgs, lib ? pkgs.lib }:

{ name, homeFiles, homeDirectory }:

let
  # Relative paths of every leaf in the dotfile tree, computed at build
  # time (LC_ALL=C so `comm` can diff old vs new manifests at runtime).
  manifest = pkgs.runCommand "holm-${name}-manifest" { } ''
    cd ${homeFiles}
    find . \( -type f -o -type l \) -print | sed 's|^\./||' | LC_ALL=C sort > "$out"
  '';
in
pkgs.writeShellApplication {
  name = "holm-${name}-link-home";
  runtimeInputs = [ pkgs.coreutils ];
  text = ''
    ihome=${lib.escapeShellArg homeDirectory}
    files=${homeFiles}
    manifest=${manifest}
    state="$ihome/.local/state/holm"
    marker="$state/home-files"

    old="$(readlink "$marker" 2>/dev/null || true)"
    [ "$old" = "$files" ] && exit 0
    echo "holm(${name}): linking dotfiles..." >&2
    mkdir -p "$state"

    # Refuse to clobber anything we don't manage (links into the current,
    # previous, or any HM-generation home-files tree are ours).
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

    # Link the new generation.
    while IFS= read -r rel; do
      mkdir -p "$ihome/$(dirname "$rel")"
      ln -sfT "$files/$rel" "$ihome/$rel"
    done < "$manifest"

    # Prune links present in the previous generation but not this one,
    # then any directories that became empty.
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

    cp "$manifest" "$state/manifest"
    ln -sfT "$files" "$marker"
  '';
}
