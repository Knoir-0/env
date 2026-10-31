#!/usr/bin/env bash
# ==============================================================================
# macOS Development Environment Setup Script
# ==============================================================================
# Description:
#   Automates the setup of a clean macOS development workstation by:
#     1. Ensuring Apple Xcode Command Line Tools are installed
#     2. Installing Homebrew (if missing) and configuring shell environment
#     3. Directly executing 'brew bundle' against the companion Brewfile
#     4. Configuring mise (Node.js, Java, Python versions from shared/mise.toml)
#     5. Providing post-installation guidance and macOS permission reminders
#
# Usage:
#   ./macos/setup_mac.sh             # Full interactive / automated installation
#   ./macos/setup_mac.sh --check     # Check status of all applications without installing
#   ./macos/setup_mac.sh --dry-run   # Preview actions without executing install commands
#   ./macos/setup_mac.sh --help      # Show help menu
#
# Requirements:
#   - macOS 13+ (Ventura, Sonoma, Sequoia, or later)
#   - Administrator (sudo) privileges for initial Xcode CLI tools / Homebrew setup
#   - Active internet connection
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BREWFILE="${SCRIPT_DIR}/Brewfile"

# Shared flags, logging, and Homebrew helpers (also provides SHARED_BREWFILE)
# shellcheck source=../shared/lib.sh
source "${SCRIPT_DIR}/../shared/lib.sh"
parse_flags "Brewfile and shared/Brewfile" "$@"

# ------------------------------------------------------------------------------
# Environment & OS Verification
# ------------------------------------------------------------------------------
verify_environment() {
    log_step "Verifying Environment..."

    if [[ "$(uname -s)" != "Darwin" ]]; then
        log_error "This script is designed for macOS (Darwin). Current OS: $(uname -s)"
        exit 1
    fi

    local f
    for f in "$BREWFILE" "$SHARED_BREWFILE" "$SHARED_MISE_CONFIG"; do
        if [[ ! -f "$f" ]]; then
            log_error "Required manifest not found at expected location: $f"
            exit 1
        fi
    done

    local arch
    arch="$(uname -m)"
    local os_version
    os_version="$(sw_vers -productVersion)"
    log_info "Operating System: macOS $os_version ($arch)"

    if [[ "$arch" == "arm64" ]]; then
        HOMEBREW_PREFIX="/opt/homebrew"
    else
        HOMEBREW_PREFIX="/usr/local"
    fi
    log_info "Homebrew Prefix target: $HOMEBREW_PREFIX"
    log_info "Using package manifests: $SHARED_BREWFILE, $BREWFILE"
}

# ------------------------------------------------------------------------------
# Xcode Command Line Tools
# ------------------------------------------------------------------------------
ensure_xcode_tools() {
    log_step "Checking Apple Xcode Command Line Tools..."

    if xcode-select -p &>/dev/null; then
        log_success "Xcode Command Line Tools already installed ($(xcode-select -p))"
    else
        if [[ "$CHECK_ONLY" == "true" ]]; then
            log_warn "Xcode Command Line Tools: NOT INSTALLED"
            return 0
        fi

        log_info "Installing Xcode Command Line Tools..."
        if [[ "$DRY_RUN" == "true" ]]; then
            log_warn "[Dry Run] Would run: xcode-select --install"
        else
            xcode-select --install
            echo "Press any key once the Xcode Command Line Tools GUI installation finishes..."
            read -r -n 1
        fi
    fi
}

# ------------------------------------------------------------------------------
# Homebrew Installation & Setup
# ------------------------------------------------------------------------------
ensure_homebrew() {
    log_step "Checking Homebrew Installation..."

    # Check if brew binary is available in PATH or at the standard location
    if command -v brew &>/dev/null; then
        log_success "Homebrew is available in PATH: $(which brew)"
    elif [[ -x "$HOMEBREW_PREFIX/bin/brew" ]]; then
        log_info "Homebrew found at $HOMEBREW_PREFIX/bin/brew, activating for this session..."
        eval "$("$HOMEBREW_PREFIX/bin/brew" shellenv)"
        log_success "Homebrew activated."
    else
        if [[ "$CHECK_ONLY" == "true" ]]; then
            log_error "Homebrew: NOT INSTALLED"
            return 0
        fi

        log_info "Homebrew not found. Installing via official script..."
        if [[ "$DRY_RUN" == "true" ]]; then
            log_warn "[Dry Run] Would execute Homebrew installation curl script."
        else
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            eval "$("$HOMEBREW_PREFIX/bin/brew" shellenv)"
        fi
    fi

    # Ensure Homebrew is configured in ~/.zprofile / ~/.zshrc
    local shell_rc="$HOME/.zprofile"
    [[ ! -f "$shell_rc" && -f "$HOME/.zshrc" ]] && shell_rc="$HOME/.zshrc"
    persist_brew_shellenv "$HOMEBREW_PREFIX/bin/brew" "$shell_rc"

    # Update Homebrew indices
    if [[ "$CHECK_ONLY" != "true" && "$DRY_RUN" != "true" ]]; then
        log_info "Updating Homebrew metadata..."
        brew update --quiet || true
    fi
}

# ------------------------------------------------------------------------------
# Audit Brewfile Packages (For --check and --dry-run)
# ------------------------------------------------------------------------------
audit_brewfile_packages() {
    log_step "Auditing packages defined in Brewfile..."

    echo -e "\n  ${COLOR_BOLD}CLI Tools & Formulae:${COLOR_RESET}"
    audit_brew_formulae "$SHARED_BREWFILE" "$BREWFILE"

    local installed_casks
    installed_casks="$(brew list --cask 2>/dev/null || true)"
    local current_comment=""
    local current_category="General"

    echo -e "\n  ${COLOR_BOLD}GUI Applications & Casks:${COLOR_RESET}"
    current_comment=""
    local printed_category=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [[ -z "$line" ]] && continue

        if [[ "$line" =~ ^#[[:space:]]*-+[[:space:]]*(.*)[[:space:]]*-+ ]]; then
            current_category="$(echo "${BASH_REMATCH[1]}" | sed -e 's/^[[:space:]-]*//' -e 's/[[:space:]-]*$//')"
            continue
        elif [[ "$line" =~ ^#[[:space:]]*(.*) ]]; then
            current_comment="${BASH_REMATCH[1]}"
            continue
        fi

        if [[ "$line" =~ ^cask[[:space:]]+\"([^\"]+)\" ]]; then
            local cask="${BASH_REMATCH[1]}"
            local desc="${current_comment:-$cask}"

            if [[ "$current_category" != "$printed_category" ]]; then
                printed_category="$current_category"
                echo -e "\n  ${COLOR_BOLD}[$printed_category]${COLOR_RESET}"
            fi

            local is_installed=false
            if echo "$installed_casks" | grep -Fxq "$cask"; then
                is_installed=true
            elif [[ "$cask" == "docker-desktop" ]] && echo "$installed_casks" | grep -Fxq "docker"; then
                is_installed=true
            else
                # Check /Applications directory for known app bundles
                case "$cask" in
                    docker-desktop) [[ -d "/Applications/Docker.app" ]] && is_installed=true ;;
                    raspberry-pi-imager) [[ -d "/Applications/Raspberry Pi Imager.app" ]] && is_installed=true ;;
                    cursor) [[ -d "/Applications/Cursor.app" ]] && is_installed=true ;;
                    zed) [[ -d "/Applications/Zed.app" ]] && is_installed=true ;;
                    visual-studio-code) [[ -d "/Applications/Visual Studio Code.app" ]] && is_installed=true ;;
                    github) [[ -d "/Applications/GitHub Desktop.app" ]] && is_installed=true ;;
                    ollama-app) [[ -d "/Applications/Ollama.app" ]] && is_installed=true ;;
                    antigravity) [[ -d "/Applications/Antigravity.app" ]] && is_installed=true ;;
                    firefox) [[ -d "/Applications/Firefox.app" ]] && is_installed=true ;;
                    freecad) [[ -d "/Applications/FreeCAD.app" ]] && is_installed=true ;;
                    orcaslicer) [[ -d "/Applications/OrcaSlicer.app" ]] && is_installed=true ;;
                    blender) [[ -d "/Applications/Blender.app" ]] && is_installed=true ;;
                    libreoffice) [[ -d "/Applications/LibreOffice.app" ]] && is_installed=true ;;
                    maccy) [[ -d "/Applications/Maccy.app" ]] && is_installed=true ;;
                    scroll-reverser) [[ -d "/Applications/Scroll Reverser.app" ]] && is_installed=true ;;
                    caffeine) [[ -d "/Applications/Caffeine.app" ]] && is_installed=true ;;
                    freelens) [[ -d "/Applications/Freelens.app" ]] && is_installed=true ;;
                    beekeeper-studio) [[ -d "/Applications/Beekeeper Studio.app" ]] && is_installed=true ;;
                    insomnia) [[ -d "/Applications/Insomnia.app" ]] && is_installed=true ;;
                    *) [[ -d "/Applications/${cask}.app" || -d "$HOME/Applications/${cask}.app" ]] && is_installed=true ;;
                esac
            fi

            if [[ "$is_installed" == "true" ]]; then
                log_success "$cask - $desc (Installed)"
            else
                if [[ "$CHECK_ONLY" == "true" ]]; then
                    log_warn "$cask - $desc (Not installed)"
                elif [[ "$DRY_RUN" == "true" ]]; then
                    log_warn "[Dry Run] Would install cask: $cask ($desc)"
                fi
            fi
            current_comment=""
        fi
    done < "$BREWFILE"
}

# ------------------------------------------------------------------------------
# Configure mise (Node.js, Java, Python versions from shared/mise.toml)
# ------------------------------------------------------------------------------
configure_mise() {
    setup_mise
    add_mise_activation zsh "$HOME/.zshrc"
    add_mise_activation zsh "$HOME/.zprofile" --shims
}

# ------------------------------------------------------------------------------
# Post-Installation Notes & System Permissions
# ------------------------------------------------------------------------------
show_post_install_notes() {
    log_step "macOS Permissions & Configuration Notes"

    cat << 'EOF'
  The following installed utilities require macOS Accessibility or System permissions:
  1. Maccy (Clipboard Manager):
     - Go to: System Settings -> Privacy & Security -> Accessibility
     - Enable: Maccy
  2. Scroll Reverser:
     - Go to: System Settings -> Privacy & Security -> Accessibility
     - Enable: Scroll Reverser

  CLI Tools Quickstart:
  - Runtimes (mise): open a new terminal, then run 'mise ls' to see active versions.
    * Node.js: 'node -v' / 'npm -v'   Java: 'java --version'   Python: 'python --version'
    * Defaults live in shared/mise.toml; pin per project with 'mise use node@22'
    * Update "latest" runtimes with 'mise upgrade'
  - Docker: Launch Docker.app to initialize the container daemon.
  - Kubernetes: Run 'kubectl version --client' to verify CLI.
    * Enable Kubernetes in Docker Desktop: Settings -> Kubernetes -> Enable Kubernetes
    * Or start a local minikube cluster: run 'minikube start'
    * Launch 'k9s' for real-time cluster dashboard
  - Ollama: Run 'ollama run llama3' to pull and test your first model.
  - Code Search: Run 'rg <pattern>' for blazing-fast recursive code search.
EOF
}

# ------------------------------------------------------------------------------
# Main Execution Flow
# ------------------------------------------------------------------------------
main() {
    print_banner "macOS Development Environment Setup"

    verify_environment
    ensure_xcode_tools
    ensure_homebrew

    if [[ "$CHECK_ONLY" == "true" ]]; then
        audit_brewfile_packages
        configure_mise
        echo ""
        log_info "Audit check complete."
    elif [[ "$DRY_RUN" == "true" ]]; then
        audit_brewfile_packages
        configure_mise
        echo ""
        log_info "Dry-run simulation complete."
    else
        run_brew_bundle "$SHARED_BREWFILE" "$BREWFILE"
        configure_mise
        show_post_install_notes
        echo ""
        log_success "All macOS applications and development tools configured successfully!"
    fi
}

main "$@"
