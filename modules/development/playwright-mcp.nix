# Playwright MCP — nix-managed browsers for NixOS + shell fixes for agent daemons.
#
# Provides playwright-driver.browsers from unstable (NixOS-patched Chromium)
# and fixes the missing SHELL/bash issue in agent daemon systemd services.
#
# After provisioning, run this once to register the MCP server:
#   claude mcp add --scope user \
#     -e PLAYWRIGHT_BROWSERS_PATH=$PLAYWRIGHT_BROWSERS_PATH \
#     -e PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
#     playwright -- npx @playwright/mcp@0.0.71 --headless
{ pkgs, ... }:
let
  playwrightBrowsers = pkgs.playwright-driver.browsers;
in
{
  environment.systemPackages = [ playwrightBrowsers ];

  home-manager.users.nix =
    { ... }:
    {
      home.sessionVariables = {
        PLAYWRIGHT_BROWSERS_PATH = "${playwrightBrowsers}";
        PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
      };
    };
}
