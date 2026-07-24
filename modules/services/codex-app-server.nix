# Always-on Codex app-server, toggled via machine0.codexAppServer.enable.
#
# Requires a profile that provides `pkgs.codex` (loaded, openclaw, hermes —
# anything importing development/packages.nix; base does not). Also
# requires the VM to have been created with a machine0 profile that has a
# connected "codex" integration (`machine0 new <vm> --profile <p>`), so
# machine0-profile-inject (../machine0.nix) lands ~/.codex/auth.json before
# this service starts — this unit declares that dependency explicitly.
#
# Transport: `--listen ws://127.0.0.1:<port>`, not `unix://`. `unix://` is
# advertised (and `codex app-server proxy --sock <path>` is the CLI's own
# documented way to attach over it for "SSH-driven use") but verified
# live not to work in this build (0.144.4): a plain client connecting to
# the unix socket gets no response and an immediate clean close, with
# nothing logged anywhere, and `codex app-server proxy` against that same
# socket produces zero output and exits 0 with no error either. `ws://`
# was verified end-to-end (full JSON-RPC handshake, authenticated turn,
# real assistant reply), so that's what's shipped — reach it with an SSH
# tunnel (`ssh -L <port>:localhost:<port>`), never exposed on the network.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkEnableOption mkOption mkIf types;
  cfg = config.machine0.codexAppServer;
in
{
  options.machine0.codexAppServer = {
    enable = mkEnableOption "an always-on Codex app-server (loopback websocket, systemd-supervised)";

    port = mkOption {
      type = types.port;
      default = 41455;
      description = ''
        Loopback port for the app-server's websocket listener. Bound to
        127.0.0.1 only, never exposed on the network — reach it with an SSH
        tunnel (`ssh -L <port>:localhost:<port> nix@<vm-ip>`).
      '';
    };

    user = mkOption {
      type = types.str;
      default = "nix";
      description = "User to run the app-server as. Must own ~/.codex/auth.json.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.codex ];

    # Foreground `codex app-server` under systemd's own supervision
    # (Type=simple + Restart=on-failure) rather than the CLI's own
    # `daemon`/`bootstrap` self-management, which forks into the
    # background and expects to own its own persistence — that fights
    # systemd's supervision instead of using it.
    systemd.services.codex-app-server = {
      description = "Codex app-server (always on, loopback websocket)";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "machine0-profile-inject.service"
      ];
      requires = [ "machine0-profile-inject.service" ];
      wants = [ "network-online.target" ];
      environment.HOME = "/home/${cfg.user}";
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = "users";
        WorkingDirectory = "/home/${cfg.user}";
        ExecStart = "${pkgs.codex}/bin/codex app-server --listen ws://127.0.0.1:${toString cfg.port}";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
  };
}
