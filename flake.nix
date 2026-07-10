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

      # Reusable builders, closed over this flake's inputs. Consumers pass a
      # module list: machine0.lib.mkSystem [ machine0.nixosModules.loaded ./mine.nix ]
      lib = { inherit mkSystem mkImage; };

      # Profile entry-point modules (each imports its full parent chain).
      nixosModules =
        builtins.mapAttrs (_: modules: {
          imports = modules;
        }) profiles
        // {
          default = self.nixosModules.loaded;
        };

      # Eval-only guards for the exported consumer API (lib + nixosModules),
      # one per profile plus the image path. CI evals the drvPaths so a
      # regression in the exported surface fails fast without building.
      checks.${system} =
        builtins.mapAttrs (
          name: _:
          (mkSystem [
            self.nixosModules.${name}
            {
              machine0.motd.text = nixpkgs.lib.mkOverride 10 "consumer-api check";
              system.autoUpgrade.enable = nixpkgs.lib.mkForce false;
            }
          ]).config.system.build.toplevel
        ) profiles
        // {
          consumer-image = mkImage [ self.nixosModules.base ];
        };
    };
}
