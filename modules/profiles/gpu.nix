# GPU profile — base + NVIDIA datacenter userland (hardware/nvidia.nix).
# No dev stack: GPU boxes are compute-first; fork and layer loaded.nix (or
# your own module) if you want the tooling. Caveat when layering loaded:
# its rootless Docker exports DOCKER_HOST to the per-user socket, which
# shadows the rootful GPU daemon `--gpus all` relies on — disable
# virtualisation.docker.rootless (or at least setSocketVariable) in your
# module.
{ config, lib, ... }:
{
  imports = [
    ./base.nix
    ../hardware/nvidia.nix
  ];

  # Normal priority (100) overrides base's mkDefault (1000). Driver version
  # is derived from the actual pin in hardware/nvidia.nix so the banner
  # can't drift when the dc branch attr moves on a nixpkgs bump.
  machine0.motd.text = import ../../lib/mkMotd.nix {
    title = "[ m0 ] NixOS 25.11 · GPU";
    body = [
      "# NVIDIA dc driver ${config.hardware.nvidia.package.version} · CUDA via containers (--gpus all)"
      "$ nvidia-smi"
      ""
      "Built with the #gpu profile, fork to customize:"
      "-> https://github.com/fdmtl/machine0-nixos"
    ];
  };

  # Auto-upgrade tracks the gpu profile, not the default. Normal priority
  # overrides core/nix.nix's mkDefault. (Same pattern as openclaw/hermes.)
  system.autoUpgrade.flake = "github:fdmtl/machine0-nixos#gpu";

  # core/nix.nix tunes the nix daemon for 1 GB VMs (max-jobs = 1, cores =
  # 1). GPU droplets start at 8 vCPU / 64 GB — let provisions and nightly
  # upgrades use the hardware.
  nix.settings.max-jobs = lib.mkForce "auto";
  nix.settings.cores = lib.mkForce 0;

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
