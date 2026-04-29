# Playwright MCP — nix-managed Chromium for NixOS with declarative Claude Code registration.
#
# Provides playwright-driver.browsers from unstable (NixOS-patched Chromium),
# sets env vars so Playwright finds the nix-managed browser, and upserts the
# MCP server definition into ~/.claude/settings.json on every rebuild.
#
# Key flags:
#   --executable-path  Points directly at the nix store chromium binary.
#                      The MCP's --browser flag only accepts chrome/firefox/
#                      webkit/msedge (not "chromium"), so --executable-path
#                      is the only reliable way to use nix-provided Chromium.
#   --no-sandbox       Required on NixOS where the kernel sandbox expectations
#                      differ from upstream Chrome's assumptions.
#   --user-agent       Real browser UA to avoid headless bot detection.
{
  pkgs,
  ...
}:
let
  playwrightBrowsers = pkgs.playwright-driver.browsers;
  chromiumBin = "${playwrightBrowsers}/chromium-1208/chrome-linux64/chrome";

  # JSON blob for the playwright MCP server entry in ~/.claude/settings.json.
  playwrightMcpConfig = builtins.toJSON {
    command = "npx";
    args = [
      "@playwright/mcp@0.0.71"
      "--headless"
      "--no-sandbox"
      "--executable-path"
      chromiumBin
      "--user-agent"
      "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
    ];
    env = {
      PLAYWRIGHT_BROWSERS_PATH = "${playwrightBrowsers}";
      PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
    };
  };
in
{
  environment.systemPackages = [ playwrightBrowsers ];

  home-manager.users.nix = { lib, ... }: {
    home.sessionVariables = {
      PLAYWRIGHT_BROWSERS_PATH = "${playwrightBrowsers}";
      PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
    };

    # Upsert the playwright MCP server into ~/.claude/settings.json on every
    # rebuild. Creates the file if missing; merges into existing settings if
    # present (preserving other MCP servers and user config).
    home.activation.claudePlaywrightMcp = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      settings="$HOME/.claude/settings.json"
      pw_config=${lib.escapeShellArg playwrightMcpConfig}
      mkdir -p "$HOME/.claude"
      if [ -f "$settings" ] && ${pkgs.jq}/bin/jq empty "$settings" 2>/dev/null; then
        ${pkgs.jq}/bin/jq --argjson pw "$pw_config" '.mcpServers.playwright = $pw' \
          "$settings" > "$settings.tmp" && mv "$settings.tmp" "$settings"
      else
        ${pkgs.jq}/bin/jq -n --argjson pw "$pw_config" \
          '{"mcpServers":{"playwright":$pw}}' > "$settings"
      fi
    '';
  };
}
