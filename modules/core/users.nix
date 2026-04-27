# Users — single `nix` user with passwordless sudo. Bash by default; the
# loaded profile flips this to zsh via lib.mkForce.
{ pkgs, ... }:
{
  users.users.nix = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.bashInteractive;
  };

  security.sudo.wheelNeedsPassword = false;
}
