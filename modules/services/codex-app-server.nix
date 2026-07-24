# Always-on Codex app-server, toggled via machine0.codexAppServer.enable.
#
# Requires a profile that provides `pkgs.codex` (loaded, openclaw, hermes —
# anything importing development/packages.nix; base does not). Also
# requires the VM to have been created with a machine0 profile that has a
# connected "codex" integration (`machine0 new <vm> --profile <p>`), so
# machine0-profile-inject (../machine0.nix) lands ~/.codex/auth.json before
# this service starts — this unit declares that dependency explicitly.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkEnableOption mkOption mkIf types;
  cfg = config.machine0.codexAppServer;
  runtimeDir = "codex-app-server";
in
{
  options.machine0.codexAppServer = {
    enable = mkEnableOption "an always-on Codex app-server (Unix control socket, systemd-supervised)";

    user = mkOption {
      type = types.str;
      default = "nix";
      description = "User to run the app-server as. Must own ~/.codex/auth.json.";
    };

    socketPath = mkOption {
      type = types.str;
      readOnly = true;
      default = "/run/${runtimeDir}/app-server.sock";
      description = "Unix control socket clients attach to via `codex app-server proxy --sock <path>`.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.codex ];

    # Foreground `codex app-server` under systemd's own supervision
    # (Type=simple + Restart=on-failure) rather than the CLI's own
    # `daemon`/`bootstrap` self-management, which forks into the
    # background and expects to own its own persistence — that fights
    # systemd's supervision instead of using it. Unix socket only, no
    # network exposure: clients SSH in and run
    # `codex app-server proxy --sock ${cfg.socketPath}` to attach, the
    # server keeps running independent of that connection — this is the
    # "SSH-driven use" mode `codex app-server daemon bootstrap` itself
    # describes, just supervised by systemd instead of the CLI's own
    # daemon-management.
    systemd.services.codex-app-server = {
      description = "Codex app-server (always on, Unix control socket)";
      wantedBy = [ "multi-user.target" ];
      after = [ "machine0-profile-inject.service" ];
      requires = [ "machine0-profile-inject.service" ];
      environment.HOME = "/home/${cfg.user}";
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = "users";
        WorkingDirectory = "/home/${cfg.user}";
        RuntimeDirectory = runtimeDir;
        RuntimeDirectoryMode = "0700";
        ExecStart = "${pkgs.codex}/bin/codex app-server --listen unix://${cfg.socketPath}";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
  };
}
