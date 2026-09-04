# DevBox — WSL2 Multi-Agents | Orca + Tailscale

Script de instalación para dejar una máquina Ubuntu/WSL2 lista para trabajar remotamente con múltiples proyectos y agentes de IA, usando **Orca** como entorno de trabajo y **Tailscale** para acceso remoto seguro.

## Requisitos previos

- Windows con WSL2 + Ubuntu instalado
- Acceso a internet desde dentro de WSL

## Uso rápido

```bash
curl -fsSL https://raw.githubusercontent.com/anthuanvasquez/devbox/main/install.sh | bash
```

O clona el repo y ejecútalo localmente:

```bash
./install.sh
```

### Tailscale sin browser (recomendado)

Si tienes un auth key de Tailscale, evitas la autenticación interactiva:

```bash
export TS_AUTHKEY="tskey-auth-..."
./install.sh
```

> **No ejecutes el script como root.** Usa tu usuario normal; el script usa `sudo` donde lo necesita.

## Qué instala

| Herramienta | Descripción |
|---|---|
| **[Git](https://git-scm.com/)** | Control de versiones |
| **[Docker Engine + Compose](https://www.docker.com/)** | Contenedores |
| **[Tailscale](https://tailscale.com/)** | VPN mesh para acceso remoto |
| **[Orca](https://www.onorca.dev/)** | Entorno de trabajo con agentes de IA (headless via AppImage) |
| **[GitHub CLI](https://cli.github.com/) (`gh`)** | Interacción con GitHub (issues, PRs, repos) |
| **[GitHub Copilot CLI](https://github.com/features/copilot/cli) (`copilot`)** | Agente de IA en la terminal |
| **[Antigravity CLI](https://antigravity.google/docs/cli/overview/) (`agy`)** | CLI de Antigravity |
| **[FNM](https://github.com/schniz/fnm)** | Fast Node Manager |
| **[Node.js LTS](https://nodejs.org/en)** | Runtime de JavaScript |
| **[PNPM](https://pnpm.io/)** | Package manager (vía Corepack) |
| **[1Password CLI](https://www.1password.dev/cli) (`op`)** | Gestión de secretos |
| **[fzf](https://junegunn.github.io/fzf/), [ripgrep](https://github.com/burntsushi/ripgrep), [fd](https://github.com/sharkdp/fd), [tmux](https://github.com/tmux/tmux), [jq](https://jqlang.org/)** | Utilidades de shell |
| **[OpenSSH server](https://www.openssh.org/)** | Acceso SSH remoto |

## Cómo funciona el acceso remoto

```
Mac / móvil
    │
    │  Tailscale VPN
    ▼
WSL2 Ubuntu (IP de Tailscale)
    ├── Orca (port 6768)   ← acceso desde la app Orca en Mac/móvil
    └── SSH (port 22)      ← acceso con cualquier cliente SSH o editor
```

1. El script instala y conecta Tailscale — tu WSL queda con una IP privada estable en tu red Tailscale
2. Orca corre como servicio systemd (`orca-serve.service`) escuchando en el puerto `6768`
3. Desde la app Orca en tu Mac o móvil: **Settings → Remote Orca Servers → Add Server**

## Pasos manuales post-instalación

El script no puede automatizar las siguientes acciones porque requieren credenciales:

### 1. Copiar tu clave SSH (desde tu Mac)

```bash
ssh-copy-id -i ~/.ssh/id_rsa.pub <usuario>@<tailscale-ip>
```

### 2. Autenticar las herramientas CLI

```bash
gh auth login          # GitHub CLI
copilot auth           # GitHub Copilot CLI
op signin              # 1Password CLI
agy auth               # Antigravity CLI
```

### 3. Verificar que Orca está corriendo

```bash
systemctl --user status orca-serve.service
journalctl --user -u orca-serve.service -f
```

### 4. Verificar Docker

```bash
docker run hello-world
```

## Estructura del workspace

```
~/workspace
├── developer   — proyectos personales
├── work        — proyectos de trabajo
└── playground  — experimentos y aprendizaje
```

## Comandos útiles

```bash
# Ver IP de Tailscale
tailscale ip -4

# Estado del servicio Orca
systemctl --user status orca-serve.service

# Logs de Orca en tiempo real
journalctl --user -u orca-serve.service -f

# Reiniciar Orca
systemctl --user restart orca-serve.service

# Conectarse por SSH desde Mac
ssh <usuario>@<tailscale-ip>
```

## Re-ejecutar el script

El script es idempotente — detecta lo que ya está instalado y lo omite. Puedes re-ejecutarlo sin problema si algo falla a mitad.

## Notas

- Requiere **systemd activo en WSL**. Si no está activo, el script lo configura y te pide que reinicies WSL (`wsl --shutdown` desde PowerShell)
- Orca necesita `xvfb` porque corre headless (sin GPU/display)
- El servicio Orca se configura con `loginctl enable-linger` para que sobreviva sin sesión activa

## Testing con Docker

El `Dockerfile` incluido permite validar el script en un contenedor Ubuntu sin tocar ninguna máquina real.

### Qué testea

Corre el script completo con mocks para las partes que son WSL/systemd-específicas y no aplican en Docker:

| Mockeado | Real |
|---|---|
| `systemctl` / `systemd` | Paquetes APT |
| `tailscale` / `tailscaled` | FNM + Node.js LTS + pnpm |
| Docker (evita Docker-in-Docker) | GitHub CLI (`gh`) |
| Orca AppImage (evita descarga ~150MB) | 1Password CLI (`op`) |
| `xvfb-run` | GitHub Copilot CLI |
| `loginctl` | Antigravity CLI (`agy`) |

Al final del build corre un smoke test que verifica: `git`, `node`, `npm`, `pnpm`, `gh`, `op`, `jq`, `fzf`, `tmux`.

### Correr el test

```bash
docker build -t devbox-test .
```

El build falla si cualquier instalación o el smoke test falla — `set -e` está activo en todo el proceso.

### Limpiar

```bash
docker rmi devbox-test
```
