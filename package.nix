# SPDX-FileCopyrightText: © 2026 Jeffrey C. Ollie
# SPDX-License-Identifier: MIT

{
  lib,
  stdenv,
  zig,
  uid,
  gid,
  username,
  groups,
  coreutils-full,
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
    "-Dgid=${toString gid}"
    "-Dgroups=${groups}"
    "-Dusername=${username}"
    "-Dtail=${lib.getExe' coreutils-full "tail"}"
    "-Dnix=${lib.getExe' nix "nix"}"
    "-Dbash=${lib.getExe' bashInteractive "bash"}"
  ];
  meta = {
    mainProgram = "execas-${toString uid}";
    license = lib.licenses.mit;
  };
})
