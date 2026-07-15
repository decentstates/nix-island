{ lib
, stdenv
, pkg-config
, wayland
, wayland-protocols
, wayland-scanner
}:

stdenv.mkDerivation {
  pname = "island-security-context";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ pkg-config wayland-scanner ];
  buildInputs = [ wayland ];

  buildPhase = ''
    runHook preBuild

    xml=${wayland-protocols}/share/wayland-protocols/staging/security-context/security-context-v1.xml
    wayland-scanner client-header "$xml" security-context-v1-client-protocol.h
    wayland-scanner private-code "$xml" security-context-v1-protocol.c

    $CC -O2 -Wall -Wextra \
      island-security-context.c security-context-v1-protocol.c \
      $(pkg-config --cflags --libs wayland-client) \
      -o island-security-context

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm555 island-security-context $out/bin/island-security-context
    runHook postInstall
  '';

  meta = {
    description = "Wayland security-context-v1 wrapper for nix-island launches";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "island-security-context";
  };
}
