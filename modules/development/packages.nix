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
  ];

  programs.zsh.enable = true;
}
