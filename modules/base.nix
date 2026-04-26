# machine0 base module — platform integration (virtio, metadata) plus base
# system config (nix user, SSH hardening, packages).
#
# This file is baked into the image as /etc/nixos/base.nix and imported by
# /etc/nixos/configuration.nix so that `nixos-rebuild switch` (e.g. from
# `machine0 provision`) re-applies it. The loaded profile layers dev tools
# on top.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  metadataFile = "/run/do-metadata/v1.json";
in
{
  options.machine0.profile.loaded = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Whether the loaded machine0 profile is active.";
  };

  config = {
    # ── Virtio kernel modules (from profiles/qemu-guest.nix) ──────────────
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

    # ── Boot / filesystem ─────────────────────────────────────────────────
    fileSystems."/" = lib.mkDefault {
      device = "/dev/disk/by-label/nixos";
      autoResize = true;
      fsType = "ext4";
    };

    boot.growPartition = true;
    boot.kernelParams = [
      "console=ttyS0"
      "panic=1"
      "boot.panic_on_fail"
    ];
    boot.kernelModules = [
      "virtio_pci"
      "virtio_net"
    ];
    boot.loader.grub.devices = [ "/dev/vda" ];

    # ── SSH hardening ─────────────────────────────────────────────────────
    # VMs expect connections as the `nix` user. Root SSH is closed.
    services.openssh = {
      enable = true;
      settings = {
        PermitRootLogin = lib.mkForce "no";
        PasswordAuthentication = lib.mkForce false;
        KbdInteractiveAuthentication = lib.mkForce false;
        X11Forwarding = lib.mkForce false;

        # Pin modern crypto only — no weak ciphers/KEX/MACs.
        Ciphers = [
          "chacha20-poly1305@openssh.com"
          "aes256-gcm@openssh.com"
          "aes128-gcm@openssh.com"
        ];
        KexAlgorithms = [
          "curve25519-sha256"
          "curve25519-sha256@libssh.org"
        ];
        Macs = [
          "hmac-sha2-512-etm@openssh.com"
          "hmac-sha2-256-etm@openssh.com"
        ];
        PubkeyAcceptedAlgorithms = "ssh-ed25519,rsa-sha2-512,rsa-sha2-256";

        # Online brute-force / DoS bounds.
        MaxAuthTries = 3;
        LoginGraceTime = 20;
        MaxStartups = "10:30:60";

        # Forwarding off — this is a workload VM, not a jump host.
        AllowAgentForwarding = "no";
        AllowTcpForwarding = "no";
        GatewayPorts = "no";

        # Only the provisioned user may log in.
        AllowUsers = [ "nix" ];
      };
    };

    # Prevent sshd from restarting during nixos-rebuild switch activation.
    # SSH config changes only take effect on next boot. This ensures the
    # SSH connection survives through remote provisioning.
    systemd.services.sshd.restartIfChanged = false;

    # ── User ──────────────────────────────────────────────────────────────
    users.users.nix = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      shell = pkgs.bashInteractive;
    };
    security.sudo.wheelNeedsPassword = false;

    # ── Metadata service ──────────────────────────────────────────────────
    # Fetches the instance metadata blob from the hypervisor link-local endpoint.
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
        After =
          [ "network-pre.target" ]
          ++ lib.optional config.networking.dhcpcd.enable "dhcpcd.service"
          ++ lib.optional config.systemd.network.enable "systemd-networkd.service";
      };
    };

    # ── Hostname from user-data ───────────────────────────────────────────
    # machine0 CLI sends: { networking.hostName = "name"; }
    systemd.services.machine0-set-hostname = {
      description = "Set hostname from user-data";
      wantedBy = [ "network.target" ];
      path = [ pkgs.jq pkgs.inetutils ];
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

    # ── SSH keys from metadata → nix user directly ───────────────────────
    # Reads public_keys from the metadata JSON and writes them straight to
    # the nix user's authorized_keys. Gates sshd startup so there's no
    # window where SSH is up but keys aren't in place.
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
        Before = lib.optional config.services.openssh.enable "sshd.service";
        After = [ "machine0-metadata.service" ];
        Requires = [ "machine0-metadata.service" ];
      };
    };

    # ── Packages ──────────────────────────────────────────────────────────
    environment.systemPackages = with pkgs; [
      vim
      git
      curl
      htop
      wget
      tmux
      jq
    ];

    nix.settings.experimental-features = [ "nix-command" "flakes" ];
    nix.nixPath = [ "nixos-config=/etc/nixos/configuration.nix" "nixpkgs=flake:nixpkgs" ];

    # Bake the active module set into /etc/nixos so a first-boot
    # `nixos-rebuild switch` can re-evaluate the same base profile.
    environment.etc."nixos/base.nix".source = ./base.nix;
    environment.etc."nixos/configuration.nix".text = lib.mkIf (!config.machine0.profile.loaded) ''
      { ... }:
      {
        imports = [
          /etc/nixos/base.nix
        ];
      }
    '';

    # Let the metadata service set hostname at runtime.
    networking.hostName = lib.mkDefault "";

    networking.firewall.allowedTCPPorts = [ 22 ];

    # ── Brute-force protection ────────────────────────────────────────────
    # Lives in base so #base images aren't deployed without it.
    services.fail2ban = {
      enable = true;
      maxretry = 3;
      bantime = "24h";
      bantime-increment = {
        enable = true;
        maxtime = "168h";
        factor = "4";
      };
      jails.sshd.settings = {
        enabled = true;
        port = "ssh";
        findtime = 300;
      };
    };

    # ── Automatic security updates ────────────────────────────────────────
    # Tracks the upstream flake; the lock file in that flake pins inputs.
    # mkDefault so forks / private deployments can override the source.
    system.autoUpgrade = {
      enable = true;
      flake = lib.mkDefault "github:fdmtl/machine0-nixos";
      flags = [ "--refresh" "--no-write-lock-file" ];
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
  };
}
