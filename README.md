# Dev Environment Setup

Automated scripts and declarative manifests to set up a development workstation across **macOS** and **Linux** (`x86_64` and `arm64`/`aarch64`).

---

## Repository Layout

- **[`shared/Brewfile`](file:///Users/null/Desktop/env/shared/Brewfile)** — Cross-platform CLI formulae installed via Homebrew on **both** macOS and Linux (`mise`, `cmake`, `kubectl`, `minikube`, `helm`, `k9s`, `ripgrep`, `fd`, `bat`, `lazygit`, `helix`).
- **[`shared/mise.toml`](file:///Users/null/Desktop/env/shared/mise.toml)** — Global [`mise`](https://mise.jdx.dev) configuration symlinked to `~/.config/mise/config.toml` on both platforms. Manages language runtimes (`node = "latest"`, `java = "latest"` via Eclipse Temurin, `python = "latest"`), per-project environment variables, and tasks.
- **[`shared/lib.sh`](file:///Users/null/Desktop/env/shared/lib.sh)** — Shared shell helpers for flag parsing (`--check`, `--dry-run`, `--help`), logging, Homebrew bundle/audit, and `mise` setup.
- **[`macos/setup_mac.sh`](file:///Users/null/Desktop/env/macos/setup_mac.sh)** & **[`macos/Brewfile`](file:///Users/null/Desktop/env/macos/Brewfile)** — macOS setup script and macOS-specific formulae/casks.
- **[`linux/setup_linux.sh`](file:///Users/null/Desktop/env/linux/setup_linux.sh)** & **[`linux/packages.conf`](file:///Users/null/Desktop/env/linux/packages.conf)** — Linux setup script and manifest for distro bootstrap packages, Flathub GUI apps, AppImages, Docker Engine, Ollama, and Zed.

---

## macOS Workstation Setup

The macOS environment is automated using [`macos/setup_mac.sh`](file:///Users/null/Desktop/env/macos/setup_mac.sh), which bootstraps Xcode Command Line Tools and Homebrew, executes `brew bundle` against [`shared/Brewfile`](file:///Users/null/Desktop/env/shared/Brewfile) and [`macos/Brewfile`](file:///Users/null/Desktop/env/macos/Brewfile), and configures `mise`.

### Quickstart

```bash
chmod +x macos/setup_mac.sh
./macos/setup_mac.sh
```

### Script Modes & Flags

- **Audit / Check status** (no changes made):
  ```bash
  ./macos/setup_mac.sh --check
  ```
- **Dry run simulation** (previews actions without installing):
  ```bash
  ./macos/setup_mac.sh --dry-run
  ```
- **Help menu**:
  ```bash
  ./macos/setup_mac.sh --help
  ```

---

## Linux Workstation Setup

The Linux environment is automated using [`linux/setup_linux.sh`](file:///Users/null/Desktop/env/linux/setup_linux.sh), which reads [`linux/packages.conf`](file:///Users/null/Desktop/env/linux/packages.conf) and [`shared/Brewfile`](file:///Users/null/Desktop/env/shared/Brewfile):
1. Installs distro bootstrap packages (`git`, `git-lfs`, `curl`, `flatpak`, FUSE, build tools).
2. Installs GUI apps from Flathub and official AppImages (`Cursor`, `Antigravity`).
3. Installs Homebrew on Linux (`/home/linuxbrew/.linuxbrew`) and runs `brew bundle` against [`shared/Brewfile`](file:///Users/null/Desktop/env/shared/Brewfile).
4. Installs Docker Engine, Ollama, and Zed using their official installers.
5. Links [`shared/mise.toml`](file:///Users/null/Desktop/env/shared/mise.toml) and installs default runtimes (`node`, `java`, `python`).

Supported families: Debian/Ubuntu, Fedora/RHEL, and Arch. Architectures: `x86_64` and `aarch64`.

### Quickstart

```bash
chmod +x linux/setup_linux.sh
./linux/setup_linux.sh
```

### Script Modes & Flags

- **Audit / Check status** (no changes made):
  ```bash
  ./linux/setup_linux.sh --check
  ```
- **Dry run simulation** (previews actions without installing):
  ```bash
  ./linux/setup_linux.sh --dry-run
  ```
- **Help menu**:
  ```bash
  ./linux/setup_linux.sh --help
  ```

---

## Installed Software Inventory

### Language Runtimes (`shared/mise.toml` via `mise`)
- **Node.js** (`node = "latest"`, includes `npm` and `npx`)
- **Java OpenJDK** (`java = "latest"`, Eclipse Temurin; automatically manages `JAVA_HOME`)
- **Python 3** (`python = "latest"`, includes `pip`)

### Shared CLI Tools (`shared/Brewfile` via Homebrew)
- **mise** (`mise`) — Polyglot runtime version, environment variable, and task manager
- **CMake** (`cmake`) — Cross-platform build system generator
- **Kubernetes CLI** (`kubectl`), **Minikube** (`minikube`), **Helm** (`helm`), **K9s** (`k9s`)
- **Ripgrep** (`ripgrep`)

### GUI Applications & Platform Services

| Application | macOS (`macos/Brewfile`) | Linux (`linux/packages.conf`) | Category |
| :--- | :--- | :--- | :--- |
| **Docker** | `docker-desktop` (Cask) + `docker` / `docker-compose` | `get.docker.com` (`docker-engine` + Compose plugin) | Containers & DevOps |
| **Freelens** | `freelens` (Cask) | `app.freelens.Freelens` (Flathub) | Kubernetes IDE |
| **Beekeeper Studio** | `beekeeper-studio` (Cask) | `io.beekeeperstudio.Studio` (Flathub) | Database Manager |
| **Insomnia** | `insomnia` (Cask) | `rest.insomnia.Insomnia` (Flathub) | API Client |
| **Cursor** | `cursor` (Cask) | Official AppImage (`~/Applications/Cursor.AppImage`) | AI & Code Editors |
| **Zed** | `zed` (Cask) | Official installer (`zed.dev/install.sh`) | AI & Code Editors |
| **Visual Studio Code** | `visual-studio-code` (Cask) | `com.visualstudio.code` (Flathub) | AI & Code Editors |
| **GitHub Desktop** | `github` (Cask) | `io.github.shiftey.Desktop` (Flathub) | AI & Code Editors |
| **Ollama** | `ollama-app` (Cask) | Official installer (`ollama.com/install.sh`) | Local LLM Runner |
| **Antigravity** | `antigravity` (Cask) | Official AppImage (`~/Applications/Antigravity.AppImage`) | Agent Orchestration |
| **Raspberry Pi Imager** | `raspberry-pi-imager` (Cask) | `org.raspberrypi.rpi-imager` (Flathub) | Embedded & Hardware |
| **Firefox** | `firefox` (Cask) | `org.mozilla.firefox` (Flathub) | Web Browser |
| **FreeCAD** | `freecad` (Cask) | `org.freecad.FreeCAD` (Flathub) | 3D & CAD |
| **OrcaSlicer** | `orcaslicer` (Cask) | `com.orcaslicer.OrcaSlicer` (Flathub) | 3D & CAD |
| **Blender** | `blender` (Cask) | `org.blender.Blender` (Flathub) | 3D & CAD |
| **LibreOffice** | `libreoffice` (Cask) | `org.libreoffice.LibreOffice` (Flathub) | Office Suite |
| **Maccy, Scroll Reverser, Caffeine** | Casks | Skipped (macOS-only) | macOS Utilities |
