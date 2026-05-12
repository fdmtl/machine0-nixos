# machine0-nixos

This repository contains the profiles that are used to build the [machine0](https://machine0.io) NixOS system images. This is a great place to start if you want to customize your NixOS VM.

### Usage
```bash
# install the machine0 CLI
curl -LsSf https://machine0.io/install.sh | sh

# create a NixOS VM
machine0 new nixos --image nixos-25-11-loaded --size medium

# clone the repo, customize and rebuild
git clone https://github.com/fdmtl/machine0-nixos.git && cd machine0-nixos
claude -p "make any change to the loaded profile you'd like"
machine0 provision nixos ./flake.nix#loaded

# or, rebuild from within the VM
machine0 ssh nixos
git clone https://github.com/fdmtl/machine0-nixos.git && cd machine0-nixos
./rebuild.sh
```
> **Note:** We strongly recommend `--size medium` or larger. Nix builds are CPU and memory intensive — small instances work but take forever.

### Profiles

| Image Name | Profile | Description |
|---|---|---|
| `nixos-25-11` | `#base` | Minimal NixOS installation |
| `nixos-25-11-loaded` | `#loaded` | Modern agents (Claude, Codex...) and dev tools (e.g. Docker, Node, Python...). |
| `nixos-25-11-openclaw` | `#openclaw` | Loaded + [OpenClaw](https://github.com/openclaw/nix-openclaw). |
| `nixos-25-11-hermes` | `#hermes` | Loaded + [Hermes Agent](https://github.com/NousResearch/hermes-agent). |

The (profile → image) mapping is canonical in [`manifest.json`](manifest.json) and consumed by the build/test scripts.
