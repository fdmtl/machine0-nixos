<h1 align="center">machine0-nixos</h1>
<p align="center">NixOS system configurations for <a href="https://machine0.io">machine0</a> cloud VMs</p>

## Overview

Declarative NixOS configurations purpose-built for AI coding agents. Two profiles ship as machine0 base images or can be applied to a running VM via `machine0 provision`.

Everything is a Nix flake. One evaluation produces an identical system whether you're building a fresh image or rebuilding on a live server.

## Why NixOS

- **Reproducible** — the flake lockfile pins every input. The same config produces the same system, every time, on every machine.
- **Atomic** — `nixos-rebuild switch` is all-or-nothing. A bad config rolls back; the running system is never half-configured.
- **Declarative** — packages, services, firewall, the user, and the user's dotfiles (via Home Manager) are all defined in Nix. No manual setup, no config drift.
- **Agent-friendly** — agents can provision a full dev environment with a single command. No shell scripts, no apt dependency chains, no version conflicts.

## Layout

Each module owns one concern, so finding (and changing) a setting is straightforward.

```
flake.nix                          # inputs (nixpkgs, nixpkgs-unstable, home-manager) + profiles
lib/
├── mksystem.nix                   # nixosSystem factory; injects specialArgs
├── mkimage.nix                    # qcow2 image builder factory
└── overlays.nix                   # unstable-nixpkgs overlay (eval-time + bake-time)
modules/
├── image.nix                      # gzipped qcow2 disk image
├── motd.nix                       # machine0.motd.text → users.motd (PAM-correct)
├── machine0.nix                   # metadata-driven systemd services + machine0 options
├── profiles/{base,loaded}.nix     # the two top-level profiles
├── core/                          # boot, networking, nix daemon, ssh, fail2ban, users, /etc/nixos
├── development/                   # build tools, AI agents, rootless docker, npm
└── home/                          # Home Manager hookup + per-user dotfiles
```

## Profiles

| machine0 Image | Profile | Description |
|---|---|---|
| `nixos-25-11` | `#base` | Minimal — virtio drivers, SSH hardening, metadata service, core utils. A clean slate for custom provisioning. |
| `nixos-25-11-loaded` | `#loaded` | Full dev stack — Node.js, Python, Rust, Go, Docker, Claude Code, [Codex CLI](https://github.com/openai/codex), zsh + starship, fail2ban. Ready to code. |

### What's in `#loaded`

| Category | Packages |
|---|---|
| Build tools | gcc, gnumake, cmake, pkg-config |
| Runtimes | nodejs 22, bun, python3, uv, rustc + cargo, go |
| CLI | ripgrep, fzf, jq, eza, zoxide, btop, screen |
| AI agents | claude-code, codex |
| Infra | docker, fail2ban, firewall (22/80/443) |

## Usage

### Provision a remote VM

```bash
git clone https://github.com/fdmtl/machine0-nixos.git
cd machine0-nixos
machine0 new my-vm --image nixos-25-11 --size medium
machine0 provision my-vm ./flake.nix#loaded
```

The CLI syncs the flake to the VM and runs `nixos-rebuild switch`.

> **Note:** We strongly recommend `--size medium` or larger. Nix builds are CPU- and memory-intensive — small instances work but take forever.

### Rebuild on the server

Clone this repo and apply a profile on any nixos machine:

```bash
machine0 new my-vm --image nixos-25-11 --size medium
machine0 ssh my-vm
git clone https://github.com/fdmtl/machine0-nixos.git
cd machine0-nixos
./rebuild.sh loaded
```

## Scripts

| Script | Description |
|---|---|
| `rebuild.sh <profile>` | Run `nixos-rebuild switch` with the given profile. Must be run on NixOS. |
| `make-image.sh <profile>` | Build a gzipped qcow2 disk image. Prints the store path on success. |
