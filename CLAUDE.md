# machine0-nixos

NixOS images for machine0 VMs. Four profiles: base, loaded, openclaw, hermes.

## Codebase layout

```
flake.nix                         # Defines profiles as module lists, exposes packages + nixosConfigurations
manifest.json                     # Maps profile name → machine0 image slug (used by build scripts)
lib/
  mksystem.nix                    # nixpkgs.lib.nixosSystem wrapper (injects inputs, stateVersion, overlays)
  mkimage.nix                     # Appends image.nix to produce .qcow2.gz
  mkMotd.nix                      # ANSI-styled SSH banner builder
  overlays.nix                    # Pins claude-code, codex, playwright-driver from nixpkgs-unstable
modules/
  profiles/
    base.nix                      # Minimal: boot, networking, ssh, fail2ban, users, system, motd
    loaded.nix                    # base + dev stack (packages, services, home-manager/zsh)
    openclaw.nix                  # loaded + playwright-mcp + openclaw CLI
    hermes.nix                    # loaded + playwright-mcp + hermes CLI + nixosModule
  core/                           # System-level modules shared by all profiles
    boot.nix networking.nix nix.nix ssh.nix fail2ban.nix system.nix users.nix
  development/
    packages.nix                  # Build tools, runtimes, AI agents (loaded+)
    services.nix                  # Rootless Docker, npm, nginx, firewall 80/443, sysctl (loaded+)
    playwright-mcp.nix            # Playwright browsers (openclaw/hermes only)
  home/
    default.nix                   # Home Manager setup
    nix-user.nix                  # zsh, starship, zoxide, eza, fzf, screen, agent shims
  machine0.nix                    # Metadata service, hostname, SSH key install (systemd oneshots)
  motd.nix                        # machine0.motd.text option
  image.nix                       # qcow2 image builder (appended by mkimage.nix, not used at runtime)
```

## Profile inheritance

```
base → loaded → openclaw
                 hermes
```

- **base**: core/* modules, basic CLI packages (vim, git, curl, htop, wget, tmux, jq). Bash shell.
- **loaded**: base + development/packages.nix + development/services.nix + home/. Zsh shell. Rootless Docker, npm, nginx, firewall 80/443.
- **openclaw**: loaded + playwright-mcp + openclaw CLI from nix-openclaw flake input.
- **hermes**: loaded + playwright-mcp + hermes CLI + nixosModule from hermes-agent flake input.

## Where to make changes

- **Add a system package**: `modules/development/packages.nix` (loaded+) or `modules/profiles/base.nix` (all profiles).
- **Add/change a systemd service**: `modules/development/services.nix` (loaded+) or create a new module and import it from the relevant profile.
- **Add a firewall port**: `modules/development/services.nix` has `networking.firewall.allowedTCPPorts` (loaded+ already opens 80, 443). `modules/core/networking.nix` has port 22 for all profiles.
- **Change shell config**: `modules/home/nix-user.nix` (Home Manager, loaded+).
- **Change boot/disk/grub**: `modules/core/boot.nix`.
- **Profile-specific changes**: edit the profile file directly (`modules/profiles/<name>.nix`) or create a new module file and import it from the profile.

## Provisioning workflow

When the user asks to modify a profile and test it on a VM, follow this procedure.

### 1. Make the code change

Edit the appropriate module file(s). Read the file first before editing. Do not over-engineer — keep changes minimal.

### 2. Determine the target VM

**User names a VM** (e.g. "provision the `foo` vm"):
```bash
machine0 get <name> --json
```
- If it exists and `"distribution": "nixos"` → use it. Note the profile from context or ask the user.
- If it exists but is not NixOS → tell the user it's not a NixOS VM.
- If it doesn't exist → create it:
  ```bash
  machine0 new <name> --image <image-slug> --size large
  ```
  Use `manifest.json` to map profile → image slug:
  - base → `nixos-25-11`
  - loaded → `nixos-25-11-loaded`
  - openclaw → `nixos-25-11-openclaw`
  - hermes → `nixos-25-11-hermes`

**User doesn't name a VM** (e.g. "add nginx to the loaded profile"):
- Create a temporary VM for test provisioning:
  ```bash
  machine0 new test-<profile>-tmp --image <image-slug> --size large
  ```
- After successful verification, tear it down:
  ```bash
  machine0 rm test-<profile>-tmp -y
  ```

### 3. Provision

```bash
machine0 provision <vm> ".#<profile>"
```

The flake reference is always `.#<profile>` where profile is one of: `base`, `loaded`, `openclaw`, `hermes`. This syncs the local flake to the VM and runs `nixos-rebuild switch`. Use a 10-minute timeout — builds can be slow.

### 4. Verify

SSH into the VM and verify the change works:
```bash
machine0 ssh <vm> "<verification command>"
```

For services: check they're running (`systemctl status <service>`), check ports respond (`curl -s http://localhost`), etc.

### 5. Clean up (temporary VMs only)

If you created a temporary VM in step 2, destroy it after verification:
```bash
machine0 rm test-<profile>-tmp -y
```

## machine0 CLI reference

```
machine0 new <vm> --image <image> [--size large]    # Create VM (sizes: small/medium/large/xl/xxl)
machine0 get <vm> --json                             # VM details (check .distribution, .image, .status)
machine0 rm <vm> -y                                  # Destroy VM (skip confirmation)
machine0 provision <vm> ".#<profile>"                # NixOS provision (syncs flake, runs nixos-rebuild)
machine0 ssh <vm> "<command>"                        # Run command on VM
machine0 ls                                          # List all VMs
machine0 images ls                                   # List available images
```

## Skill routing

When the user's request matches an available skill, invoke it via the Skill tool. When in doubt, invoke the skill.

Key routing rules:
- Product ideas/brainstorming → invoke /office-hours
- Strategy/scope → invoke /plan-ceo-review
- Architecture → invoke /plan-eng-review
- Design system/plan review → invoke /design-consultation or /plan-design-review
- Full review pipeline → invoke /autoplan
- Bugs/errors → invoke /investigate
- QA/testing site behavior → invoke /qa or /qa-only
- Code review/diff check → invoke /review
- Visual polish → invoke /design-review
- Ship/deploy/PR → invoke /ship or /land-and-deploy
- Save progress → invoke /context-save
- Resume context → invoke /context-restore
