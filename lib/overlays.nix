# Single source of truth for the unstable-nixpkgs overlay. Two forms:
#
#   unstableModule  — a real overlay function used at flake-eval time.
#   unstableText    — the same overlay, hash-pinned, emitted as text into
#                     /etc/nixos/configuration.nix so a runtime rebuild on
#                     the live VM evaluates the *same* nixpkgs-unstable
#                     revision and can't be tricked by a substituted tree.
#
# Both forms must yield the same closure for the inherited attrs.
{ nixpkgsUnstable }:
{
  unstableModule =
    _final: prev:
    let
      unstable = import nixpkgsUnstable {
        inherit (prev.stdenv.hostPlatform) system;
        config.allowUnfree = true;
      };
    in
    {
      inherit (unstable) claude-code codex;
    };

  unstableText = ''
    nixpkgs.overlays = [
      (final: prev:
        let
          unstable = import (builtins.fetchTarball {
            url = "https://github.com/NixOS/nixpkgs/archive/${nixpkgsUnstable.rev}.tar.gz";
            sha256 = "${nixpkgsUnstable.narHash}";
          }) { inherit (prev.stdenv.hostPlatform) system; config.allowUnfree = true; };
        in {
          inherit (unstable) claude-code codex;
        })
    ];
    nixpkgs.config.allowUnfree = true;
  '';
}
