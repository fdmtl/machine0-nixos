# Nix — daemon caps, store substituters, GC + optimise, automatic security
# updates from the upstream flake, and zramSwap so eval doesn't OOM on 1 GB
# VMs.
{ lib, ... }:
{
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    # Small VMs: one job, one core. Avoids OOM during builds.
    max-jobs = 1;
    cores = 1;
    substituters = [
      "https://cache.nixos.org"
      "https://machine0.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "machine0.cachix.org-1:l34M6e3/+rNZJqlpANywfgeOhBBW6r0eo0VSVIh0PIk="
    ];
  };

  nix.nixPath = [
    "nixos-config=/etc/nixos/configuration.nix"
    "nixpkgs=flake:nixpkgs"
  ];

  # Daemon memory caps stop builds from OOMing the host on small VMs.
  systemd.services.nix-daemon.serviceConfig = {
    MemoryMax = "75%";
    MemoryHigh = "65%";
  };

  # Compressed-RAM swap so nixos-rebuild eval (runs in user nix client,
  # not the daemon) doesn't get killed by the kernel OOM-killer.
  zramSwap.enable = true;

  # Automatic security updates. Pinned-by-default to the upstream flake;
  # forks override via lib.mkForce.
  system.autoUpgrade = {
    enable = true;
    flake = lib.mkDefault "github:fdmtl/machine0-nixos";
    flags = [
      "--refresh"
      "--no-write-lock-file"
    ];
    dates = "04:00";
    randomizedDelaySec = "45min";
    allowReboot = true;
    rebootWindow = {
      lower = "04:00";
      upper = "06:00";
    };
  };

  # Keep the store from filling the disk over many auto-upgrades.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  nix.optimise.automatic = true;
}
