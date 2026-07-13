# SSH — hardened sshd. Modern crypto, post-quantum hybrids, brute-force
# bounds, key auth only, AllowUsers = nix.
#
# `restartIfChanged = false` is critical: SSH config changes only take
# effect on next boot anyway, and restarting sshd during nixos-rebuild
# switch would break the active provisioning connection.
{ lib, ... }:
{
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
      # Post-quantum hybrids first to defeat "store now, decrypt later"
      # attacks; classical curve25519 retained as fallback.
      KexAlgorithms = [
        "mlkem768x25519-sha256"
        "sntrup761x25519-sha512@openssh.com"
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

      # machine0 profile/env injection writes ~/.ssh/environment (sshd's own
      # KEY=value format). This makes the vars reach EVERY ssh session
      # regardless of shell — including non-interactive `ssh vm cmd` under
      # bash, which reads no rc file (verified live: /etc/bashrc does not
      # source /etc/set-environment). Single-user workload VM with
      # passwordless sudo: the usual LD_PRELOAD escalation concern doesn't
      # apply — there is no privilege boundary to cross.
      PermitUserEnvironment = true;
    };
  };

  systemd.services.sshd.restartIfChanged = false;
}
