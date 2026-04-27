# Networking — firewall (SSH only by default) and a metadata-driven hostname.
#
# Hostname is left empty here so the machine0-set-hostname systemd service
# can populate it at first boot from the instance metadata (user-data).
# The loaded profile extends `allowedTCPPorts` with 80/443; NixOS list-types
# merge by concatenation, so no mkForce/mkMerge is needed.
{ lib, ... }:
{
  networking.hostName = lib.mkDefault "";

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };
}
