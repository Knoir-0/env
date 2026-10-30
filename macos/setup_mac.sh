#!/usr/bin/env bash
# ==============================================================================
# macOS Development Environment Setup Script
# ==============================================================================
# Description:
#   Automates the setup of a clean macOS development workstation by:
#     1. Ensuring Apple Xcode Command Line Tools are installed
#     2. Installing Homebrew (if missing) and configuring shell environment
#     3. Directly executing 'brew bundle' against the companion Brewfile
#     4. Configuring OpenJDK Java symlinks and environment variables
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
            echo "  --check     Audit installed status of all packages defined in Brewfile"
            echo "  --dry-run   Simulate the installation steps without modifying system"
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
# Environment & OS Verification
# ------------------------------------------------------------------------------
verify_environment() {
    log_step "Verifying Environment..."

    if [[ "$(uname -s)" != "Darwin" ]]; then
        log_error "This script is designed for macOS (Darwin). Current OS: $(uname -s)"
        exit 1
    fi

    if [[ ! -f "$BREWFILE" ]]; then
        log_error "Brewfile not found at expected location: $BREWFILE"
        exit 1
    fi

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
    log_info "Using package manifest: $BREWFILE"
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

    local shellenv_line="eval \"\$($HOMEBREW_PREFIX/bin/brew shellenv)\""
    if ! grep -qs "brew shellenv" "$shell_rc" 2>/dev/null; then
        if [[ "$DRY_RUN" == "true" || "$CHECK_ONLY" == "true" ]]; then
            log_info "Homebrew shellenv missing from $shell_rc (will be appended during install)"
        else
            log_info "Configuring Homebrew shellenv in $shell_rc..."
            echo "" >> "$shell_rc"
            echo "# Load Homebrew environment" >> "$shell_rc"
            echo "$shellenv_line" >> "$shell_rc"
            log_success "Added Homebrew to $shell_rc"
        fi
    fi

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

    local installed_formulae
    installed_formulae="$(brew list --formula 2>/dev/null || true)"
    local installed_casks
    installed_casks="$(brew list --cask 2>/dev/null || true)"

    local current_comment=""
    local current_category="General"

    echo -e "\n  ${COLOR_BOLD}CLI Tools & Formulae:${COLOR_RESET}"
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [[ -z "$line" ]] && continue

        if [[ "$line" =~ ^#[[:space:]]*---[[:space:]]*(.*)[[:space:]]*--- ]]; then
            continue
        elif [[ "$line" =~ ^#[[:space:]]*(.*) ]]; then
            current_comment="${BASH_REMATCH[1]}"
            continue
        fi

        if [[ "$line" =~ ^brew[[:space:]]+\"([^\"]+)\" ]]; then
            local formula="${BASH_REMATCH[1]}"
            local desc="${current_comment:-$formula}"
            if echo "$installed_formulae" | grep -Fxq "$formula"; then
                log_success "$formula - $desc (Installed)"
            else
                if [[ "$CHECK_ONLY" == "true" ]]; then
                    log_warn "$formula - $desc (Not installed)"
                elif [[ "$DRY_RUN" == "true" ]]; then
                    log_warn "[Dry Run] Would install formula: $formula ($desc)"
                fi
            fi
            current_comment=""
        fi
    done < "$BREWFILE"

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
# Execute Homebrew Bundle
# ------------------------------------------------------------------------------
run_brew_bundle() {
    log_step "Executing 'brew bundle' using $BREWFILE..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[Dry Run] Skipping bundle execution."
        return 0
    fi

    brew bundle --file="$BREWFILE"
    log_success "All packages from Brewfile installed/verified."
}

# ------------------------------------------------------------------------------
# Configure Java (OpenJDK) Environment & Symlinks
# ------------------------------------------------------------------------------
configure_java() {
    log_step "Configuring Java Environment..."

    local openjdk_path="$HOMEBREW_PREFIX/opt/openjdk"

    if brew list --formula 2>/dev/null | grep -Fxq "openjdk" || [[ -d "$openjdk_path" ]]; then
        local jvm_dir="/Library/Java/JavaVirtualMachines"

        # 1. macOS system wrapper symlink so /usr/libexec/java_home recognizes OpenJDK
        if [[ -d "$openjdk_path/libexec/openjdk.jdk" ]]; then
            if [[ -L "$jvm_dir/openjdk.jdk" ]] && [[ "$(readlink "$jvm_dir/openjdk.jdk")" == "$openjdk_path/libexec/openjdk.jdk" ]]; then
                log_success "Java system symlink active ($jvm_dir/openjdk.jdk)"
            else
                if [[ "$CHECK_ONLY" == "true" ]]; then
                    log_warn "Java system symlink missing in $jvm_dir/openjdk.jdk"
                elif [[ "$DRY_RUN" == "true" ]]; then
                    log_warn "[Dry Run] Would create symlink: sudo ln -sfn \"$openjdk_path/libexec/openjdk.jdk\" \"$jvm_dir/openjdk.jdk\""
                else
                    log_info "Creating JDK symlink for macOS system wrappers (requires sudo)..."
                    sudo ln -sfn "$openjdk_path/libexec/openjdk.jdk" "$jvm_dir/openjdk.jdk" 2>/dev/null || {
                        log_warn "Could not create $jvm_dir/openjdk.jdk (requires sudo). System wrappers might need manual linking."
                    }
                fi
            fi
        fi

        # 2. Add OpenJDK to shell PATH and set JAVA_HOME in ~/.zprofile / ~/.zshrc
        local shell_rc="$HOME/.zprofile"
        [[ ! -f "$shell_rc" && -f "$HOME/.zshrc" ]] && shell_rc="$HOME/.zshrc"

        if ! grep -qs "openjdk/bin" "$shell_rc" 2>/dev/null; then
            if [[ "$CHECK_ONLY" == "true" || "$DRY_RUN" == "true" ]]; then
                log_info "Java PATH & JAVA_HOME missing from $shell_rc"
            else
                log_info "Adding Java environment variables to $shell_rc..."
                {
                    echo ""
                    echo "# OpenJDK configuration"
                    echo "export PATH=\"$openjdk_path/bin:\$PATH\""
                    echo "export JAVA_HOME=\"\$(/usr/libexec/java_home 2>/dev/null || echo '$openjdk_path')\""
                } >> "$shell_rc"
                log_success "Java environment variables added to $shell_rc"
            fi
        fi

        # Export for current session
        export PATH="$openjdk_path/bin:$PATH"
        export JAVA_HOME="$(/usr/libexec/java_home 2>/dev/null || echo "$openjdk_path")"
        if command -v java &>/dev/null; then
            log_success "Java active: $(java --version 2>&1 | head -n 1)"
        fi
    else
        if [[ "$CHECK_ONLY" == "true" ]]; then
            log_warn "Java (OpenJDK) is not installed."
        elif [[ "$DRY_RUN" == "true" ]]; then
            log_info "[Dry Run] Java environment will be configured after openjdk formula installation."
        fi
    fi
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
  - Node.js: Run 'node -v' and 'npm -v' to verify latest stable Node environment.
  - Java: Run 'java --version' and 'javac --version' to verify latest stable OpenJDK.
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
    echo -e "${COLOR_BOLD}${COLOR_CYAN}======================================================"
    echo -e "       macOS Development Environment Setup"
    echo -e "======================================================${COLOR_RESET}"

    if [[ "$CHECK_ONLY" == "true" ]]; then
        echo -e "${COLOR_YELLOW}Running in CHECK-ONLY mode (no changes will be made)...${COLOR_RESET}"
    elif [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${COLOR_YELLOW}Running in DRY-RUN mode (simulating actions)...${COLOR_RESET}"
    fi

    verify_environment
    ensure_xcode_tools
    ensure_homebrew

    if [[ "$CHECK_ONLY" == "true" ]]; then
        audit_brewfile_packages
        configure_java
        echo ""
        log_info "Audit check complete."
    elif [[ "$DRY_RUN" == "true" ]]; then
        audit_brewfile_packages
        configure_java
        echo ""
        log_info "Dry-run simulation complete."
    else
        run_brew_bundle
        configure_java
        show_post_install_notes
        echo ""
        log_success "All macOS applications and development tools configured successfully!"
    fi
}

main "$@"
