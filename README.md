# nix-island

> Warning:
> Build on top of the WIP island and LandlockConfig, things will break.
> I am not a security expert, this is an experiment.

I built this to provide a layer of isolation for data between applications.

How I use it:
- Minimal programs installed into my base.
- In my WM (sway) I intercept graphical applications being launched and run them in a sandbox.
- There are different terminal emulators with different of sandboxing, I use different themes to distinguish them.
- I have an unsandboxed shell available, with simple old programs, disabling git-hooks and other automatic code running.

The result:
- Sandboxing by default.
- Data isolation between sandboxes.
- Ability to run the unsandboxed shell if I need to escalate.

why not user namespaces / containers, or using different users:
- simpler than containers. simpler then seccomp (no bpf, no suid.) (e.g. firejail).
- no file permission issues.

is this similar to flatpack:
- maybe a bit
- but I want to sandbox environments, multiple applications paired with data.
- seems like landlock is a simpler mechanism than filtering syscalls?

### capabilities

Islands grant access through **capability modules**, evaluated with the Nix
module system (`island.islands.<name>.capabilities`, a module; compose
further capability modules via `imports`).
Every capability contributes to the shared grant options: `passthroughEnv`,
`execWrappers` (setup scripts composed around the sandbox entry),
`bindTcpPorts`, `connectTcpPorts`, `readOnlyPaths`, `readWritePaths`.
Grants are additive across modules.

Four capabilities ship in-tree (`nix/lib/capabilities/`) and are always
imported, gated by enable flags:

- `defaults` (enabled by default) — terminal/locale/identity environment
  passthrough, tty access, island home + tmpdir read/write, and the setup
  wrapper that creates the island tmpdir and a private `TMPDIR` and
  `XDG_RUNTIME_DIR`. Disable it for a bare island and restate what you need.
- `dbus` — session bus access through a filtering `xdg-dbus-proxy` running
  outside the sandbox; `DBUS_SESSION_BUS_ADDRESS` points at the proxy
  socket in the island's private runtime dir, and `dbus.talk` / `dbus.own`
  control the filter (default: portals and notifications). See the threat
  model below.
- `gpu` — `/dev/dri` read/write (incl. `ioctl_dev`), `/run/opengl-driver`
  and `/sys` read-only.
- `wayland` — see below; implies `dbus` and `gpu` (via `mkDefault`).

```nix
island.islands.browser.capabilities = {
  wayland.enable = true;
  connectTcpPorts = [ 443 ];
};
```

Ad-hoc grants go straight in the module (or its `imports`); capability
modules receive
`pkgs` and the frozen island identity `island` (`profileName`, `runnerName`,
`islandHomeDir`, `tmpDir`, `runDir`, `realHomeDir`, `username`) as specialArgs.
The evaluated result is introspectable via the read-only
`island.islands.<name>.capabilityConfig`.

### desktop (Wayland) apps

Enable the `wayland` capability to run native Wayland GUI applications
inside an island:

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
- The app gets a private `XDG_RUNTIME_DIR` under the island tmpdir.
- X11/Xwayland is deliberately unsupported: X11 clients can snoop each other,
  which would undo the island boundary.

Each island exposes read-only outputs under `island.islands.<name>.hm`:

- `hm.homeManagerConfiguration` — the evaluated nested home-manager
  configuration (e.g. `.activationPackage`).
- `hm.desktopEntries` — a derivation of `share/applications/*.desktop`
  entries for the island's applications, `Exec=` rewritten through the island
  runner and `Name=` tagged with `⟦<island>⟧`. Point a launcher's
  `XDG_DATA_DIRS` at an aggregation of these to get a sandboxed-apps menu.

### threat model / known gaps

- **Landlock cannot block `connect()` on named unix sockets** (true up to and
  including ABI 7, which only adds audit). Consequently the session D-Bus bus
  at `/run/user/N/bus` is reachable by any malicious island process that
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
- island home-manager modules recieve the same extraSpecialArgs as the parent home-manager

### todo:
- [ ] home-manager-module: during activation find some way to indicate that the configuration is nested, maybe filter the output of the activation script via piping to another application or function.
- [ ] provide separate nix-store, and have the closure inserted into and loaded from that store.
- [ ] look into dbus activateable, also the menu side of desktop entries

### future ideas:
- [ ] provide already made sandboxes for each application.
