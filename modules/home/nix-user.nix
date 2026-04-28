# Home Manager configuration for the `nix` user.
#
# Replaces the old `system.activationScripts.nixUserConfig` block and the
# `files/{init.zsh,starship.toml,screenrc}` raw dotfiles with declarative
# Home Manager program modules. HM regenerates the dotfiles atomically on
# every `nixos-rebuild switch`, so wrong-ownership / drift bugs from the
# old `install`-based activation script can't recur.
{ pkgs, ... }:
{
  home.username = "nix";
  home.homeDirectory = "/home/nix";
  home.stateVersion = "25.11";

  # ── Shell ──────────────────────────────────────────────────────────────
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    history = {
      size = 10000;
      save = 10000;
      append = true;
      share = true;
      ignoreDups = true;
      ignoreSpace = true;
    };

    shellAliases = {
      # General
      json = "python -m json.tool";
      l = "eza -l --icons";
      ll = "ls -lGh";
      reload = "source ~/.zshrc";
      myip = ''curl http://jsonip.com/ | cut -d\" -f4'';
      key = "cat ~/.ssh/id_rsa.pub";
      webserver = "python3 -m http.server";
      docker-ps = ''docker ps -a --format "table {{.ID}}\t{{.Status}}\t{{.Names}}"'';
      gen-passwd = ''openssl rand -base64 12 | tr -d "/+=" | head -c 16 && echo'';
      decompress = "tar -xzf";

      # git
      gpl = "git pull";
      gpu = "git push";
      gs = "git status";
      ga = "git add";
      gb = "git switch -c";
      gco = "git checkout";
      gm = "git checkout main";

      # MCP
      mcp-inspector = "npx @modelcontextprotocol/inspector";
    };

    initContent = ''
      # Terminal
      export TERM=xterm-256color

      # Word navigation (Ctrl+Left/Right)
      bindkey '^[[1;5D' backward-word
      bindkey '^[[1;5C' forward-word

      # History search with Up/Down (matches prefix of current input)
      bindkey '^[[A' history-search-backward
      bindkey '^[[B' history-search-forward

      # Right arrow accepts autosuggestion (must come after the plugin loads)
      bindkey '^[[C' autosuggest-accept

      # Functions
      killport() { lsof -ti tcp:$1 | xargs kill; }
      listport() { lsof -i :$1; }
      compress() { tar -czf "''${1%/}.tar.gz" "''${1%/}"; }
      gc() { git commit -a -m "$1"; }
      spc() { for _ in {1..30}; do echo; done; }

      # Use ls completion for the `l` alias.
      compdef l=ls 2>/dev/null
    '';
  };

  # ── Prompt ─────────────────────────────────────────────────────────────
  # Translated 1:1 from the old files/starship.toml. HM renders this
  # attrset to TOML at ~/.config/starship.toml and starship picks it up
  # automatically (no STARSHIP_CONFIG override needed).
  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      command_timeout = 200;
      format = "\\[ $username$hostname \\] $directory$character";

      username = {
        show_always = true;
        format = "[$user@](green)";
      };
      hostname = {
        ssh_only = false;
        format = "[$hostname](green)";
      };
      character = {
        error_symbol = "[\\$]()";
        success_symbol = "[\\$]()";
      };
      directory = {
        truncation_length = 0;
        truncate_to_repo = false;
        format = "[$path](magenta) ";
      };
    };
  };

  # ── Shell tools ────────────────────────────────────────────────────────
  # Replaces `cd='z'`. With --cmd cd, zoxide rebinds cd to z directly.
  programs.zoxide = {
    enable = true;
    options = [
      "--cmd"
      "cd"
    ];
  };

  programs.eza.enable = true;
  programs.fzf.enable = true;

  # ── Agent daemon shims ──────────────────────────────────────────────────
  # Agent daemons (openclaw, hermes) generate systemd user services with a
  # hardcoded PATH that omits /run/current-system/sw/bin. These symlinks
  # bridge the gap via ~/.local/bin which IS in their PATH.
  home.file.".local/bin/claude" = {
    executable = true;
    text = ''
      #!/bin/sh
      export SHELL="${pkgs.bash}/bin/bash"
      export PATH="${pkgs.bash}/bin:$PATH"
      exec "${pkgs.claude-code}/bin/claude" "$@"
    '';
  };
  home.file.".local/bin/codex".source = "${pkgs.codex}/bin/codex";
  home.file.".local/bin/lsof".source = "${pkgs.lsof}/bin/lsof";
  home.file.".local/bin/bash".source = "${pkgs.bash}/bin/bash";
  home.file.".local/bin/sh".source = "${pkgs.bash}/bin/sh";

  # ── screen(1) ──────────────────────────────────────────────────────────
  # Home Manager 25.11 doesn't have a `programs.screen` module, so we drop
  # the file in directly. The screen binary itself is installed system-wide
  # by `environment.systemPackages` (see development/packages.nix).
  home.file.".screenrc".text = ''
    startup_message off

    # If we accidentally hangup, don't be all attached when we come back.
    autodetach on

    # More scrollback!
    defscrollback 10000

    # Disable use of the "alternate" terminal — keeps scrollbars working
    # in many terminal emulators.
    termcapinfo xterm* ti@:te@

    # Have screen update terminal emulators' titlebars.
    termcapinfo xterm* 'hs:ts=\E]0;:fs=\007:ds=\E]0;\007'
    defhstatus "screen ^E (^Et) | $USER@^EH"

    shelltitle "$ |bash"

    hardstatus alwayslastline
    hardstatus string '%{= kG}[ %{G}%H %{g}][%= %{=kw}%?%-Lw%?%{r}(%{W}%n*%f%t%?(%u)%?%{r})%{w}%?%+Lw%?%?%= %{g}][%{B}%Y-%m-%d %{W}%c %{g}]'

    defflow off

    # rvm needs this
    shell -''${SHELL}
  '';
}
