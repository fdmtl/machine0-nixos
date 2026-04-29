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

  # mkForce (50) overrides loaded.nix's normal priority (100).
  machine0.motd.text = lib.mkForce (
    import ../../lib/mkMotd.nix {
      title = "[ m0 ] NixOS 25.11 · Hermes Agent ☤";
      body = [
        "# Quick start:"
        "$ hermes setup"
        "$ hermes"
        ""
        "# Messaging gateway (Telegram / Discord / Slack / ...):"
        "$ hermes gateway setup"
        "$ hermes gateway start"
        ""
        "Built with the #hermes profile, fork to customize:"
        "-> https://github.com/fdmtl/machine0-nixos"
      ];
    }
  );

  # Auto-upgrade tracks the hermes profile, not the default (loaded).
  # Normal priority overrides core/nix.nix's mkDefault.
  system.autoUpgrade.flake = "github:fdmtl/machine0-nixos#hermes";
}
