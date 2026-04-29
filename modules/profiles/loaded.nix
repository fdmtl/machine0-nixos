# Loaded profile — base + dev stack. Build tools, language runtimes,
# AI agents, rootless Docker, npm, and a Home Manager-driven shell
# (zsh + starship + zoxide + eza + screen) for the `nix` user.
{ pkgs, lib, ... }:
{
  imports = [
    ./base.nix
    ../development/packages.nix
    ../development/services.nix
    ../home
  ];

  machine0.profile.loaded = true;

  # Login shell switches to zsh in the loaded profile. mkForce because
  # core/users.nix sets shell at the same priority.
  users.users.nix.shell = lib.mkForce pkgs.zsh;

  # Normal priority (100) overrides base's mkDefault (1000).
  machine0.motd.text = import ../../lib/mkMotd.nix {
    title = "[ m0 ] NixOS 25.11";
    body = [
      "Built with the #loaded profile, fork to customize:"
      "-> https://github.com/fdmtl/machine0-nixos"
    ];
  };
}
