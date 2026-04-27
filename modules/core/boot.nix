# Boot — virtio guest drivers, ext4 root with auto-resize, GRUB on /dev/vda.
{ lib, ... }:
{
  boot.initrd.availableKernelModules = [
    "virtio_net"
    "virtio_pci"
    "virtio_mmio"
    "virtio_blk"
    "virtio_scsi"
    "9p"
    "9pnet_virtio"
  ];
  boot.initrd.kernelModules = [
    "virtio_balloon"
    "virtio_console"
    "virtio_rng"
    "virtio_gpu"
    "virtio_scsi"
  ];
  boot.kernelModules = [
    "virtio_pci"
    "virtio_net"
  ];
  boot.kernelParams = [
    "console=ttyS0"
    "panic=1"
    "boot.panic_on_fail"
  ];
  boot.loader.grub.devices = [ "/dev/vda" ];
  boot.growPartition = true;

  fileSystems."/" = lib.mkDefault {
    device = "/dev/disk/by-label/nixos";
    autoResize = true;
    fsType = "ext4";
  };
}
