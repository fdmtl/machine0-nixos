# machine0 platform integration — declares the machine0.* options and the
# four metadata-driven systemd services that turn a generic NixOS boot
# into a machine0 VM:
#
#   machine0-metadata       — fetches /run/do-metadata/v1.json from the
#                             hypervisor link-local endpoint.
#   machine0-set-hostname   — extracts the hostname from user-data.
#   machine0-ssh-keys       — installs SSH keys before sshd starts.
#   machine0-profile-inject — decodes and runs the profile-injection
#                             script (codex/github/claude-code credentials,
#                             the machine0 MCP API key, ...) embedded in
#                             user-data by `machine0 new --profile` /
#                             `machine0 profiles deploy`.
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

    # `machine0 new --profile <p>` / `machine0 profiles deploy` embed a
    # base64-encoded shell script in user_data, delimited by
    # `# machine0-inject-begin` / `# machine0-inject-end` (each line
    # prefixed with "# " so it reads as a comment if user_data is ever
    # interpreted as the nix expression it starts as). Decoding and running
    # it is what actually lands profile credentials on the VM — without
    # this service, `--profile` has no effect on NixOS images. Any service
    # that depends on those credentials being present should declare
    # `after`/`requires` on this unit.
    #
    # Gated to run once ever (ConditionPathExists on the same
    # /etc/machine0/profile-injected marker the script itself writes at
    # the end of a successful run): verified live, re-running it is NOT
    # safe — it includes `git config --global credential.<url>.helper ''`
    # followed by `--add ... '!gh auth git-credential'`, and a second run
    # hits "cannot overwrite multiple values with a single value" because
    # the first run's `--add` already left two values behind. To force a
    # refresh after `machine0 profiles deploy`, remove the marker and
    # restart the unit: `rm /etc/machine0/profile-injected && systemctl
    # restart machine0-profile-inject`.
    systemd.services.machine0-profile-inject = {
      description = "Decode and run the machine0 profile-injection script embedded in instance user_data";
      wantedBy = [ "multi-user.target" ];
      path = [
        pkgs.jq
        pkgs.coreutils
        pkgs.gnused
        pkgs.bash
      ];
      script = ''
        set -eu
        UD=$(jq -r '.user_data' ${metadataFile})
        if echo "$UD" | grep -qx '# machine0-inject-begin'; then
          echo "$UD" \
            | sed -n '/^# machine0-inject-begin$/,/^# machine0-inject-end$/p' \
            | sed '1d;$d;s/^# //' \
            | tr -d '\n' \
            | base64 -d \
            | bash
        fi
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      unitConfig = {
        ConditionPathExists = "!/etc/machine0/profile-injected";
        After = [ "machine0-metadata.service" ];
        Requires = [ "machine0-metadata.service" ];
      };
    };
  };
}
