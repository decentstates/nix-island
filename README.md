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

### notes:
- nix.settings.use-xdg-base-directories should be set to true to allow isolated home-manager environments to be set up.

### todo:
- [ ] home-manager-module: during activation find some way to indicate that the configuration is nested, maybe filter the output of the activation script via piping to another application or function.

### future ideas:
- [ ] provide already made sandboxes for each application.
