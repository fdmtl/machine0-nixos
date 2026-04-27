# Home Manager hook-up. Imports the HM NixOS module from the flake input
# (passed via `homeManager` specialArg by lib/mksystem.nix), pins it to
# the system's nixpkgs, and points it at the per-user config in
# ./nix-user.nix.
#
# `useGlobalPkgs = true` shares overlays/configs with the system.
# `useUserPackages = true` installs HM packages into
# /etc/profiles/per-user/<name>/, not ~/.nix-profile, so they survive
# logins cleanly and don't fight system activation.
{ homeManager, ... }:
{
  imports = [ homeManager.nixosModules.home-manager ];

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.nix = import ./nix-user.nix;
}
