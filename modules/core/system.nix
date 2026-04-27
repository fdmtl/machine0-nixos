# System — toplevel tag and /etc/nixos baking so a non-flake nixos-rebuild
# on the live VM still works.
#
# The flake's source files (flake.nix, flake.lock, lib/, modules/) are
# baked into /etc/nixos as sibling environment.etc entries. Directories
# pass through `lib.cleanSource` so editor backups, result symlinks, and
# .git aren't copied into the store. Without that filter, an editor
# swapfile or a fresh commit would change the /etc/nixos store path,
# change the system toplevel, and break the provision-is-no-op invariant
# asserted by CI.
#
# `system.nixos.tags = [ "machine0" ]` lives here (not in image.nix) so
# the toplevel hash is identical whether we're building an image or
# rebuilding on a live VM.
{
  config,
  lib,
  nixpkgsUnstable,
  ...
}:
let
  overlays = import ../../lib/overlays.nix { inherit nixpkgsUnstable; };

  configurationText =
    if config.machine0.profile.loaded then
      ''
        { ... }:
        {
          imports = [ /etc/nixos/modules/profiles/loaded.nix ];

          # Hash-pinned at image build time from the flake input's narHash,
          # so a runtime nixos-rebuild reading this file cannot be tricked
          # into evaluating a substituted nixpkgs-unstable tree.
          ${overlays.unstableText}
        }
      ''
    else
      ''
        { ... }:
        {
          imports = [ /etc/nixos/modules/profiles/base.nix ];
        }
      '';
in
{
  system.nixos.tags = [ "machine0" ];

  environment.etc = {
    "nixos/flake.nix".source = ../../flake.nix;
    "nixos/flake.lock".source = ../../flake.lock;
    "nixos/lib".source = lib.cleanSource ../../lib;
    "nixos/modules".source = lib.cleanSource ../../modules;
    "nixos/configuration.nix".text = configurationText;
  };
}
