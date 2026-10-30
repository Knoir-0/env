# Dev Environment Setup

Automated scripts and configuration to set up a new development environment quickly across different operating systems.

---

## macOS Workstation Setup

The macOS environment is automated using [`macos/setup_mac.sh`](file:///Users/null/Desktop/env/macos/setup_mac.sh), which bootstraps system dependencies and directly executes the declarative [`macos/Brewfile`](file:///Users/null/Desktop/env/macos/Brewfile).

### Quickstart

To install all applications, development tools, and global runtimes:

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

Alternatively, if you prefer using Homebrew Bundle directly:
```bash
brew bundle --file=./macos/Brewfile
```

---

## Linux Workstation Setup

The Linux environment is automated using [`linux/setup_linux.sh`](linux/setup_linux.sh), which reads [`linux/packages.conf`](linux/packages.conf). GUI apps are installed from Flathub first, then official AppImages. CLI tools that have no Flatpak or AppImage are installed from distro packages or official upstream binaries. Docker Engine (not Docker Desktop) and Ollama use their official install scripts.

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

### Linux Software Inventory

| Application | Source | Identifier / location | Notes |
| :--- | :--- | :--- | :--- |
| Git, Git LFS | Distro package | `git`, `git-lfs` | Installed during bootstrap |
| Python 3, pip | Distro package | `python3`, `python3-pip` | General-purpose language and package manager |
| Node.js | Official binary | `~/.local/opt/node` | Latest Current tarball from nodejs.org |
| OpenJDK | Official binary | `~/.local/opt/openjdk` | Latest Eclipse Temurin GA |
| CMake | Official binary | `~/.local/opt/cmake` | Kitware GitHub release |
| kubectl, minikube, helm, k9s, ripgrep | Official binary | `~/.local/bin` | Upstream release artifacts |
| Docker Engine + Compose | Official installer | `get.docker.com` | Replaces Docker Desktop on Linux |
| Ollama | Official installer | `ollama.com/install.sh` | No Flatpak or AppImage |
| Raspberry Pi Imager | Flathub | `org.raspberrypi.rpi-imager` | |
| Visual Studio Code | Flathub | `com.visualstudio.code` | |
| GitHub Desktop | Flathub | `io.github.shiftey.Desktop` | Linux community fork |
| Firefox | Flathub | `org.mozilla.firefox` | |
| FreeCAD | Flathub | `org.freecad.FreeCAD` | |
| OrcaSlicer | Flathub | `com.orcaslicer.OrcaSlicer` | |
| Blender | Flathub | `org.blender.Blender` | |
| LibreOffice | Flathub | `org.libreoffice.LibreOffice` | |
| Cursor | Official AppImage | `~/Applications/Cursor.AppImage` | |
| Zed | Official installer | `zed.dev/install.sh` | |
| Antigravity | Official AppImage | `~/Applications/Antigravity.AppImage` | Fails if Google does not publish an AppImage |
| Maccy, Scroll Reverser, Caffeine | Skipped | — | macOS-only utilities |

### Linux Post-Installation Notes

- Log out and back in so `docker` group membership takes effect, then run `docker version` and `docker compose version`.
- Reload the shell (or `source ~/.bashrc`) so `~/.local/bin` and `JAVA_HOME` are on PATH.
- AppImages require FUSE and live in `~/Applications`.
- Start a local cluster with `minikube start`; use `k9s` for a dashboard.
- Test Ollama with `ollama run llama3`.

---

## macOS Installed Software Inventory

### CLI Tools & Runtimes (Homebrew Formulae)
- **Node.js** (`node`) - Latest stable JavaScript runtime environment (includes `npm` and `npx`)
- **Java OpenJDK** (`openjdk`) - Latest stable Open Java Development Kit (JDK)
- **Docker CLI** (`docker`) & **Docker Compose** (`docker-compose`) - Command-line tools for container execution and composition
- **Kubernetes CLI** (`kubectl`) - Command-line interface for running commands against Kubernetes clusters
- **K9s** (`k9s`) - Interactive terminal dashboard for managing Kubernetes clusters
- **Minikube** (`minikube`) - Local single-node Kubernetes cluster tool
- **Helm** (`helm`) - The package manager for Kubernetes
- **Ripgrep** (`ripgrep`) - Ultra-fast recursive line-oriented code search tool (`rg`)
- **CMake** (`cmake`) - Cross-platform build system generator (required for C/C++ projects like `biotech`)
- **Python 3** (`python`) - General-purpose programming language (includes `pip`)
- **Git** (`git`) & **Git LFS** (`git-lfs`) - Version control system and large file storage

### GUI Applications (Homebrew Casks)

| Application | Cask Identifier | Category | Purpose |
| :--- | :--- | :--- | :--- |
| **Docker Desktop** | `docker-desktop` | Containers & DevOps | GUI application, container daemon, and built-in Kubernetes engine |
| **Raspberry Pi Imager** | `raspberry-pi-imager` | Embedded & Hardware | Official utility to flash and preconfigure OS images to SD cards |
| **Cursor** | `cursor` | AI & Development | AI-first code editor built on VS Code |
| **Zed** | `zed` | AI & Development | High-performance, multiplayer code editor |
| **Visual Studio Code** | `visual-studio-code` | AI & Development | Extensible code editor from Microsoft |
| **GitHub Desktop** | `github` | AI & Development | Official GUI client for GitHub repositories |
| **Ollama** | `ollama-app` | AI & Development | Local LLM runner and CLI tool |
| **Antigravity** | `antigravity` | AI & Development | Agent orchestration platform |
| **Firefox** | `firefox` | Web Browsers | Mozilla Firefox browser |
| **FreeCAD** | `freecad` | 3D & CAD | 3D parametric modeler |
| **OrcaSlicer** | `orcaslicer` | 3D & CAD | Slicer for 3D printers |
| **Blender** | `blender` | 3D & CAD | 3D creation and mesh modeling suite |
| **LibreOffice** | `libreoffice` | Office & Productivity | Free and open-source office productivity suite |
| **Maccy** | `maccy` | Utilities | Lightweight keyboard-driven clipboard manager |
| **Scroll Reverser** | `scroll-reverser` | Utilities | Independent scrolling for mouse & trackpad |
| **Caffeine** | `caffeine` | Utilities | Menu bar utility to keep system awake |

---

## Post-Installation Notes & macOS Permissions

After running the setup script, grant Accessibility permissions to system utilities that require window/keyboard hooks:
1. Open **System Settings** → **Privacy & Security** → **Accessibility**
2. Toggle on permissions for:
   - **Maccy**
   - **Scroll Reverser**
