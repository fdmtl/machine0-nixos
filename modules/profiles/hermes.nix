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
in
{
  imports = [
    ./loaded.nix
    ../development/playwright-mcp.nix
  ];

  environment.systemPackages = [ hermesPkg ];

  # mkForce overrides loaded.nix's MOTD at the same priority.
  machine0.motd.text = lib.mkForce (import ../../lib/mkMotd.nix {
    title = "[ m0 ] NixOS 25.11 · Hermes Agent ☤";
    body = [
      "Welcome to your new Hermes Agent VM!"
      ""
      "Quick start:"
      "$ hermes setup       # Run setup wizard"
      "$ hermes             # Start chatting"
      ""
      "Messaging gateway (Telegram / Discord / Slack / ...):"
      "$ hermes gateway setup"
      "$ hermes gateway start"
    ];
    docsUrl = "https://hermes-agent.nousresearch.com/docs";
  });

  # Auto-upgrade tracks the hermes profile, not the default (loaded).
  # Normal priority overrides core/nix.nix's mkDefault.
  system.autoUpgrade.flake = "github:fdmtl/machine0-nixos#hermes";
}
