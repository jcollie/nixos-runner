# SPDX-FileCopyrightText: © 2023 Jeffrey C. Ollie
# SPDX-License-Identifier: MIT

{
  description = "nixos-runner";

  inputs = {
    nixpkgs = {
      url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
    };
    push-container = {
      url = "git+https://git.ocjtech.us/jeff/push-container.git";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      push-container,
    }:
    let
      makePackages =
        system:
        import nixpkgs {
          inherit system;
        };
      forAllSystems = (
        function:
        nixpkgs.lib.genAttrs [
          "x86_64-linux"
        ] (system: function (makePackages system))
      );
    in
    {
      packages = forAllSystems (
        pkgs:
        let
          lib = pkgs.lib;
        in
        {
          docker-client = pkgs.docker_28.override {
            clientOnly = true;
          };
          git = pkgs.git.override {
            perlSupport = false;
            pythonSupport = false;
            svnSupport = false;
            sendEmailSupport = false;
            withManual = false;
            withSsh = true;
          };
          nixos-runner =
            let
              bundleNixpkgs = true;
              channelName = "nixpkgs";
              channelURL = "https://nixos.org/channels/nixos-unstable";
              defaultPkgs = [
                pkgs.attic-client
                pkgs.bashInteractive
                pkgs.bind.dnsutils
                pkgs.coreutils-full
                pkgs.curl
                pkgs.forgejo-cli
                pkgs.gawk
                pkgs.gh
                pkgs.glibc
                pkgs.gnugrep
                pkgs.gnused
                pkgs.gnutar
                pkgs.gzip
                pkgs.iputils
                pkgs.less
                pkgs.more
                pkgs.nix
                pkgs.nodejs_25
                pkgs.nushell
                pkgs.pinact
                pkgs.podman
                pkgs.reuse
                pkgs.regctl
                pkgs.stdenv.cc.cc.lib
                pkgs.sudo
                pkgs.tailscale
                pkgs.which
                pkgs.xz
                pkgs.zstd

                self.packages.${pkgs.stdenv.hostPlatform.system}.docker-client
                self.packages.${pkgs.stdenv.hostPlatform.system}.git
                push-container.packages.${pkgs.stdenv.hostPlatform.system}.push-container
              ];

              flake-registry = null;

              users = {
                root = {
                  uid = 0;
                  shell = "${pkgs.bashInteractive}/bin/bash";
                  home = "/root";
                  gid = 0;
                  groups = [ "root" ];
                  description = "System administrator";
                };
                github = {
                  uid = 1001;
                  shell = "${pkgs.bashInteractive}/bin/bash";
                  home = "/github/home";
                  gid = 1001;
                  groups = [
                    "github"
                    "nixbld"
                    "wheel"
                  ];
                  description = "Github runner";
                };
                nobody = {
                  uid = 65534;
                  shell = "${pkgs.shadow}/bin/nologin";
                  home = "/var/empty";
                  gid = 65534;
                  groups = [ "nobody" ];
                  description = "Unprivileged account (don't use!)";
                };
              }
              // pkgs.lib.listToAttrs (
                map (n: {
                  name = "nixbld${toString n}";
                  value = {
                    uid = 30000 + n;
                    gid = 30000;
                    groups = [ "nixbld" ];
                    description = "Nix build user ${toString n}";
                  };
                }) (pkgs.lib.lists.range 1 32)
              );

              groups = {
                root.gid = 0;
                wheel.gid = 1;
                github.gid = 1001;
                nixbld.gid = 30000;
                nobody.gid = 65534;
              };

              userToPasswd = (
                data:
                {
                  uid,
                  gid ? 65534,
                  home ? "/var/empty",
                  description ? "",
                  shell ? "/bin/false",
                  ...
                }:
                "${data}:x:${toString uid}:${toString gid}:${description}:${home}:${shell}"
              );

              passwdContents = (lib.concatStringsSep "\n" (lib.attrValues (lib.mapAttrs userToPasswd users)));

              userToShadow = username: { ... }: "${username}:!:1::::::";

              shadowContents = (lib.concatStringsSep "\n" (lib.attrValues (lib.mapAttrs userToShadow users)));

              groupMemberMap = (
                let
                  # Create a flat list of user/group mappings
                  mappings = (
                    builtins.foldl' (
                      acc: user:
                      let
                        groups = users.${user}.groups or [ ];
                      in
                      acc
                      ++ map (group: {
                        inherit user group;
                      }) groups
                    ) [ ] (lib.attrNames users)
                  );
                in
                (builtins.foldl' (
                  acc: v:
                  acc
                  // {
                    ${v.group} = acc.${v.group} or [ ] ++ [ v.user ];
                  }
                ) { } mappings)
              );

              groupToGroup =
                k:
                { gid }:
                let
                  members = groupMemberMap.${k} or [ ];
                in
                "${k}:x:${toString gid}:${lib.concatStringsSep "," members}";

              groupContents = (lib.concatStringsSep "\n" (lib.attrValues (lib.mapAttrs groupToGroup groups)));

              defaultNixConf = {
                sandbox = "false";
                build-users-group = "nixbld";
                trusted-public-keys = [
                  "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
                ];
                experimental-features = [
                  "flakes"
                  "nix-command"
                ];
              };

              nixConfContents =
                (lib.concatStringsSep "\n" (
                  lib.attrsets.mapAttrsToList (
                    n: v:
                    let
                      vStr = if builtins.isList v then lib.concatStringsSep " " v else v;
                    in
                    "${n} = ${vStr}"
                  ) defaultNixConf
                ))
                + "\n";

              containerSettings = ''
                [engine]
                init_path = "${pkgs.catatonit}/bin/catatonit"
                helper_binaries_dir = [ "${pkgs.podman}/libexec/podman" ]

                [network]
                cni_plugin_dirs = [ "${pkgs.cni-plugins}/bin" ]
                network_backend = "netavark"
              '';

              containerStorage = ''
                [storage]
                driver = "overlay"
                graphroot = "/var/lib/containers/storage"
                runroot = "/run/containers/storage"
              '';

              containerRegistries = ''
                [registries]
                [registries.block]
                registries = [ ]

                [registries.insecure]
                registries = [ ]

                [registries.search]
                registries = [ "docker.io", "quay.io" ]
              '';

              containerPolicy = builtins.toJSON {
                default = [
                  {
                    type = "insecureAcceptAnything";
                  }
                ];
                transports = {
                  docker-daemon = {
                    "" = [
                      {
                        type = "insecureAcceptAnything";
                      }
                    ];
                  };
                };
              };

              gitConfig = ''
                [safe]
                  directory = *
              '';

              sudoers = ''
                root ALL=(ALL:ALL) SETENV:ALL
                %wheel ALL=(ALL:ALL) NOPASSWD:ALL SETENV:ALL
              '';

              baseSystem =
                let
                  nixpkgs = pkgs.path;
                  channel = pkgs.runCommand "channel-nixos" { inherit bundleNixpkgs; } ''
                    mkdir $out
                    if [ "$bundleNixpkgs" ]; then
                      ln -s ${nixpkgs} $out/nixpkgs
                      echo "[]" > $out/manifest.nix
                    fi
                  '';
                  rootEnv = pkgs.buildPackages.buildEnv {
                    name = "root-profile-env";
                    paths = defaultPkgs;
                  };
                  manifest = pkgs.buildPackages.runCommand "manifest.nix" { } ''
                    cat > $out <<EOF
                    [
                    ${lib.concatStringsSep "\n" (
                      map (
                        drv:
                        let
                          outputs = drv.outputsToInstall or [ "out" ];
                        in
                        ''
                          {
                            ${lib.concatStringsSep "\n" (
                              map (output: ''
                                ${output} = { outPath = "${lib.getOutput output drv}"; };
                              '') outputs
                            )}
                            outputs = [ ${lib.concatStringsSep " " (map (x: "\"${x}\"") outputs)} ];
                            name = "${drv.name}";
                            outPath = "${drv}";
                            system = "${drv.system}";
                            type = "derivation";
                            meta = { };
                          }
                        ''
                      ) defaultPkgs
                    )}
                    ]
                    EOF
                  '';
                  profile = pkgs.buildPackages.runCommand "user-environment" { } ''
                    mkdir $out
                    cp -a ${rootEnv}/* $out/
                    ln -s ${manifest} $out/manifest.nix
                  '';
                in
                pkgs.runCommand "base-system"
                  {
                    inherit
                      containerPolicy
                      containerRegistries
                      containerSettings
                      containerStorage
                      groupContents
                      nixConfContents
                      passwdContents
                      shadowContents
                      gitConfig
                      sudoers
                      ;
                    passAsFile = [
                      "containerPolicy"
                      "containerRegistries"
                      "containerSettings"
                      "containerStorage"
                      "groupContents"
                      "nixConfContents"
                      "passwdContents"
                      "shadowContents"
                      "gitConfig"
                      "sudoers"
                    ];
                    allowSubstitutes = false;
                    preferLocalBuild = true;
                  }
                  ''
                    env
                    set -x
                    mkdir -p $out/etc
                    mkdir -p $out/etc/ssl/certs
                    ln -s /nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt $out/etc/ssl/certs
                    cat $passwdContentsPath > $out/etc/passwd
                    echo "" >> $out/etc/passwd
                    cat $groupContentsPath > $out/etc/group
                    echo "" >> $out/etc/group
                    cat $shadowContentsPath > $out/etc/shadow
                    echo "" >> $out/etc/shadow
                    cat $sudoersPath > $out/etc/sudoers
                    mkdir -p $out/usr
                    ln -s /nix/var/nix/profiles/share $out/usr/
                    mkdir -p $out/nix/var/nix/gcroots
                    mkdir -p $out/tmp
                    mkdir -p $out/var/tmp
                    mkdir -p $out/etc/nix
                    cat $nixConfContentsPath > $out/etc/nix/nix.conf
                    mkdir -p $out/root
                    mkdir -p $out/nix/var/nix/profiles/per-user/root
                    mkdir -p $out/github
                    mkdir -p $out/github/home
                    mkdir -p $out/nix/var/nix/profiles/per-user/github

                    mkdir -p $out/etc/containers
                    mkdir -p $out/etc/containers/networks
                    mkdir -p $out/var/lib/containers/storage
                    mkdir -p $out/run/containers/storage
                    cat $containerSettingsPath > $out/etc/containers/containers.conf
                    cat $containerStoragePath > $out/etc/containers/storage.conf
                    cat $containerRegistriesPath > $out/etc/containers/registry.conf
                    cat $containerPolicyPath > $out/etc/containers/policy.json

                    ln -s ${profile} $out/nix/var/nix/profiles/default-1-link
                    ln -s $out/nix/var/nix/profiles/default-1-link $out/nix/var/nix/profiles/default
                    ln -s /nix/var/nix/profiles/default $out/root/.nix-profile
                    ln -s /nix/var/nix/profiles/default $out/github/home/.nix-profile
                    ln -s ${channel} $out/nix/var/nix/profiles/per-user/root/channels-1-link
                    ln -s $out/nix/var/nix/profiles/per-user/root/channels-1-link $out/nix/var/nix/profiles/per-user/root/channels

                    mkdir -p $out/root/.nix-defexpr
                    ln -s $out/nix/var/nix/profiles/per-user/root/channels $out/root/.nix-defexpr/channels
                    echo "${channelURL} ${channelName}" > $out/root/.nix-channels

                    mkdir -p $out/github/home/.nix-defexpr
                    ln -s $out/nix/var/nix/profiles/per-user/github/channels $out/github/home/.nix-defexpr/channels
                    echo "${channelURL} ${channelName}" > $out/github/home/.nix-channels

                    mkdir -p $out/root/.config/git
                    cat $gitConfigPath > $out/root/.config/git/config
                    mkdir -p $out/github/home/.config/git
                    cat $gitConfigPath > $out/github/home/.config/git/config

                    mkdir -p $out/bin $out/usr/bin
                    ln -s ${pkgs.coreutils}/bin/env $out/usr/bin/env
                    ln -s ${pkgs.bashInteractive}/bin/bash $out/bin/sh


                  ''
                + (lib.optionalString (flake-registry != null) ''
                  nixCacheDir="/root/.cache/nix"
                  mkdir -p $out$nixCacheDir
                  globalFlakeRegistryPath="$nixCacheDir/flake-registry.json"
                  ln -s ${flake-registry}/flake-registry.json $out$globalFlakeRegistryPath
                  mkdir -p $out/nix/var/nix/gcroots/auto
                  rootName=$(${pkgs.nix}/bin/nix --extra-experimental-features nix-command hash file --type sha1 --base32 <(echo -n $globalFlakeRegistryPath))
                  ln -s $globalFlakeRegistryPath $out/nix/var/nix/gcroots/auto/$rootName
                '');
            in
            pkgs.dockerTools.buildLayeredImageWithNixDb {
              name = "nixos-runner";
              tag = "latest";
              maxLayers = 2;
              contents = [
                baseSystem
              ]
              ++ defaultPkgs;
              extraCommands = ''
                rm -rf nix-support
                ln -s /nix/var/nix/profiles nix/var/nix/gcroots/profiles

                # https://github.com/containerd/containerd/issues/12683
                ln --symbolic --force "$(realpath --relative-to=etc etc/passwd)" etc/passwd
                ln --symbolic --force "$(realpath --relative-to=etc etc/group)" etc/group
              '';
              fakeRootCommands = ''
                chmod 1777 tmp
                chmod 1777 var/tmp
                chown 1001:1001 github
                chown 1001:1001 github/home
                chown 1001:1001 github/home/.nix-defexpr
                chown 1001:1001 github/home/.config
                chown 1001:1001 github/home/.config/git
                chown 1001:1001 github/home/.config/git/config
              '';
              config = {
                Cmd = [ "${pkgs.bashInteractive}/bin/bash" ];
                User = "github";
                WorkingDir = "/github/home";
                Env = [
                  "USER=github"
                  "PATH=${
                    lib.concatStringsSep ":" [
                      "/github/home/.nix-profile/bin"
                      "/nix/var/nix/profiles/default/bin"
                      "/nix/var/nix/profiles/default/sbin"
                    ]
                  }"
                  "MANPATH=${
                    lib.concatStringsSep ":" [
                      "/github/home/.nix-profile/share/man"
                      "/nix/var/nix/profiles/default/share/man"
                    ]
                  }"
                  "LD_LIBRARY_PATH=${
                    pkgs.lib.makeLibraryPath [
                      pkgs.glibc
                      pkgs.stdenv.cc.cc.lib
                    ]
                  }"
                  "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
                  "GIT_SSL_CAINFO=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
                  "NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
                  "NIX_PATH=/nix/var/nix/profiles/per-user/github/channels:/github/home/.nix-defexpr/channels"
                ];
              };
            };
        }
      );
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          name = "nixos-runner";
          nativeBuildInputs = [
            pkgs.gzip
            pkgs.pinact
            pkgs.regctl
            pkgs.reuse
            push-container.packages.${pkgs.stdenv.hostPlatform.system}.push-container
          ];

        };
      });
      apps = forAllSystems (pkgs: {
        push-container = {
          type = "app";
          program = "${pkgs.lib.getExe
            push-container.packages.${pkgs.stdenv.hostPlatform.system}.push-container
          }";
        };
        reuse-lint =
          let
            program = pkgs.writeShellScriptBin "program" ''
              ${pkgs.lib.getExe pkgs.reuse} lint
            '';
          in
          {
            type = "app";
            program = "${pkgs.lib.getExe program}";
          };
      });
    };
}
