#!/usr/bin/env bash
# ==============================================================================
# Linux Development Environment Setup Script
# ==============================================================================
# Description:
#   Automates the setup of a Linux development workstation by:
#     1. Installing bootstrap packages (git, git-lfs, curl, flatpak, FUSE)
#     2. Adding Flathub and installing GUI apps as user Flatpaks
#     3. Installing Cursor and Antigravity as official AppImages
#     4. Installing Homebrew on Linux and the cross-platform CLI tools
#        defined in shared/Brewfile (same list the macOS script uses)
#     5. Installing Docker Engine (official installer), Ollama, and Zed
#     6. Configuring mise (Node.js, Java, Python from shared/mise.toml)
#        and ~/.local/bin on PATH
#
# Usage:
#   ./linux/setup_linux.sh             # Full installation
#   ./linux/setup_linux.sh --check     # Audit installed status without installing
#   ./linux/setup_linux.sh --dry-run   # Preview actions without executing installs
#   ./linux/setup_linux.sh --help      # Show help menu
#
# Requirements:
#   - Linux (Debian/Ubuntu, Fedora/RHEL, or Arch family)
#   - x86_64 or aarch64
#   - Administrator (sudo) privileges for distro packages, Homebrew's
#     /home/linuxbrew prefix, Docker, and Ollama
#   - Active internet connection
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${SCRIPT_DIR}/packages.conf"

# Shared flags, logging, and Homebrew helpers (also provides SHARED_BREWFILE)
# shellcheck source=../shared/lib.sh
source "${SCRIPT_DIR}/../shared/lib.sh"
parse_flags "packages.conf and shared/Brewfile" "$@"

# ------------------------------------------------------------------------------
# Shared Paths & Architecture
# ------------------------------------------------------------------------------
LOCAL_BIN="${HOME}/.local/bin"
APPLICATIONS_DIR="${HOME}/Applications"
DESKTOP_DIR="${HOME}/.local/share/applications"
LINUXBREW_PREFIX="/home/linuxbrew/.linuxbrew"

HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
    x86_64)
        CURSOR_PLATFORM="linux-x64"
        ANTIGRAVITY_UPDATE_ARCH="x64"
        ANTIGRAVITY_STORAGE_ARCH="x64"
        ;;
    aarch64|arm64)
        HOST_ARCH="aarch64"
        CURSOR_PLATFORM="linux-arm64"
        ANTIGRAVITY_UPDATE_ARCH="arm64"
        ANTIGRAVITY_STORAGE_ARCH="arm"
        ;;
    *)
        echo "Unsupported architecture: $HOST_ARCH (need x86_64 or aarch64)"
        exit 1
        ;;
esac

PKG_FAMILY=""
PKG_INSTALL=()
OS_ID=""
OS_PRETTY=""

# ------------------------------------------------------------------------------
# Environment & OS Verification
# ------------------------------------------------------------------------------
detect_pkg_family() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "/etc/os-release not found; cannot detect Linux distribution."
        exit 1
    fi

    # shellcheck disable=SC1091
    source /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_PRETTY="${PRETTY_NAME:-$OS_ID}"
    local like="${ID_LIKE:-}"

    if [[ "$OS_ID" =~ ^(debian|ubuntu|linuxmint|pop|elementary|raspbian)$ ]] || [[ "$like" == *debian* ]] || [[ "$like" == *ubuntu* ]]; then
        PKG_FAMILY="debian"
        PKG_INSTALL=(sudo apt-get install -y)
    elif [[ "$OS_ID" =~ ^(fedora|rhel|centos|rocky|almalinux|nobara)$ ]] || [[ "$like" == *fedora* ]] || [[ "$like" == *rhel* ]]; then
        PKG_FAMILY="fedora"
        if command_on_path dnf; then
            PKG_INSTALL=(sudo dnf install -y)
        else
            PKG_INSTALL=(sudo yum install -y)
        fi
    elif [[ "$OS_ID" =~ ^(arch|manjaro|endeavouros|cachyos)$ ]] || [[ "$like" == *arch* ]]; then
        PKG_FAMILY="arch"
        PKG_INSTALL=(sudo pacman -S --needed --noconfirm)
    else
        log_error "Unsupported distribution: $OS_PRETTY"
        log_info "Supported families: Debian/Ubuntu, Fedora/RHEL, Arch."
        exit 1
    fi
}

verify_environment() {
    log_step "Verifying Environment..."

    if [[ "$(uname -s)" != "Linux" ]]; then
        log_error "This script is designed for Linux. Current OS: $(uname -s)"
        exit 1
    fi

    local f
    for f in "$MANIFEST" "$SHARED_BREWFILE" "$SHARED_MISE_CONFIG"; do
        if [[ ! -f "$f" ]]; then
            log_error "Required manifest not found at expected location: $f"
            exit 1
        fi
    done

    # shellcheck disable=SC1090
    source "$MANIFEST"

    detect_pkg_family
    log_info "Operating System: $OS_PRETTY ($HOST_ARCH)"
    log_info "Package family: $PKG_FAMILY"
    log_info "Using package manifests: $MANIFEST, $SHARED_BREWFILE"
}

# ------------------------------------------------------------------------------
# Bootstrap: distro packages, PATH, Flathub
# ------------------------------------------------------------------------------
bootstrap_package_names() {
    case "$PKG_FAMILY" in
        debian)
            echo "ca-certificates curl git git-lfs flatpak build-essential procps file"
            if apt-cache show libfuse2t64 &>/dev/null; then
                echo "libfuse2t64"
            else
                echo "libfuse2"
            fi
            ;;
        fedora)
            echo "ca-certificates curl git git-lfs flatpak fuse fuse-libs gcc gcc-c++ make procps-ng file"
            ;;
        arch)
            echo "ca-certificates curl git git-lfs flatpak fuse2 base-devel procps-ng file"
            ;;
    esac
}

ensure_local_path() {
    ensure_dir "$LOCAL_BIN"
    ensure_dir "$APPLICATIONS_DIR"
    ensure_dir "$DESKTOP_DIR"

    local marker="# env-setup: local bin"
    local block='export PATH="$HOME/.local/bin:$PATH"'
    [[ -f "$HOME/.bashrc" ]] || touch "$HOME/.bashrc"
    [[ -f "$HOME/.zshrc" ]] || true
    append_once "$HOME/.bashrc" "$marker" "$block"
    if [[ -f "$HOME/.zshrc" ]]; then
        append_once "$HOME/.zshrc" "$marker" "$block"
    fi
    export PATH="${LOCAL_BIN}:$PATH"
}

ensure_bootstrap() {
    log_step "Checking bootstrap packages (git, git-lfs, curl, Flatpak, FUSE, Homebrew prerequisites)..."

    local missing=()
    local pkg
    for pkg in $(bootstrap_package_names); do
        case "$PKG_FAMILY" in
            debian)
                if ! dpkg -s "$pkg" &>/dev/null; then
                    missing+=("$pkg")
                fi
                ;;
            fedora)
                if ! rpm -q "$pkg" &>/dev/null; then
                    missing+=("$pkg")
                fi
                ;;
            arch)
                if ! pacman -Qi "$pkg" &>/dev/null; then
                    missing+=("$pkg")
                fi
                ;;
        esac
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        log_success "Bootstrap packages already installed."
    else
        if [[ "$CHECK_ONLY" == "true" ]]; then
            log_warn "Bootstrap missing: ${missing[*]}"
        elif [[ "$DRY_RUN" == "true" ]]; then
            log_warn "[Dry Run] Would install: ${missing[*]}"
        else
            log_info "Installing bootstrap packages: ${missing[*]}"
            if [[ "$PKG_FAMILY" == "debian" ]]; then
                sudo DEBIAN_FRONTEND=noninteractive apt-get update -y
                sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
            else
                "${PKG_INSTALL[@]}" "${missing[@]}"
            fi
            log_success "Bootstrap packages installed."
        fi
    fi

    if should_modify; then
        ensure_local_path
    elif [[ "$DRY_RUN" == "true" ]]; then
        log_info "[Dry Run] Would ensure ${LOCAL_BIN} exists and is on PATH."
    fi

    if command_on_path flatpak; then
        if flatpak remotes --user --columns=name 2>/dev/null | grep -qx flathub; then
            log_success "Flathub user remote is configured."
        else
            if should_modify; then
                log_info "Adding Flathub as a user Flatpak remote..."
                flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
                log_success "Flathub remote added."
            elif [[ "$CHECK_ONLY" == "true" ]]; then
                log_warn "Flathub user remote is not configured."
            else
                log_warn "[Dry Run] Would add Flathub user remote."
            fi
        fi
    elif [[ "$CHECK_ONLY" == "true" ]]; then
        log_warn "flatpak is not available on PATH."
    fi
}

# ------------------------------------------------------------------------------
# Flatpak GUI apps
# ------------------------------------------------------------------------------
flatpak_installed() {
    flatpak info --user "$1" &>/dev/null || flatpak info --system "$1" &>/dev/null
}

install_flatpaks() {
    log_step "Installing Flathub applications..."
    local entry
    for entry in "${FLATPAK_PACKAGES[@]}"; do
        parse_entry "$entry"
        if command_on_path flatpak && flatpak_installed "$ENTRY_ID"; then
            log_success "$ENTRY_NAME - $ENTRY_DESC (Installed)"
            continue
        fi
        if [[ "$CHECK_ONLY" == "true" ]]; then
            log_warn "$ENTRY_NAME ($ENTRY_ID) - $ENTRY_DESC (Not installed)"
        elif [[ "$DRY_RUN" == "true" ]]; then
            log_warn "[Dry Run] Would install Flatpak: $ENTRY_ID ($ENTRY_NAME)"
        else
            log_info "Installing $ENTRY_NAME ($ENTRY_ID)..."
            if flatpak install --user -y flathub "$ENTRY_ID"; then
                log_success "$ENTRY_NAME installed."
            else
                log_warn "$ENTRY_NAME could not be installed (it may not be published for ${HOST_ARCH}). Continuing."
            fi
        fi
    done
}

# ------------------------------------------------------------------------------
# AppImages
# ------------------------------------------------------------------------------
appimage_path() {
    local id="$1"
    case "$id" in
        cursor) echo "${APPLICATIONS_DIR}/Cursor.AppImage" ;;
        antigravity) echo "${APPLICATIONS_DIR}/Antigravity.AppImage" ;;
        *) echo "${APPLICATIONS_DIR}/${id}.AppImage" ;;
    esac
}

write_desktop_entry() {
    local name="$1"
    local exec_path="$2"
    local desktop_id="$3"
    local comment="$4"
    cat > "${DESKTOP_DIR}/${desktop_id}.desktop" << EOF
[Desktop Entry]
Name=${name}
Comment=${comment}
Exec="${exec_path}" %U
Terminal=false
Type=Application
Categories=Development;
StartupNotify=true
EOF
}

resolve_cursor_url() {
    local json
    json="$(curl -fsSL "https://www.cursor.com/api/download?platform=${CURSOR_PLATFORM}&releaseTrack=stable")"
    json_string_field "$json" "downloadUrl"
}

resolve_antigravity_url() {
    local json tarball appimage
    json="$(curl -fsSL "https://antigravity-auto-updater-974169037036.us-central1.run.app/api/update/linux-${ANTIGRAVITY_UPDATE_ARCH}/stable/latest")"
    tarball="$(json_string_field "$json" "url")"
    if [[ -z "$tarball" ]]; then
        log_error "Could not parse Antigravity updater response."
        return 1
    fi
    appimage="${tarball%.tar.gz}.AppImage"
    if [[ "$appimage" == "$tarball" ]]; then
        appimage="${tarball%/*}/Antigravity.AppImage"
    fi
    # Prefer the sibling AppImage next to the official tarball.
    if [[ "$appimage" != *".AppImage" ]]; then
        appimage="https://storage.googleapis.com/antigravity-public/antigravity-hub/latest/linux-${ANTIGRAVITY_STORAGE_ARCH}/Antigravity.AppImage"
    fi
    if ! url_exists "$appimage"; then
        log_error "Official Antigravity AppImage was not found at: $appimage"
        log_info "Refusing to fall back to the .tar.gz. Install the AppImage manually when Google publishes it for this architecture."
        return 1
    fi
    printf '%s' "$appimage"
}

install_appimages() {
    log_step "Installing official AppImages..."
    local entry dest url tmp
    for entry in "${APPIMAGE_PACKAGES[@]}"; do
        parse_entry "$entry"
        dest="$(appimage_path "$ENTRY_ID")"
        if [[ -x "$dest" ]]; then
            log_success "$ENTRY_NAME - $ENTRY_DESC (Installed: $dest)"
            continue
        fi
        if [[ "$CHECK_ONLY" == "true" ]]; then
            log_warn "$ENTRY_NAME - $ENTRY_DESC (Not installed)"
            continue
        fi
        if [[ "$DRY_RUN" == "true" ]]; then
            log_warn "[Dry Run] Would download official AppImage for $ENTRY_NAME into $dest"
            continue
        fi

        log_info "Resolving official $ENTRY_NAME AppImage URL..."
        case "$ENTRY_ID" in
            cursor) url="$(resolve_cursor_url)" ;;
            antigravity) url="$(resolve_antigravity_url)" ;;
            *)
                log_error "Unknown AppImage id: $ENTRY_ID"
                exit 1
                ;;
        esac
        if [[ -z "$url" || "$url" == "null" ]]; then
            log_error "Failed to resolve AppImage URL for $ENTRY_NAME."
            exit 1
        fi
        tmp="$(mktemp "${TMPDIR:-/tmp}/${ENTRY_ID}.XXXXXX.AppImage")"
        log_info "Downloading $ENTRY_NAME..."
        download_file "$url" "$tmp"
        chmod +x "$tmp"
        mv "$tmp" "$dest"
        write_desktop_entry "$ENTRY_NAME" "$dest" "$ENTRY_ID" "$ENTRY_DESC"
        log_success "$ENTRY_NAME installed at $dest"
    done
}

# ------------------------------------------------------------------------------
# Distro CLI (git / git-lfs) — already handled in bootstrap; audit here
# ------------------------------------------------------------------------------
audit_distro_packages() {
    log_step "CLI tools from distro packages..."
    local entry
    for entry in "${DISTRO_PACKAGES[@]}"; do
        parse_entry "$entry"
        if command_on_path "$ENTRY_ID"; then
            log_success "$ENTRY_ID - $ENTRY_DESC (Installed: $(command -v "$ENTRY_ID"))"
        else
            if [[ "$CHECK_ONLY" == "true" ]]; then
                log_warn "$ENTRY_ID - $ENTRY_DESC (Not installed)"
            elif [[ "$DRY_RUN" == "true" ]]; then
                log_warn "[Dry Run] Would install distro package: $ENTRY_ID"
            else
                log_warn "$ENTRY_ID was expected from bootstrap but is not on PATH."
            fi
        fi
    done
}

# ------------------------------------------------------------------------------
# Homebrew on Linux + shared Brewfile
# ------------------------------------------------------------------------------
# Warn (don't fail) when Homebrew would fall outside its Tier 1 support,
# where some formulae may need to build from source.
check_brew_tier() {
    local glibc
    glibc="$(ldd --version 2>/dev/null | head -n 1 | grep -oE '[0-9]+\.[0-9]+$' || true)"
    if [[ "$HOST_ARCH" == "aarch64" && -n "$glibc" ]]; then
        if [[ "$(printf '%s\n' "2.39" "$glibc" | sort -V | head -n 1)" != "2.39" ]]; then
            log_warn "glibc ${glibc} < 2.39: Homebrew on ARM64 Linux is not Tier 1 here; some formulae may build from source."
        fi
    fi
}

ensure_homebrew() {
    log_step "Checking Homebrew on Linux..."

    local brew_bin=""
    if command_on_path brew; then
        brew_bin="$(command -v brew)"
    elif [[ -x "${LINUXBREW_PREFIX}/bin/brew" ]]; then
        brew_bin="${LINUXBREW_PREFIX}/bin/brew"
    elif [[ -x "${HOME}/.linuxbrew/bin/brew" ]]; then
        brew_bin="${HOME}/.linuxbrew/bin/brew"
    fi

    if [[ -n "$brew_bin" ]]; then
        eval "$("$brew_bin" shellenv)"
        log_success "Homebrew available: $brew_bin"
    elif [[ "$CHECK_ONLY" == "true" ]]; then
        log_warn "Homebrew: NOT INSTALLED"
        return 0
    elif [[ "$DRY_RUN" == "true" ]]; then
        log_warn "[Dry Run] Would run Homebrew's official install script (prefix ${LINUXBREW_PREFIX})"
        return 0
    else
        check_brew_tier
        log_info "Installing Homebrew via official script (sudo needed to create ${LINUXBREW_PREFIX})..."
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        brew_bin="${LINUXBREW_PREFIX}/bin/brew"
        eval "$("$brew_bin" shellenv)"
        log_success "Homebrew installed."
    fi

    local rc_files=("$HOME/.bashrc")
    [[ -f "$HOME/.zshrc" ]] && rc_files+=("$HOME/.zshrc")
    persist_brew_shellenv "$brew_bin" "${rc_files[@]}"

    if should_modify; then
        log_info "Updating Homebrew metadata..."
        brew update --quiet || true
    fi
}

install_shared_brewfile() {
    if ! command_on_path brew; then
        log_step "Shared CLI tools (shared/Brewfile)..."
        log_warn "Homebrew is not available; skipping shared/Brewfile."
        return 0
    fi
    if should_modify; then
        run_brew_bundle "$SHARED_BREWFILE"
    else
        log_step "Auditing shared CLI tools (shared/Brewfile)..."
        audit_brew_formulae "$SHARED_BREWFILE"
    fi
}

# ------------------------------------------------------------------------------
# Docker Engine & Ollama
# ------------------------------------------------------------------------------
install_docker_engine() {
    log_step "Installing Docker Engine..."
    if command_on_path docker; then
        log_success "Docker Engine - already present ($(docker --version 2>/dev/null || true))"
    else
        if [[ "$CHECK_ONLY" == "true" ]]; then
            log_warn "Docker Engine - Not installed"
        elif [[ "$DRY_RUN" == "true" ]]; then
            log_warn "[Dry Run] Would run Docker's official install script (get.docker.com)"
        else
            log_info "Running Docker's official convenience script..."
            curl -fsSL https://get.docker.com | sudo sh
            log_success "Docker Engine installed."
        fi
    fi

    if should_modify; then
        if command_on_path systemctl; then
            sudo systemctl enable --now docker 2>/dev/null || sudo systemctl enable --now docker.service || true
        fi
        local current_user
        current_user="$(id -un)"
        if ! id -nG "$current_user" | grep -qw docker; then
            log_info "Adding $current_user to the docker group..."
            sudo usermod -aG docker "$current_user"
            log_warn "Log out and back in (or run 'newgrp docker') before using Docker without sudo."
        else
            log_success "User $current_user is already in the docker group."
        fi
        if docker compose version &>/dev/null; then
            log_success "Docker Compose plugin available."
        else
            log_warn "docker compose plugin was not detected. Re-run get.docker.com or install docker-compose-plugin."
        fi
    elif [[ "$CHECK_ONLY" == "true" ]]; then
        if docker compose version &>/dev/null; then
            log_success "Docker Compose plugin (Installed)"
        else
            log_warn "Docker Compose plugin (Not installed)"
        fi
    fi
}

install_ollama() {
    log_step "Installing Ollama..."
    if command_on_path ollama; then
        log_success "Ollama - already installed ($(ollama --version 2>/dev/null | tail -n 1 || true))"
        return 0
    fi
    if [[ "$CHECK_ONLY" == "true" ]]; then
        log_warn "Ollama - Not installed"
        return 0
    fi
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "[Dry Run] Would run Ollama's official install script"
        return 0
    fi
    curl -fsSL https://ollama.com/install.sh | sh
    log_success "Ollama installed."
}

install_zed() {
    log_step "Installing Zed Editor..."
    if command_on_path zed; then
        log_success "Zed - already installed ($(zed --version 2>/dev/null || true))"
        return 0
    fi
    if [[ "$CHECK_ONLY" == "true" ]]; then
        log_warn "Zed - Not installed"
        return 0
    fi
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "[Dry Run] Would run Zed's official install script"
        return 0
    fi
    curl -fsSL https://zed.dev/install.sh | sh
    log_success "Zed installed."
}

# ------------------------------------------------------------------------------
# mise (Node.js, Java, Python versions from shared/mise.toml)
# ------------------------------------------------------------------------------
configure_mise() {
    setup_mise
    add_mise_activation bash "$HOME/.bashrc"
    if [[ -f "$HOME/.zshrc" ]]; then
        add_mise_activation zsh "$HOME/.zshrc"
    fi
    # ~/.profile is read by login shells and most desktop sessions (GUI apps/IDEs)
    add_mise_activation bash "$HOME/.profile" --shims
}

# ------------------------------------------------------------------------------
# Skipped macOS-only packages
# ------------------------------------------------------------------------------
show_skipped() {
    log_step "Skipped macOS-only utilities..."
    local entry
    for entry in "${SKIPPED_PACKAGES[@]}"; do
        parse_entry "$entry"
        log_info "$ENTRY_NAME ($ENTRY_ID) — $ENTRY_DESC (not installed on Linux)"
    done
}

# ------------------------------------------------------------------------------
# Post-installation notes
# ------------------------------------------------------------------------------
show_post_install_notes() {
    log_step "Linux Configuration Notes"

    cat << EOF
  Docker:
    - Docker Engine is installed instead of Docker Desktop.
    - Log out and back in so the docker group membership takes effect.
    - Verify with: docker version && docker compose version

  AppImages:
    - Cursor and Antigravity live in ${APPLICATIONS_DIR}
    - Desktop entries are in ${DESKTOP_DIR}
    - FUSE (libfuse2 / fuse2) is required to run AppImages

  Homebrew:
    - Installed at ${LINUXBREW_PREFIX}; shared CLI tools come from shared/Brewfile
    - Reload the shell (or source ~/.bashrc) to pick up brew, mise, and PATH
    - Keep tools current with: brew update && brew upgrade

  Flatpak apps:
    - Beekeeper Studio is sandboxed; to open SQLite files outside your home dir:
      flatpak override --user --filesystem=host io.beekeeperstudio.Studio

  CLI Tools:
    - Runtimes (mise): run 'mise ls' to see active versions
      * Node.js: node -v   Java: java --version   Python: python --version
      * The distro python3 stays in place for the OS
      * Defaults live in shared/mise.toml; pin per project with: mise use node@22
      * Update "latest" runtimes with: mise upgrade
    - Kubernetes: kubectl version --client
      * Start a local cluster: minikube start
      * Dashboard: k9s
    - Code search: rg <pattern>

  Ollama:
    - Run: ollama run llama3

  Skipped (macOS-only): Maccy, Scroll Reverser, Caffeine
EOF
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
main() {
    print_banner "Linux Development Environment Setup"

    verify_environment
    ensure_bootstrap
    audit_distro_packages
    install_flatpaks
    install_appimages
    ensure_homebrew
    install_shared_brewfile
    install_docker_engine
    install_ollama
    install_zed
    configure_mise
    show_skipped

    if [[ "$CHECK_ONLY" == "true" ]]; then
        echo ""
        log_info "Audit check complete."
    elif [[ "$DRY_RUN" == "true" ]]; then
        echo ""
        log_info "Dry-run simulation complete."
    else
        show_post_install_notes
        echo ""
        log_success "Linux applications and development tools configured successfully!"
    fi
}

main "$@"
