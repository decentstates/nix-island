# nix-holm

**holm** — landlocked island-homes for your shell.

*holm* (Old Norse **holmr**): a small island — the one in Stock**holm**. One
letter from *home*, which is exactly what each one is.

Holm builds **separate named shell executables** — `work-shell`, `oss-shell`,
`untrusted-run` — where each command drops you onto its own *holm*: an
isolated user environment sandboxed by
[Island](https://github.com/landlock-lsm/island) (the Landlock policy is the
reef around it) and furnished by **its own home-manager configuration** — its
own `$HOME`, dotfiles, git identity, packages, and `programs.*` modules.
Configured in plain Nix or with home-manager modules; your mainland home
stays both untouched and unreadable from inside.

```
$ work-shell                 # activates the holm's HM generation, enters the sandbox
holm(work-shell): activating home-manager configuration...
$ echo $HOME
/home/alice/islands/work
$ git config user.email      # this holm's identity, from ITS home-manager config
alice@corp.example
$ ls /home/alice/.ssh
ls: cannot open directory '/home/alice/.ssh': Permission denied
$ work-shell git status      # or run one command inside the same environment
```

Note the direction of the relationship: home-manager does not configure the
sandbox — **home-manager configures the world *inside* the sandbox**. Each
holm evaluates and activates a completely independent HM home.

## How it works

Island reads profiles from `~/.config/island/profiles/<name>/`
(`profile.toml` + [landlockconfig](https://github.com/landlock-lsm/landlockconfig)
TOML policies) and runs commands with `island run -p <name> -- cmd`. Per
holm, this repo wires up four pieces:

1. **Package** (`nix/island-package.nix`): `buildRustPackage` for Island at
   a pinned rev. Upstream commits no `Cargo.lock`, so one is vendored
   (`nix/Cargo.lock`); the `landlockconfig` git dependency is fetched via
   `cargoLock.allowBuiltinFetchGit`.
2. **Profile & policy** (`nix/mk-profile.nix`, `nix/mk-landlock-policy.nix`):
   deny-by-default Landlock policy with NixOS-aware allow rules
   (`/nix/store`, `/run/current-system`, ttys; `/run/wrappers` excluded),
   read/write only on the holm's directory, per-port TCP control, scoped
   signals/abstract sockets.
3. **Per-holm home** (`nix/mk-holm-home.nix`): evaluates a standalone
   `homeManagerConfiguration` whose `home.homeDirectory` is the holm's
   directory. A base module keeps activation from touching your real
   session (`systemd.user.startServices = false`, release-check off).
4. **The executable** (`nix/mk-holm.nix`): a wrapper that, on launch,
   - symlinks the store-rendered Island profile into
     `~/.config/island/profiles/<name>/` (pruning stale links from old
     generations — fully declarative without any module system),
   - **links the holm's dotfiles** (`home-files`) into the island home —
     *outside* the sandbox, generation-aware, and a no-op when nothing
     changed (`nix/mk-home-linker.nix`),
   - `exec`s `island run -p <name> -- <launcher>`, where the launcher —
     now *inside* the sandbox — sets `HOME`/`USER` to the holm's,
     sources `hm-session-vars.sh`, prepends the HM environment's `bin/`,
     `cd`s home, and execs `$SHELL` as a login shell (or whatever args
     you passed) — after first re-exec'ing itself through `env -i` so the
     holm starts from a **fresh environment** (see below).

Deliberately, holm does **not** run home-manager's activation script — it
extracts the one part that matters. The stock script's nix-profile step
falls back to the *shared* `/nix/var/nix/profiles/per-user/$USER` whenever
`$HOME/.local/state/nix/profiles` doesn't exist yet — which is exactly the
state of a fresh island home — so holms would overwrite each other's (and
your real home-manager's) generation pointer. It also drags in a nix-daemon
dependency at launch, and its module hooks assume a real login home. The
extracted linker (`mk-home-linker.nix`) keeps HM's linking semantics —
leaf-by-leaf symlinks so directories stay real, refuse-to-clobber safety,
and pruning of links (and emptied directories) that vanished between
generations — while touching nothing outside the island directory. GC
safety comes from the wrapper's closure reference, not from profile
registration.

## Usage

### Flake

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  home-manager.url = "github:nix-community/home-manager";
  home-manager.inputs.nixpkgs.follows = "nixpkgs";
  nix-holm.url = "github:youruser/nix-holm";
};
```

```nix
let
  mkHolm = nix-holm.lib.mkHolm {
    inherit pkgs;
    inherit (inputs) home-manager;
    island = nix-holm.packages.${pkgs.system}.island;
  };
in
mkHolm {
  name = "work-shell";
  directory = "/home/alice/islands/work";     # the holm's $HOME (absolute)
  landlock.tcpConnectPorts = [ 443 22 ];
  homeManager = {
    username = "alice";                        # your real login name
    stateVersion = "25.05";
    modules = [{
      home.packages = [ pkgs.ripgrep pkgs.kubectl ];
      programs.bash.enable = true;
      programs.git = {
        enable = true;
        userName = "Alice @ Work";
        userEmail = "alice@corp.example";
      };
    }];
  };
}
```

Install the result anywhere: `environment.systemPackages`,
`users.users.alice.packages`, `nix profile install`, or even
`home.packages` of your *real* home-manager — the outer HM only installs
the executable; it does not configure the holm.

`nix run .#demo-shell` builds a pure (no-HM) demo shell. See
`examples/flake-usage.nix` for multiple holms with different identities
and `examples/plain-nix.nix` for channel/no-flake usage
(`home-manager` may be a flake input **or** any HM source path/tarball —
both API styles are handled).

### Options (mkHolm)

| option | default | meaning |
|---|---|---|
| `name` / `profileName` | — / `name` | executable / Island profile name |
| `directory` | `null` | holm root; created on launch; rw in the policy; the holm's `$HOME` when `homeManager` is set |
| `shell` | `pkgs.bashInteractive` | becomes `$SHELL` inside and runs as a login shell when invoked with no args; CLI args run an arbitrary command in the same sandbox instead (`work-shell git status`) |
| `passEnv` | terminal, locale, user + Island workspace vars | the only variables allowed to cross from your session into the holm |
| `homeManager` | `null` | `{ username, modules, stateVersion?, extraSpecialArgs? }` — this holm's HM config |
| `env` | `{ }` | extra env vars exported inside the holm's fresh environment |
| `workspace` | `homeManager == null` | Island's own isolated XDG dirs + ephemeral TMPDIR; off for HM holms since the HM home *is* the isolation (leaving it on would shadow HM's `~/.config` links) |
| `landlock.*` | NixOS-safe defaults | `readExecutePaths`, `readOnlyPaths`, `readWritePaths`, `writableDevices`, `tcpConnectPorts`, `tcpBindPorts`, `scoped`, `extraRules` |
| `confineToClosure` | `false` | replace the blanket `/nix/store` grant with the holm's exact runtime closure (see below) |
| `extraClosureRoots` | `[ ]` | extra store paths to allow when confined |
| `extraLandlockFiles` | `{ }` | additional policy layers (Landlock layers intersect: they can only tighten) |
| `logAudit` | `false` | log denials to the kernel audit log (Linux ≥ 6.15) |
| `syncProfile` | `true` | disable if something else installs the profile files |

## Fresh environment

Holms do not inherit your session's environment. The in-sandbox launcher
re-execs itself through `env -i` carrying only an explicit allowlist —
by default: `TERM`, `COLORTERM`, `LANG`, `LC_ALL`, `TZ`, `USER`,
`LOGNAME`, plus the `XDG_*`/`TMPDIR` variables Island's workspace feature
uses (absent when `workspace = false`), plus `HOME` only when the holm has
no `directory` of its own. Everything else — `SSH_AUTH_SOCK`, API tokens,
`DBUS_SESSION_BUS_ADDRESS`, your real `PATH` — never enters. Tune with
`passEnv`; note that passing socket addresses (D-Bus, SSH agent, display)
re-extends the sandbox through whatever those sockets can do, and the
Landlock policy must also grant the socket path for them to work.

Inside, the environment is rebuilt from declared parts: `PATH` is the
holm's HM environment, then the system profile (`/run/current-system/sw/bin`)
— the mainland `PATH` is never consulted; `SHELL` is the holm's `shell`;
`hm-session-vars.sh` supplies `home.sessionVariables`; and `env` entries
are exported last. This also means Island's per-profile `[[env]]`
mechanism isn't used — profile-injected variables would be wiped by the
reset, so holm exports them after it instead.

## Confining to the closure

By default the policy grants read+execute on all of `/nix/store` — the
profile does **not** enumerate closure paths. The closure is referenced by
the *wrapper* (so building the shell builds the whole home, GC can't
collect it, and `nix copy` ships it as one unit), but inside the sandbox
any store path is readable and executable. That's the pragmatic default:
the store is world-readable on NixOS anyway, and the boundary being
enforced is your `$HOME` and the network.

With `confineToClosure = true`, the holm's runtime closure (the HM
environment, launcher, and command — plus `extraClosureRoots`) is
enumerated at build time and written into the policy as the *only*
read+execute store grant:

```toml
[[path_beneath]]
allowed_access = ["abi.read_execute"]
parent = [
    "/nix/store/...-bash-interactive-5.2",
    "/nix/store/...-git-2.47.0",
    ...
]
```

Consequences to be aware of:

- Only what the holm's home-manager config declares can run. `nix run`,
  `nix-shell`, and ad-hoc store paths fail inside; so does
  `work-shell some-tool` if `some-tool` isn't in the closure.
- The remaining defaults (`/run/current-system`, `/bin`) stop being
  useful for *running* system tools: those resolve through symlinks into
  store paths that are no longer granted. Set
  `landlock.readExecutePaths = [ ]` for a fully closure-only policy.
- Listing `/nix/store` itself is denied (no `read_dir` on the store root),
  so the holm can't even enumerate what else exists.
- Cost: one Landlock rule per store path at startup (a large dev
  environment is a few thousand `open` + `landlock_add_rule` calls —
  measured in milliseconds), and the policy TOML gets correspondingly big.

## Notes & caveats

- `username` is used at evaluation time (`home.username`, substituted
  into HM modules) and exported as `$USER` inside the sandbox; since the
  activation script never runs, nothing checks it at launch. Different
  holms share it freely and never collide — each holm's link state lives
  in its own `.local/state/holm/`.
- Launch cost: one `readlink` when the generation is unchanged; a quick
  relink pass when it changed. No nix daemon is needed at launch.
- Known limitation of skipping full activation: `home.activation.*`
  snippets and `onChange` hooks don't run (e.g. fontconfig cache
  regeneration, dconf writes). For shell-centric holms this rarely
  matters; if a module you use depends on such a hook, run
  `env HOME=<holm-dir> USER=$USER <activationPackage>/activate` once by
  hand — but create `<holm-dir>/.local/state/nix/profiles` first so its
  profile step cannot fall back to the shared per-user path.
- Inside a holm, `~` means the holm's home everywhere — including in
  its HM modules (`programs.ssh.matchBlocks.*.identityFile = "~/.ssh/id_work"`
  refers to `islands/work/.ssh/`).
- Island is upstream-declared **work in progress**; treat this as
  defense-in-depth, not a container boundary. Landlock denies paths but
  doesn't hide them, and D-Bus/Wayland/X11 sockets can extend the sandbox
  if you expose them.
- Requires Landlock (kernel ≥ 5.13; ABI 6 ≈ 6.7+, NixOS enables it by
  default — lower `landlock.abi` for older kernels). Policy paths must be
  absolute; missing paths only warn.
- Since Nix owns the policies, `island update` (which manages the embedded
  `island-default-base.toml`) has nothing to do in these profiles — expected.
- Because `directory` is a `when_beneath` context, Island's zsh hook
  (`source <(island hook zsh)`) will additionally sandbox plain commands
  typed while `cd`'d into a holm from your normal shell — though they
  won't get the holm's `$HOME`; use the named executable for the full
  environment.

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
  island-package.nix        # buildRustPackage for Island (the sandboxer)
  Cargo.lock                # vendored (upstream doesn't commit one)
  mk-landlock-policy.nix    # landlockconfig TOML generator, NixOS defaults
  mk-profile.nix            # renders profile.toml + landlock/ into the store
  mk-holm-home.nix          # per-holm homeManagerConfiguration evaluator
  mk-holm.nix               # the named executable (bootstrap + activate + run)
examples/
  flake-usage.nix
  plain-nix.nix
```
