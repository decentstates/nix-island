hmArgs@{ config, inputs, lib, pkgs, modulesPath, ... }:

let
  cfg = config.island;
  islandLib = import ./lib.nix { inherit pkgs; island = cfg.package; };

  realHomeDir = config.home.homeDirectory;

  tmpDir = i: "/tmp/islands-${config.home.username}/${i.profileName}";
  runDir = i: "/tmp/islands-${config.home.username}/${i.profileName}/run";

  islandCtx = i: {
    inherit (i) profileName runnerName islandHomeDir;
    inherit realHomeDir;
    tmpDir = tmpDir i;
    runDir = runDir i;
    username = config.home.username;
  };

  mkRunner = i:
    let
      inner = pkgs.writeShellScript "activate" ''
        set -e

        # Bootstrapping the env vars
        export HOME="${i.islandHomeDir}"
        export TMPDIR="${tmpDir i}"
        # Required for the sourcing below to correcly find the nix-profile:
        export XDG_STATE_HOME="${i.islandHomeDir}/.local/state"

        . /etc/profile
        . ${i.hm.homeManagerConfiguration.activationPackage}/home-path/etc/profile.d/hm-session-vars.sh

        [ "$#" -gt 0 ] && exec "$@" || exec "$SHELL" -l
      '';
      capabilitiesRunner = islandLib.mkCapabilitiesRunner {
        island = islandCtx i;
        capabilitiesModule = i.capabilities;
      };
    in
    pkgs.writeShellApplication {
      name = i.runnerName;
      text = ''
        exec ${capabilitiesRunner}/bin/${i.runnerName} ${inner} "$@"
      '';
    };

  mkProfile = i: islandLib.mkIslandProfile {
    inherit (i) profileName;
    inherit (i.capabilityConfig)
      readOnlyPaths readWritePaths
      bindTcpPorts connectTcpPorts;
  };

  mkIslandHm = i: import modulesPath {
    inherit pkgs;
    check = true;
    # HACK: But should be stable as HM adding extra args is a breaking
    #       change to their API, with nix used namespaces more...
    extraSpecialArgs = builtins.removeAttrs hmArgs.specialArgs [
     "modulesPath" "lib" "osConfig" "osClass"
    ];
    configuration = innerHomeManagerArgs:
      let
        innerConfig = innerHomeManagerArgs.config;
      in
      {
        imports = i.modules;
        home = {
          inherit (config.home) username stateVersion;
          homeDirectory = i.islandHomeDir;
          sessionVariables = {
            HOME = innerConfig.home.homeDirectory;
            TMPDIR = (tmpDir i);
            ISLAND_NAME = i.profileName;
            # Used directly in Fish shell, added into other shells below:
            SHELL_PROMPT_PREFIX = "⟦${i.profileName}⟧ ";
          };
        };
        programs.bash.initExtra = lib.mkAfter ''
          PS1="$SHELL_PROMPT_PREFIX$PS1"
        '';
        programs.zsh.initContent = lib.mkOrder 1500 ''
          PROMPT="$SHELL_PROMPT_PREFIX$PROMPT"
        '';
        xdg = {
          enable = true;
        };
      };
  };

  mkDesktopEntries = i: pkgs.runCommand "island-${i.profileName}-desktop-entries" { } ''
    apps=${i.hm.homeManagerConfiguration.activationPackage}/home-path/share/applications
    mkdir -p "$out/share/applications"
    [ -d "$apps" ] || exit 0
    for entry in "$apps"/*.desktop; do
      [ -e "$entry" ] || continue
      sed \
        -e 's|^Exec=|Exec=${mkRunner i}/bin/${i.runnerName} |' \
        -e 's|^\(Name\(\[[^]]*\]\)\{0,1\}=.*\)$|\1 ⟦${i.profileName}⟧|' \
        -e '/^DBusActivatable=/d' \
        -e '/^TryExec=/d' \
        "$entry" > "$out/share/applications/island-${i.profileName}-$(basename "$entry")"
    done
  '';

  islandModule = { name, config, ... }:
    let
      i = config;
    in
    {
    options = {
      profileName = lib.mkOption {
        type = lib.types.strMatching "[a-zA-Z0-9_-]+";
        default =  "${name}";
        description = "Island profile name";
      };
      runnerName = lib.mkOption {
        type = lib.types.strMatching "[a-zA-Z0-9_-]+";
        default =  "island-${name}";
        description = "Island runner executable name";
      };
      islandHomeDir = lib.mkOption {
        type = lib.types.str;
        default = "${realHomeDir}/islands/${name}";
        defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/islands/<name>"'';
        description = "The island's home directory (absolute, beneath the user home).";
      };
      modules = lib.mkOption {
        type = lib.types.listOf lib.types.deferredModule;
        default = [ ];
        description = "The island's home-manager modules.";
      };
      capabilities = lib.mkOption {
        type = lib.types.deferredModule;
        default = { };
        description = ''
          a separate modules system.

          The actual config used:
          `passthroughEnv`, `execWrappers`,
          `bindTcpPorts`, `connectTcpPorts`, `readOnlyPaths` and
          `readWritePaths`

          You might want:
          `waylands.enable = true`

          Can use `imports = []` to provide your own capabilities modules:
          ```
          imports = [ { pkgs, lib, island }: { ... } ]
          ```

          Where island is:
          ```
          { profileName, runnerName, islandHomeDir, tmpDir, runDir, realHomeDir, username }
          ```
        '';
      };
      capabilityConfig = lib.mkOption {
        type = lib.types.raw;
        readOnly = true;
        default = (islandLib.evalCapabilities {
          island = islandCtx i;
          module = i.capabilities;
        }).config;
        defaultText = lib.literalMD "the evaluated capability configuration of this island";
        description = ''
          The island's evaluated capability configuration (read-only),
          e.g. `.readWritePaths`, `.execWrappers`.
        '';
      };
      hm = {
        homeManagerConfiguration = lib.mkOption {
          type = lib.types.raw;
          readOnly = true;
          default = mkIslandHm i;
          defaultText = lib.literalMD "the evaluated nested home-manager configuration of this island";
          description = ''
            The island's evaluated nested home-manager configuration
            (read-only). Exposes e.g. `.activationPackage` and `.config`.
          '';
        };
        desktopEntries = lib.mkOption {
          type = lib.types.package;
          readOnly = true;
          default = mkDesktopEntries i;
          defaultText = lib.literalMD "generated desktop entries for this island's applications";
          description = ''
            Derivation with `share/applications/*.desktop` entries for every
            desktop entry installed in the island's nested home-manager
            environment, rewritten to launch through the island runner and
            tagged with `⟦<profileName>⟧` (read-only).
          '';
        };
      };
    };
  };
in
{
  options.island = {
    enable = lib.mkEnableOption "Enable island.";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./island/island-package.nix { };
      description = "Island package.";
    };
    islands = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule islandModule);
      default = { };
      description = "Island sandbox profiles";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = lib.mapAttrsToList (name: i: {
      assertion = lib.hasPrefix "${realHomeDir}/" i.islandHomeDir;
      message = ''
        island.islands.${name}.islandHomeDir (${i.islandHomeDir}) must be
        an absolute path beneath the user home (${realHomeDir}).
      '';
    }) cfg.islands;

    home.packages =
      [ cfg.package ]
        ++ lib.mapAttrsToList (_: i: mkRunner i) cfg.islands;

    xdg.configFile = lib.mapAttrs' (_: i:
      lib.nameValuePair "island/profiles/${i.profileName}" {
        source = mkProfile i;
        recursive = true;
      }) cfg.islands;

    home.file = lib.mapAttrs' (_: i:
      lib.nameValuePair
        "${lib.removePrefix "${realHomeDir}/" i.islandHomeDir}/.keep"
        { text = ""; }) cfg.islands;

    home.activation = lib.mapAttrs' (_: i:
      lib.nameValuePair "island-nested-home-manager-activate-${i.profileName}"
        (lib.hm.dag.entryAfter [ "writeBoundary" "linkGeneration" "installPackages"] (
         ''
           if [ -e "$HOME/.nix-profile" ] && [ -z "$HAS_WARNED_ABOUT_NIX_PROFILE" ]; then
               warnEcho "nix-island: WARNING: ~/.nix-profile exists."
               warnEcho "nix-island: Home-manager now stores profiles under XDG dirs allowing isolation."
               warnEcho "nix-island: You still have the legacy profile link, this will prevent environment isolation."
               warnEcho "nix-island: It should be safe to delete it AFAIK:"
               warnEcho "nix-island:    rm ~/.nix-profile"
               HAS_WARNED_ABOUT_NIX_PROFILE="true"
           fi

           run ${mkRunner i}/bin/${(mkRunner i).name} ${i.hm.homeManagerConfiguration.activationPackage}/activate
         ''))) cfg.islands;
  };
}
