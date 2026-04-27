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

  # Banner shown on SSH login. Lives only on loaded — base ships bare.
  machine0.motd.text = ''

    ┌─────────────────────────────────────┐
    │                                     │
    │   machine0 — NixOS 25.11            │
    │                                     │
    │   Docs: https://machine0.io/docs    │
    │                                     │
    └─────────────────────────────────────┘

  '';
}
