# Builds a NixOS system for machine0. Wires up specialArgs (stateVersion,
# unstable nixpkgs) so individual modules don't need to know about flake
# plumbing.
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
    inherit stateVersion;
    nixpkgsUnstable = inputs.nixpkgs-unstable;
  };
  modules = modules ++ [
    { system.stateVersion = stateVersion; }
  ];
}
