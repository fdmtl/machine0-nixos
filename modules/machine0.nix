# machine0 platform integration — declares the machine0.* options and the
# three metadata-driven systemd services that turn a generic NixOS boot
# into a machine0 VM:
#
#   machine0-metadata     — fetches /run/do-metadata/v1.json from the
#                           hypervisor link-local endpoint.
#   machine0-set-hostname — extracts the hostname from user-data.
#   machine0-ssh-keys     — installs SSH keys before sshd starts.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (lib) mkOption optional types;
  metadataFile = "/run/do-metadata/v1.json";
in
{
  options.machine0.profile.loaded = mkOption {
    type = types.bool;
    default = false;
    description = "Whether the loaded machine0 profile (dev stack) is active.";
  };

  config = {
    # Fetch the instance metadata blob from the hypervisor.
    systemd.services.machine0-metadata = {
      path = [ pkgs.curl ];
      description = "Fetch instance metadata from the metadata service";
      script = ''
        set -eu
        ATTEMPTS=0
        while ! curl -fsSL -o $RUNTIME_DIRECTORY/v1.json http://169.254.169.254/metadata/v1.json; do
          ATTEMPTS=$((ATTEMPTS + 1))
          if (( ATTEMPTS >= 10 )); then
            echo "giving up"
            exit 1
          fi
          echo "metadata unavailable, trying again in 1s..."
          sleep 1
        done
        chmod 600 $RUNTIME_DIRECTORY/v1.json
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        RuntimeDirectory = "do-metadata";
        RuntimeDirectoryPreserve = "yes";
      };
      unitConfig = {
        ConditionPathExists = "!${metadataFile}";
        After = [
          "network-pre.target"
        ]
        ++ optional config.networking.dhcpcd.enable "dhcpcd.service"
        ++ optional config.systemd.network.enable "systemd-networkd.service";
      };
    };

    # Set hostname from user-data: { networking.hostName = "name"; }
    systemd.services.machine0-set-hostname = {
      description = "Set hostname from user-data";
      wantedBy = [ "network.target" ];
      path = [
        pkgs.jq
        pkgs.inetutils
      ];
      script = ''
        set -e
        HOSTNAME=$(jq -er '.user_data | capture("hostName *= *\"(?<h>[^\"]+)\"") | .h' ${metadataFile}) || exit 0
        hostname "$HOSTNAME"
        if [[ ! -e /etc/hostname || -w /etc/hostname ]]; then
          printf "%s\n" "$HOSTNAME" > /etc/hostname
        fi
      '';
      serviceConfig.Type = "oneshot";
      unitConfig = {
        Before = [ "network.target" ];
        After = [ "machine0-metadata.service" ];
        Requires = [ "machine0-metadata.service" ];
      };
    };

    # Read public_keys[] from metadata and write them to the nix user's
    # authorized_keys *before* sshd starts, so there's no window where SSH
    # is up but keys aren't in place.
    systemd.services.machine0-ssh-keys = {
      description = "Set SSH keys for nix user from instance metadata";
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.jq ];
      script = ''
        set -e
        NIX_SSH="/home/nix/.ssh"
        mkdir -p "$NIX_SSH"
        jq -er '.public_keys[]' ${metadataFile} > "$NIX_SSH/authorized_keys"
        chown -R nix:users "$NIX_SSH"
        chmod 700 "$NIX_SSH"
        chmod 600 "$NIX_SSH/authorized_keys"
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      unitConfig = {
        ConditionPathExists = "!/home/nix/.ssh/authorized_keys";
        Before = optional config.services.openssh.enable "sshd.service";
        After = [ "machine0-metadata.service" ];
        Requires = [ "machine0-metadata.service" ];
      };
    };
  };
}
