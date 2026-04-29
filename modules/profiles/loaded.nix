# Loaded profile — base + dev stack. Build tools, language runtimes,
# AI agents, rootless Docker, npm, and a Home Manager-driven shell
# (zsh + starship + zoxide + eza + screen) for the `nix` user.
{ pkgs, lib, ... }:
let
  esc = builtins.fromJSON ''"\u001b"'';
  dc = "${esc}[2;36m";
  r = "${esc}[0m";
in
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

    ${dc}╭─────────────────────────────────────╮${r}
    ${dc}│${r}                                     ${dc}│${r}
    ${dc}│${r}   machine0 — NixOS 25.11            ${dc}│${r}
    ${dc}│${r}                                     ${dc}│${r}
    ${dc}│${r}   Docs: https://machine0.io/docs    ${dc}│${r}
    ${dc}│${r}                                     ${dc}│${r}
    ${dc}╰─────────────────────────────────────╯${r}

  '';
}
