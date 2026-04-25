#!/usr/bin/env bash
set -euo pipefail

if [ ! -f /etc/NIXOS ]; then
  echo "Error: this script must be run on NixOS" >&2
  exit 1
fi

if [ -z "${1:-}" ]; then
  echo "Usage: $0 <profile>" >&2
  echo "Example: $0 loaded" >&2
  exit 1
fi

PROFILE="$1"

cd "$(dirname "$0")"

OUT=$(nix build ".#${PROFILE}" --no-link --print-out-paths --extra-experimental-features nix-command --extra-experimental-features flakes)
IMAGE=$(find "$OUT" -maxdepth 1 -name '*.qcow2.gz' -print -quit)

if [ -z "$IMAGE" ]; then
  echo "no qcow2.gz found in $OUT" >&2
  exit 1
fi

echo "$IMAGE"
