# Base profile — minimal cloud VM. Boot, networking, hardened SSH,
# fail2ban, the metadata-driven systemd services, and a small set of
# always-useful CLI utilities. No dev stack, no MOTD.
{ pkgs, ... }:
{
  imports = [
    ../core/boot.nix
    ../core/networking.nix
    ../core/nix.nix
    ../core/ssh.nix
    ../core/fail2ban.nix
    ../core/system.nix
    ../core/users.nix
    ../machine0.nix
    ../motd.nix
  ];

  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    htop
    wget
    tmux
    jq
  ];
}
