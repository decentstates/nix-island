# Package for https://github.com/landlock-lsm/island
#
# Upstream has no releases and does not commit a Cargo.lock, so we vendor a
# lockfile (./Cargo.lock, generated with `cargo generate-lockfile` at the
# pinned rev) and link it into the source tree.
#
# The landlockconfig dependency is a git dependency; `allowBuiltinFetchGit`
# lets importCargoLock fetch it without a manually maintained outputHash.
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
    # NAR hash of the unpacked GitHub tarball at `rev`. When bumping `rev`,
    # refresh with:
    #   nix run nixpkgs#nix-prefetch-github -- landlock-lsm island --rev <rev>
    # and regenerate ./Cargo.lock (upstream doesn't commit one):
    #   cargo generate-lockfile
    hash = "sha256-H3+BQxUtogcO0LdO8ayHH1aThg6+SZW+++ixelvzUxA=";
  };

  cargoLock = {
    lockFile = ./Cargo.lock;
    allowBuiltinFetchGit = true;
  };

  postPatch = ''
    ln -sf ${./Cargo.lock} Cargo.lock
  '';

  nativeBuildInputs = [ installShellFiles ];

  # Tests exercise Landlock and expect a writable sandbox-capable kernel;
  # the Nix build sandbox is not a good place for them.
  doCheck = false;

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
