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

  # machine0 CLI, packaged from the published npm release. The tarball is a
  # self-contained bundle (no runtime dependencies, no native modules), so no
  # npm install is needed — unpack and wrap with node. Profile injection writes
  # ~/.machine0/auth-token + machine0.env at boot, so this CLI is
  # authenticated out of the box on profile-carrying VMs.
  #
  # Bump: update version + hash from `npm view @machine0/cli version` and
  # `nix-prefetch-url --type sha256 <tarball>`.
  #
  # BEFORE BUMPING, CHECK: `npm view @machine0/cli@<version> dependencies`
  # MUST be empty. This unpack-and-wrap has no node_modules, so a CLI release
  # that declares runtime dependencies produces a package that builds fine and
  # then dies at *runtime* with ERR_MODULE_NOT_FOUND on every VM built from
  # this image. That is not hypothetical: 1.0.147–1.0.163 externalised `open`
  # and `update-notifier` out of the bundle (fdmtl/machine0#626) and 1.0.163
  # shipped here in #31 broken for exactly that reason. fdmtl/machine0#733
  # re-bundled them, and machine0's own CLI Package CI now packs the tarball
  # and installs it on a clean runner, so a regression is caught upstream —
  # but this derivation is the thing that breaks, so check it here too.
  machine0-cli = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "machine0-cli";
    version = "1.0.164";
    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/@machine0/cli/-/cli-${finalAttrs.version}.tgz";
      hash = "sha256-7BLWBUZcV7l4KTwf0RvIn2+z7P1w5Q4KWAwsiA1jHdw=";
    };
    nativeBuildInputs = [ pkgs.makeWrapper ];
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib/machine0-cli $out/bin
      cp -r . $out/lib/machine0-cli
      makeWrapper ${pkgs.nodejs_22}/bin/node $out/bin/machine0 \
        --add-flags "$out/lib/machine0-cli/bin/entry.cjs"
      runHook postInstall
    '';
    meta = {
      description = "Cloud VMs from the CLI";
      homepage = "https://machine0.io";
      mainProgram = "machine0";
    };
  });
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
