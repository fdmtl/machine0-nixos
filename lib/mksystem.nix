# Builds a NixOS system for machine0. Wires up specialArgs (stateVersion,
# unstable nixpkgs, home-manager flake) so individual modules don't need to
# know about flake plumbing.
{
  nixpkgs,
  inputs,
  system,
  stateVersion,
}:

modules:

nixpkgs.lib.nixosSystem {
  inherit system;
  specialArgs = {
    inherit inputs stateVersion;
    nixpkgsUnstable = inputs.nixpkgs-unstable;
    homeManager = inputs.home-manager;
  };
  modules = modules ++ [
    { system.stateVersion = stateVersion; }
  ];
}
