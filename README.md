# DevBox — WSL2 Multi-Agents | Orca + Tailscale

Bootstrap script to configure an Ubuntu/WSL2 machine ready for remote development across multiple projects and AI agents, using **Orca** as the workspace environment and **Tailscale** for secure remote access.

## Prerequisites

- Windows with WSL2 + Ubuntu installed
- Internet connectivity within WSL

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/anthuanvasquez/devbox/main/install.sh | bash
```

Or clone the repository and run it locally:

```bash
./install.sh
```

### Headless Tailscale (Recommended)

Provide a Tailscale auth key beforehand to skip interactive browser login:

```bash
export TS_AUTHKEY="tskey-auth-..."
./install.sh
```

> **Do not run the script as root.** Run as your regular user; the script invokes `sudo` whenever elevated privileges are required.

## What It Installs

| Tool | Description |
|---|---|
| **[Git](https://git-scm.com/)** | Version control |
| **[Docker Engine + Compose](https://www.docker.com/)** | Container runtime and orchestration |
| **[Tailscale](https://tailscale.com/)** | Mesh VPN for secure remote access |
| **[Orca](https://www.onorca.dev/)** | AI agent workspace environment (headless via `.deb` package) |
| **[GitHub CLI](https://cli.github.com/) (`gh`)** | GitHub management (issues, PRs, repos) |
| **[GitHub Copilot CLI](https://github.com/features/copilot/cli) (`copilot`)** | Terminal AI agent |
| **[Antigravity CLI](https://antigravity.google/docs/cli/overview/) (`agy`)** | Antigravity CLI |
| **[FNM](https://github.com/schniz/fnm)** | Fast Node Manager |
| **[Node.js LTS](https://nodejs.org/en)** | JavaScript runtime |
| **[PNPM](https://pnpm.io/)** | Package manager (via Corepack) |
| **[1Password CLI](https://www.1password.dev/cli) (`op`)** | Secrets management |
| **[fzf](https://junegunn.github.io/fzf/), [ripgrep](https://github.com/burntsushi/ripgrep), [fd](https://github.com/sharkdp/fd), [tmux](https://github.com/tmux/tmux), [jq](https://jqlang.org/)** | Essential shell utilities |
| **[OpenSSH server](https://www.openssh.org/)** | Remote SSH access |

## How Remote Access Works

```
Mac / Mobile
    │
    │  Tailscale VPN
    ▼
WSL2 Ubuntu (Tailscale IP)
    ├── Orca (port 6768)   ← access from the Orca app on Mac/mobile
    └── SSH (port 22)      ← access using any SSH client or editor
```

1. The script installs and links Tailscale — giving your WSL machine a persistent private IP on your Tailscale tailnet.
2. Orca runs as a user systemd service (`orca-serve.service`) listening on port `6768`.
3. From the Orca app on your Mac or mobile device: **Settings → Remote Orca Servers → Add Server**.

## Post-Installation Manual Steps

The script cannot automate these steps because they require interactive credentials:

### 1. Copy your SSH public key (from your Mac)

```bash
ssh-copy-id -i ~/.ssh/id_rsa.pub <username>@<tailscale-ip>
```

### 2. Authenticate CLI tools

```bash
gh auth login          # GitHub CLI
copilot auth           # GitHub Copilot CLI
op signin              # 1Password CLI
agy auth               # Antigravity CLI
```

### 3. Verify Orca is running

```bash
systemctl --user status orca-serve.service
journalctl --user -u orca-serve.service -f
```

### 4. Verify Docker

```bash
docker run hello-world
```

## Workspace Structure

```
~/workspace
├── developer   — personal projects
├── work        — work / team projects
└── playground  — experiments and learning
```

## Useful Commands

```bash
# View Tailscale IP
tailscale ip -4

# Orca service status
systemctl --user status orca-serve.service

# Real-time Orca logs
journalctl --user -u orca-serve.service -f

# Restart Orca
systemctl --user restart orca-serve.service

# Update Orca to the latest release
./update-orca.sh

# SSH into devbox from Mac
ssh <username>@<tailscale-ip>
```

## Re-running the Script

The bootstrap script is idempotent — it detects existing tools and skips them. You can safely re-run it if a network issue interrupts the initial setup.

> **Note on updating Orca:** Re-running `install.sh` will skip Orca because it is already installed. Use `./update-orca.sh` to update Orca to the latest release without disrupting other services.

## Notes

- Requires **systemd enabled in WSL**. If not active, the script configures `/etc/wsl.conf` and prompts you to restart WSL (`wsl --shutdown` from PowerShell).
- Orca runs headless with `xvfb-run` to ensure a virtual display is available without a physical GUI.
- The Orca service is configured with `loginctl enable-linger` so that user background services keep running when you disconnect.

## Docker-based Testing

The included `Dockerfile` allows testing the bootstrap logic inside an Ubuntu container without affecting any live machines.

### What it tests

Runs the complete script with mocks for WSL/systemd-specific parts that do not apply in Docker:

| Mocked | Real |
|---|---|
| `systemctl` / `systemd` | APT packages |
| `tailscale` / `tailscaled` | FNM + Node.js LTS + pnpm |
| Docker (avoids Docker-in-Docker) | GitHub CLI (`gh`) |
| Orca .deb (avoids ~150MB download) | 1Password CLI (`op`) |
| `xvfb-run` | GitHub Copilot CLI |
| `loginctl` | Antigravity CLI (`agy`) |

At the end of the build, it runs a smoke test validating: `git`, `node`, `npm`, `pnpm`, `gh`, `op`, `jq`, `fzf`, `tmux`.

### Run the test

```bash
docker build -t devbox-test .
```

The build will fail if any installation step or the smoke test fails (`set -e` is active throughout).

### Cleanup

```bash
docker rmi devbox-test
```

## License
MIT License © 2026 Anthuan Vásquez. See [LICENSE](LICENSE) for details.
