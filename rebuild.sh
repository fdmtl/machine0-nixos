#!/usr/bin/env bash
set -e

if [ ! -f /etc/NIXOS ]; then
  echo "Error: this script must be run on NixOS" >&2
  exit 1
fi

if [ -z "$1" ]; then
  echo "Usage: $0 <profile>" >&2
  echo "Example: $0 loaded" >&2
  exit 1
fi

cd "$(dirname "$0")"

sudo nixos-rebuild switch --flake ".#$1"
