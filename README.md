# nix-housing

Better hygiene for your shell.

nix-housing, inspired by [Island](https://github.com/landlock-lsm/island), realises that for effective sandboxing:
- Data must be paired with software.
- Environments of applications are necessary for power users, instead of single sandboxed apps.
- An inversion of the existing model is needed: 
  Instead of running some software in sandboxes, we should always be in a sandboxed environment.
- Building those environments deterministically and composably becomes trivial with nix.

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

## FAQs

What threat are we mitigating:
- Undesirable user-context code execution, malicious or not.
  - Slop code.
  - Supply-chain attacks.
  - Dev-tool attacks.
  - Accidental authenticated actions.

  From limiting what data we have access to (hard control via landlock), 
  and environment software and configuration (soft control via nix/home-manager.)

What doesn't this protect from:
- Landlock escapes.
- Privilege escalation attacks.
- Kernel attacks.

Why not user namespaces / containers, seccomp-bpf, different users, bubblewrap for sandboxing:
- A different sandboxing mechanism can be used.
- I'm no expert here but landlock seems simpler, lower surface area, purpose built for this.
- Avoid file permission issues between users/namespaces.

Isn't this similar to bubblewrap/flatpack/etc:
- probably
- but focused on environments + data, instead of executables, or apps + data.
- I want to achieve something similar to MacOS, where the terminal can't access
  my documents directory.


### capabilities

Houses grant access through **capability modules**, evaluated with the Nix
module system (`housing.houses.<name>.capabilities`, a module; compose
further capability modules via `imports`).
Every capability contributes to the shared grant options: `passthroughEnv`,
`execWrappers` (setup scripts composed around the sandbox entry),
`bindTcpPorts`, `connectTcpPorts`, `readOnlyPaths`, `readWritePaths`.
Grants are additive across modules.

Four capabilities ship in-tree (`nix/lib/capabilities/`) and are always
imported, gated by enable flags:

- `defaults` (enabled by default) — terminal/locale/identity environment
  passthrough, tty access, house home + tmpdir read/write, and the setup
  wrapper that creates the house tmpdir and a private `TMPDIR` and
  `XDG_RUNTIME_DIR`. Disable it for a bare house and restate what you need.
- `dbus` — session bus access through a filtering `xdg-dbus-proxy` running
  outside the sandbox; `DBUS_SESSION_BUS_ADDRESS` points at the proxy
  socket in the house's private runtime dir, and `dbus.talk` / `dbus.own`
  control the filter (default: portals and notifications). See the threat
  model below.
- `gpu` — `/dev/dri` read/write (incl. `ioctl_dev`), `/run/opengl-driver`
  and `/sys` read-only.
- `wayland` — see below; implies `dbus` and `gpu` (via `mkDefault`).

```nix
housing.houses.browser.capabilities = {
  wayland.enable = true;
  connectTcpPorts = [ 443 ];
};
```

Ad-hoc grants go straight in the module (or its `imports`); capability
modules receive
`pkgs` and the frozen house identity `house` (`profileName`, `runnerName`,
`houseHomeDir`, `tmpDir`, `runDir`, `realHomeDir`, `username`) as specialArgs.
The evaluated result is introspectable via the read-only
`housing.houses.<name>.capabilityConfig`.

### desktop (Wayland) apps

Enable the `wayland` capability to run native Wayland GUI applications
inside a house:

- The runner connects to the compositor *before* sandboxing and creates a
  per-launch **restricted** Wayland socket via `security-context-v1`
  (`nix/security-context/`). The compositor denies privileged protocols
  (screencopy, data-control, virtual keyboard/pointer, foreign-toplevel) to
  clients of that socket. Fail-closed: if the compositor does not support the
  protocol, the app runs without Wayland access rather than with the
  unrestricted socket. Requires sway >= 1.10 / a wlroots compositor with
  security-context support.
- GPU and session-bus access come from the implied `gpu` and `dbus`
  capabilities.
- The app gets a private `XDG_RUNTIME_DIR` under the house tmpdir.
- X11/Xwayland is deliberately unsupported: X11 clients can snoop each other,
  which would undo the house boundary.

Each house exposes read-only outputs under `housing.houses.<name>.hm`:

- `hm.homeManagerConfiguration` — the evaluated nested home-manager
  configuration (e.g. `.activationPackage`).
- `hm.desktopEntries` — a derivation of `share/applications/*.desktop`
  entries for the house's applications, `Exec=` rewritten through the house
  runner and `Name=` tagged with `⟦<house>⟧`. Point a launcher's
  `XDG_DATA_DIRS` at an aggregation of these to get a sandboxed-apps menu.

### threat model / known gaps

- **Landlock cannot block `connect()` on named unix sockets** (true up to and
  including ABI 7, which only adds audit). Consequently the session D-Bus bus
  at `/run/user/N/bus` is reachable by any malicious house process that
  hardcodes the path, and the bus is an escape hatch: e.g.
  `org.freedesktop.systemd1` `StartTransientUnit` runs commands outside the
  sandbox. Because blocking is impossible at this layer, the `dbus`
  capability routes the *intended* path through a filtering
  `xdg-dbus-proxy` (portals, notifications) — least privilege for benign
  apps, not a boundary. Revisit when Landlock ships unix-socket scoping.
- The same applies to any other named session socket (pipewire, etc.):
  hiding paths from the environment is hygiene for benign apps, not a
  security boundary.
- Abstract unix sockets and signals *are* scoped (`scoped = abi.all`).
- Without the `wayland` capability, a process that finds the unrestricted
  Wayland socket path can still connect to it (same named-socket gap) and use
  privileged compositor protocols; the security-context runner exists
  precisely to make the *intended* GUI path restricted.

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

### todo:
- [ ] home-manager-module: during activation find some way to indicate that the configuration is nested, maybe filter the output of the activation script via piping to another application or function.
- [ ] provide separate nix-store, and have the closure inserted into and loaded from that store.
- [ ] look into dbus activateable, also the menu side of desktop entries
- [ ] Compare with flatpacks approach for wayland/pulseaudio/etc
  https://github.com/flatpak/flatpak/commit/b4822e2230c62dc890f0392677fa4a5f98f10450

### future ideas:
- [ ] provide already made sandboxes for each application.
