# nix-holm core: a named executable dropping into an Island/Landlock-
# sandboxed home. Contents = `packages` (PATH) + `holmFiles` (dotfile
# tree); mk-holm-manager.nix plugs home-manager into these two inputs.
{ pkgs
, lib ? pkgs.lib
, island ? pkgs.callPackage ./island-package.nix { }
}:

{ name # executable and Island profile name
, directory # the holm's $HOME; absolute
, packages ? [ ] # on PATH inside (plus shell + coreutils); their etc/profile.d/*.sh are sourced
, holmFiles ? null # derivation linked into the holm's $HOME
, environment ? { }
, shell ? pkgs.bashInteractive # $SHELL inside; runs with no args; CLI args run instead
, passEnv ? [ "TERM" "COLORTERM" "LANG" "LC_ALL" "TZ" "TZDIR" "LOCALE_ARCHIVE" "USER" "LOGNAME" ] # sole env crossing in
, readOnlyPaths ? [ ]
, readWritePaths ? [ ]
, tcpPorts ? [ ] # connect + bind; empty = no TCP
}:

# Landlock policies have no ~ expansion; relative paths would grant nothing.
assert lib.assertMsg (lib.hasPrefix "/" (toString directory))
  "mkHolm(${name}): `directory` must be an absolute path";

let
  tomlFormat = pkgs.formats.toml { };

  profileEnv = pkgs.buildEnv {
    name = "holm-${name}-env";
    paths = [ shell pkgs.coreutils ] ++ packages;
  };

  homeLinker = import ./mk-home-linker.nix { inherit pkgs lib; } {
    inherit name holmFiles;
    homeDirectory = directory;
  };

  # Extends island-default-base.toml (shipped below). Files in a profile
  # COMPOSE — grants union, handled accesses intersect — so this file must
  # declare the full ruleset, sibling files can WIDEN, and tightening
  # needs a stacked second profile (`island run -p a -p b`).
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
        # ttys: pty-allocating programs (tmux, script) open these themselves
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

  # Runs inside the sandbox. Stage 1 re-execs through `env -i` carrying
  # only the allowlist; stage 2 builds PATH from the profile alone and
  # sources its profile.d (how hm-session-vars arrives). No `set -u`:
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
    # NixOS login/interactive shells source /etc/set-environment, which
    # would reimport the full system PATH and variables; guard it off.
    export __NIXOS_SET_ENVIRONMENT_DONE=1
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
    # Island only reads profiles from its config dir; sync ours in,
    # pruning store links from older generations, keeping hand-written
    # files.
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
      ${homeLinker}/bin/${homeLinker.name}
    ''}

    if [ "$#" -gt 0 ]; then
      exec island run -p ${lib.escapeShellArg name} -- ${launcher} "$@"
    else
      exec island run -p ${lib.escapeShellArg name} -- ${launcher}
    fi
  '';
}
