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

### Optional services

Toggleable via options on `base` and everything built on it (`loaded`/`openclaw`/`hermes`):

| Option | Description |
|---|---|
| `machine0.codexAppServer.enable` | Always-on Codex app-server (`modules/services/codex-app-server.nix`), systemd-supervised over a Unix control socket (`machine0.codexAppServer.socketPath`, default `/run/codex-app-server/app-server.sock`). Needs `pkgs.codex` (so a `loaded`-derived profile) and a VM created with a machine0 profile that has a connected `codex` integration (`machine0 new <vm> --profile <p>`) — see `machine0-profile-inject` below. SSH in and run `codex app-server proxy --sock <socketPath>` to attach a client. |

`machine0-profile-inject` (in `modules/machine0.nix`, always present) is what actually lands a profile's credentials — codex/github/claude-code OAuth, the machine0 MCP API key — onto the VM from the `--profile` flag; without it those credentials never materialize, regardless of which services are enabled.

### Use as a flake input (private profile)

You don't have to fork this repo to customize it. A separate (possibly private) flake can layer its own module on top of any profile — the exported `lib.mkSystem` / `lib.mkImage` builders come pre-wired with this repo's inputs (nixpkgs, home-manager, agent flakes), so your flake needs only one input:

```nix
{
  description = "private machine0 profile";
  inputs.machine0.url = "github:fdmtl/machine0-nixos";

  outputs = { self, machine0, ... }:
    let
      system = "x86_64-linux";
      modules = [
        machine0.nixosModules.loaded   # or base / openclaw / hermes
        ./profile.nix                  # private customizations
      ];
    in {
      nixosConfigurations.private = machine0.lib.mkSystem modules;
      packages.${system}.private = machine0.lib.mkImage modules;
    };
}
```

A minimal `profile.nix` showing the common override points:

```nix
{ pkgs, lib, ... }:
{
  # Extra packages, services, secrets wiring, etc.
  environment.systemPackages = [ pkgs.cowsay ];

  # MOTD override: the profiles set this at different priorities (loaded:
  # normal, openclaw/hermes: mkForce). mkOverride 10 beats all of them.
  machine0.motd.text = lib.mkOverride 10 "welcome to my private box";

  # Auto-upgrade defaults to pulling this public repo nightly, which would
  # revert a private profile. Pointing it at a private repo also needs
  # GitHub credentials on the VM (keep any token out of the Nix store).
  # Simplest: disable it and rely on `machine0 provision` instead. To keep
  # it and point at your own repo, set system.autoUpgrade.flake with
  # mkForce (openclaw/hermes pin it at normal priority).
  system.autoUpgrade.enable = lib.mkForce false;
}
```

Then provision as usual from your private repo — `machine0 provision <vm> ".#private"` syncs the local flake to the VM, so nothing needs to be published.

Notes:
- The exported `nixosModules` require `machine0.lib.mkSystem` — they read machine0-specific `specialArgs` (`nixpkgsUnstable`, `homeManager`, `inputs`) and will not evaluate under a plain `nixpkgs.lib.nixosSystem`.
- The styled banner builder used by the built-in profiles is exported as `machine0.lib.mkMotd` (`{ title, body ? [ ], width ? null } -> string`; body lines: `""` blank, `"$ cmd"` command, `"# text"` comment, `"-> url"` link, anything else plain). It is a plain function, not a module — to use it inside your `profile.nix`, pass it in from your flake: add `{ _module.args.machine0Lib = machine0.lib; }` to your module list and take `machine0Lib` as a module argument.
- Inside your `profile.nix`, the `inputs` module arg is *machine0's* inputs. To use your own flake's inputs, pass them under a different name: add `{ _module.args.privateInputs = inputs; }` to your module list.
- `mkSystem` is closed over *this* repo's locked inputs. Declaring your own `nixpkgs` input has no effect on it; to actually re-pin, use `inputs.machine0.inputs.nixpkgs.follows = "nixpkgs"` (not generally recommended — the agent inputs intentionally track their own nixpkgs, see `flake.nix`). To bump machine0 itself, run `nix flake update machine0`.
- `/etc/nixos` on the VM always contains the *upstream* machine0-nixos source (baked in for non-flake rebuilds). An in-VM `sudo nixos-rebuild switch` without your flake — like the nightly auto-upgrade — rebuilds the upstream profile and silently drops your private config. Rebuild by re-running `machine0 provision <vm> ".#private"` from your repo.
- `nix build .#private` produces a gzipped qcow2 image, same as the upstream profiles. Everything here is `x86_64-linux`; building the image (or the system) needs an x86_64-linux builder — evaluation works anywhere.
