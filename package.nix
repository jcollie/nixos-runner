# SPDX-FileCopyrightText: © 2026 Jeffrey C. Ollie
# SPDX-License-Identifier: MIT

{
  lib,
  stdenv,
  zig,
  uid,
  coreutils,
  bashInteractive,
  nix,
  ...
}:
stdenv.mkDerivation (finalAttrs: {
  name = "execas-${toString uid}";
  src = lib.cleanSource ./.;
  nativeBuildInputs = [
    zig
  ];
  zigBuildFlags = [
    "-Duid=${toString uid}"
    "-Dtail=${lib.getExe' coreutils "tail"}"
    "-Dnix=${lib.getExe' nix "nix"}"
    "-Dbash=${lib.getExe' bashInteractive "bash"}"
  ];
  meta = {
    mainProgram = "execas-${toString uid}";
    license = lib.licenses.mit;
  };
})
