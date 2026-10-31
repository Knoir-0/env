#!/usr/bin/env bash
# ==============================================================================
# Shared library for macos/setup_mac.sh and linux/setup_linux.sh
# ==============================================================================
# Source this file; do not execute it directly. It provides:
#   - CLI flag parsing (--check, --dry-run, --help) -> DRY_RUN / CHECK_ONLY
#   - Terminal color & logging helpers
#   - Generic filesystem / network / manifest helpers
#   - Homebrew helpers shared by both platforms (shellenv, bundle, audit)
# ==============================================================================

SHARED_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_BREWFILE="${SHARED_DIR}/Brewfile"

# ------------------------------------------------------------------------------
# Script Flags & Configuration
# ------------------------------------------------------------------------------
DRY_RUN=false
CHECK_ONLY=false

# Usage: parse_flags "<manifest description>" "$@"
parse_flags() {
    local manifest_desc="$1"
    shift
    local arg
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
                echo "  --check     Audit installed status of all packages defined in ${manifest_desc}"
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
}

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

print_banner() {
    echo -e "${COLOR_BOLD}${COLOR_CYAN}======================================================"
    echo -e "       $1"
    echo -e "======================================================${COLOR_RESET}"

    if [[ "$CHECK_ONLY" == "true" ]]; then
        echo -e "${COLOR_YELLOW}Running in CHECK-ONLY mode (no changes will be made)...${COLOR_RESET}"
    elif [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${COLOR_YELLOW}Running in DRY-RUN mode (simulating actions)...${COLOR_RESET}"
    fi
}

# ------------------------------------------------------------------------------
# Generic Helpers
# ------------------------------------------------------------------------------
# Parse a manifest entry of the form id|display_name|description
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
# Homebrew Helpers (macOS + Linux)
# ------------------------------------------------------------------------------
# Add `brew shellenv` to the given rc files (idempotent).
# Usage: persist_brew_shellenv <brew_bin> <rc_file>...
persist_brew_shellenv() {
    local brew_bin="$1"
    shift
    local marker="# env-setup: Homebrew"
    local block="eval \"\$(${brew_bin} shellenv)\""
    local rc
    for rc in "$@"; do
        if grep -qs "brew shellenv" "$rc" 2>/dev/null; then
            continue
        fi
        if should_modify; then
            append_once "$rc" "$marker" "$block"
            log_success "Added Homebrew shellenv to $rc"
        else
            log_info "Homebrew shellenv missing from $rc (will be appended during install)"
        fi
    done
}

# Report install status of every `brew "..."` formula in the given Brewfiles.
# Usage: audit_brew_formulae <Brewfile>...
audit_brew_formulae() {
    local installed_formulae
    installed_formulae="$(brew list --formula 2>/dev/null || true)"

    local file line formula desc current_comment
    for file in "$@"; do
        current_comment=""
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
            [[ -z "$line" ]] && continue

            if [[ "$line" =~ ^#[[:space:]]*-+ ]]; then
                continue
            elif [[ "$line" =~ ^#[[:space:]]*(.*) ]]; then
                current_comment="${BASH_REMATCH[1]}"
                continue
            fi

            if [[ "$line" =~ ^brew[[:space:]]+\"([^\"]+)\" ]]; then
                formula="${BASH_REMATCH[1]}"
                desc="${current_comment:-$formula}"
                if echo "$installed_formulae" | grep -Fxq "${formula##*/}"; then
                    log_success "$formula - $desc (Installed)"
                elif [[ "$CHECK_ONLY" == "true" ]]; then
                    log_warn "$formula - $desc (Not installed)"
                elif [[ "$DRY_RUN" == "true" ]]; then
                    log_warn "[Dry Run] Would install formula: $formula ($desc)"
                fi
                current_comment=""
            fi
        done < "$file"
    done
}

# Run `brew bundle` against each Brewfile (skipped in dry-run / check mode).
# Usage: run_brew_bundle <Brewfile>...
run_brew_bundle() {
    local file
    for file in "$@"; do
        log_step "Executing 'brew bundle' using $file..."
        if ! should_modify; then
            log_info "[Dry Run] Skipping bundle execution."
            continue
        fi
        brew bundle --file="$file"
        log_success "All packages from $(basename "$(dirname "$file")")/$(basename "$file") installed/verified."
    done
}

# ------------------------------------------------------------------------------
# mise Helpers (language runtime versions; mise itself comes from shared/Brewfile)
# ------------------------------------------------------------------------------
SHARED_MISE_CONFIG="${SHARED_DIR}/mise.toml"
MISE_CONFIG_PATH="${XDG_CONFIG_HOME:-$HOME/.config}/mise/config.toml"

# Add mise activation to a shell rc file (idempotent).
#   Interactive rc (.zshrc/.bashrc): full activation (PATH + env on every prompt).
#   Login rc (.zprofile/.profile):   --shims, so GUI apps and IDEs find tools too.
# Uses the absolute mise path, so it works even if this rc is read before the
# one that sets up Homebrew.
# Usage: add_mise_activation <bash|zsh> <rc_file> [--shims]
add_mise_activation() {
    local shell_name="$1"
    local rc="$2"
    local shims="${3:-}"

    local marker="# env-setup: mise"
    [[ -n "$shims" ]] && marker="# env-setup: mise shims"

    if grep -qsF "$marker" "$rc" 2>/dev/null; then
        log_success "mise activation${shims:+ (shims)} present in $rc"
    elif should_modify; then
        command_on_path mise || return 0
        local mise_bin
        mise_bin="$(command -v mise)"
        local block="eval \"\$(${mise_bin} activate ${shell_name}${shims:+ $shims})\""
        append_once "$rc" "$marker" "$block"
        log_success "Added mise activation${shims:+ (shims)} to $rc"
    elif [[ "$DRY_RUN" == "true" ]]; then
        log_warn "[Dry Run] Would add mise activation${shims:+ (shims)} to $rc"
    else
        log_info "mise activation${shims:+ (shims)} missing from $rc (will be appended during install)"
    fi
}

# Link shared/mise.toml as the global mise config, then install (or audit)
# the runtimes it lists. Call add_mise_activation separately per rc file.
setup_mise() {
    log_step "Configuring mise (Node.js, Java, Python)..."

    if [[ -L "$MISE_CONFIG_PATH" && "$(readlink "$MISE_CONFIG_PATH")" == "$SHARED_MISE_CONFIG" ]]; then
        log_success "Global config linked: $MISE_CONFIG_PATH -> shared/mise.toml"
    elif should_modify; then
        ensure_dir "$(dirname "$MISE_CONFIG_PATH")"
        if [[ -e "$MISE_CONFIG_PATH" || -L "$MISE_CONFIG_PATH" ]]; then
            local backup
            backup="${MISE_CONFIG_PATH}.bak.$(date +%Y%m%d%H%M%S)"
            mv "$MISE_CONFIG_PATH" "$backup"
            log_warn "Existing mise config moved to $backup"
        fi
        ln -s "$SHARED_MISE_CONFIG" "$MISE_CONFIG_PATH"
        log_success "Linked $MISE_CONFIG_PATH -> shared/mise.toml"
    elif [[ "$DRY_RUN" == "true" ]]; then
        log_warn "[Dry Run] Would link $MISE_CONFIG_PATH -> shared/mise.toml"
    else
        log_warn "Global config not linked ($MISE_CONFIG_PATH -> shared/mise.toml)"
    fi

    if ! command_on_path mise; then
        if should_modify; then
            log_error "mise not found on PATH; it should have been installed by shared/Brewfile."
            exit 1
        elif [[ "$DRY_RUN" == "true" ]]; then
            log_warn "[Dry Run] Would run 'mise install' for tools in shared/mise.toml (node, java, python)"
        else
            log_warn "mise: NOT INSTALLED (will be installed via shared/Brewfile)"
        fi
        return 0
    fi

    # Run from $HOME so a project mise.toml in the current directory isn't picked up.
    if should_modify; then
        mise trust "$SHARED_MISE_CONFIG" >/dev/null 2>&1 || true
        log_info "Installing runtimes from shared/mise.toml (first run downloads each one)..."
        (cd "$HOME" && mise install)
        log_success "mise runtimes installed."
    else
        if [[ "$DRY_RUN" == "true" ]]; then
            log_warn "[Dry Run] Would run 'mise install' for tools in shared/mise.toml"
        fi
        if [[ -L "$MISE_CONFIG_PATH" ]]; then
            (cd "$HOME" && mise ls --current 2>/dev/null | sed 's/^/    /') || true
        fi
    fi
}
