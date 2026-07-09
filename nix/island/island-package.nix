# https://github.com/landlock-lsm/island — no releases, no committed
# Cargo.lock (vendored at ./Cargo.lock; regenerate on rev bump).
{ lib
, rustPlatform
, fetchFromGitHub
, installShellFiles
}:

rustPlatform.buildRustPackage rec {
  pname = "island";
  version = "0-unstable-2026-05-22";

  src = fetchFromGitHub {
    owner = "landlock-lsm";
    repo = "island";
    rev = "05a9d699fbf30289fd2af4311becf38ceb334df2";
    # refresh: nix run nixpkgs#nix-prefetch-github -- landlock-lsm island --rev <rev>
    hash = "sha256-H3+BQxUtogcO0LdO8ayHH1aThg6+SZW+++ixelvzUxA=";
  };

  cargoLock = {
    lockFile = ./Cargo.lock;
    allowBuiltinFetchGit = true; # landlockconfig is a git dep; no outputHash needed
  };

  postPatch = ''
    ln -sf ${./Cargo.lock} Cargo.lock
    # Nix-native base; embedded via include_str!, so `island create`
    # writes it and `island update` migrates older profiles to it.
    cp ${./island-default-base.toml} assets/landlock/island-default-base.toml
  '';

  nativeBuildInputs = [ installShellFiles ];

  doCheck = false; # tests need a Landlock-capable kernel, not the build sandbox

  postInstall = ''
    installShellCompletion --cmd island \
      --bash <($out/bin/island completion bash) \
      --zsh  <($out/bin/island completion zsh) \
      --fish <($out/bin/island completion fish) || true
  '';

  meta = {
    description = "Sandboxing tool powered by Landlock";
    homepage = "https://github.com/landlock-lsm/island";
    license = with lib.licenses; [ mit asl20 ];
    platforms = lib.platforms.linux;
    mainProgram = "island";
  };
}
