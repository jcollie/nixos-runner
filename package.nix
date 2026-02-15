# SPDX-FileCopyrightText: © 2026 Jeffrey C. Ollie
# SPDX-License-Identifier: MIT

{
  lib,
  stdenv,
  zig,
  uid,
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
  ];
  meta = {
    mainProgram = "execas-${toString uid}";
    license = lib.licenses.mit;
  };
})
