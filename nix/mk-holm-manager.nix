# nix-holm-manager: plug a home-manager configuration into a holm.
#
# Evaluates a standalone HM home whose homeDirectory is the holm's
# directory, then calls the nix-holm core with exactly its two inputs:
#   packages += home-path    (home.packages + programs.*; brings
#                             hm-session-vars.sh in via etc/profile.d)
#   dotfiles  = home-files   (the rendered dotfile tree)
# All other mkHolm arguments pass straight through.
{ pkgs
, lib ? pkgs.lib
, island ? pkgs.callPackage ./island-package.nix { }
, home-manager # flake input or source path (both coerce to a path)
}:

args@{ name
, directory
, username # for home.username (evaluation-time only)
, modules ? [ ] # this holm's home-manager modules
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
  dotfiles = "${home.activationPackage}/home-files";
})
