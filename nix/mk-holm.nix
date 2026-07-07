# nix-holm core: build a named executable (e.g. `work-shell`) that drops
# you into an isolated home — a "holm" — sandboxed by Island/Landlock.
#
# The core knows nothing about home-manager. A holm's contents are:
#   * `packages`  — merged (with the shell + coreutils baseline) into one
#                   profile; its bin/ is the ONLY PATH inside, and every
#                   etc/profile.d/*.sh in it is sourced on entry;
#   * `holmFiles` — any derivation whose tree is linked, leaf by leaf and
#                   generation-aware, into the holm's $HOME.
# nix-holm-manager (mk-holm-manager.nix) plugs home-manager into exactly
# these two inputs.
#
# On launch the wrapper: (1) symlinks the Nix-rendered Island profile into
# ~/.config/island/profiles/<name>/ (Island reads only from there); (2)
# links the dotfiles via mk-home-linker.nix; (3) execs `island run` with a
# launcher that resets to a fresh environment (explicit allowlist only),
# points HOME at the holm, and runs $SHELL or your arguments.
{ pkgs
, lib ? pkgs.lib
, island ? pkgs.callPackage ./island-package.nix { }
}:

{ name # executable and Island profile name, e.g. "work-shell"
, directory # the holm's $HOME; absolute; created on launch
, packages ? [ ] # on PATH inside, next to the shell + coreutils baseline
, holmFiles ? null # derivation linked into the holm's $HOME
, environment ? { } # extra env vars exported inside the fresh environment
, shell ? pkgs.bashInteractive # becomes $SHELL; runs (login) when invoked with no args; args run arbitrary commands instead
, passEnv ? [ "TERM" "COLORTERM" "LANG" "LC_ALL" "TZ" "USER" "LOGNAME" ]
  # ^ the only variables that cross from your session into the holm
, readOnlyPaths ? [ ] # extra hierarchies readable inside
, readWritePaths ? [ ] # extra hierarchies read/writable inside
, tcpPorts ? [ ] # TCP ports usable inside (connect + bind); empty = no TCP
}:

assert lib.assertMsg (lib.hasPrefix "/" (toString directory))
  "mkHolm(${name}): `directory` must be an absolute path";

let
  tomlFormat = pkgs.formats.toml { };

  # --- the holm's environment: one merged profile --------------------
  profileEnv = pkgs.buildEnv {
    name = "holm-${name}-env";
    paths = [ shell pkgs.coreutils ] ++ packages;
  };

  homeLinker = import ./mk-home-linker.nix { inherit pkgs lib; } {
    inherit name holmFiles;
    homeDirectory = directory;
  };

  # --- Island profile: deny-by-default Landlock policy ----------------
  # The profile ships the SAME base file the island binary embeds
  # (./island-default-base.toml, one source of truth) — `island update`
  # recognizes it as current — plus a holm-specific file with the
  # directory, ttys (for pty-opening programs like tmux), and
  # the caller's extra grants. Files in a profile COMPOSE: grants union,
  # handled access rights intersect — so each standalone file must
  # declare the full ruleset, and note that hand-written files dropped
  # in the profile dir can WIDEN access; to genuinely tighten, stack a
  # second profile: `island run -p <name> -p strict -- ...`.
  holmRules = {
    abi = 6;
    ruleset = [{
      handled_access_fs = [ "abi.all" ];
      handled_access_net = [ "abi.all" ];
      scoped = [ "abi.all" ];
    }];
    path_beneath = [
      {
        allowed_access = [ "abi.read_write" ];
        parent = [ directory "/dev/tty" "/dev/pts" "/dev/ptmx" ]
          ++ readWritePaths;
      }
    ] ++ lib.optional (readOnlyPaths != [ ]) {
      allowed_access = [ "read_dir" "read_file" ];
      parent = readOnlyPaths;
    };
  } // lib.optionalAttrs (tcpPorts != [ ]) {
    net_port = [{
      allowed_access = [ "connect_tcp" "bind_tcp" ];
      port = tcpPorts;
    }];
  };

  profile = pkgs.runCommand "holm-profile-${name}" { } ''
    mkdir -p "$out/landlock"
    cp ${tomlFormat.generate "profile.toml" {
      workspace = false;
      context = [{ when_beneath = toString directory; }];
    }} "$out/profile.toml"
    cp ${./island-default-base.toml} \
       "$out/landlock/island-default-base.toml"
    cp ${tomlFormat.generate "holm.toml" holmRules} \
       "$out/landlock/20-holm.toml"
  '';

  # --- launcher: runs INSIDE the sandbox, in two stages ---------------
  # Stage 1 (mainland env, as spawned by island) re-execs itself through
  # `env -i` carrying only the allowlist. Stage 2 (fresh env) puts the
  # holm profile — and nothing else — on PATH, sources the profile's
  # etc/profile.d/*.sh (this is how e.g. hm-session-vars.sh arrives),
  # and execs $SHELL (login) or the given command. No `set -u` —
  # profile.d scripts are not written for it.
  launcher = pkgs.writeShellScript "holm-${name}-launch" ''
    if [ -z "''${__HOLM_CLEAN:-}" ]; then
      keep=(__HOLM_CLEAN=1 SHELL=${lib.getExe shell} HOME=${lib.escapeShellArg directory})
      for v in ${toString passEnv}; do
        if [ -n "''${!v+x}" ]; then keep+=("$v=''${!v}"); fi
      done
      exec ${pkgs.coreutils}/bin/env -i "''${keep[@]}" "$0" "$@"
    fi
    unset __HOLM_CLEAN
    export PATH="${profileEnv}/bin"
    for f in ${profileEnv}/etc/profile.d/*.sh; do
      # shellcheck disable=SC1090
      [ -f "$f" ] && . "$f"
    done
    ${lib.concatStrings (lib.mapAttrsToList
      (n: v: "export ${n}=${lib.escapeShellArg (toString v)}\n")
      environment)}
    export TMPDIR="$HOME/.tmp"
    ${pkgs.coreutils}/bin/mkdir -p "$TMPDIR"
    cd "$HOME" || exit 1
    if [ "$#" -gt 0 ]; then
      exec "$@"
    else
      exec "$SHELL" -l
    fi
  '';
in
pkgs.writeShellApplication {
  inherit name;
  runtimeInputs = [ island pkgs.coreutils ];

  text = ''
    # Sync the declarative profile into Island's config dir: link current
    # files, prune store links from older generations, keep hand-written
    # ones.
    cfg="''${XDG_CONFIG_HOME:-$HOME/.config}/island/profiles/${name}"
    mkdir -p "$cfg/landlock"
    ln -sfT ${profile}/profile.toml "$cfg/profile.toml"
    for f in "$cfg/landlock"/*; do
      [ -L "$f" ] || continue
      case "$(readlink "$f")" in
        /nix/store/*) rm -f "$f" ;;
      esac
    done
    for f in ${profile}/landlock/*; do
      ln -sfT "$f" "$cfg/landlock/$(basename "$f")"
    done

    mkdir -p ${lib.escapeShellArg directory}

    ${lib.optionalString (holmFiles != null) ''
      # Materialize this holm's dotfiles (no-op when unchanged).
      ${homeLinker}/bin/${homeLinker.name}
    ''}

    if [ "$#" -gt 0 ]; then
      exec island run -p ${lib.escapeShellArg name} -- ${launcher} "$@"
    else
      exec island run -p ${lib.escapeShellArg name} -- ${launcher}
    fi
  '';
}
