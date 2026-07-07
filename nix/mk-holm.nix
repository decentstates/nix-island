# mkHolm: build a named executable (e.g. `work-shell`) that launches a
# shell (or any command) inside an Island/Landlock sandbox — optionally with
# its OWN home-manager configuration governing that isolated environment.
#
# Island only reads profiles from $XDG_CONFIG_HOME/island/profiles/<name>/ and
# has no flag to point at a store path, so the wrapper "bootstraps" on every
# launch: it (re)links the Nix-generated profile files into that directory,
# then execs `island run -p <profile>`.
#
# With `homeManager` set, the holm's `directory` becomes a full home
# directory of its own: the wrapper links the holm's home-manager dotfiles
# into it (generation-aware, via mk-home-linker.nix — the full HM activation
# script is deliberately NOT run; see that file for why), then enters the
# sandbox with HOME pointed there, hm-session-vars sourced, and the HM
# environment (home.packages, programs.*) on PATH. Your real $HOME stays
# both untouched and unreadable.
{ pkgs
, lib ? pkgs.lib
, island ? pkgs.callPackage ./island-package.nix { }
, home-manager ? null # flake input or source path; required for `homeManager`
}:

{ name # executable name, e.g. "work-shell"
, profileName ? name # Island profile name
, command ? [ (lib.getExe pkgs.bashInteractive) "-l" ] # default command when run with no args
, directory ? null # created + cd'd into on launch; granted rw; the holm's $HOME when homeManager is set
, contexts ? lib.optional (directory != null) directory
, env ? { }
, workspace ? (homeManager == null) # Island's per-profile XDG dirs; off when the holm has its own home
, logAudit ? false # pass --log-audit (denials in kernel audit log; Linux >= 6.15)
, syncProfile ? true # set false if something else installs the profile files
, landlock ? { } # arguments to mk-landlock-policy.nix
, extraLandlockFiles ? { }

  # Replace the blanket "/nix/store" read+execute grant with the exact
  # runtime closure of this holm's environment (HM home, launcher,
  # command), enumerated at build time. Anything outside the closure —
  # other users' profiles, tools the holm never declared — becomes
  # unreadable and unexecutable. See README for the tradeoffs.
, confineToClosure ? false
, extraClosureRoots ? [ ] # additional store paths/derivations to allow

  # Per-holm home-manager configuration (null = plain sandboxed shell):
  # {
  #   username;              # your real login name (HM activation checks $USER)
  #   modules = [ ... ];     # this holm's home-manager modules
  #   stateVersion ? "25.05";
  #   extraSpecialArgs ? { };
  # }
, homeManager ? null
}:

let
  # Landlock configs have no ~/$HOME expansion, and the same path is baked
  # into the policy, so relative/tilde paths would silently grant nothing.
  _assertAbs = lib.assertMsg
    (directory == null || lib.hasPrefix "/" (toString directory))
    "mkHolm(${name}): `directory` must be an absolute path";

  _assertHm = lib.assertMsg
    (homeManager == null || (directory != null && home-manager != null))
    ("mkHolm(${name}): `homeManager` needs a `directory` (the holm's "
      + "home) and a `home-manager` input passed to the builder");

  mkPolicyLib = import ./mk-landlock-policy.nix { inherit lib; };
  inherit (mkPolicyLib) mkPolicy;
  mkProfile = import ./mk-profile.nix { inherit pkgs lib; };
  mkHome = import ./mk-holm-home.nix { inherit pkgs lib; };
  tomlFormat = pkgs.formats.toml { };

  hm =
    if homeManager == null then null
    else mkHome {
      inherit home-manager;
      inherit (homeManager) username;
      homeDirectory = directory;
      modules = homeManager.modules or [ ];
      stateVersion = homeManager.stateVersion or "25.05";
      extraSpecialArgs = homeManager.extraSpecialArgs or { };
    };

  mkHomeLinker = import ./mk-home-linker.nix { inherit pkgs lib; };
  homeLinker =
    if hm == null then null
    else mkHomeLinker {
      inherit name;
      inherit (hm) homeFiles;
      homeDirectory = directory;
    };

  # The launch directory must be writable, or the shell can't even
  # read its own cwd.
  policyArgs = landlock // {
    readWritePaths =
      (landlock.readWritePaths or [ ])
      ++ lib.optional (directory != null) directory;
  } // lib.optionalAttrs confineToClosure {
    # The closure replaces the blanket store grant (appended below).
    readExecutePaths = lib.subtractLists [ "/nix/store" ]
      (landlock.readExecutePaths or mkPolicyLib.defaults.readExecutePaths);
  };

  basePolicyFile =
    tomlFormat.generate "holm-${name}-base-policy.toml" (mkPolicy policyArgs);

  # Everything that must be reachable INSIDE the sandbox, as a single
  # aggregate root whose closure we enumerate at build time. Activation
  # runs outside the sandbox, but innerLaunch references the activation
  # package (via home-path), so the whole HM environment is included.
  closureRootsFile = pkgs.writeText "holm-${name}-closure-roots"
    (lib.concatMapStrings (p: "${toString p}\n")
      (command
        ++ lib.optional (hm != null) innerLaunch
        ++ extraClosureRoots));

  closureList =
    if pkgs ? writeClosure
    then pkgs.writeClosure [ closureRootsFile ]
    else pkgs.writeReferencesToFile closureRootsFile;

  # TOML permits appending further [[path_beneath]] entries after other
  # top-level tables; store paths never need escaping.
  policyFile =
    if !confineToClosure then basePolicyFile
    else
      pkgs.runCommand "holm-${name}-policy.toml" { } ''
        {
          cat ${basePolicyFile}
          echo
          echo '# Runtime closure of this holm (generated at build time).'
          echo '[[path_beneath]]'
          echo 'allowed_access = ["abi.read_execute"]'
          echo 'parent = ['
          sed 's|.*|    "&",|' ${closureList}
          echo ']'
        } > "$out"
      '';

  profileDrv = mkProfile {
    name = profileName;
    inherit contexts env workspace extraLandlockFiles;
    landlockPolicyFile = policyFile;
  };

  runArgs = lib.escapeShellArgs
    (lib.optional logAudit "--log-audit" ++ [ "-p" profileName ]);

  # Runs INSIDE the sandbox: adopt the holm home, load the HM session,
  # then exec the requested command. No `set -u` here — hm-session-vars.sh
  # is not written for it.
  innerLaunch = lib.optionalString (hm != null)
    (pkgs.writeShellScript "holm-${name}-launch" ''
      export HOME=${lib.escapeShellArg directory}
      export USER=${lib.escapeShellArg homeManager.username}
      cd "$HOME" || exit 1
      hmVars="${hm.homePath}/etc/profile.d/hm-session-vars.sh"
      # shellcheck disable=SC1090
      [ -f "$hmVars" ] && . "$hmVars"
      export PATH="${hm.homePath}/bin:$PATH"
      if [ "$#" -gt 0 ]; then
        exec "$@"
      else
        exec ${lib.escapeShellArgs command}
      fi
    '');
in
assert _assertAbs;
assert _assertHm;
pkgs.writeShellApplication {
  inherit name;
  runtimeInputs = [ island pkgs.coreutils ];

  text = ''
    ${lib.optionalString syncProfile ''
      # --- sync the declarative profile into Island's config dir ---
      cfg="''${XDG_CONFIG_HOME:-$HOME/.config}/island/profiles/${profileName}"
      mkdir -p "$cfg/landlock"
      ln -sfT ${profileDrv}/profile.toml "$cfg/profile.toml"
      # Drop stale policy symlinks from previous generations, keep any
      # hand-written local files.
      for f in "$cfg/landlock"/*; do
        [ -L "$f" ] || continue
        case "$(readlink "$f")" in
          /nix/store/*) rm -f "$f" ;;
        esac
      done
      for f in ${profileDrv}/landlock/*; do
        ln -sfT "$f" "$cfg/landlock/$(basename "$f")"
      done
    ''}
    ${lib.optionalString (directory != null) ''
      mkdir -p ${lib.escapeShellArg directory}
      cd ${lib.escapeShellArg directory}
    ''}
    ${lib.optionalString (hm != null) ''
      # --- materialize this holm's dotfiles (generation-aware; no nix
      # daemon, no shared per-user profile state; no-op when unchanged) ---
      ${homeLinker}/bin/${homeLinker.name}
    ''}
    ${lib.optionalString (hm != null) ''
      if [ "$#" -gt 0 ]; then
        exec island run ${runArgs} -- ${innerLaunch} "$@"
      else
        exec island run ${runArgs} -- ${innerLaunch}
      fi
    ''}
    ${lib.optionalString (hm == null) ''
      if [ "$#" -gt 0 ]; then
        exec island run ${runArgs} -- "$@"
      else
        exec island run ${runArgs} -- ${lib.escapeShellArgs command}
      fi
    ''}
  '';
}
