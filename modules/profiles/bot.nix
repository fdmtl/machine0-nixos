# Bot profile — loaded + Claude Code autostarted in a detached screen
# session at boot. Attach with `screen -x claude` (advertised in MOTD).
{ pkgs, lib, ... }:
let
  # Submitted on the very first start, so the thread is already running
  # when you attach. Fork to customize.
  initialPrompt = ''
    You are the resident agent on a fresh machine0 bot VM (NixOS). Look
    around: check the hardware (CPU, RAM, disk), the installed tooling,
    and confirm docker works. Write a short MACHINE.md in the current
    directory summarising what this box can do, then wait for further
    instructions.
  '';

  # Claude stores conversations per-cwd under ~/.claude/projects/<escaped
  # cwd>. Presence of a session file is what distinguishes "resume the
  # thread" from "first real start".
  sessionDir = "/home/nix/.claude/projects/-home-nix-workspace";

  # Store-path launcher — a root-managed boot service must not exec the
  # user-writable ~/.local/bin/claude shim (user-level compromise would
  # become persistent, and `nix` has passwordless sudo). Mirrors the
  # shim's env bridging (see home/nix-user.nix).
  #
  # Restart flow: a conversation exists → --continue resumes it; none
  # exists → submit the initial prompt. If the first boot was
  # unauthenticated and the prompt never ran, no session file is written,
  # so the next start retries the initial prompt — the two branches
  # converge on a resumable thread.
  claudeLauncher = pkgs.writeShellScript "claude-screen-launcher" ''
    export SHELL="${pkgs.bashInteractive}/bin/bash"
    export PATH="${pkgs.bashInteractive}/bin:${pkgs.coreutils}/bin:$PATH"
    if [ -n "$(ls ${sessionDir}/*.jsonl 2>/dev/null)" ]; then
      exec "${pkgs.claude-code}/bin/claude" --continue
    fi
    exec "${pkgs.claude-code}/bin/claude" ${lib.escapeShellArg initialPrompt}
  '';
in
{
  imports = [ ./loaded.nix ];

  # Rootless Docker lives in the nix user's systemd manager; linger starts
  # it at boot so claude can use docker before anyone has logged in.
  users.users.nix.linger = true;

  # Created before services start — systemd applies WorkingDirectory
  # before ExecStartPre, so the service itself can't mkdir it.
  systemd.tmpfiles.rules = [ "d /home/nix/workspace 0755 nix users -" ];

  systemd.services.claude-screen = {
    description = "Claude Code in a detached screen session";
    wantedBy = [ "multi-user.target" ];
    # Claude shows connection errors until the network is up.
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    # Don't restart on nixos-rebuild switch — a restart kills the live
    # screen session (and any in-flight claude work). New unit config and
    # a newer claude binary apply on the next natural respawn or reboot.
    restartIfChanged = false;
    # Full system PATH so claude's subshells see all tools.
    path = [
      pkgs.screen
      "/run/current-system/sw"
    ];
    environment = {
      HOME = "/home/nix";
      # ~/.screenrc has `shell -$SHELL` (claude itself gets SHELL from
      # the launcher, which overrides this).
      SHELL = "${pkgs.bashInteractive}/bin/bash";
      # The rootless docker socket lives in the nix user's runtime dir
      # (uid 1000); a system service gets no XDG_RUNTIME_DIR or
      # sessionVariables, so point the docker CLI at it explicitly.
      DOCKER_HOST = "unix:///run/user/1000/docker.sock";
    };
    serviceConfig = {
      User = "nix";
      Group = "users";
      # A dedicated workdir keeps ~/.ssh and a stray ~/CLAUDE.md out of
      # the agent's project scope.
      WorkingDirectory = "/home/nix/workspace";
      # Clear stale sockets from unclean shutdowns — a dead <pid>.claude
      # socket makes the advertised attach command ambiguous. `-` because
      # -wipe exits non-zero when there is nothing to wipe.
      ExecStartPre = "-${pkgs.screen}/bin/screen -wipe";
      # -D: don't fork (systemd tracks screen); -m: force new session.
      ExecStart = "${pkgs.screen}/bin/screen -DmS claude ${claudeLauncher}";
      # Respawn if claude exits — the MOTD promises an attachable session.
      # Back off 5s → 5min so a broken claude doesn't spin the journal.
      # Stop manually: systemctl stop claude-screen.
      Restart = "always";
      RestartSec = 5;
      RestartSteps = 5;
      RestartMaxDelaySec = "5min";
      # Keep a runaway claude from starving nginx/docker (same idea as
      # the nix-daemon caps in core/nix.nix).
      MemoryHigh = "65%";
      MemoryMax = "75%";
    };
  };

  # mkForce (50) overrides loaded.nix's normal priority (100).
  machine0.motd.text = lib.mkForce (
    import ../../lib/mkMotd.nix {
      title = "[ m0 ] NixOS 25.11 · Bot 🤖";
      body = [
        "# Claude is running in a screen session. Attach with:"
        "$ screen -x claude"
        ""
        "# Detach again with Ctrl-a d"
        ""
        "Built with the #bot profile, fork to customize:"
        "-> https://github.com/fdmtl/machine0-nixos"
      ];
    }
  );

  # Kernel auto-reboot would kill the claude session; switch-level
  # security upgrades still run nightly.
  system.autoUpgrade.allowReboot = lib.mkForce false;

  # Auto-upgrade tracks the bot profile, not the default (loaded).
  system.autoUpgrade.flake = "github:fdmtl/machine0-nixos#bot";
}
