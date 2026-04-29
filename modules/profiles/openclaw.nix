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

  # mkForce (50) overrides loaded.nix's normal priority (100).
  machine0.motd.text = lib.mkForce (
    import ../../lib/mkMotd.nix {
      title = "[ m0 ] NixOS 25.11 · OpenClaw 🦞";
      body = [
        "# Start onboarding (~60s on first run):"
        "$ openclaw onboard --install-daemon"
        ""
        "Built with the #openclaw profile, fork to customize:"
        "-> https://github.com/fdmtl/machine0-nixos"
      ];
    }
  );

  # Auto-upgrade tracks the openclaw profile, not the default (loaded).
  # Normal priority overrides core/nix.nix's mkDefault.
  system.autoUpgrade.flake = "github:fdmtl/machine0-nixos#openclaw";
}
