# nix-housing

> little houses inside your home. 
> better hygiene for your shell.
> nix-defined sandboxed enviromnents.

- Landlock + namespacing
- home-manager configurable
- composable
- lightweight and easy to configure


## Using with home-manager

1. Add this repo as a flake input.
   ```nix
   inputs.nix-housing.url = "github:decentstates/nix-housing";
   inputs.nix-housing.inputs.nixpkgs.follows = "nixpkgs";
   inputs.nix-housing.inputs.home-manager.follows = "home-manager";
   ```
2. Define your houses in your home-manager config:
   ```
   { pkgs, inputs, config, ... }:
   let
     lib = pkgs.lib;
   in
   {
     imports = [
       inputs.nix-housing.homeManagerModules.default
     ];

     housing = {
       enable = true;
       houses = {
        secure = {
          modules = [
            ./profiles/common.nix
            ./profiles/no-autorun.nix
            ./profiles/vim-minimal.nix
          ];
          capabilities = {
            readWritePaths = [
              config.housing.houses.development.houseHomeDir
            ];
          };
        };
        development = {
          modules = [
            ./profiles/common.nix
            ./profiles/unsafe-development.nix
            ./profiles/vim-full.nix
          ];
          capabilities = {
            readWritePaths = [
              config.housing.houses.slop.houseHomeDir
            ];
          };
        };
        slop = {
          capabilities = {
            connectTcpPorts = [ 443 ];
          };
          modules = [
            ./profiles/common.nix
            ./profiles/unsafe-development.nix
            ./profiles/unsafe-development-rust.nix
            ./profiles/unsafe-llm.nix
            ./profiles/vim-full.nix
          ];
        };
        desktop = {
          capabilities = {
            wayland.enable = true;
            connectTcpPorts = [ 80 443 ];
          };
          modules = [
            ./profiles/common.nix
            {
              programs.firefox.enable = true;
              home.packages = [ pkgs.zeal ];
              fonts.fontconfig.enable = true;
            }
          ];
        };
      };
    };
    ```

### `housing.house.<house-name>.runnerName`

The houses runner executable, by default `house-<house-name>`
The above config creates `house-secure`, `house-development`, `house-slop` and `house-desktop`.

### `housing.house.<house-name>.houseHomeDir`

The houses home directory, by default `~/houses/<house-name>`

### `housing.house.<house-name>.modules`

This behaves just like home-manager modules, except they don't exist in your
home-manager but in the house's home-manager.

### `housing.house.<house-name>.capabilities`

This attribute set specifies what a house has access to.
This is generally a white listing system.

The `simple` capability provides sensible default filesystem and network
allow-lists and is enabled by default; set `simple.enable = false` to start
from an empty sandbox and grant everything explicitly.

These are the actual options:
- `envPassthrough` What env vars to pass through to the sandbox.
- `execWrappers` You can wrap the runner to run code before the sandbox, useful
  for setting up proxy sockets.
- `bindTcpPorts`
- `connectTcpPorts`
- `readExecutePaths`
- `readWritePaths`

On top of these you might want to use `capabilites.wayland.enable`.

You can also make your own capability modules, capabilites functions as an
independent module system to home-manager, providing the same module mechanics:
```nix
{ config, pkgs, lib, osConfig, ... }:
let 
  capabilityPersistent = {
    readWritePaths = [
      osConfig.environment.sessionVariables.USER_PERSISTENT_DIR
    ];
    envPassthrough = [
      "USER_PERSISTENT_DIR"
    ];
  };
  capabilityTPM = {
    readWritePaths = [ "/dev/tpmrm0" ];
  };
in
{
  housing.houses.secure = {
    capabilities = {
      imports = [ 
        capabilityPersistent 
        capabilityTPM
        ];
    };
    modules = [ 
      ...
    ];
  };
}
```

### Desktop applications: `housing.house.<house-name>.hm.desktopEntries`

Houses export desktop entries rewritten to launch within the sandbox, this is how I use them in sway:

```nix
{
  xdg.dataFile."house-applications/applications".source =
    "${pkgs.symlinkJoin {
      name = "house-applications";
      paths = lib.mapAttrsToList (_: h: h.hm.desktopEntries) config.housing.houses;
    }}/share/applications";

  home.file."scripts/wmenu-house-apps.sh" = {
    text =
    ''
      #!/usr/bin/env bash

      export XDG_DATA_DIRS="$HOME/.local/share/house-applications"
      exec j4-dmenu-desktop --skip-i3-exec-check --dmenu=wmenu --term=foot
    '';
    executable = true;
  };
}
```

Integrating into your WM is left as an exercise for the reader.


## Using without home-manager

The `lib` code can be used without home-manager, left as an exercise for the reader.

## Design

nix-housing, inspired by [Island](https://github.com/landlock-lsm/island), realises that for effective sandboxing:
- Data must be paired with software, and software paired with data.
- On the shell environments of apps are necessary, not single sandboxed apps.
- Instead of some software running in sandboxes, we should always be in a sandboxed environment.
- With nix, building and composing sandboxed environments becomes nice.

> Warning:
> I am not a security expert, this is experimental.

Recommended use:
- Have minimal applications installed into your base system and user profile.
- Houses for `untrusted`, `development`, `secure`, `personal`.
- Each has repositories, `secure` can pull/push to `development` which can pull/push to `untrusted`.
- `secure`:
  - has access to keys and SUID binaries
  - prevents auto-running code like git-hooks, direnv
  - prevents auto-proliferating data like undo-files and backup files in vim.
- `personal` has email, messaging, web browser.
- When you want a terminal you choose an environment, on sway I use wmenu to list them.
  - I add an unsandboxed shell option.
  - Each house/unsandboxed gets a different terminal theme.
- When the WM shows Apps, it builds them from the house's desktopEntries, that automatically sandbox them.
- Customise it as you like, have a house for no-javascript web browsing, that can only access certain websites if you need.

The result:
- Sandboxing by default.
- Data isolation between sandboxes.
- Low attack surface outside the sandboxes.
- Ability to run the unsandboxed shell if I need to escalate.

### FAQs

#### What threat are we mitigating:
- Undesirable user-context code execution, malicious or not.
  - Slop code.
  - Supply-chain attacks.
  - Dev-tool attacks.
  - Accidental authenticated actions.

  From limiting what data we have access to (hard control via landlock), 
  and environment software and configuration (soft control via nix/home-manager.)

#### What doesn't this protect from:
- Landlock escapes.
- Privilege escalation attacks.
- Kernel attacks.

#### Why not user namespaces / containers, seccomp-bpf, different users, bubblewrap for sandboxing:
- A different sandboxing mechanism can be used.
- I'm no expert here but landlock seems simpler, lower surface area, purpose built for this.
- Avoid file permission issues between users/namespaces.

#### Isn't this similar to bubblewrap/flatpack/etc:
- probably
- but focused on environments + data, instead of executables, or apps + data.
- I want to achieve something similar to MacOS, where the terminal can't access
  my documents directory.


### notes:
- nix.settings.use-xdg-base-directories should be set to true to allow isolated home-manager environments to be set up.
- house home-manager modules recieve the same extraSpecialArgs as the parent home-manager


## similar and related tools

data-oriented sandboxing:
- island - (landlock) this tool is built using and inspired heavily by island.

executable-oriented sandboxing:
- flatpak - App wrapping using bubblewrap.
- firejail - namespace+seccomp-bpf sandboxing
- bubblewrap -
- bubblejail
- landrun - (landlock) similar to bubblewrap but using landlock.

System wide sandboxing:
- systemd - sandboxing services (complementary)
- apparmor - file-path based security policy
- selinux - similar to above but file-label based security policy

## Limitations

These can be addresses somewhat but haven't yet.
- [ ] /proc is by default read-write to make a lot of apps work. It is
  currently a fresh /proc in its own PID namespace but still has access to a
  lot of /proc files it shouldn't. bubblewrap and other sandboxing apps
  bindmount on top of these files to remove access
- [ ] No real network isolation. Can add a network namespace.

## todo:
- [ ] home-manager-module: during activation find some way to indicate that the configuration is nested, maybe filter the output of the activation script via piping to another application or function.
- [ ] provide separate nix-store, and have the closure inserted into and loaded from that store.
- [ ] look into dbus activateable, also the menu side of desktop entries
- [ ] Compare with flatpacks approach for wayland/pulseaudio/etc
  https://github.com/flatpak/flatpak/commit/b4822e2230c62dc890f0392677fa4a5f98f10450
- [ ] Move all the default to defaults.

## future ideas:
- [ ] provide already made sandboxes for each application.
- [ ] premade integration into WM
- [ ] pre-shell that you set as your shell, where you choose your house.
