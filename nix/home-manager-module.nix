hmArgs@{ config, inputs, lib, pkgs, modulesPath, ... }:

let
  cfg = config.housing;
  housingLib = import ./lib.nix { inherit pkgs; island = cfg.islandPackage; };

  realHomeDir = config.home.homeDirectory;

  tmpDir = h: "/tmp/houses-${config.home.username}/${h.profileName}";
  runDir = h: "/tmp/houses-${config.home.username}/${h.profileName}/run";

  houseCtx = h: {
    inherit (h) profileName runnerName houseHomeDir;
    inherit realHomeDir;
    tmpDir = tmpDir h;
    runDir = runDir h;
    username = config.home.username;
  };

  mkRunner = h:
    let
      inner = pkgs.writeShellScript "activate" ''
        set -e

        # Bootstrapping the env vars
        export HOME="${h.houseHomeDir}"
        export TMPDIR="${tmpDir h}"
        # Required for the sourcing below to correcly find the nix-profile:
        export XDG_STATE_HOME="${h.houseHomeDir}/.local/state"

        . /etc/profile
        . ${h.hm.homeManagerConfiguration.activationPackage}/home-path/etc/profile.d/hm-session-vars.sh

        [ "$#" -gt 0 ] && exec "$@" || exec "$SHELL" -l
      '';
      capabilitiesRunner = housingLib.mkCapabilitiesRunner {
        house = houseCtx h;
        capabilitiesModule = h.capabilities;
      };
    in
    pkgs.writeShellApplication {
      name = h.runnerName;
      text = ''
        exec ${capabilitiesRunner}/bin/${h.runnerName} ${inner} "$@"
      '';
    };

  mkProfile = h: housingLib.mkHouseProfile {
    inherit (h) profileName;
    inherit (h.capabilityConfig)
      readOnlyPaths readWritePaths
      bindTcpPorts connectTcpPorts;
  };

  mkHouseHm = h: import modulesPath {
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
        imports = h.modules;
        home = {
          inherit (config.home) username stateVersion;
          homeDirectory = h.houseHomeDir;
          sessionVariables = {
            HOME = innerConfig.home.homeDirectory;
            TMPDIR = (tmpDir h);
            HOUSE_NAME = h.profileName;
            # Used directly in Fish shell, added into other shells below:
            SHELL_PROMPT_PREFIX = "⟦${h.profileName}⟧ ";
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

  mkDesktopEntries = h: pkgs.runCommand "house-${h.profileName}-desktop-entries" { } ''
    apps=${h.hm.homeManagerConfiguration.activationPackage}/home-path/share/applications
    mkdir -p "$out/share/applications"
    [ -d "$apps" ] || exit 0
    for entry in "$apps"/*.desktop; do
      [ -e "$entry" ] || continue
      sed \
        -e 's|^Exec=|Exec=${mkRunner h}/bin/${h.runnerName} |' \
        -e 's|^\(Name\(\[[^]]*\]\)\{0,1\}=.*\)$|\1 ⟦${h.profileName}⟧|' \
        -e '/^DBusActivatable=/d' \
        -e '/^TryExec=/d' \
        "$entry" > "$out/share/applications/house-${h.profileName}-$(basename "$entry")"
    done
  '';

  houseModule = { name, config, ... }:
    let
      h = config;
    in
    {
    options = {
      profileName = lib.mkOption {
        type = lib.types.strMatching "[a-zA-Z0-9_-]+";
        default =  "${name}";
        description = "House profile name";
      };
      runnerName = lib.mkOption {
        type = lib.types.strMatching "[a-zA-Z0-9_-]+";
        default =  "house-${name}";
        description = "House runner executable name";
      };
      houseHomeDir = lib.mkOption {
        type = lib.types.str;
        default = "${realHomeDir}/houses/${name}";
        defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/houses/<name>"'';
        description = "The house's home directory (absolute, beneath the user home).";
      };
      modules = lib.mkOption {
        type = lib.types.listOf lib.types.deferredModule;
        default = [ ];
        description = "The house's home-manager modules.";
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
          imports = [ { pkgs, lib, house }: { ... } ]
          ```

          Where house is:
          ```
          { profileName, runnerName, houseHomeDir, tmpDir, runDir, realHomeDir, username }
          ```
        '';
      };
      capabilityConfig = lib.mkOption {
        type = lib.types.raw;
        readOnly = true;
        default = (housingLib.evalCapabilities {
          house = houseCtx h;
          module = h.capabilities;
        }).config;
        defaultText = lib.literalMD "the evaluated capability configuration of this house";
        description = ''
          The house's evaluated capability configuration (read-only),
          e.g. `.readWritePaths`, `.execWrappers`.
        '';
      };
      hm = {
        homeManagerConfiguration = lib.mkOption {
          type = lib.types.raw;
          readOnly = true;
          default = mkHouseHm h;
          defaultText = lib.literalMD "the evaluated nested home-manager configuration of this house";
          description = ''
            The house's evaluated nested home-manager configuration
            (read-only). Exposes e.g. `.activationPackage` and `.config`.
          '';
        };
        desktopEntries = lib.mkOption {
          type = lib.types.package;
          readOnly = true;
          default = mkDesktopEntries h;
          defaultText = lib.literalMD "generated desktop entries for this house's applications";
          description = ''
            Derivation with `share/applications/*.desktop` entries for every
            desktop entry installed in the house's nested home-manager
            environment, rewritten to launch through the house runner and
            tagged with `⟦<profileName>⟧` (read-only).
          '';
        };
      };
    };
  };
in
{
  options.housing = {
    enable = lib.mkEnableOption "Enable housing.";
    islandPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./island/island-package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ./island/island-package.nix { }";
      description = "The island (Landlock sandboxing tool) package to use.";
    };
    houses = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule houseModule);
      default = { };
      description = "House sandbox profiles";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = lib.mapAttrsToList (name: h: {
      assertion = lib.hasPrefix "${realHomeDir}/" h.houseHomeDir;
      message = ''
        housing.houses.${name}.houseHomeDir (${h.houseHomeDir}) must be
        an absolute path beneath the user home (${realHomeDir}).
      '';
    }) cfg.houses;

    home.packages =
      [ cfg.islandPackage ]
        ++ lib.mapAttrsToList (_: h: mkRunner h) cfg.houses;

    xdg.configFile = lib.mapAttrs' (_: h:
      lib.nameValuePair "island/profiles/${h.profileName}" {
        source = mkProfile h;
        recursive = true;
      }) cfg.houses;

    home.file = lib.mapAttrs' (_: h:
      lib.nameValuePair
        "${lib.removePrefix "${realHomeDir}/" h.houseHomeDir}/.keep"
        { text = ""; }) cfg.houses;

    home.activation = lib.mapAttrs' (_: h:
      lib.nameValuePair "house-nested-home-manager-activate-${h.profileName}"
        (lib.hm.dag.entryAfter [ "writeBoundary" "linkGeneration" "installPackages"] (
         ''
           run ${mkRunner h}/bin/${(mkRunner h).name} ${h.hm.homeManagerConfiguration.activationPackage}/activate
         ''))) cfg.houses;
  };
}
