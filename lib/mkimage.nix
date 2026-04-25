# Layers the image-builder module on top of the given profile and returns
# the gzipped qcow2 derivation. Use the same module list you would pass to
# mkSystem.
{ mkSystem }:

modules:

(mkSystem (modules ++ [ ../modules/image.nix ])).config.system.build.machine0Image
