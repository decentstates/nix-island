# nix-holm-manager: evaluate a home-manager configuration and feed the
# core its two inputs — packages += home-path (hm-session-vars rides in
# via etc/profile.d), holmFiles = home-files. Other args pass through.
# The full HM activation script is never run; see mk-home-linker.nix.
{ pkgs
, lib ? pkgs.lib
, island ? pkgs.callPackage ./island-package.nix { }
, home-manager # flake input or source path (both coerce to a path)
}:

args@{ name
, directory
, username # evaluation-time only (home.username)
, modules ? [ ]
, stateVersion ? "25.05"
, ...
}:

let
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

  mkHolm = import ./mk-holm.nix { inherit pkgs lib island; };
in
mkHolm (builtins.removeAttrs args [ "username" "modules" "stateVersion" ] // {
  packages = (args.packages or [ ])
    ++ [ "${home.activationPackage}/home-path" ];
  holmFiles = "${home.activationPackage}/home-files";
})
