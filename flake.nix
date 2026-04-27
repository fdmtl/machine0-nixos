{
  description = "machine0 NixOS images — base, loaded, openclaw, hermes";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Agent profiles. Both pin nixos-unstable upstream; we deliberately do
    # NOT make them follow our 25.11 nixpkgs to avoid eval breakage.
    nix-openclaw.url = "github:openclaw/nix-openclaw";
    hermes-agent.url = "github:NousResearch/hermes-agent";
  };

  outputs =
    inputs@{ self, nixpkgs, ... }:
    let
      system = "x86_64-linux";

      mkSystem = import ./lib/mksystem.nix {
        inherit nixpkgs inputs system;
        stateVersion = "25.11";
      };

      mkImage = import ./lib/mkimage.nix { inherit mkSystem; };

      # Each profile is the list of modules layered to produce that system.
      # Keep in sync with manifest.json (single source of truth for the
      # (profile -> machine0 image name) mapping consumed by build scripts).
      profiles = {
        base = [ ./modules/profiles/base.nix ];
        loaded = [ ./modules/profiles/loaded.nix ];
        openclaw = [ ./modules/profiles/openclaw.nix ];
        hermes = [ ./modules/profiles/hermes.nix ];
      };
    in
    {
      packages.${system} = builtins.mapAttrs (_: mkImage) profiles // {
        default = self.packages.${system}.loaded;
      };

      nixosConfigurations = builtins.mapAttrs (_: mkSystem) profiles // {
        default = self.nixosConfigurations.loaded;
      };
    };
}
