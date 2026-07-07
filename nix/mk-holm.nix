# mkHolm: build a named executable (e.g. `work-shell`) that drops you into
# an isolated home — a "holm" — sandboxed by Island/Landlock and furnished
# by its own home-manager configuration.
#
# On launch the wrapper: (1) symlinks the Nix-rendered Island profile into
# ~/.config/island/profiles/<name>/ (Island reads only from there); (2)
# links the holm's dotfiles into its directory, generation-aware, via
# mk-home-linker.nix — the full HM activation script is deliberately NOT
# run, see that file for why; (3) execs `island run` with a launcher that
# resets to a fresh environment (explicit allowlist only), points HOME at
# the holm, sources hm-session-vars, and runs $SHELL or your arguments.
{ pkgs
, lib ? pkgs.lib
, island ? pkgs.callPackage ./island-package.nix { }
, home-manager # flake input or source path (both coerce to a path)
}:

{ name # executable and Island profile name, e.g. "work-shell"
, directory # the holm's $HOME; absolute; created on launch
, username # your login name, for home.username (evaluation-time only)
, modules ? [ ] # this holm's home-manager modules
, stateVersion ? "25.05"
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

  # --- this holm's home-manager configuration -------------------------
  home = import "${home-manager}/modules" {
    inherit pkgs;
    configuration = {
      imports = modules;
      home = {
        inherit username stateVersion;
        homeDirectory = directory;
      };
    };
  };
  homePath = "${home.activationPackage}/home-path";

  homeLinker = import ./mk-home-linker.nix { inherit pkgs lib; } {
    inherit name;
    homeFiles = "${home.activationPackage}/home-files";
    homeDirectory = directory;
  };

  # --- Island profile: deny-by-default Landlock policy ----------------
  # NixOS essentials are baked in; /run/wrappers (setuid) is deliberately
  # absent. Hand-written *.toml dropped next to the generated one survive
  # profile syncs, and Landlock layers intersect — so local files can
  # tighten the policy further, never widen it.
  policy = {
    abi = 6;
    ruleset = [{
      handled_access_fs = [ "abi.all" ];
      handled_access_net = [ "abi.all" ];
      scoped = [ "abi.all" ];
    }];
    path_beneath = [
      {
        allowed_access = [ "abi.read_execute" ];
        parent = [
          "/nix/store"
          "/run/current-system"
          "/run/booted-system"
          "/run/opengl-driver"
          "/bin"
          "/usr/bin"
        ];
      }
      {
        allowed_access = [ "read_dir" "read_file" ];
        parent = [ "/etc" "/proc/self" "/proc/cpuinfo" ] ++ readOnlyPaths;
      }
      {
        allowed_access = [ "abi.read_write" ];
        parent = [
          directory
          "/dev/null"
          "/dev/zero"
          "/dev/full"
          "/dev/random"
          "/dev/urandom"
          "/dev/tty"
          "/dev/pts"
          "/dev/ptmx"
        ] ++ readWritePaths;
      }
    ];
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
    cp ${tomlFormat.generate "policy.toml" policy} \
       "$out/landlock/00-nix-managed.toml"
  '';

  # --- launcher: runs INSIDE the sandbox, in two stages ---------------
  # Stage 1 (mainland env, as spawned by island) re-execs itself through
  # `env -i` carrying only the allowlist. Stage 2 (fresh env) builds PATH
  # from the holm's HM environment plus the system profile, loads
  # hm-session-vars, and execs $SHELL (login) or the given command.
  # No `set -u` — hm-session-vars.sh is not written for it.
  launcher = pkgs.writeShellScript "holm-${name}-launch" ''
    if [ -z "''${__HOLM_CLEAN:-}" ]; then
      keep=(__HOLM_CLEAN=1 SHELL=${lib.getExe shell} HOME=${lib.escapeShellArg directory})
      for v in ${toString passEnv}; do
        if [ -n "''${!v+x}" ]; then keep+=("$v=''${!v}"); fi
      done
      exec ${pkgs.coreutils}/bin/env -i "''${keep[@]}" "$0" "$@"
    fi
    unset __HOLM_CLEAN
    export PATH="${homePath}/bin:/run/current-system/sw/bin:/usr/bin:/bin"
    hmVars="${homePath}/etc/profile.d/hm-session-vars.sh"
    # shellcheck disable=SC1090
    [ -f "$hmVars" ] && . "$hmVars"
    export TMPDIR="$HOME/.tmp"
    mkdir -p "$TMPDIR"
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

    # Materialize this holm's dotfiles (no-op when unchanged).
    ${homeLinker}/bin/${homeLinker.name}

    if [ "$#" -gt 0 ]; then
      exec island run -p ${lib.escapeShellArg name} -- ${launcher} "$@"
    else
      exec island run -p ${lib.escapeShellArg name} -- ${launcher}
    fi
  '';
}
