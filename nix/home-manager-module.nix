hmArgs@{ config, inputs, lib, pkgs, modulesPath, ... }:

let
  cfg = config.housing;

  housingLib = import ./lib.nix { inherit pkgs; island = cfg.islandPackage; };

  realHomeDir = config.home.homeDirectory;

  tmpDir = houseName: "/tmp/houses-${config.home.username}/${houseName}";
  runDir = houseName: "/tmp/houses-${config.home.username}/${houseName}/run";

  # TODO: Simplify/remove
  # TODO: remove profile name runner name, add just name
  houseCtx = houseName: houseConfig: {
    inherit houseName;
    inherit (houseConfig) 
      runnerName 

      username
      realHomeDir

      tmpDir
      runDir
      houseHomeDir;
  };

  mkHouseHm = houseConfig: import modulesPath {
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
        imports = houseConfig.modules;
        home = {
          inherit (config.home) stateVersion;
          inherit (houseConfig) username;
          homeDirectory = houseConfig.houseHomeDir;
          sessionVariables = {
            HOME = innerConfig.home.homeDirectory;
            TMPDIR = houseConfig.tmpDir;
            HOUSE_NAME = houseConfig.houseName;
            # Used directly in Fish shell, added into other shells below:
            SHELL_PROMPT_PREFIX = "⟦${houseConfig.houseName}⟧ ";
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

  houseModule = { name, houseConfig, ... }:
    {
    # TODO: Add defaultText for these
    options = {
      runnerName = lib.mkOption {
        type = lib.types.strMatching "[a-zA-Z0-9_-]+";
        default =  "house-${houseName}";
        description = "House runner executable name";
      };

      # TODO make home-manager/nixos agnostic, use null if not avail and throw an assertion.
      username = lib.mkOption {
        type = lib.types.strMatching "[a-zA-Z0-9_-]+";
        default = config.home.username;
        description = "Owner of the house";
      };
      realHomeDir = lib.mkOption {
        type = lib.types.path;
        default = config.home.homeDirectory;
        defaultText = lib.literalExpression ''"''${config.home.homeDirectory}"'';
        description = "The user's real home.";
      };

      tmpDir = lib.mkOption {
        type = lib.types.path;
        default = "/tmp/houses-${cfg.username}/${cfg.houseName}";
        description = "$TMPDIR";
      };
      runDir = lib.mkOption {
        type = lib.types.path;
        default = "/tmp/houses-${cfg.username}/${cfg.houseName}/run";
        description = "$XDG_RUNTIME_DIR";
      };
      houseHomeDir = lib.mkOption {
        type = lib.types.path;
        default = "${cfg.realHomeDir}/houses/${name}";
        defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/houses/<name>"'';
        description = "The house's home directory.";
      };

      capabilities = lib.mkOption {
        type = lib.types.deferredModule;
        default = { };
        description = ''
          a separate modules system.

          builds a series of execWrapper (type: dagOf).

          You might want:
          `simple.connectTcpPorts = [80, 443]`
          `simple.bindTcpPorts = [0]`
          `waylands.enable = true`

          Can use `imports = []` to provide your own capabilities modules:
          ```
          imports = [ { pkgs, lib, house }: { ... } ]
          ```

          Where house is:
          ```
          { runnerName, houseHomeDir, tmpDir, runDir, realHomeDir, username }
          ```
        '';
      };

      runner = lib.mkOption {
        type = lib.types.raw;
        readOnly = true;
        default = housinglib.mkCapabilitiesRunner houseConfig.capabilities;
        description = ''
          The runner pkg.
        '';
      };

      hm = {
        modules = lib.mkOption {
          type = lib.types.listOf lib.types.deferredModule;
          default = [ ];
          description = "The house's home-manager modules.";
        };
        homeManagerConfiguration = lib.mkOption {
          type = lib.types.raw;
          readOnly = true;
          default = mkHouseHm houseConfig;
          defaultText = lib.literalMD "the evaluated nested home-manager configuration of this house";
          description = ''
            The house's evaluated nested home-manager configuration
            (read-only). Exposes e.g. `.activationPackage` and `.config`.
          '';
        };
        desktopEntries = lib.mkOption {
          type = lib.types.package;
          readOnly = true;
          default = mkDesktopEntries houseConfig;
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
      default = pkgs.callPackage ./pkgs/island/package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ./pkgs/island/package.nix { }";
      description = "The island (Landlock sandboxing tool) package to use.";
    };
    houses = lib.mkOption {
      # TODO: Assert house name is a reasonable identifier
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
