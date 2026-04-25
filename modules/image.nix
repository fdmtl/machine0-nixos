# machine0 image builder — produces a gzipped qcow2 disk image via
# nixpkgs' make-disk-image.nix, replacing nixos-generators and the
# upstream digital-ocean-image.nix module.
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
{
  imports = [
    (modulesPath + "/virtualisation/disk-size-option.nix")
    (modulesPath + "/image/file-options.nix")
  ];

  config =
    let
      format = "qcow2";
    in
    {
      image.extension = "${format}.gz";
      system.nixos.tags = [ "machine0" ];
      system.build.machine0Image = import (modulesPath + "/../lib/make-disk-image.nix") {
        name = "machine0-image";
        inherit (config.image) baseName;
        inherit (config.virtualisation) diskSize;
        inherit
          config
          lib
          pkgs
          format
          ;
        postVM = ''
          ${pkgs.gzip}/bin/gzip $diskImage
        '';
      };
    };
}
