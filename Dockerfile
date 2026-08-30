FROM ubuntu:24.04

# Prevent interactive prompts from APT
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

# ============================================================
# Base system: sudo + non-root user
# ============================================================

RUN apt-get update -y && apt-get install -y sudo && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash devbox \
 && echo "devbox ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# ============================================================
# Mocks for WSL/systemd-specific commands
#
# Placed in /usr/local/bin/ so they are found by both the user
# and sudo (sudo's secure_path includes /usr/local/bin).
# The install script runs unmodified; mocks intercept only
# what doesn't apply inside a container.
# ============================================================


# pidof: pretend systemd is PID 1 so verify_systemd() continues
RUN printf '#!/bin/bash\n[[ "$1" == "systemd" ]] && echo 1 && exit 0\nexit 1\n' \
    > /usr/local/bin/pidof && chmod +x /usr/local/bin/pidof

# systemctl: no-op
RUN printf '#!/bin/bash\nexit 0\n' \
    > /usr/local/bin/systemctl && chmod +x /usr/local/bin/systemctl

# loginctl: no-op (enable-linger in configure_orca)
RUN printf '#!/bin/bash\nexit 0\n' \
    > /usr/local/bin/loginctl && chmod +x /usr/local/bin/loginctl

# tailscale: returns a fake IP for 'tailscale ip -4'
RUN printf '#!/bin/bash\ncase "$1" in\n  status) exit 0 ;;\n  ip)     echo "100.64.0.1" ;;\n  up)     exit 0 ;;\n  *)      exit 0 ;;\nesac\n' \
    > /usr/local/bin/tailscale && chmod +x /usr/local/bin/tailscale

# tailscaled: no-op daemon
RUN printf '#!/bin/bash\nexit 0\n' \
    > /usr/local/bin/tailscaled && chmod +x /usr/local/bin/tailscaled

# docker: mock so install_docker() idempotency check passes (avoids Docker-in-Docker)
RUN printf '#!/bin/bash\necho "Docker version 99.0.0-mock"\nexit 0\n' \
    > /usr/local/bin/docker && chmod +x /usr/local/bin/docker

# xvfb-run: pass-through (no display in CI)
RUN printf '#!/bin/bash\nshift\nexec "$@"\n' \
    > /usr/local/bin/xvfb-run && chmod +x /usr/local/bin/xvfb-run

# Orca AppImage mock: pre-create so the idempotency check ([[ -x ...]]) passes
# and configure_orca() has a valid binary to point the service unit at
RUN mkdir -p /opt/orca \
 && printf '#!/bin/bash\necho "Orca mock: $*"\nexit 0\n' > /opt/orca/orca.AppImage \
 && chmod +x /opt/orca/orca.AppImage

# ============================================================
# Copy install script
# ============================================================

COPY install.sh /home/devbox/install.sh
RUN chown devbox:devbox /home/devbox/install.sh && chmod +x /home/devbox/install.sh

# ============================================================
# Run as non-root (the script rejects root)
# ============================================================

USER devbox
WORKDIR /home/devbox

# /usr/local/bin is already in PATH for both user and sudo — no changes needed

# TS_AUTHKEY skips the browser login prompt in install_tailscale()
ENV TS_AUTHKEY="tskey-auth-mock-for-ci-only"

# Run the installer. Git name/email are piped via stdin to answer
# the configure_git() prompts (git itself is installed by the script).
# Pre-create ~/.gitconfig so configure_git() sees it already set and skips
# the interactive read prompts. Git doesn't need to be installed to write this file.
RUN printf '[user]\n\tname = Test User\n\temail = test@devbox.local\n' \
 > /home/devbox/.gitconfig

# Run the installer (no stdin pipe needed — git config is already in place)
RUN bash /home/devbox/install.sh

# ============================================================
# Smoke-test: verify the tools that matter
# ============================================================

RUN bash -c ' \
    export PATH="$HOME/.local/share/fnm:$PATH"; \
    eval "$(fnm env --shell bash)"; \
    set -e; \
    echo "--- Smoke test ---"; \
    git   --version; \
    node  --version; \
    npm   --version; \
    pnpm  --version; \
    gh    --version; \
    op    --version; \
    jq    --version; \
    fzf   --version; \
    tmux  -V; \
    echo "--- All checks passed ---"; \
'
