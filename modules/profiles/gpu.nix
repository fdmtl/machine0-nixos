# GPU profile — base + NVIDIA datacenter userland (hardware/nvidia.nix).
# No dev stack: GPU boxes are compute-first; fork and layer loaded.nix (or
# your own module) if you want the tooling.
{ lib, ... }:
{
  imports = [
    ./base.nix
    ../hardware/nvidia.nix
  ];

  # Normal priority (100) overrides base's mkDefault (1000).
  machine0.motd.text = import ../../lib/mkMotd.nix {
    title = "[ m0 ] NixOS 25.11 · GPU";
    body = [
      "# NVIDIA dc driver 580.126.09 · CUDA via containers (--gpus all)"
      "$ nvidia-smi"
      ""
      "Built with the #gpu profile, fork to customize:"
      "-> https://github.com/fdmtl/machine0-nixos"
    ];
  };

  # Auto-upgrade tracks the gpu profile, not the default. Normal priority
  # overrides core/nix.nix's mkDefault. (Same pattern as openclaw/hermes.)
  system.autoUpgrade.flake = "github:fdmtl/machine0-nixos#gpu";

  # core/system.nix bakes /etc/nixos/configuration.nix for base/loaded
  # only; without this override a non-flake `nixos-rebuild` on a GPU VM
  # would rebuild as plain base and silently drop the NVIDIA stack.
  environment.etc."nixos/configuration.nix".text = lib.mkForce ''
    { ... }:
    {
      imports = [ /etc/nixos/modules/profiles/gpu.nix ];
    }
  '';
}
