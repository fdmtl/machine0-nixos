# machine0 loaded module — layers dev tools on top of base.nix.
#
# This file is baked into the image as /etc/nixos/loaded.nix and imported
# by /etc/nixos/configuration.nix so that first-boot `nixos-rebuild switch`
# (e.g. from `machine0 provision`) re-applies it and produces the same
# toplevel that was built into the image.
{
  pkgs,
  lib,
  nixpkgsUnstable ? null,
  ...
}:

{
  machine0.profile.loaded = true;

  # Pull AI agents from unstable so we get fresh upstream releases without
  # waiting for the 25.11 channel.
  nixpkgs.overlays = lib.optionals (nixpkgsUnstable != null) [
    (final: prev:
      let
        unstable = import nixpkgsUnstable {
          inherit (prev.stdenv.hostPlatform) system;
          config.allowUnfree = true;
        };
      in
      {
        inherit (unstable) claude-code codex;
      })
  ];
  nixpkgs.config.allowUnfree = true;

  # Base image creates the `nix` user with wheel + passwordless sudo and bash.
  # Loaded layer: flip shell to zsh. mkForce because base sets shell at the
  # same priority. Docker runs rootless under this user — no docker group.
  users.users.nix = {
    shell = lib.mkForce pkgs.zsh;
  };

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
    fzf
    ripgrep

    # Runtimes
    bun
    python3
    uv
    pipx
    rustc
    cargo
    go

    # Shell tools
    eza
    zoxide
    starship
    screen
    chafa

    # AI agents
    claude-code
    codex
  ];

  programs.zsh = {
    enable = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
  };

  # Point npm's global prefix at the user's home so `npm install -g` works
  # without trying to write into the read-only nodejs store path. The
  # default npmrc shipped by this module already sets prefix = ${HOME}/.npm.
  programs.npm = {
    enable = true;
    package = pkgs.nodejs_22;
  };

  environment.sessionVariables = {
    PATH = [ "$HOME/.npm/bin" ];
  };

  # Rootless Docker — daemon runs as the `nix` user, not root.
  # `setSocketVariable = true` exports DOCKER_HOST so the docker CLI talks to
  # the per-user socket without needing sudo or docker-group membership.
  virtualisation.docker.rootless = {
    enable = true;
    setSocketVariable = true;
  };

  # SSH hardening + fail2ban live in base.nix.
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 80 443 ];
  };

  # Let rootless Docker (and any other unprivileged process) bind 80/443
  # directly. Without this, rootlesskit refuses with EACCES on ports < 1024.
  boot.kernel.sysctl."net.ipv4.ip_unprivileged_port_start" = 80;

  # Deploy shell configs to the nix user's home. Files are nix paths so
  # they're baked into the store (edit-then-rebuild flow).
  system.activationScripts.nixUserConfig = lib.stringAfter [ "users" ] ''
    NIX_HOME="/home/nix"
    if [ -d "$NIX_HOME" ]; then
      # `install -d` only applies -o/-g/-m to directories it creates and
      # only to the leaf, so .config got root-owned on fresh boots. Create
      # the tree, then chown -R to self-heal any wrong ownership inherited
      # from older activations (including subdirs created by other tools).
      install -d -m 0755 -o nix -g users "$NIX_HOME/.config"
      install -d -m 0755 -o nix -g users "$NIX_HOME/.config/starship"
      chown -R nix:users "$NIX_HOME/.config"
      install -m 0644 -o nix -g users ${../files/init.zsh} "$NIX_HOME/.zshrc"
      install -m 0644 -o nix -g users ${../files/starship.toml} \
        "$NIX_HOME/.config/starship/starship.toml"
      install -m 0644 -o nix -g users ${../files/screenrc} "$NIX_HOME/.screenrc"
    fi
  '';

  # Override the base wrapper so rebuilds keep loading the dev profile.
  environment.etc = {
    "nixos/loaded.nix".source = ./loaded.nix;
    "nixos/files".source = ../files;
    "motd".text = ''

        ┌─────────────────────────────────────┐
        │                                     │
        │   machine0 — NixOS 25.11            │
        │                                     │
        │   Docs: https://machine0.io/docs    │
        │                                     │
        └─────────────────────────────────────┘

    '';
    # Hash-pinned at image build time from the flake input's narHash, so a
    # runtime `nixos-rebuild` reading this file cannot be tricked into
    # evaluating a substituted nixpkgs-unstable tree.
    "nixos/configuration.nix".text = ''
      { ... }:
      {
        imports = [
          /etc/nixos/base.nix
          /etc/nixos/loaded.nix
        ];
        nixpkgs.overlays = [
          (final: prev:
            let
              unstable = import (builtins.fetchTarball {
                url = "https://github.com/NixOS/nixpkgs/archive/${nixpkgsUnstable.rev}.tar.gz";
                sha256 = "${nixpkgsUnstable.narHash}";
              }) { inherit (prev.stdenv.hostPlatform) system; config.allowUnfree = true; };
            in {
              inherit (unstable) claude-code codex;
            })
        ];
        nixpkgs.config.allowUnfree = true;
      }
    '';
  };
}
