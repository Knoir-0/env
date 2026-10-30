#!/usr/bin/env bash
# ==============================================================================
# Linux Development Environment Setup Script
# ==============================================================================
# Description:
#   Automates the setup of a Linux development workstation by:
#     1. Installing bootstrap packages (git, git-lfs, curl, flatpak, FUSE)
#     2. Adding Flathub and installing GUI apps as user Flatpaks
#     3. Installing Cursor and Antigravity as official AppImages
#     4. Installing CLI tools from official upstream binaries
#     5. Installing Docker Engine (official installer) and Ollama
#     6. Configuring OpenJDK (JAVA_HOME) and ~/.local/bin on PATH
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
#   - Administrator (sudo) privileges for distro packages, Docker, and Ollama
#   - Active internet connection
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${SCRIPT_DIR}/packages.conf"

# ------------------------------------------------------------------------------
# Script Flags & Configuration
# ------------------------------------------------------------------------------
DRY_RUN=false
CHECK_ONLY=false

for arg in "$@"; do
    case "$arg" in
        --dry-run)
            DRY_RUN=true
            ;;
        --check)
            CHECK_ONLY=true
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --check     Audit installed status of all packages defined in packages.conf"
            echo "  --dry-run   Simulate the installation steps without modifying the system"
            echo "  -h, --help  Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg"
            echo "Run '$0 --help' for usage."
            exit 1
            ;;
    esac
done

# ------------------------------------------------------------------------------
# Terminal Color & Formatting Helpers
# ------------------------------------------------------------------------------
if [ -t 1 ]; then
    COLOR_RESET="\033[0m"
    COLOR_BOLD="\033[1m"
    COLOR_GREEN="\033[32m"
    COLOR_BLUE="\033[34m"
    COLOR_YELLOW="\033[33m"
    COLOR_RED="\033[31m"
    COLOR_CYAN="\033[36m"
else
    COLOR_RESET=""
    COLOR_BOLD=""
    COLOR_GREEN=""
    COLOR_BLUE=""
    COLOR_YELLOW=""
    COLOR_RED=""
    COLOR_CYAN=""
fi

log_step() {
    echo -e "\n${COLOR_BOLD}${COLOR_BLUE}==>${COLOR_RESET} ${COLOR_BOLD}$1${COLOR_RESET}"
}

log_info() {
    echo -e "  ${COLOR_CYAN}•${COLOR_RESET} $1"
}

log_success() {
    echo -e "  ${COLOR_GREEN}✔${COLOR_RESET} $1"
}

log_warn() {
    echo -e "  ${COLOR_YELLOW}⚠${COLOR_RESET} $1"
}

log_error() {
    echo -e "  ${COLOR_RED}✘${COLOR_RESET} $1"
}

# ------------------------------------------------------------------------------
# Shared Paths & Architecture
# ------------------------------------------------------------------------------
LOCAL_BIN="${HOME}/.local/bin"
LOCAL_OPT="${HOME}/.local/opt"
APPLICATIONS_DIR="${HOME}/Applications"
DESKTOP_DIR="${HOME}/.local/share/applications"
JAVA_HOME_DIR="${LOCAL_OPT}/openjdk"

HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
    x86_64)
        NODE_ARCH="x64"
        JAVA_ARCH="x64"
        K8S_ARCH="amd64"
        CMAKE_ARCH="x86_64"
        K9S_ARCH="amd64"
        RG_ARCH="x86_64-unknown-linux-musl"
        CURSOR_PLATFORM="linux-x64"
        ANTIGRAVITY_UPDATE_ARCH="x64"
        ANTIGRAVITY_STORAGE_ARCH="x64"
        MINIKUBE_ARCH="amd64"
        ;;
    aarch64|arm64)
        HOST_ARCH="aarch64"
        NODE_ARCH="arm64"
        JAVA_ARCH="aarch64"
        K8S_ARCH="arm64"
        CMAKE_ARCH="aarch64"
        K9S_ARCH="arm64"
        RG_ARCH="aarch64-unknown-linux-gnu"
        CURSOR_PLATFORM="linux-arm64"
        ANTIGRAVITY_UPDATE_ARCH="arm64"
        ANTIGRAVITY_STORAGE_ARCH="arm"
        MINIKUBE_ARCH="arm64"
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
# Helpers
# ------------------------------------------------------------------------------
parse_entry() {
    local entry="$1"
    ENTRY_ID="${entry%%|*}"
    local rest="${entry#*|}"
    ENTRY_NAME="${rest%%|*}"
    ENTRY_DESC="${rest#*|}"
}

json_string_field() {
    local json="$1"
    local field="$2"
    local match
    match="$(printf '%s' "$json" | grep -o "\"${field}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -n 1 || true)"
    if [[ -z "$match" ]]; then
        return 1
    fi
    printf '%s' "$match" | sed 's/.*"\([^"]*\)"$/\1/'
}

github_release_json() {
    local repo="$1"
    curl -fsSL \
        -H "Accept: application/vnd.github+json" \
        -A "env-linux-setup" \
        "https://api.github.com/repos/${repo}/releases/latest"
}

github_tag_name() {
    json_string_field "$1" "tag_name"
}

download_file() {
    local url="$1"
    local dest="$2"
    curl -fL --retry 3 --retry-delay 2 -o "$dest" "$url"
}

url_exists() {
    local url="$1"
    local code
    code="$(curl -fsI -o /dev/null -w '%{http_code}' -L "$url" || true)"
    [[ "$code" == "200" ]]
}

ensure_dir() {
    mkdir -p "$1"
}

append_once() {
    local file="$1"
    local marker="$2"
    local block="$3"
    touch "$file"
    if grep -qsF "$marker" "$file"; then
        return 0
    fi
    printf '\n%s\n%s\n' "$marker" "$block" >> "$file"
}

command_on_path() {
    command -v "$1" &>/dev/null
}

should_modify() {
    [[ "$CHECK_ONLY" != "true" && "$DRY_RUN" != "true" ]]
}

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

    if [[ ! -f "$MANIFEST" ]]; then
        log_error "Package manifest not found at expected location: $MANIFEST"
        exit 1
    fi

    # shellcheck disable=SC1090
    source "$MANIFEST"

    detect_pkg_family
    log_info "Operating System: $OS_PRETTY ($HOST_ARCH)"
    log_info "Package family: $PKG_FAMILY"
    log_info "Using package manifest: $MANIFEST"
}

# ------------------------------------------------------------------------------
# Bootstrap: distro packages, PATH, Flathub
# ------------------------------------------------------------------------------
bootstrap_package_names() {
    case "$PKG_FAMILY" in
        debian)
            echo "ca-certificates curl git git-lfs flatpak"
            if apt-cache show libfuse2t64 &>/dev/null; then
                echo "libfuse2t64"
            else
                echo "libfuse2"
            fi
            ;;
        fedora)
            echo "ca-certificates curl git git-lfs flatpak fuse fuse-libs"
            ;;
        arch)
            echo "ca-certificates curl git git-lfs flatpak fuse2"
            ;;
    esac
}

ensure_local_path() {
    ensure_dir "$LOCAL_BIN"
    ensure_dir "$LOCAL_OPT"
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
    log_step "Checking bootstrap packages (git, git-lfs, curl, Flatpak, FUSE)..."

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
            flatpak install --user -y flathub "$ENTRY_ID"
            log_success "$ENTRY_NAME installed."
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
# Official CLI binaries
# ------------------------------------------------------------------------------
install_node() {
    if [[ -x "${LOCAL_OPT}/node/bin/node" ]] && command_on_path node; then
        log_success "node - already installed ($(node --version 2>/dev/null || true))"
        return 0
    fi
    local index version url tmp
    index="$(curl -fsSL https://nodejs.org/dist/index.json)"
    version="$(printf '%s' "$index" | grep -o '"version":"v[^"]*"' | head -n 1 | cut -d'"' -f4)"
    if [[ -z "$version" ]]; then
        log_error "Could not determine latest Node.js version."
        exit 1
    fi
    url="https://nodejs.org/dist/${version}/node-${version}-linux-${NODE_ARCH}.tar.xz"
    tmp="$(mktemp -d)"
    download_file "$url" "${tmp}/node.tar.xz"
    rm -rf "${LOCAL_OPT}/node"
    ensure_dir "${LOCAL_OPT}/node"
    tar -xJf "${tmp}/node.tar.xz" -C "${LOCAL_OPT}/node" --strip-components=1
    ln -sfn "${LOCAL_OPT}/node/bin/node" "${LOCAL_BIN}/node"
    ln -sfn "${LOCAL_OPT}/node/bin/npm" "${LOCAL_BIN}/npm"
    ln -sfn "${LOCAL_OPT}/node/bin/npx" "${LOCAL_BIN}/npx"
    rm -rf "$tmp"
    log_success "Node.js ${version} installed."
}

install_openjdk() {
    if [[ -x "${JAVA_HOME_DIR}/bin/java" ]]; then
        log_success "openjdk - already installed ($("${JAVA_HOME_DIR}/bin/java" --version 2>&1 | head -n 1))"
        return 0
    fi
    local releases feature url tmp
    releases="$(curl -fsSL https://api.adoptium.net/v3/info/available_releases)"
    feature="$(printf '%s' "$releases" | grep -o '"most_recent_feature_release":[0-9]*' | head -n 1 | cut -d: -f2)"
    if [[ -z "$feature" ]]; then
        log_error "Could not determine latest Temurin feature release."
        exit 1
    fi
    url="https://api.adoptium.net/v3/binary/latest/${feature}/ga/linux/${JAVA_ARCH}/jdk/hotspot/normal/eclipse?project=jdk"
    tmp="$(mktemp -d)"
    download_file "$url" "${tmp}/jdk.tar.gz"
    rm -rf "$JAVA_HOME_DIR"
    ensure_dir "$JAVA_HOME_DIR"
    tar -xzf "${tmp}/jdk.tar.gz" -C "$JAVA_HOME_DIR" --strip-components=1
    ln -sfn "${JAVA_HOME_DIR}/bin/java" "${LOCAL_BIN}/java"
    ln -sfn "${JAVA_HOME_DIR}/bin/javac" "${LOCAL_BIN}/javac"
    rm -rf "$tmp"
    log_success "OpenJDK (Temurin ${feature}) installed."
}

install_cmake() {
    if command_on_path cmake && [[ -x "${LOCAL_OPT}/cmake/bin/cmake" || "$(command -v cmake)" == "${LOCAL_BIN}/cmake" ]]; then
        log_success "cmake - already installed ($(cmake --version 2>/dev/null | head -n 1))"
        return 0
    fi
    local json tag version url tmp
    json="$(github_release_json Kitware/CMake)"
    tag="$(github_tag_name "$json")"
    version="${tag#v}"
    url="https://github.com/Kitware/CMake/releases/download/${tag}/cmake-${version}-linux-${CMAKE_ARCH}.tar.gz"
    tmp="$(mktemp -d)"
    download_file "$url" "${tmp}/cmake.tar.gz"
    rm -rf "${LOCAL_OPT}/cmake"
    ensure_dir "${LOCAL_OPT}/cmake"
    tar -xzf "${tmp}/cmake.tar.gz" -C "${LOCAL_OPT}/cmake" --strip-components=1
    ln -sfn "${LOCAL_OPT}/cmake/bin/cmake" "${LOCAL_BIN}/cmake"
    ln -sfn "${LOCAL_OPT}/cmake/bin/ccmake" "${LOCAL_BIN}/ccmake"
    ln -sfn "${LOCAL_OPT}/cmake/bin/ctest" "${LOCAL_BIN}/ctest"
    ln -sfn "${LOCAL_OPT}/cmake/bin/cpack" "${LOCAL_BIN}/cpack"
    rm -rf "$tmp"
    log_success "CMake ${version} installed."
}

install_kubectl() {
    if command_on_path kubectl && [[ "$(command -v kubectl)" == "${LOCAL_BIN}/kubectl" || -x "${LOCAL_BIN}/kubectl" ]]; then
        log_success "kubectl - already installed ($(kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null | head -n 1))"
        return 0
    fi
    local version
    version="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
    download_file "https://dl.k8s.io/release/${version}/bin/linux/${K8S_ARCH}/kubectl" "${LOCAL_BIN}/kubectl"
    chmod +x "${LOCAL_BIN}/kubectl"
    log_success "kubectl ${version} installed."
}

install_minikube() {
    if command_on_path minikube && [[ -x "${LOCAL_BIN}/minikube" ]]; then
        log_success "minikube - already installed ($(minikube version 2>/dev/null | head -n 1))"
        return 0
    fi
    download_file "https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-${MINIKUBE_ARCH}" "${LOCAL_BIN}/minikube"
    chmod +x "${LOCAL_BIN}/minikube"
    log_success "minikube installed."
}

install_helm() {
    if command_on_path helm && [[ -x "${LOCAL_BIN}/helm" ]]; then
        log_success "helm - already installed ($(helm version --short 2>/dev/null || true))"
        return 0
    fi
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | HELM_INSTALL_DIR="$LOCAL_BIN" USE_SUDO=false bash
    log_success "Helm installed."
}

install_k9s() {
    if command_on_path k9s && [[ -x "${LOCAL_BIN}/k9s" ]]; then
        log_success "k9s - already installed ($(k9s version 2>/dev/null | head -n 1 || true))"
        return 0
    fi
    local json tag version url tmp
    json="$(github_release_json derailed/k9s)"
    tag="$(github_tag_name "$json")"
    version="${tag#v}"
    url="https://github.com/derailed/k9s/releases/download/${tag}/k9s_Linux_${K9S_ARCH}.tar.gz"
    if [[ "$K9S_ARCH" == "amd64" ]] && ! url_exists "$url"; then
        url="https://github.com/derailed/k9s/releases/download/${tag}/k9s_Linux_x86_64.tar.gz"
    fi
    tmp="$(mktemp -d)"
    download_file "$url" "${tmp}/k9s.tar.gz"
    tar -xzf "${tmp}/k9s.tar.gz" -C "$tmp"
    install -m 0755 "${tmp}/k9s" "${LOCAL_BIN}/k9s"
    rm -rf "$tmp"
    log_success "k9s ${version} installed."
}

install_ripgrep() {
    if command_on_path rg && [[ -x "${LOCAL_BIN}/rg" ]]; then
        log_success "ripgrep - already installed ($(rg --version 2>/dev/null | head -n 1))"
        return 0
    fi
    local json tag version url tmp
    json="$(github_release_json BurntSushi/ripgrep)"
    tag="$(github_tag_name "$json")"
    version="${tag#v}"
    url="https://github.com/BurntSushi/ripgrep/releases/download/${tag}/ripgrep-${version}-${RG_ARCH}.tar.gz"
    tmp="$(mktemp -d)"
    download_file "$url" "${tmp}/rg.tar.gz"
    tar -xzf "${tmp}/rg.tar.gz" -C "$tmp"
    local rg_bin
    rg_bin="$(find "$tmp" -type f -name rg | head -n 1)"
    if [[ -z "$rg_bin" ]]; then
        log_error "ripgrep archive did not contain an rg binary."
        exit 1
    fi
    install -m 0755 "$rg_bin" "${LOCAL_BIN}/rg"
    rm -rf "$tmp"
    log_success "ripgrep ${version} installed."
}

cli_is_installed() {
    local id="$1"
    case "$id" in
        node) [[ -x "${LOCAL_OPT}/node/bin/node" ]] && command_on_path node ;;
        openjdk) [[ -x "${JAVA_HOME_DIR}/bin/java" ]] ;;
        cmake) command_on_path cmake ;;
        kubectl) command_on_path kubectl ;;
        minikube) command_on_path minikube ;;
        helm) command_on_path helm ;;
        k9s) command_on_path k9s ;;
        ripgrep) command_on_path rg ;;
        *) return 1 ;;
    esac
}

install_cli_binaries() {
    log_step "Installing official CLI binaries..."
    local entry
    for entry in "${CLI_BINARIES[@]}"; do
        parse_entry "$entry"
        if cli_is_installed "$ENTRY_ID"; then
            log_success "$ENTRY_ID - $ENTRY_DESC (Installed)"
            continue
        fi
        if [[ "$CHECK_ONLY" == "true" ]]; then
            log_warn "$ENTRY_ID - $ENTRY_DESC (Not installed)"
            continue
        fi
        if [[ "$DRY_RUN" == "true" ]]; then
            log_warn "[Dry Run] Would install official binary: $ENTRY_ID ($ENTRY_DESC)"
            continue
        fi
        case "$ENTRY_ID" in
            node) install_node ;;
            openjdk) install_openjdk ;;
            cmake) install_cmake ;;
            kubectl) install_kubectl ;;
            minikube) install_minikube ;;
            helm) install_helm ;;
            k9s) install_k9s ;;
            ripgrep) install_ripgrep ;;
            *)
                log_error "Unknown CLI binary: $ENTRY_ID"
                exit 1
                ;;
        esac
    done
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
        log_success "Ollama - already installed ($(ollama --version 2>/dev/null || true))"
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
    curl -fC sSL https://zed.dev/install.sh | sh
    log_success "Zed installed."
}

# ------------------------------------------------------------------------------
# Java environment
# ------------------------------------------------------------------------------
configure_java() {
    log_step "Configuring Java Environment..."

    if [[ ! -x "${JAVA_HOME_DIR}/bin/java" ]]; then
        if [[ "$CHECK_ONLY" == "true" ]]; then
            log_warn "Java (OpenJDK) is not installed."
        elif [[ "$DRY_RUN" == "true" ]]; then
            log_info "[Dry Run] Java environment will be configured after Temurin installation."
        fi
        return 0
    fi

    local marker="# env-setup: OpenJDK"
    local block
    block="$(cat << EOF
export JAVA_HOME="${JAVA_HOME_DIR}"
export PATH="\$JAVA_HOME/bin:\$PATH"
EOF
)"

    if should_modify; then
        append_once "$HOME/.bashrc" "$marker" "$block"
        if [[ -f "$HOME/.zshrc" ]]; then
            append_once "$HOME/.zshrc" "$marker" "$block"
        fi
        export JAVA_HOME="$JAVA_HOME_DIR"
        export PATH="${JAVA_HOME}/bin:${PATH}"
        log_success "JAVA_HOME=${JAVA_HOME_DIR}"
        log_success "Java active: $("${JAVA_HOME_DIR}/bin/java" --version 2>&1 | head -n 1)"
    else
        log_info "Java present at ${JAVA_HOME_DIR} (shell rc will be updated during install)"
    fi
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

  CLI Tools:
    - Binaries are on PATH via ${LOCAL_BIN} (reload the shell or source ~/.bashrc)
    - Node.js: node -v && npm -v
    - Java: java --version && javac --version
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
    echo -e "${COLOR_BOLD}${COLOR_CYAN}======================================================"
    echo -e "       Linux Development Environment Setup"
    echo -e "======================================================${COLOR_RESET}"

    if [[ "$CHECK_ONLY" == "true" ]]; then
        echo -e "${COLOR_YELLOW}Running in CHECK-ONLY mode (no changes will be made)...${COLOR_RESET}"
    elif [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${COLOR_YELLOW}Running in DRY-RUN mode (simulating actions)...${COLOR_RESET}"
    fi

    verify_environment
    ensure_bootstrap
    audit_distro_packages
    install_flatpaks
    install_appimages
    install_cli_binaries
    install_docker_engine
    install_ollama
    install_zed
    configure_java
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
