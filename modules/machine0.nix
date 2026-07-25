# machine0 platform integration — declares the machine0.* options and the
# four metadata-driven systemd services that turn a generic NixOS boot
# into a machine0 VM:
#
#   machine0-metadata       — fetches /run/do-metadata/v1.json from the
#                             hypervisor link-local endpoint.
#   machine0-set-hostname   — extracts the hostname from user-data.
#   machine0-ssh-keys       — installs SSH keys before sshd starts.
#   machine0-profile-inject — extracts and runs the machine0 inject payload
#                             (profile credentials + env vars) from
#                             user-data, once per droplet.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (lib) mkOption optional types;
  metadataFile = "/run/do-metadata/v1.json";
  # Everything the machine0 inject payload and `machine0 profiles deploy`
  # script may call as root. Pinned on EVERY profile (base included) so
  # injection has full coverage regardless of what the profile ships in its
  # system path; /etc/machine0/tool-path exposes the same set to the
  # SSH-delivered deploy script.
  injectTools = with pkgs; [
    bash
    coreutils
    jq
    gnugrep
    gnused
    python3
    git
    util-linux
  ];
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

    # Pinned tool PATH for machine0 root scripts. The `machine0 profiles
    # deploy` script (delivered over SSH) prepends this to its PATH; the
    # inject unit below gets the same set via its `path`.
    environment.etc."machine0/tool-path".text = "${lib.makeBinPath injectTools}\n";

    # machine0-managed user env vars (profiles / env sets): the backend
    # reconciles a user-writable file; this hook sources it for login shells
    # (/etc/profile) and every zsh invocation (/etc/zshenv). Non-interactive
    # bash SSH commands read neither — that path is covered by
    # PermitUserEnvironment + ~/.ssh/environment (core/ssh.nix).
    environment.shellInit = ''
      if [ -r "$HOME/.machine0/env.sh" ]; then
        . "$HOME/.machine0/env.sh"
      fi
    '';

    # Extract and run the machine0 inject payload (profile credentials + env
    # vars) from user-data, once per INSTANCE (droplet id). BYTE-CONTRACT
    # with the backend generator (machine0 repo,
    # apps/api/src/providers/cloud-init.ts generateNixOSUserData): the marker
    # lines and the strip/decode pipeline below must match byte-for-byte —
    # the backend's cloud-init.test.ts replicates this pipeline verbatim.
    #
    # Not Before=sshd on purpose (Ubuntu runcmd parity — creds may land a few
    # seconds after SSH opens; the deploy script waits, users retry).
    #
    # Semantics:
    #  - Same droplet id as the last successful run → exit 0. Plain reboots
    #    and nightly autoUpgrade never re-apply the creation-time payload.
    #  - New droplet id (resume-from-suspend, machine created from a
    #    snapshot) → run with THIS droplet's fresh user-data. This is what
    #    lets a machine created via `machine0 new --image <snapshot>` get
    #    its OWN fresh credentials rather than inheriting whatever was
    #    baked into the snapshot at capture time (or perpetually skipping
    #    injection because a marker file survived into the snapshot).
    #  - The guard check MUST stay the first step: `machine0 profiles
    #    deploy` claims the instance-id after rewriting the machine, so a
    #    queued/failed first-boot inject can never later re-apply the stale
    #    creation payload over a deploy.
    #  - Writing the id even for an EMPTY payload is safe: user_data is
    #    immutable per droplet, so a payload change always arrives with a
    #    new droplet id.
    #  - A FAILED inject writes no id and retries on the next boot.
    systemd.services.machine0-profile-inject = {
      description = "Apply machine0 profile inject payload from user-data";
      wantedBy = [ "multi-user.target" ];
      path = injectTools;
      script = ''
        set -eu
        instance_id=$(jq -r '.droplet_id // empty' ${metadataFile})
        if [ -z "$instance_id" ]; then
          instance_id=$(jq -r '.user_data // ""' ${metadataFile} | sha256sum | cut -d" " -f1)
        fi
        if [ -f /var/lib/machine0/instance-id ] \
          && [ "$(cat /var/lib/machine0/instance-id)" = "$instance_id" ]; then
          exit 0
        fi
        umask 077
        jq -r '.user_data // ""' ${metadataFile} \
          | sed -n '/^# machine0-inject-begin$/,/^# machine0-inject-end$/p' \
          | sed -e '/^# machine0-inject-/d' -e 's/^# //' \
          | base64 -d > "$STATE_DIRECTORY/inject.sh"
        if [ -s "$STATE_DIRECTORY/inject.sh" ]; then
          bash "$STATE_DIRECTORY/inject.sh"
        fi
        rm -f "$STATE_DIRECTORY/inject.sh"
        printf '%s\n' "$instance_id" > /var/lib/machine0/instance-id
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StateDirectory = "machine0";
      };
      unitConfig = {
        After = [ "machine0-metadata.service" ];
        Requires = [ "machine0-metadata.service" ];
      };
    };
  };
}
