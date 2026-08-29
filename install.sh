#!/usr/bin/env bash
# ============================================================
# DevBox Bootstrap
# Ubuntu / WSL2
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/anthuanvasquez/devbox/main/install.sh | bash
#
# Or:
#   ./install.sh
#
# Create TS_AUTHKEY environment variable before running
# the script to avoid tailscale browser login.
# ============================================================

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly NODE_MAJOR="22"

ORCA_DIR="/opt/orca"
ORCA_BIN="${ORCA_DIR}/orca.AppImage"
ORCA_PORT="6768"
STATE_DIR="${HOME}/.local/state/wsl-devbox-bootstrap"

mkdir -p "${STATE_DIR}"

# ------------------------------------------------------------
# Colors / output
# ------------------------------------------------------------

info() { printf '\n\033[1;34m[INFO]\033[0m %s\n' "$1"; }
success() { printf '\033[1;32m[OK]\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$1"; }
error() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$1" >&2; }
die() { error "$1"; exit 1; }

# ------------------------------------------------------------
# Error handling
# ------------------------------------------------------------

trap 'error "Installation failed at line $LINENO."' ERR

# ------------------------------------------------------------
# Requirements
# ------------------------------------------------------------

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

if [[ "${EUID}" -eq 0 ]]; then
    die "Do not run this script as root."
fi

require_command sudo

# ------------------------------------------------------------
# OS detection
# ------------------------------------------------------------

if [[ ! -f /etc/os-release ]]; then
    die "Cannot determine operating system."
fi

source /etc/os-release

if [[ "${ID}" != "ubuntu" ]]; then
    die "This bootstrap currently supports Ubuntu only."
fi

info "Detected Ubuntu ${VERSION_ID}"

# ------------------------------------------------------------
# WSL detection
# ------------------------------------------------------------

if grep -qi microsoft /proc/version 2>/dev/null; then
    success "Running inside WSL"
else
    warn "WSL was not detected. Continuing anyway."
fi

# Systemd detection

verify_systemd() {
    info "Verifying systemd..."

    if ! pidof systemd >/dev/null 2>&1; then
        warn "systemd is not active yet."
        if ! grep -q "^systemd=true" /etc/wsl.conf 2>/dev/null; then
            info "Configuring /etc/wsl.conf to enable systemd"
            sudo tee -a /etc/wsl.conf >/dev/null <<'EOF'

[boot]
systemd=true
EOF
        fi
        cat <<'EOF'

>>> MANUAL ACTION REQUIRED <<
I have configured systemd in /etc/wsl.conf, but WSL needs to be restarted
for it to take effect. From PowerShell (in Windows, not here):

    wsl --shutdown

Then reopen Ubuntu and run this script again:

    curl -fsSL <raw-url>/install.sh | bash

EOF
        exit 0
    fi

    info "systemd active. Continuing."
}

# ------------------------------------------------------------
# APT
# ------------------------------------------------------------

install_apt_packages() {
    info "Updating APT repositories..."

    sudo apt-get update -y

    info "Installing base development packages..."

    sudo apt-get install -y \
        ca-certificates \
        curl \
        wget \
        gnupg \
        lsb-release \
        apt-transport-https \
        software-properties-common \
        build-essential \
        python3 \
        make \
        g++ \
        libfuse2 \
        xvfb \
        git \
        unzip \
        zip \
        jq \
        ripgrep \
        fd-find \
        fzf \
        tmux \
        tree \
        shellcheck \
        htop \
        openssh-server
}

# ------------------------------------------------------------
# Git configuration
# Change the git user and email in the top.
# ------------------------------------------------------------

configure_git() {
    info "Configuring Git..."

    if git config --global user.name >/dev/null 2>&1 && git config --global user.email >/dev/null 2>&1; then
        warn "Git user name and email are already set. Skipping configuration."
        return
    fi

    read -rp "Enter your Git user name: " GIT_USER_NAME
    read -rp "Enter your Git user email: " GIT_USER_EMAIL

    git config --global init.defaultBranch main
    git config --global pull.rebase false
    git config --global fetch.prune true
    git config --global rerere.enabled true
    git config --global user.name "$GIT_USER_NAME"
    git config --global user.email "$GIT_USER_EMAIL"

    success "Git configured"
}

# ------------------------------------------------------------
# SSH
# ------------------------------------------------------------

configure_ssh() {
    log "Configuring OpenSSH server..."

    sudo systemctl enable --now ssh

    cat <<EOF

>>> MANUAL ACTION REQUIRED: copy your SSH public key (from your Mac) to this devbox:
    ssh-copy-id -i ~/.ssh/id_rsa.pub $(whoami)@${TS_IP:-<ip-tailscale>}
    (or manually paste the content into ~/.ssh/authorized_keys here)
EOF
}

# ------------------------------------------------------------
# Docker
# ------------------------------------------------------------

install_docker() {
    if command -v docker >/dev/null 2>&1; then
        success "Docker already installed"
        return
    fi

    info "Installing Docker Engine..."

    sudo install -m 0755 -d /etc/apt/keyrings

    sudo curl -fsSL \
        https://download.docker.com/linux/ubuntu/gpg \
        -o /etc/apt/keyrings/docker.asc

    sudo chmod a+r /etc/apt/keyrings/docker.asc

    cat <<EOF | sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME:-${VERSION_CODENAME}}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

    sudo apt-get update -y

    sudo apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    sudo usermod -aG docker "${USER}"

    success "Docker installed"
}

#------------------------------------------------------------
# Tailscale
#------------------------------------------------------------

install_tailscale() {
    if ! command -v tailscale >/dev/null 2>&1; then
        log "Installing Tailscale..."
        curl -fsSL https://tailscale.com/install.sh | sh
    else
        log "Tailscale is already installed."
    fi

    sudo systemctl enable --now tailscaled

    if ! tailscale status >/dev/null 2>&1; then
        log "Starting Tailscale login (check the link below)..."

        # If you define TS_AUTHKEY as an environment variable before running the script,
        # automatic auth without a browser is used:
        if [[ -n "${TS_AUTHKEY:-}" ]]; then
            sudo tailscale up --authkey="${TS_AUTHKEY}" --accept-dns=true --ssh
        else
            sudo tailscale up --accept-dns=true --ssh
            cat <<'EOF'

>>> MANUAL ACTION REQUIRED: if a login URL appeared above, open it in
    any browser (Windows, Mac, or mobile) and authorize this node. <

EOF
        fi
    fi

    TS_IP="$(tailscale ip -4 2>/dev/null | head -n1 || true)"
    [[ -n "${TS_IP}" ]] || warn "Could not read the Tailscale IP yet; run 'tailscale ip -4' manually later."
}

#------------------------------------------------------------
# Orca
#------------------------------------------------------------

install_orca() {
    log "Installing Orca..."

    LATEST_URL="$(curl -fsSL https://api.github.com/repos/stablyai/orca/releases/latest \
    | jq -r '.assets[] | select(.name | test("AppImage$")) | .browser_download_url' \
    | head -n1)"

    [[ -n "${LATEST_URL}" ]] || die "Could not resolve the URL of the latest Orca AppImage. Check https://github.com/stablyai/orca/releases manually."

    sudo mkdir -p "${ORCA_DIR}"
    sudo curl -fsSL "${LATEST_URL}" -o "${ORCA_BIN}"
    sudo chmod +x "${ORCA_BIN}"

    log "Orca downloaded to ${ORCA_BIN}"
}

# ------------------------------------------------------------
# Configure Orca as a systemd --user service
# ------------------------------------------------------------

configure_orca() {
    log "Configuring systemd --user service: orca-serve.service"

    mkdir -p "${HOME}/.config/systemd/user"

    cat > "${HOME}/.config/systemd/user/orca-serve.service" <<EOF
[Unit]
Description=Orca headless server (WSL devbox)
After=network-online.target tailscaled.service
Wants=network-online.target

[Service]
Environment=LIBGL_ALWAYS_SOFTWARE=1
ExecStart=/usr/bin/xvfb-run --auto-servernum ${ORCA_BIN} serve --port ${ORCA_PORT} --pairing-address ${TS_IP:-127.0.0.1}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

    # 'linger' allows --user services to keep running without an active session
    sudo loginctl enable-linger "$(whoami)"

    systemctl --user daemon-reload
    systemctl --user enable --now orca-serve.service
}

#------------------------------------------------------------
# 1Password CLI
#------------------------------------------------------------

install_1password() {
    if command -v op >/dev/null 2>&1; then
        success "1Password CLI already installed"
        return
    fi

    info "Installing 1Password CLI..."

    curl -sS https://downloads.1password.com/linux/keys/1password.asc | sudo gpg --dearmor -o /usr/share/keyrings/1password-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/1password.list

    sudo apt-get update -y
    sudo apt-get install -y 1password-cli

    success "1Password CLI installed"
}

# ------------------------------------------------------------
# FNM + Node.js
# ------------------------------------------------------------

install_fnm() {
    if command -v fnm >/dev/null 2>&1; then
        success "FNM already installed"
    else
        info "Installing FNM..."

        curl -fsSL https://fnm.vercel.app/install | bash

        # Load FNM for the current shell
        export PATH="${HOME}/.local/share/fnm:${PATH}"

        if [[ -f "${HOME}/.bashrc" ]]; then
            # FNM installer normally adds this itself.
            # Make sure it exists.
            if ! grep -q 'fnm env' "${HOME}/.bashrc"; then
                cat >> "${HOME}/.bashrc" <<'EOF'

# FNM
export PATH="$HOME/.local/share/fnm:$PATH"
eval "$(fnm env --use-on-cd --shell bash)"
EOF
            fi
        fi
    fi

    # Reload shell configuration
    export PATH="${HOME}/.local/share/fnm:${PATH}"

    if command -v fnm >/dev/null 2>&1; then
        success "FNM $(fnm --version)"
    else
        die "FNM installation failed"
    fi
}

# ------------------------------------------------------------
# Node.js
# ------------------------------------------------------------

install_node() {
    info "Installing Node.js..."

    export PATH="${HOME}/.local/share/fnm:${PATH}"

    if ! command -v fnm >/dev/null 2>&1; then
        die "FNM is not installed"
    fi

    # Install latest LTS
    fnm install --lts

    # Make LTS the default
    fnm default lts-latest

    # Use LTS in the current shell
    fnm use lts-latest

    success "Node.js $(node --version)"
}

# ------------------------------------------------------------
# PNPM
# ------------------------------------------------------------

install_pnpm() {
    info "Configuring pnpm via Corepack..."

    if ! command -v corepack >/dev/null 2>&1; then
        die "Corepack is not available in the current Node.js installation."
    fi

    corepack enable

    # Prepare the latest pnpm release.
    corepack install --global pnpm@latest

    if command -v pnpm >/dev/null 2>&1; then
        success "pnpm $(pnpm --version)"
    else
        die "pnpm installation failed"
    fi
}

# ------------------------------------------------------------
# GitHub CLI
# ------------------------------------------------------------

install_gh() {
    if command -v gh >/dev/null 2>&1; then
        success "GitHub CLI already installed"
        return
    fi

    info "Installing GitHub CLI..."

    sudo mkdir -p -m 755 /etc/apt/keyrings

    curl -fsSL \
        https://cli.github.com/packages/githubcli-archive-keyring.gpg |
        sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null

    sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg

    sudo mkdir -p -m 755 /etc/apt/sources.list.d

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" |
        sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null

    sudo apt-get update

    sudo apt-get install -y gh

    success "GitHub CLI $(gh --version | head -n 1)"
}

# ------------------------------------------------------------
# GitHub Copilot CLI
# ------------------------------------------------------------

install_copilot() {
    if command -v copilot >/dev/null 2>&1; then
        success "GitHub Copilot CLI already installed"
        return
    fi

    info "Installing GitHub Copilot CLI..."

    curl -fsSL https://gh.io/copilot-install | bash

    success "GitHub Copilot CLI installed"
}

# ------------------------------------------------------------
# Antigravity CLI
# ------------------------------------------------------------

install_antigravity() {
    if command -v antigravity >/dev/null 2>&1; then
        success "Antigravity CLI already installed"
        return
    fi

    info "Installing Antigravity CLI..."

    curl -fsSL https://antigravity.google/cli/install.sh | bash

    success "Antigravity CLI installed"
}

# ------------------------------------------------------------
# Shell utilities
# ------------------------------------------------------------

configure_shell_tools() {
    info "Configuring shell tools..."

    local shell_rc="${HOME}/.bashrc"

    touch "${shell_rc}"

    # pnpm
    if ! grep -q 'PNPM_HOME' "${shell_rc}"; then
        cat >> "${shell_rc}" <<'EOF'

# pnpm
export PNPM_HOME="$HOME/.local/share/pnpm"
export PATH="$PNPM_HOME:$PATH"
EOF
    fi

    # fzf
    if ! grep -q 'fzf.bash' "${shell_rc}"; then
        cat >> "${shell_rc}" <<'EOF'

# fzf
if [[ -f /usr/share/doc/fzf/examples/key-bindings.bash ]]; then
    source /usr/share/doc/fzf/examples/key-bindings.bash
fi

if [[ -f /usr/share/doc/fzf/examples/completion.bash ]]; then
    source /usr/share/doc/fzf/examples/completion.bash
fi
EOF
    fi

    success "Shell configured"
}

# ------------------------------------------------------------
# DevBox directories
# ------------------------------------------------------------

create_directories() {
    info "Creating DevBox directories..."

    mkdir -p \
        "${HOME}/workspace" \
        "${HOME}/workspace/developer" \
        "${HOME}/workspace/work" \
        "${HOME}/workspace/playground" \
        "${HOME}/.config"

    success "Workspace created at ${HOME}/workspace"
}

# ------------------------------------------------------------
# Verification
# ------------------------------------------------------------

verify_installation() {
    info "Verifying installation..."

    local commands=(
        git
        node
        npm
        pnpm
        docker
        gh
        copilot
        agy
        jq
        rg
        fzf
        tmux
        op
    )

    local failed=0

    for command in "${commands[@]}"; do
        if command -v "${command}" >/dev/null 2>&1; then
            printf '  %-12s %s\n' "${command}" "$(command -v "${command}")"
        else
            printf '  %-12s MISSING\n' "${command}"
            failed=1
        fi
    done

    if [[ "${failed}" -eq 1 ]]; then
        warn "Some commands are not available in the current shell."
        warn "Restart WSL and run the verification again."
    else
        success "All core tools are available"
    fi

    # clean up apt cache
    sudo apt-get clean
    sudo apt-get autoremove -y
}

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

print_summary() {
    cat <<'EOF'

============================================================
 DevBox installation complete
============================================================

IP of Tailscale on this WSL: ${TS_IP:-<pending, run 'tailscale ip -4'>}
Port of Orca               : ${ORCA_PORT}
Service                    : systemctl --user status orca-serve.service
Logs                       : journalctl --user -u orca-serve.service -f

>>> MANUAL STEPS PENDING <
 1. In Orca (Mac and mobile): Settings → Remote Orca Servers → Add Server,
    using the Tailscale IP above and the port ${ORCA_PORT}.
    (The first time, check the service log to copy the URL/code
    printed by orca serve.)
 2. Login your CLI agents inside the devbox (this is per agent and cannot
    be automated without exposing credentials):
       claude   (login to Claude Code)
       codex    (login to Codex)
       etc.
 3. Confirm SSH access from the Mac:
       ssh $(whoami)@${TS_IP:-<ip-tailscale>}

Workspace:

    ~/workspace
    ├── developer   - for your personal projects
    ├── work        - for your work projects
    └── playground  - for experiments and learning

Installed:

    Git
    GitHub CLI
    GitHub Copilot CLI
    Antigravity CLI
    FNM (Fast Node Manager)
    Node.js
    PNPM
    Orca
    Tailscale
    Docker Engine
    Docker Compose
    1Password CLI

Next steps:

    1. Restart WSL
    2. Authenticate GitHub:

       gh auth login

    4. Verify Docker:

       docker run hello-world

    5. Clone your projects into:

       ~/workspace

============================================================

EOF
}

# ------------------------------------------------------------
# Main
# ------------------------------------------------------------

main() {
    info "Starting DevBox bootstrap..."

    verify_systemd
    install_apt_packages
    configure_git
    configure_ssh
    install_docker
    install_tailscale
    install_orca
    configure_orca
    install_1password
    install_fnm
    install_node
    install_pnpm
    install_gh
    install_copilot
    install_antigravity
    configure_shell_tools
    create_directories
    verify_installation
    print_summary

    success "DevBox bootstrap finished."
}

main "$@"
