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

      # Reusable builders. mkSystem/mkImage are closed over this flake's
      # inputs; consumers pass a module list:
      #   machine0.lib.mkSystem [ machine0.nixosModules.loaded ./mine.nix ]
      # mkMotd is the pure banner builder ({ title, body ? [], width ? null }
      # -> string) used by the profiles' MOTDs, exported so consumer profiles
      # can build a styled banner instead of a plain string.
      lib = {
        inherit mkSystem mkImage;
        mkMotd = import ./lib/mkMotd.nix;
      };

      # Profile entry-point modules (each imports its full parent chain).
      # These require machine0.lib.mkSystem — they read machine0-specific
      # specialArgs and will not evaluate under a plain nixosSystem.
      nixosModules =
        builtins.mapAttrs (
          name: modules:
          nixpkgs.lib.setDefaultModuleLocation "machine0-nixos#nixosModules.${name}" {
            imports = modules;
          }
        ) profiles
        // {
          default = self.nixosModules.loaded;
        };

      # Eval-only guards for the exported consumer API (lib + nixosModules),
      # one per profile plus the image path. Each check is a trivial
      # runCommand whose *instantiation* forces the full system eval, so
      # `nix flake check` and the CI drvPath step both catch API regressions
      # without ever building a system or disk image.
      checks.${system} =
        let
          pkgs = nixpkgs.legacyPackages.${system};
          evalGuard =
            name: drv:
            pkgs.runCommand "consumer-api-${name}" { } ''
              echo "${builtins.unsafeDiscardStringContext drv.drvPath}" > "$out"
            '';
        in
        builtins.mapAttrs (
          name: _:
          evalGuard name
            (mkSystem [
              self.nixosModules.${name}
              {
                # Route the override through self.lib.mkMotd so the eval
                # guards also pin the exported banner-builder API (every
                # body-line convention: plain, blank, command, comment, link).
                machine0.motd.text = nixpkgs.lib.mkOverride 10 (
                  self.lib.mkMotd {
                    title = "consumer-api check";
                    body = [
                      "plain line"
                      ""
                      "$ machine0 ssh check"
                      "# dim comment"
                      "-> machine0.io"
                    ];
                  }
                );
                system.autoUpgrade.enable = nixpkgs.lib.mkForce false;
              }
            ]).config.system.build.toplevel
        ) profiles
        // {
          consumer-image = evalGuard "image" (mkImage [ self.nixosModules.base ]);
        };
    };
}
