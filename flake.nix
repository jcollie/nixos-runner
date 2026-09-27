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

              # nodejs_24 is nodejs-slim plus npm and corepack. nodejs-slim
              # records its configure flags twice -- in the headers it ships for
              # building native addons, and inside the binary as
              # `process.config` -- and those flags name the `dev` output of
              # every library node was built against: icu4c, openssl, gtest and
              # a dozen more, none of which a running node ever loads. Copy what
              # node needs at run time into a single tree without the headers,
              # blank the `dev` paths and node's own install prefix in the
              # binary (`process.config` is informational only), and point npm's
              # shebangs at the copy, so that nodejs-slim and everything its
              # build flags drag along drop out of the closure.
              nodejs =
                pkgs.runCommand "nodejs-runtime-${pkgs.nodejs_24.version}"
                  {
                    nativeBuildInputs = [ pkgs.removeReferencesTo ];
                    disallowedReferences = [ pkgs.nodejs-slim_24 ];
                  }
                  ''
                    mkdir -p $out/bin
                    cp -L ${pkgs.nodejs_24}/bin/node $out/bin/node
                    chmod u+w $out/bin/node
                    remove-references-to -t ${pkgs.nodejs-slim_24} $out/bin/node
                    grep -aoE '${builtins.storeDir}/[a-z0-9]{32}-[^/"]+-dev' $out/bin/node \
                      | sort -u \
                      | while read -r dev; do remove-references-to -t "$dev" $out/bin/node; done
                    cp -P ${pkgs.nodejs_24}/bin/{npm,npx,corepack} $out/bin/
                    cp -rL ${pkgs.nodejs_24}/lib $out/lib
                    chmod -R u+w $out
                    grep -rlF ${pkgs.nodejs-slim_24} $out/lib \
                      | xargs -r sed -i "s|${pkgs.nodejs-slim_24}|$out|g"
                  '';

              # git without its translations: those are 13 MB of message
              # catalogs in git itself plus gettext, another 25 MB, and nothing
              # in CI reads git's output in anything but English. This is the
              # one package here that is built rather than substituted.
              #
              # nixpkgs still hardcodes gettext.sh into `git-sh-i18n`, but built
              # without NLS that script pins itself to the English-only
              # "fallthrough" scheme before the branch naming gettext.sh can be
              # reached, so the reference is dead and can be blanked.
              git =
                (pkgs.gitMinimal.override {
                  nlsSupport = false;
                  doInstallCheck = false;
                }).overrideAttrs
                  (old: {
                    nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.removeReferencesTo ];
                    disallowedReferences = (old.disallowedReferences or [ ]) ++ [ pkgs.gettext ];
                    postFixup = (old.postFixup or "") + ''
                      remove-references-to -t ${pkgs.gettext} $out/libexec/git-core/git-sh-i18n
                    '';
                  });

              defaultPkgs = map stripDocs [
                pkgs.bashInteractive
                pkgs.bind.dnsutils
                pkgs.cacert
                pkgs.coreutils
                pkgs.curl
                pkgs.gawk
                git
                pkgs.glibc
                pkgs.gnugrep
                pkgs.gnused
                pkgs.gnutar
                pkgs.gzip
                pkgs.iputils
                pkgs.less
                pkgs.nix
                nodejs
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
                  # Not shadow's nologin: that would pull shadow, linux-pam and
                  # berkeley db into the image for one program that is never run.
                  shell = "${pkgs.coreutils}/bin/false";
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
