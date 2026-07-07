# nix-holm

**holm** — landlocked island-homes for your shell.

*holm* (Old Norse **holmr**): a small island — the one in Stock**holm**. One
letter from *home*, which is exactly what each one is.

Holm builds **separate named shell executables** — `work-shell`, `oss-shell`,
`untrusted-run` — where each command drops you onto its own *holm*: an
isolated user environment with its own `$HOME`, sandboxed by
[Island](https://github.com/landlock-lsm/island) (the Landlock policy is
the reef around it). Your mainland home stays untouched, unreadable, and
un-leaked.

Two libraries share this repo and flake:

- **nix-holm** (`lib.mkHolm`) — the core. A holm's contents are just two
  inputs: a list of `packages` for its PATH, and a `dotfiles` derivation
  linked into its home. Trivial to build by hand.
- **nix-holm-manager** (`lib.mkHolmManager`) — plugs a full
  **home-manager configuration** into those same two inputs: `home-path`
  becomes the packages, `home-files` becomes the dotfiles, and
  `home.sessionVariables` arrive through the profile's
  `etc/profile.d/*.sh`, which the launcher sources generically.

```
$ work-shell                 # links the holm's dotfiles, enters the sandbox
holm(work-shell): linking dotfiles...
$ echo $HOME
/home/alice/islands/work
$ git config user.email      # this holm's identity, from ITS home-manager config
alice@corp.example
$ env | grep -c SSH_AUTH     # mainland environment never crosses over
0
$ ls /home/alice/.ssh
ls: cannot open directory '/home/alice/.ssh': Permission denied
$ work-shell git status      # or run one command inside the same environment
```

Note the direction of the relationship: home-manager does not configure
the sandbox — **home-manager (optionally) furnishes the world *inside*
the sandbox**. Each holm evaluates an independent HM home; or none at all.

## Usage

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  home-manager.url = "github:nix-community/home-manager";
  home-manager.inputs.nixpkgs.follows = "nixpkgs";
  nix-holm.url = "github:youruser/nix-holm";
};
```

With home-manager (nix-holm-manager):

```nix
nix-holm.lib.mkHolmManager
  {
    inherit pkgs;
    inherit (inputs) home-manager;
    island = nix-holm.packages.${pkgs.system}.island;
  }
  {
    name = "work-shell";
    directory = "/home/alice/islands/work";  # the holm's $HOME (absolute)
    username = "alice";                       # for home.username (eval-time only)
    tcpPorts = [ 443 22 ];
    modules = [{
      home.packages = [ pkgs.ripgrep pkgs.kubectl ];
      programs.bash.enable = true;
      programs.git = {
        enable = true;
        userName = "Alice @ Work";
        userEmail = "alice@corp.example";
      };
    }];
  }
```

By hand (nix-holm core, no home-manager anywhere):

```nix
nix-holm.lib.mkHolm { inherit pkgs; island = ...; } {
  name = "plain-shell";
  directory = "/home/alice/islands/plain";
  packages = [ pkgs.ripgrep pkgs.jq ];
  environment.EDITOR = "vi";
  dotfiles = pkgs.runCommand "plain-dotfiles" { } ''
    mkdir -p "$out"
    printf '[user]\n  name = Alice\n' > "$out/.gitconfig"
  '';
}
```

Install the result anywhere: `environment.systemPackages`,
`users.users.alice.packages`, `nix profile install`, or `home.packages` of
your *real* home-manager — the outer HM only installs the executable.
`home-manager` may be a flake input **or** any HM source path/tarball.
`nix run .#demo-shell` builds a demo; see `examples/`.

### Options — mkHolm (core)

| option | default | meaning |
|---|---|---|
| `name` | — | executable and Island profile name |
| `directory` | — | the holm's `$HOME`; absolute; created on launch; the only read/write hierarchy by default |
| `packages` | `[ ]` | on PATH inside, next to the `shell` + coreutils baseline; their `etc/profile.d/*.sh` are sourced on entry |
| `dotfiles` | `null` | derivation linked (generation-aware) into the holm's `$HOME` |
| `environment` | `{ }` | extra env vars exported inside the fresh environment |
| `shell` | `pkgs.bashInteractive` | becomes `$SHELL` inside; runs as a login shell with no args; CLI args run an arbitrary command instead (`work-shell git status`) |
| `passEnv` | terminal, locale, user vars | the only variables that cross from your session into the holm |
| `readOnlyPaths` | `[ ]` | extra hierarchies readable inside |
| `readWritePaths` | `[ ]` | extra hierarchies read/writable inside |
| `tcpPorts` | `[ ]` | TCP ports usable inside (connect + bind); empty = no TCP at all |

### Options — mkHolmManager (adds home-manager)

Takes every mkHolm option above, plus:

| option | default | meaning |
|---|---|---|
| `username` | — | `home.username` for the holm's HM evaluation |
| `modules` | `[ ]` | this holm's home-manager modules |
| `stateVersion` | `"25.05"` | `home.stateVersion` |

`home-path` is appended to `packages` and `home-files` becomes `dotfiles`.

## How it works

Island reads profiles from `~/.config/island/profiles/<name>/`
(`profile.toml` + [landlockconfig](https://github.com/landlock-lsm/landlockconfig)
TOML policies) and runs commands with `island run -p <name> -- cmd`.
`mkHolm` produces a wrapper that, per launch:

1. **Syncs the profile**: symlinks the Nix-rendered `profile.toml` and
   Landlock policy into Island's config dir, pruning store links from
   older generations. Hand-written `*.toml` files you drop next to them
   survive — and since Landlock layers *intersect*, local files can only
   tighten the policy, never widen it.
2. **Links the dotfiles** (`nix/mk-home-linker.nix`) — any derivation's
   tree; the linker is the useful core of home-manager's
   `linkGeneration`, extracted: leaf-by-leaf symlinks so
   directories stay real, refuse-to-clobber safety, pruning of links (and
   emptied directories) that vanished between generations, no-op when
   unchanged. The full HM activation script is deliberately not run: its
   nix-profile step can fall back to the *shared*
   `/nix/var/nix/profiles/per-user/$USER` on a fresh home (holms would
   clobber each other's and your real HM's generation pointer), it needs
   the nix daemon, and its hooks assume a login home. Known limitation:
   `home.activation.*` / `onChange` hooks don't run. (These HM caveats
   apply to nix-holm-manager; the core linker just links trees.)
3. **Enters the sandbox** with a two-stage launcher: stage 1 re-execs
   itself through `env -i` carrying only `passEnv` (default: `TERM`,
   `COLORTERM`, `LANG`, `LC_ALL`, `TZ`, `USER`, `LOGNAME`) plus
   `HOME=<directory>` and `SHELL`; stage 2 — now in a fresh environment —
   sets `PATH` to the holm's merged profile — and nothing else: no
   system profile, no mainland `PATH` — sources the profile's
   `etc/profile.d/*.sh` (with nix-holm-manager that's where
   `hm-session-vars.sh` and thus `home.sessionVariables` come from),
   exports `environment`, points `TMPDIR` at `$HOME/.tmp`, and execs
   `$SHELL -l` or your arguments.

The Landlock policy is deny-by-default: read+execute on `/nix/store`
only (that still covers `/bin/sh` and `/usr/bin/env` shebangs — those are
symlinks, and Landlock checks the store object a path *resolves* to),
read-only `/etc`, read/write only on the holm's directory and ttys; no
TCP unless `tcpPorts` says so; signals and abstract unix sockets are
scoped to the sandbox. The whole HM environment
is part of the executable's Nix closure — building the shell builds the
home, GC can't collect it, `nix copy` ships it as one unit.

## Notes & caveats

- Island is upstream-declared **work in progress**; treat this as
  defense-in-depth, not a container boundary. Landlock denies paths but
  doesn't hide them; passing socket addresses (D-Bus, SSH agent, display)
  through `passEnv` re-extends the sandbox through whatever those sockets
  can do — and needs matching path grants anyway.
- Requires Landlock (kernel ≥ 5.13; the targeted ABI 6 ≈ 6.7+; NixOS
  enables it by default). Policy paths must be absolute; missing paths
  only warn.
- To debug denials: `island run --log-audit -p <name> -- <cmd>` (Linux
  ≥ 6.15) — the profile is on disk, so the CLI works directly.
- Inside a holm, `~` means the holm's home everywhere, including in its
  HM modules. Launch cost after the first run: one `readlink`.
- Only the holm's declared environment is on `PATH`; every holm gets its
  `shell` + coreutils as a baseline, everything else goes in `packages`
  (or `home.packages`). System tools remain *executable by absolute path*
  (the store-wide grant is the documented default — Landlock denies,
  it doesn't hide); drop a hand-written policy layer into the profile
  dir if you want to intersect that down.
- Since Nix owns the policies, `island update` has nothing to manage in
  these profiles — expected.

## Development

```console
$ nix fmt                 # nixpkgs-fmt
$ nix flake check -L      # builds island + the demo shell
$ nix run .#demo-shell
```

Commit `flake.lock` after the first `nix flake check`. When bumping the
Island rev: update `rev` + `hash` in `nix/island-package.nix` and
regenerate `nix/Cargo.lock` with `cargo generate-lockfile` (upstream does
not commit a lockfile).

## License

MIT — see [LICENSE](./LICENSE). Island itself is MIT OR Apache-2.0.

## Layout

```
flake.nix
LICENSE
.github/workflows/ci.yml   # fmt + flake check
nix/
  island-package.nix       # buildRustPackage for Island (the sandboxer)
  Cargo.lock               # vendored (upstream doesn't commit one)
  mk-holm.nix              # nix-holm core: profile, policy, launcher, wrapper
  mk-holm-manager.nix      # nix-holm-manager: home-manager -> packages + dotfiles
  mk-home-linker.nix       # generation-aware dotfile linker
examples/
  flake-usage.nix
  plain-nix.nix
```
