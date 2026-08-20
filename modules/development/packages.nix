# Development packages — build tools, language runtimes, CLI essentials,
# AI agents. The unstable-nixpkgs overlay is wired in here so claude-code
# and codex track upstream releases without waiting for the 25.11 channel.
#
# Note: zsh/starship/zoxide/eza/screen/fzf are *not* in this list —
# Home Manager owns them per-user and places their configs in the right
# spot. `programs.zsh.enable = true` stays at the system level so zsh is a
# valid login shell and /etc/zshenv is set up.
{
  pkgs,
  lib,
  nixpkgsUnstable ? null,
  ...
}:
let
  overlays = import ../../lib/overlays.nix { inherit nixpkgsUnstable; };

  # machine0 CLI, packaged from the published npm release. Profile injection
  # writes ~/.machine0/auth-token + machine0.env at boot, so this CLI is
  # authenticated out of the box on profile-carrying VMs.
  #
  # This USED to be a plain unpack-and-wrap, on the basis that the tarball is
  # "a single bundled cjs with no dependencies". That stopped being true after
  # 1.0.144: every release since declares runtime deps
  #
  #   "dependencies": { "open": "^11.0.0", "update-notifier": "^7.3.1" }
  #
  # and dist/cli.bundle.mjs statically `import`s both. Without node_modules the
  # CLI dies at ES-module link time on EVERY invocation, including
  # `machine0 --version`:
  #
  #   Error [ERR_MODULE_NOT_FOUND]: Cannot find package 'open' imported from
  #   .../dist/cli.bundle.mjs
  #
  # That is a total break, not a degraded feature, and it is silent at build
  # time — the derivation succeeds and the binary is broken at runtime. Do not
  # "simplify" this back to a bare copy without first checking
  # `npm view @machine0/cli@<version> dependencies` is empty.
  #
  # The deps are fetched by a fixed-output derivation rather than
  # buildNpmPackage because the published tarball ships no package-lock.json,
  # so there is no lockfile for buildNpmPackage's npmDepsHash to pin. An FOD
  # with an explicit output hash gives the same reproducibility guarantee: the
  # build is still sandboxed, the result is still content-addressed, and a
  # registry change fails the hash check rather than sneaking through.
  #
  # Bump: update version + both hashes. Get the tarball hash from
  # `nix-prefetch-url`, then set nodeModules' outputHash to
  # lib.fakeHash, build once, and copy the hash nix reports. Then VERIFY
  # `machine0 --version` actually prints a version — a missing runtime dep does
  # not fail the build, only the binary.
  machine0-cli =
    let
      version = "1.0.163";
      src = pkgs.fetchurl {
        url = "https://registry.npmjs.org/@machine0/cli/-/cli-${version}.tgz";
        hash = "sha256-AInMzjielQ7c754hl1K/M2PJqeaePDchXSw4Y8Ml0bs=";
      };

      # A fixed-output derivation, so it may reach the network — but FODs are
      # forbidden from referencing store paths in their *inputs*, which rules
      # out mkDerivation's usual `src = <store path>` unpack. Hence runCommand
      # plus an explicit `tar` of just the manifest.
      nodeModules = pkgs.runCommand "machine0-cli-node-modules-${version}" {
        nativeBuildInputs = [
          pkgs.nodejs_22
          pkgs.cacert
          pkgs.gnutar
          pkgs.gzip
        ];
        outputHashMode = "recursive";
        outputHashAlgo = "sha256";
        outputHash = "sha256-5kR1PuAV6IT/QRwqZLVpoodSY5P4K4D8dwNi8wbtCk0=";
      } ''
        export HOME=$TMPDIR
        mkdir -p $TMPDIR/build && cd $TMPDIR/build
        tar xzf ${src} --strip-components=1 package/package.json

        # Install from a SCRATCH manifest holding only `dependencies`. Using the
        # published package.json directly fails outright:
        #
        #   npm error code EUNSUPPORTEDPROTOCOL
        #   npm error Unsupported URL Type "workspace:": workspace:*
        #
        # because devDependencies carries `@machine0/api: workspace:*` (and two
        # siblings) that only resolve inside machine0's own monorepo and are not
        # published. npm parses the whole manifest before applying --omit=dev, so
        # those entries break the install even though they are not wanted.
        # Copying just the runtime deps sidesteps that, and has the useful
        # property that a new upstream dep changes this hash and gets noticed.
        node -e '
          const pkg = require(process.cwd() + "/package.json");
          require("fs").writeFileSync("package.json", JSON.stringify({
            name: "machine0-cli-deps", version: "0.0.0", private: true,
            dependencies: pkg.dependencies || {},
          }));
        '
        npm install --ignore-scripts --no-audit --no-fund

        mkdir -p $out
        cp -r node_modules $out/
      '';
    in
    pkgs.stdenvNoCC.mkDerivation {
      pname = "machine0-cli";
      inherit version src;
      nativeBuildInputs = [ pkgs.makeWrapper ];
      dontBuild = true;
      installPhase = ''
        runHook preInstall
        mkdir -p $out/lib/machine0-cli $out/bin
        cp -r . $out/lib/machine0-cli
        # Beside the bundle, so node's normal resolution finds it with no
        # NODE_PATH games.
        cp -r ${nodeModules}/node_modules $out/lib/machine0-cli/
        makeWrapper ${pkgs.nodejs_22}/bin/node $out/bin/machine0 \
          --add-flags "$out/lib/machine0-cli/bin/entry.cjs"
        runHook postInstall
      '';
      meta = {
        description = "Cloud VMs from the CLI";
        homepage = "https://machine0.io";
        mainProgram = "machine0";
      };
    };
in
{
  nixpkgs.overlays = lib.optionals (nixpkgsUnstable != null) [ overlays.unstableModule ];
  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    # Build tools
    gcc
    gnumake
    cmake
    pkg-config

    # CLI essentials
    git
    gh
    vim
    curl
    wget
    unzip
    jq
    p7zip
    inetutils
    htop
    btop
    lsof
    ripgrep
    chafa
    screen

    # Runtimes
    bun
    python3
    uv
    pipx
    rustc
    cargo
    go

    # AI agents (from unstable via the overlay above)
    claude-code
    codex

    # machine0 CLI (npm release, see the derivation above) — authenticated
    # via profile injection (~/.machine0/auth-token).
    machine0-cli
  ];

  programs.zsh.enable = true;
}
