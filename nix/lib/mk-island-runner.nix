{ pkgs
, lib
, island
}:

{ runnerName
, profileName
, passthroughEnv ? [ ] 
}:


assert builtins.match "^[A-Za-z0-9_-]+$" runnerName != null;

assert lib.assertMsg (lib.all (v: builtins.match "^[A-Za-z_][A-Za-z0-9_]*$" v != null) passthroughEnv)
  "passthroughEnv contains an invalid environment variable name";

let
  innerRunner = pkgs.writeShellScript "island-${profileName}-inner-runner" ''
    # Testing the environment
    # TODO: Maybe disable XDG_CONFIG_DIRS/XDG_DATA_DIRS
    /usr/bin/env
    [[ -n "''${XDG_DATA_HOME:-}"       && "''${XDG_DATA_HOME:-}"   != "$HOME/.local/share" ]] \
    && [[ -n "''${XDG_CONFIG_HOME:-}"  && "''${XDG_CONFIG_HOME:-}" != "$HOME/.config" ]] \
    && [[ -n "''${XDG_STATE_HOME:-}"   && "''${XDG_STATE_HOME:-}"  != "$HOME/.local/state" ]] \
    && [[ -n "''${XDG_CACHE_HOME:-}"   && "''${XDG_CACHE_HOME:-}"  != "$HOME/.cache" ]] \
    && [[ -n "''${XDG_RUNTIME_DIR:-}"  && "''${XDG_RUNTIME_DIR:-}"  != "/tmp" ]] \
    && [[ -n "''${TMPDIR:-}"           && "''${TMPDIR:-}"  != "/tmp" ]] \
    || { echo "One or more XDG dirs are default/unset." >&2; exit 1; }

    if [ "$#" -gt 0 ]; then
      exec "$@"
    else
      exec "''${SHELL:-bash}"
    fi
  '';

  passthroughEnv' = passthroughEnv ++ [
    "XDG_DATA_HOME"
    "XDG_CONFIG_HOME"
    "XDG_STATE_HOME"
    "XDG_CACHE_HOME"
    "XDG_RUNTIME_DIR"
    "TMPDIR"
    "ISLAND_CONTEXT_BENEATH"
    ];

  envFilterer = pkgs.writeShellScript "island-${profileName}-shell-filterer" ''
      keep=()
      for v in ${toString passthroughEnv'}; do
        if [ -n "''${!v+x}" ]; then keep+=("$v=''${!v}"); fi
      done
      ${pkgs.coreutils}/bin/env -i "''${keep[@]}"  "$@"
  '';

  outerRunner = pkgs.writeShellApplication {
    name = runnerName;
    text = ''
      exec ${island}/bin/island run -p ${lib.escapeShellArg profileName} -- \
        ${envFilterer} ${innerRunner} "$@"
    '';
  };
in outerRunner
