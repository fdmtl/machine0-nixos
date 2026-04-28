# OpenClaw profile — loaded + the OpenClaw CLI from nix-openclaw.
#
# Mirrors the spirit of fdmtl/machine0-ubuntu's openclaw.yml: install the
# `openclaw` CLI and tell the user, via MOTD, to run
# `openclaw onboard --install-daemon` to start the interactive onboarding.
# We do not pre-enable services.openclaw-gateway — onboarding is what wires
# secrets/identity, and it should remain user-driven.
{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) system;
  openclawPkg = inputs.nix-openclaw.packages.${system}.openclaw;
in
{
  imports = [
    ./loaded.nix
    ../development/playwright-mcp.nix
  ];

  environment.systemPackages = [ openclawPkg ];

  # mkForce overrides loaded.nix's MOTD at the same priority.
  machine0.motd.text = lib.mkForce ''

    ┌──────────────────────────────────────────────────────────┐
    │                                                          │
    │   machine0 — NixOS 25.11 · OpenClaw                      │
    │                                                          │
    │   Welcome to your new OpenClaw VM!                       │
    │   Run this to start the onboarding process:              │
    │                                                          │
    │     $ openclaw onboard --install-daemon                  │
    │                                                          │
    │   Note: ~60s on first run — don't kill the process.      │
    │                                                          │
    │   Docs: https://github.com/openclaw/nix-openclaw         │
    │                                                          │
    └──────────────────────────────────────────────────────────┘

  '';

  # Auto-upgrade tracks the openclaw profile, not the default (loaded).
  # Normal priority overrides core/nix.nix's mkDefault.
  system.autoUpgrade.flake = "github:fdmtl/machine0-nixos#openclaw";
}
