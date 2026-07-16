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
  envFilterer = pkgs.writeShellScript "house-${profileName}-shell-filterer" ''
      keep=()
      for v in ${toString passthroughEnv}; do
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
