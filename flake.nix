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
      nixpkgs,
      push-container,
      ...
    }:
    let
      makePackages =
        system:
        import nixpkgs {
          inherit system;
          overlays = [
            # (final: prev: {
            #   nix = prev.nix.overrideAttrs (old: {
            #     postInstall = ''
            #       chmod u+s $out/bin/nix
            #     '';
            #   });
            # })
            # (final: prev: {
            #   docker_29 = prev.docker_29.override {
            #     clientOnly = true;
            #   };
            # })
            # (final: prev: {
            #   git = prev.git.override {
            #     doInstallCheck = false;
            #     guiSupport = false;
            #     perlSupport = false;
            #     pythonSupport = false;
            #     svnSupport = false;
            #     sendEmailSupport = false;
            #     withLibSecret = false;
            #     withManual = false;
            #     withSsh = false;
            #   };
            # })
          ];
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
          # docker-client = pkgs.docker_29.override {
          #   clientOnly = true;
          # };
          # git = pkgs.git.override {
          #   doInstallCheck = false;
          #   guiSupport = false;
          #   perlSupport = false;
          #   pythonSupport = false;
          #   svnSupport = false;
          #   sendEmailSupport = false;
          #   withLibSecret = false;
          #   withManual = false;
          #   withSsh = false;
          # };
          nixos-runner =
            let
              # `buildEnv` installs every output listed in `meta.outputsToInstall`,
              # which for most packages includes `man` (and sometimes `doc`/`info`).
              # Those outputs are pure documentation that nothing in a CI runner
              # image ever reads, and pulling them in drags whole store paths into
              # the image closure. Drop them while keeping whatever else the package
              # installs by default -- several packages here default to `bin` rather
              # than `out` (curl, xz, zstd, regctl, dnsutils), so hardcoding
              # `[ "out" ]` would install the wrong thing.
              docOutputs = [
                "devdoc"
                "doc"
                "docdev"
                "info"
                "man"
              ];
              stripDocs =
                drv:
                drv
                // {
                  meta = (drv.meta or { }) // {
                    outputsToInstall = lib.subtractLists docOutputs (drv.meta.outputsToInstall or [ "out" ]);
                  };
                };

              defaultPkgs = map stripDocs [
                pkgs.bashInteractive
                pkgs.bind.dnsutils
                pkgs.cacert
                pkgs.coreutils-full
                pkgs.curl
                pkgs.forgejo-cli
                pkgs.gawk
                pkgs.gh
                pkgs.gitMinimal
                pkgs.glibc
                pkgs.gnugrep
                pkgs.gnused
                pkgs.gnutar
                pkgs.gzip
                pkgs.iputils
                pkgs.less
                pkgs.nix
                pkgs.nodejs_25
                pkgs.procps
                pkgs.regctl
                pkgs.stdenv.cc.cc.lib
                pkgs.which
                pkgs.xz
                pkgs.zstd

                push-container.packages.${pkgs.stdenv.hostPlatform.system}.push-container
              ];

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
                accept-flake-config = "false";
                build-users-group = "nixbld";
                cores = "1";
                experimental-features = [
                  "flakes"
                  "nix-command"
                ];
                max-jobs = "1";
                sandbox = "true";
                trusted-users = [
                  "root"
                  "github"
                ];
                trusted-public-keys = [
                  "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
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

              gitConfig = ''
                [safe]
                ''\tdirectory = *
              '';

              baseSystem =
                let
                  userEnv = pkgs.buildPackages.buildEnv {
                    name = "root-profile-env";
                    paths = defaultPkgs;
                    # A few packages ship man pages and docs inside their default
                    # output, where dropping the doc outputs above can't reach them.
                    # Those store paths stay in the image closure regardless, but
                    # keep them out of the profile so nothing in the container
                    # (MANPATH included) surfaces documentation.
                    postBuild = ''
                      rm -rf $out/share/man $out/share/doc $out/share/info
                    '';
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
                    cp -a ${userEnv}/* $out/
                    ln -s ${manifest} $out/manifest.nix
                  '';
                in
                pkgs.runCommand "base-system"
                  {
                    inherit
                      groupContents
                      nixConfContents
                      passwdContents
                      shadowContents
                      gitConfig
                      ;
                    passAsFile = [
                      "groupContents"
                      "nixConfContents"
                      "passwdContents"
                      "shadowContents"
                      "gitConfig"
                    ];
                    allowSubstitutes = false;
                    preferLocalBuild = true;
                  }
                  ''
                    mkdir -p $out/etc

                    mkdir -p $out/etc/ssl/certs
                    ln -s /nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt $out/etc/ssl/certs
                    # zig's certificate scanner ignores SSL_CERT_FILE and only
                    # probes fixed paths like /etc/ssl/certs/ca-certificates.crt;
                    # point that name straight at the store cacert so it can
                    # never dangle
                    ln -s ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt $out/etc/ssl/certs/ca-certificates.crt

                    cat $passwdContentsPath > $out/etc/passwd
                    echo "" >> $out/etc/passwd

                    cat $groupContentsPath > $out/etc/group
                    echo "" >> $out/etc/group

                    cat $shadowContentsPath > $out/etc/shadow
                    echo "" >> $out/etc/shadow

                    cat $gitConfigPath > $out/etc/gitconfig
                    echo "" >> $out/etc/gitconfig

                    mkdir -p $out/etc/nix
                    cat $nixConfContentsPath > $out/etc/nix/nix.conf
                    echo "" >> $out/etc/nix/nix.conf

                    mkdir -p $out/usr
                    ln -s /nix/var/nix/profiles/share $out/usr/
                    mkdir -p $out/nix/var/nix/gcroots
                    mkdir -p $out/tmp
                    mkdir -p $out/var/tmp

                    mkdir -p $out/nix/var/nix/profiles
                    ln -s ${profile} $out/nix/var/nix/profiles/default-1-link
                    ln -s $out/nix/var/nix/profiles/default-1-link $out/nix/var/nix/profiles/default

                    mkdir -p $out/root
                    mkdir -p $out/nix/var/nix/profiles/per-user/root
                    ln -s /nix/var/nix/profiles/default $out/root/.nix-profile
                    mkdir -p $out/root/.config/git
                    cat $gitConfigPath > $out/root/.config/git/config

                    mkdir -p $out/github
                    mkdir -p $out/github/home
                    mkdir -p $out/nix/var/nix/profiles/per-user/github
                    ln -s /nix/var/nix/profiles/default $out/github/home/.nix-profile
                    mkdir -p $out/github/home/.config/git
                    cat $gitConfigPath > $out/github/home/.config/git/config

                    mkdir -p $out/bin $out/usr/bin
                    ln -s ${pkgs.coreutils}/bin/env $out/usr/bin/env
                  '';
            in
            pkgs.dockerTools.buildLayeredImageWithNixDb {
              name = "nixos-runner";
              tag = "latest";
              contents = [
                baseSystem
              ]
              ++ defaultPkgs;
              extraCommands = ''
                rm -rf nix-support
                ln -s /nix/var/nix/profiles nix/var/nix/gcroots/profiles
              '';
              fakeRootCommands = ''
                chmod u=rwxt,u=rwx,o=rwx tmp
                chmod u=rwxt,u=rwx,o=rwx var/tmp
                chown -R 1001:1001 github
              '';
              config =
                let
                  execas-github = pkgs.callPackage ./package.nix {
                    uid = 1001;
                    gid = 1001;
                    groups = lib.concatStringsSep "," (
                      map toString [
                        groups.wheel.gid
                        groups.github.gid
                        groups.nixbld.gid
                      ]
                    );
                    username = "github";
                    homedir = "/github/home";
                  };
                in
                {
                  Cmd = [ "${lib.getExe' execas-github "bash"}" ];
                  User = "0:0";
                  Env = [
                    "USER=root"
                    "PATH=${
                      lib.concatStringsSep ":" [
                        # "${lib.getBin execas-github}/bin"
                        "/root/.nix-profile/bin"
                        "/nix/var/nix/profiles/default/bin"
                        "/nix/var/nix/profiles/default/sbin"
                      ]
                    }"
                    "MANPATH=${
                      lib.concatStringsSep ":" [
                        "/root/.nix-profile/share/man"
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
                    # "NIX_PATH=/nix/var/nix/profiles/per-user/root/channels:/root/home/.nix-defexpr/channels"
                    # "MEMORYTEST=${lib.getExe' execas-github "memorytest"}"
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
            pkgs.zig_0_16
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
        server =
          let
            program = pkgs.writeShellScriptBin "program" ''
              ${pkgs.lib.getExe pkgs.nix} build -L .#nixos-runner
              ${pkgs.lib.getExe pkgs.podman} load < result
              ${pkgs.lib.getExe pkgs.podman} run --rm -it -e CI=true -e GITHUB_ACTIONS=true --entrypoint='["tail", "-f", "/dev/null"]' localhost/nixos-runner:latest
            '';
          in
          {
            type = "app";
            program = "${pkgs.lib.getExe program}";
          };
      });
    };
}
