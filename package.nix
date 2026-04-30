# SPDX-FileCopyrightText: © 2026 Jeffrey C. Ollie
# SPDX-License-Identifier: MIT

{
  lib,
  stdenv,
  zig_0_16,
  uid,
  gid,
  username,
  homedir,
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
    zig_0_16
  ];
  zigBuildFlags = [
    "-Duid=${toString uid}"
    "-Dgid=${toString gid}"
    "-Dgroups=${groups}"
    "-Dusername=${username}"
    "-Dhomedir=${homedir}"
    "-Dtail=${lib.getExe' coreutils-full "tail"}"
    "-Dnix=${lib.getExe' nix "nix"}"
    "-Dnix-daemon=${lib.getExe' nix "nix-daemon"}"
    "-Dbash=${lib.getExe' bashInteractive "bash"}"
    "-Dsh=${lib.getExe' bashInteractive "sh"}"
  ];
  meta = {
    mainProgram = "execas-${toString uid}";
    license = lib.licenses.mit;
  };
})
