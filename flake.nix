{
  description = "machine0 NixOS images — #base (minimal) and #loaded (dev stack)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = inputs@{ self, nixpkgs, ... }:
    let
      system = "x86_64-linux";

      mkSystem = import ./lib/mksystem.nix {
        inherit nixpkgs inputs system;
        stateVersion = "25.11";
      };

      mkImage = import ./lib/mkimage.nix { inherit mkSystem; };

      # Each profile is the list of modules layered to produce that system.
      profiles = {
        base = [ ./modules/base.nix ];
        loaded = [ ./modules/base.nix ./modules/loaded.nix ];
      };
    in
    {
      packages.${system} =
        builtins.mapAttrs (_: mkImage) profiles
        // { default = self.packages.${system}.loaded; };

      nixosConfigurations =
        builtins.mapAttrs (_: mkSystem) profiles
        // { default = self.nixosConfigurations.loaded; };
    };
}
