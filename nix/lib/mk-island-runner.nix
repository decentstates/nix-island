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

  runner = pkgs.writeShellApplication {
    name = runnerName;
    text = ''
      exec ${island}/bin/island run -p ${lib.escapeShellArg profileName} -- \
        ${envFilterer} "$@"
    '';
  };
in runner
