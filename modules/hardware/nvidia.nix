# NVIDIA datacenter userland for machine0 GPU droplets. One module covers
# every SKU machine0 sells — H100/H200 (Hopper), RTX 4000/6000 Ada and L40S
# (Ada): the R570 datacenter driver's release notes list the H-Series,
# L-Series AND the RTX Ada workstation cards as supported products
# (docs.nvidia.com/datacenter/tesla/tesla-release-notes-570-172-08).
#
# Driver is pinned to dc_570 (570.172.08) instead of following
# `nvidiaPackages.dc`, so a nixpkgs bump can't silently move every GPU
# image to a new driver branch.
#
# Boot ordering:
#
#   systemd-modules-load  (nvidia.ko; softdep pulls nvidia-uvm after udev)
#        |
#        +- nvidia-persistenced                 keeps the GPU initialized
#        |                                      on a headless box
#        +- nvidia-fabricmanager -- ExecCondition: NVSwitch present?
#        |      1x VM   -> skipped (exit 1: unit inactive, not failed)
#        |      8x box  -> runs (NVLink fabric requires it)
#        |
#        +- nvidia-container-toolkit-cdi-generator
#               |  writes the CDI spec into /var/run/cdi/
#               v
#           docker  (rootful; features.cdi=true so `--gpus all` resolves
#                    through CDI)
#
# fabricmanager must NOT run unconditionally: it errors on anything that
# isn't an NVSwitch system (i.e. everything but 8x H100/H200 boxes). The
# nixpkgs datacenter module enables the unit with no off switch, so we gate
# it with an ExecCondition that runs after the driver module has settled —
# a bare ConditionPathExistsGlob could race device creation.
#
# This image is gpuOnly on the machine0 platform: on non-GPU hardware the
# explicit module load fails and the boot comes up degraded-but-SSHable.
# That path is out of contract and deliberately not defended against.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  toolkitTools = lib.getOutput "tools" config.hardware.nvidia-container-toolkit.package;
in
{
  # NVIDIA userland/kernel modules are unfree, and the datacenter (Tesla)
  # driver additionally requires explicit license acceptance. Base doesn't
  # set either; setting them here also keeps runtime `nixos-rebuild` evals
  # working.
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.nvidia.acceptLicense = true;

  hardware.nvidia = {
    datacenter.enable = true;
    package = config.boot.kernelPackages.nvidiaPackages.dc_570;
    nvidiaPersistenced = true;
  };

  # The datacenter path only installs nvidia.ko (udev modalias autoload).
  # Load it explicitly so the fabricmanager gate below can never run before
  # the module is in.
  boot.kernelModules = [ "nvidia" ];

  # Gate fabricmanager on NVSwitch hardware. /proc/driver/nvidia-nvswitch/
  # devices is populated synchronously at module init iff NVSwitch exists.
  # The unit environment carries no useful PATH, so no external commands
  # besides full-path modprobe (idempotent — covers ordering drift).
  systemd.services.nvidia-fabricmanager = {
    after = [ "systemd-modules-load.service" ];
    serviceConfig.ExecCondition = pkgs.writeShellScript "nvswitch-present" ''
      ${pkgs.kmod}/bin/modprobe nvidia 2>/dev/null || exit 1
      set -- /proc/driver/nvidia-nvswitch/devices/*
      [ -e "$1" ]
    '';
  };

  # GPU containers: generates CDI specs at boot and turns on docker's cdi
  # feature (docker >= 25), which is what `--gpus all` resolves through.
  hardware.nvidia-container-toolkit.enable = true;

  # Rootful docker — unlike loaded's rootless daemon — because it is the
  # reliable path for `--gpus all`. The nix user drives it sudo-free via
  # group membership (extraGroups lists merge with core/users.nix's wheel).
  virtualisation.docker.enable = true;
  users.users.nix.extraGroups = [ "docker" ];

  # `docker run --gpus all` needs three more pieces on docker 28 +
  # toolkit 1.18 (each verified on real GPU hardware; CDI alone only
  # covers `--device nvidia.com/gpu=all`):
  #  1. nvidia-container-runtime-hook on dockerd's PATH — moby registers
  #     its "nvidia" GPU device driver only if it finds the hook at
  #     daemon start (moby daemon/devices_nvidia_linux.go init()).
  #  2. the nvidia runtime as docker's default runtime — the hook itself
  #     refuses non-legacy modes ("use the NVIDIA Container Runtime"), so
  #     device injection must happen in the runtime, which also strips
  #     the hook from the container spec.
  #  3. mode = "cdi" so the runtime injects from the generated CDI spec
  #     instead of the legacy nvidia-container-cli stack (deprecated on
  #     NixOS and not on the daemon PATH).
  systemd.services.docker.path = [ toolkitTools ];
  virtualisation.docker.daemon.settings = {
    default-runtime = "nvidia";
    runtimes.nvidia.path = "${toolkitTools}/bin/nvidia-container-runtime";
  };
  environment.etc."nvidia-container-runtime/config.toml".text = ''
    [nvidia-container-runtime]
    mode = "cdi"
  '';
}
