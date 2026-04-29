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
  esc = builtins.fromJSON ''"\u001b"'';
  bel = builtins.fromJSON ''"\u0007"'';
  dc = "${esc}[2;36m";
  bw = "${esc}[1;97m";
  bc = "${esc}[1;36m";
  b  = "${esc}[1m";
  ul = "${esc}[4m";
  r  = "${esc}[0m";
  osc = "${esc}]8;;";
  dollar = b + "$" + r;
  docsUrl = "https://docs.machine0.io/use/openclaw";
in
{
  imports = [
    ./loaded.nix
    ../development/playwright-mcp.nix
  ];

  environment.systemPackages = [ openclawPkg ];

  # mkForce overrides loaded.nix's MOTD at the same priority.
  machine0.motd.text = lib.mkForce ''

    ${dc}╭──────────────────────────────────────────────────────────╮${r}
    ${dc}│${r}                                                          ${dc}│${r}
    ${dc}│${r}   ${bw}[ m0 ] NixOS 25.11 · OpenClaw${r}                          ${dc}│${r}
    ${dc}│${r}                                                          ${dc}│${r}
    ${dc}│${r}   Welcome to your new OpenClaw VM!                       ${dc}│${r}
    ${dc}│${r}   Run this to start the onboarding process:              ${dc}│${r}
    ${dc}│${r}                                                          ${dc}│${r}
    ${dc}│${r}   ${dollar} ${bc}openclaw onboard --install-daemon${r}                    ${dc}│${r}
    ${dc}│${r}                                                          ${dc}│${r}
    ${dc}│${r}   Note: ~60s on first run — don't kill the process.      ${dc}│${r}
    ${dc}│${r}   Docs: ${osc}${docsUrl}${bel}${ul}${docsUrl}${r}${osc}${bel}            ${dc}│${r}
    ${dc}│${r}                                                          ${dc}│${r}
    ${dc}╰──────────────────────────────────────────────────────────╯${r}

  '';

  # Auto-upgrade tracks the openclaw profile, not the default (loaded).
  # Normal priority overrides core/nix.nix's mkDefault.
  system.autoUpgrade.flake = "github:fdmtl/machine0-nixos#openclaw";
}
