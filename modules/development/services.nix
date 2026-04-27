# Development services — rootless Docker, npm with a user-writable global
# prefix, and the firewall ports / sysctl needed for an HTTP/HTTPS workload
# VM.
{ pkgs, ... }:
{
  # Rootless Docker: daemon runs as the `nix` user, not root.
  # `setSocketVariable = true` exports DOCKER_HOST so the docker CLI talks
  # to the per-user socket without sudo or docker-group membership.
  virtualisation.docker.rootless = {
    enable = true;
    setSocketVariable = true;
  };

  # Point npm's global prefix at the user's home so `npm install -g` works
  # without trying to write into the read-only nodejs store path. The
  # default npmrc shipped by this module already sets prefix = ${HOME}/.npm.
  programs.npm = {
    enable = true;
    package = pkgs.nodejs_22;
  };

  environment.sessionVariables = {
    PATH = [ "$HOME/.npm/bin" ];
  };

  # HTTP/HTTPS in addition to the SSH port from core/networking.nix.
  # NixOS list-types merge by concatenation, no mkForce needed.
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  # Let rootless Docker (and any other unprivileged process) bind 80/443
  # directly. Without this, rootlesskit refuses with EACCES on ports < 1024.
  boot.kernel.sysctl."net.ipv4.ip_unprivileged_port_start" = 80;
}
