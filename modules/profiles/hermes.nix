# Hermes profile — loaded + the Hermes Agent CLI from NousResearch/hermes-agent.
#
# Installs the `hermes` CLI. MOTD points the user at `hermes setup`
# (interactive wizard) and the messaging-gateway flow. We do not
# pre-enable services.hermes-agent — the wizard is what wires API keys
# and platform tokens, and it should remain user-driven.
{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) system;
  hermesPkg = inputs.hermes-agent.packages.${system}.default;
  esc = builtins.fromJSON ''"\u001b"'';
  dc = "${esc}[2;36m";
  bw = "${esc}[1;97m";
  r = "${esc}[0m";
in
{
  imports = [
    ./loaded.nix
    ../development/playwright-mcp.nix
  ];

  environment.systemPackages = [ hermesPkg ];

  # mkForce overrides loaded.nix's MOTD at the same priority.
  machine0.motd.text = lib.mkForce ''

    ${dc}╭──────────────────────────────────────────────────────────╮${r}
    ${dc}│${r}                                                          ${dc}│${r}
    ${dc}│${r}   machine0 — NixOS 25.11 · Hermes Agent ☤                ${dc}│${r}
    ${dc}│${r}                                                          ${dc}│${r}
    ${dc}│${r}   Welcome to your new Hermes Agent VM!                   ${dc}│${r}
    ${dc}│${r}                                                          ${dc}│${r}
    ${dc}│${r}   Quick start:                                           ${dc}│${r}
    ${dc}│${r}     ${bw}$ hermes setup       # Run setup wizard${r}              ${dc}│${r}
    ${dc}│${r}     ${bw}$ hermes             # Start chatting${r}                ${dc}│${r}
    ${dc}│${r}                                                          ${dc}│${r}
    ${dc}│${r}   Messaging gateway (Telegram / Discord / Slack / ...):  ${dc}│${r}
    ${dc}│${r}     ${bw}$ hermes gateway setup${r}                               ${dc}│${r}
    ${dc}│${r}     ${bw}$ hermes gateway start${r}                               ${dc}│${r}
    ${dc}│${r}                                                          ${dc}│${r}
    ${dc}│${r}   Docs: https://hermes-agent.nousresearch.com/docs       ${dc}│${r}
    ${dc}│${r}                                                          ${dc}│${r}
    ${dc}╰──────────────────────────────────────────────────────────╯${r}

  '';

  # Auto-upgrade tracks the hermes profile, not the default (loaded).
  # Normal priority overrides core/nix.nix's mkDefault.
  system.autoUpgrade.flake = "github:fdmtl/machine0-nixos#hermes";
}
