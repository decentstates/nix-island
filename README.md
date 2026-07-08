# nix-holm

Named shell executables, each running in an isolated user environment: its
own `$HOME`, its own packages and dotfiles, sandboxed with
[Island](https://github.com/landlock-lsm/island) (Landlock). A *holm* is a
small island.

Two libraries share this flake:

- **`lib`** (`{ pkgs, ... } -> { mkHolm, defaultPassEnv }`) — core. A
  holm's contents are a list of `packages` (its PATH) and a `holmFiles`
  derivation (linked into its home).
- **`homeManagerModules.holm`** — declare holms in your home-manager
  configuration (`holm.holms.<name>`). Each evaluates a nested HM home
  with the same home-manager (via `modulesPath`) and maps it onto the
  core: `home-path` → `packages`, `home-files` → `holmFiles`,
  `home.sessionVariables` via the profile's `etc/profile.d/*.sh`.

```
$ work-shell
$ echo $HOME
/home/alice/islands/work
$ git config user.email        # this holm's identity
alice@corp.example
$ ls /home/alice/.ssh
ls: cannot open directory '/home/alice/.ssh': Permission denied
$ work-shell git status        # run a single command inside
```

## Usage

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  home-manager.url = "github:nix-community/home-manager";
  home-manager.inputs.nixpkgs.follows = "nixpkgs";
  nix-holm.url = "github:youruser/nix-holm";
};
```

With home-manager (in your home configuration):

```nix
imports = [ nix-holm.homeManagerModules.holm ];

holm.holms.work-shell = {
  tcpPorts = [ 443 22 ];
  modules = [{
    home.packages = [ pkgs.ripgrep ];
    programs.bash.enable = true;
    programs.git = {
      enable = true;
      userEmail = "alice@corp.example";
    };
  }];
};
```

Without:

```nix
(nix-holm.lib { inherit pkgs; }).mkHolm {
  name = "plain-shell";
  directory = "/home/alice/islands/plain";
  packages = [ pkgs.ripgrep ];
  holmFiles = pkgs.runCommand "plain-dotfiles" { } ''
    mkdir -p "$out"
    printf '[user]\n  name = Alice\n' > "$out/.gitconfig"
  '';
}
```

Core results install anywhere (`environment.systemPackages`,
`nix profile install`, ...); module shells land in `home.packages`.
Demo: `nix run .#demo-shell`. See `examples/`.

### Options — mkHolm

| option | default | meaning |
|---|---|---|
| `name` | — | executable and Island profile name |
| `directory` | — | the holm's `$HOME`; absolute; created on launch; the only read/write hierarchy by default |
| `packages` | `[ ]` | on PATH inside, next to the bash + coreutils baseline; their `etc/profile.d/*.sh` are sourced |
| `holmFiles` | `null` | derivation linked (generation-aware) into the holm's `$HOME` |
| `environment` | `{ }` | env vars exported inside |
| `passEnv` | terminal, locale, user vars | the only variables that cross from your session into the holm |
| `readOnlyPaths` | `[ ]` | extra hierarchies readable inside |
| `readWritePaths` | `[ ]` | extra hierarchies read/writable inside |
| `tcpPorts` | `[ ]` | TCP ports usable inside (connect + bind); empty = no TCP |

### Options — holm.holms.<name> (home-manager module)

`directory` (default `~/holms/<name>`), `modules` (the holm's
home-manager modules), and the mkHolm options `environment`, `passEnv`,
`readOnlyPaths`, `readWritePaths`, `tcpPorts`. The nested
`home.username`/`home.stateVersion` come from the outer home. Packages
go in the holm's `home.packages`; the login shell is bash unless the
holm sets `home.sessionVariables.SHELL`. `holm.island` sets
the Island package for all holms.

## How it works

Island reads profiles from `~/.config/island/profiles/<name>/` and runs
commands with `island run -p <name> -- cmd`. The generated wrapper, per
launch:

1. Runs the holm's profile-install script: links the Nix-rendered
   profile into that directory, pruning store links from older
   generations; hand-written `*.toml` files survive. The module also
   runs it during home-manager activation, so profiles are in place at
   switch time and `island run -p <name>` works without launching a
   wrapper first.
2. Links `holmFiles` into the holm: leaf-by-leaf symlinks (directories
   stay real), refuses to overwrite unmanaged files, prunes links and
   emptied directories that vanished between generations, no-op when
   unchanged. Home-manager's activation script is deliberately not run:
   its profile step can fall back to the shared
   `/nix/var/nix/profiles/per-user/$USER`, it needs the nix daemon, and
   its hooks assume a login home. Consequently `home.activation.*` and
   `onChange` hooks do not run.
3. Enters the sandbox with a fresh environment: the command island runs
   is `env -i <allowlist> launcher`, so only `passEnv` (default
   `TERM COLORTERM LANG LC_ALL TZ TZDIR LOCALE_ARCHIVE USER LOGNAME`)
   plus `HOME` and `SHELL` cross over. Inside, `PATH` is the holm's
   merged profile only; the profile's `etc/profile.d/*.sh` are sourced;
   `__NIXOS_SET_ENVIRONMENT_DONE=1` is exported so NixOS login/zsh
   shells do not reimport the system environment from
   `/etc/set-environment`; `TMPDIR` is `$HOME/.tmp`; then `${SHELL:-bash} -l` or the given
   arguments run (`SHELL` only exists if the holm's config sets it).

The Landlock policy denies by default: read+execute on `/nix/store` only
(this covers `/bin/sh` and `/usr/bin/env` shebangs — Landlock checks the
object a path resolves to), read-only `/etc`, read/write on the holm's
directory and ttys, no TCP unless `tcpPorts` is set, signals and abstract
unix sockets scoped to the sandbox. The base lives in
`nix/island-default-base.toml`, replaces upstream's FHS default inside
the island binary (embedded via `include_str!`, so `island create` and
`island update` use it), and is shipped verbatim in every holm profile.

## Notes

- Island is upstream-declared work in progress; treat this as
  defense-in-depth, not a container boundary. Landlock denies paths but
  does not hide them. Passing socket addresses (D-Bus, SSH agent,
  display) via `passEnv` extends the sandbox through those sockets and
  requires matching path grants.
- Requires Landlock, ABI 6 (Linux ≥ 6.7; enabled by default on NixOS).
  Policy paths must be absolute; missing paths only warn.
- Files within a profile compose: grants union, handled accesses
  intersect. Sibling files can widen access; to restrict, stack a second
  profile: `island run -p <name> -p strict -- ...`.
- Only the holm's profile is on `PATH` (baseline: bash + coreutils).
  System tools remain executable by absolute path under the store-wide
  grant.
- Debug denials with `island run --log-audit -p <name> -- cmd`
  (Linux ≥ 6.15).
- Inside a holm, `~` is the holm's home everywhere, including in its HM
  modules. Steady-state launch cost is one `readlink`.

## Development

```console
$ nix fmt
$ nix flake check -L
$ nix run .#demo-shell
```

Commit `flake.lock` after the first check. When bumping the Island rev:
update `rev` + `hash` in `nix/island-package.nix`, regenerate
`nix/Cargo.lock` (`cargo generate-lockfile`), and diff upstream's
`assets/landlock/island-default-base.toml` against
`nix/island-default-base.toml`.

## License

MIT — see [LICENSE](./LICENSE). Island is MIT OR Apache-2.0.

## Layout

```
flake.nix
LICENSE
.github/workflows/ci.yml
nix/
  island-package.nix        # buildRustPackage for Island
  lib.nix                   # common lib: mkHolm, defaultPassEnv
  island-default-base.toml  # base policy: embedded in island, shipped in holms
  Cargo.lock                # vendored (upstream commits none)
  mk-holm.nix               # core: profile, policy, launcher, wrapper
  home-manager-module.nix   # holm.holms.<name>: home-manager -> core
  mk-home-linker.nix        # generation-aware dotfile linker
examples/
  flake-usage.nix
  plain-nix.nix
```
