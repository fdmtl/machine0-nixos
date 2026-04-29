# MOTD — banner shown to users on login.
#
# Sets `users.motd`, the canonical NixOS option. It writes the banner to a
# store-path file passed directly to pam_motd, AND wires pam_motd into the
# sshd PAM session stack (gated on `users.motd != ""` in security/pam.nix).
# Setting `environment.etc."motd"` alone does NOT trigger that PAM line —
# which is why the previous implementation never showed up on SSH.
{ config, lib, ... }:
let
  inherit (lib) mkIf mkOption types;
  cfg = config.machine0.motd;
in
{
  options.machine0.motd.text = mkOption {
    type = types.str;
    default = "";
    description = "Banner shown to users on login (SSH + console). Empty = no banner.";
  };

  config = mkIf (cfg.text != "") {
    users.motd = cfg.text;
  };
}
