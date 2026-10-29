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

## Installed Software Inventory

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
- **Git** (`git`) & **Git LFS** (`git-lfs`) - Version control system and large file storage

### GUI Applications (Homebrew Casks)

| Application | Cask Identifier | Category | Purpose |
| :--- | :--- | :--- | :--- |
| **Docker Desktop** | `docker-desktop` | Containers & DevOps | GUI application, container daemon, and built-in Kubernetes engine |
| **Raspberry Pi Imager** | `raspberry-pi-imager` | Embedded & Hardware | Official utility to flash and preconfigure OS images to SD cards |
| **Cursor** | `cursor` | AI & Development | AI-first code editor built on VS Code |
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
