#!/bin/bash

# Kodachi Binary Installation Script (NO SUDO REQUIRED)
# ======================================================
#
# SPDX-License-Identifier: LicenseRef-Kodachi-SAN-1.0
# Copyright (c) 2013-2026 Warith Al Maawali
#
# This file is part of Kodachi OS.
# For full license terms, see LICENSE.md or visit:
# http://kodachi.cloud/wiki/bina/license.html
#
# Commercial or organizational use requires a written license.
# Contact: warith@digi77.com
#
# Author: Warith Al Maawali
# Version: 9.0.1
# Last updated: 2026-02-16
#
# Description:
# This script downloads and installs Kodachi security tool binaries
# WITHOUT requiring sudo or root access. It installs everything to
# the user's home directory by default (~/dashboard/hooks).
# Supports alternative installation paths including Desktop and custom directories.
#
# Links:
# - Website: https://www.digi77.com
# - Website: https://www.kodachi.cloud
# - GitHub: https://github.com/WMAL
# - Discord: https://discord.gg/KEFErEx
# - LinkedIn: https://www.linkedin.com/in/warith1977
# - X (Twitter): https://x.com/warith2020
#
# Usage:
#   # Default installation to ~/dashboard/hooks
#   curl -sSL https://www.kodachi.cloud/apps/os/install/kodachi-binary-install.sh | bash
#
#   # Install to Desktop
#   curl -sSL https://www.kodachi.cloud/apps/os/install/kodachi-binary-install.sh | bash -s -- --desktop
#
#   # Install to custom path
#   curl -sSL https://www.kodachi.cloud/apps/os/install/kodachi-binary-install.sh | bash -s -- --path /custom/path
#
# Options:
#   --desktop       Install to ~/Desktop/dashboard/hooks
#   --path PATH     Install to custom path (must be writable)
#   --version VER   Specify version (default: 9.0.1)
#   --skip-path     Don't add to PATH in .bashrc
#   --help          Show help message

set -euo pipefail

# Refuse root execution to keep this user-space only
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "[ERROR] Do not run as root. Use regular user." >&2
    exit 1
fi

# Color codes for output (only if TTY is present)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    MAGENTA='\033[0;35m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    MAGENTA=""
    BOLD=""
    NC=""
fi

# Function to print colored output
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_step() { echo -e "${CYAN}[→]${NC} $1"; }
print_highlight() { echo -e "${MAGENTA}${BOLD}$1${NC}"; }

# Configuration
CDN_BASE="https://www.kodachi.cloud/apps/os/install"
KODACHI_VERSION="9.0.1"
CONKY_PACKAGE_LOCAL_SOURCE="/home/kodachi/k900/livebuild-assets/conky"
CONKY_CONFIG_BASE="${XDG_CONFIG_HOME:-$HOME/.config}"
CONKY_INSTALL_DIR="$CONKY_CONFIG_BASE/kodachi/conky"
CONKY_AUTOSTART_FILE="$CONKY_CONFIG_BASE/autostart/kodachi-conky.desktop"
CONKY_SETUP_DONE=false
PERMISSION_GUARD_SKIPPED=false
SKIPPED_COUNT=0

# Detect whether this system has a GUI desktop environment (XFCE/GNOME/etc.)
detect_gui_environment() {
    # Active GUI session
    if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
        return 0
    fi

    # Session type hint from login manager
    if [[ "${XDG_SESSION_TYPE:-}" == "x11" || "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
        return 0
    fi

    # Installed desktop session files (XFCE, GNOME, KDE, etc.)
    if compgen -G "/usr/share/xsessions/*.desktop" >/dev/null 2>&1 || \
       compgen -G "/usr/share/wayland-sessions/*.desktop" >/dev/null 2>&1; then
        return 0
    fi

    # Common desktop environment packages (Debian/Ubuntu family)
    if command -v dpkg >/dev/null 2>&1; then
        local desktop_packages=(
            "xfce4" "xfce4-session" "gnome-shell" "plasma-desktop"
            "mate-desktop" "lxde" "lxqt-core" "cinnamon"
        )
        local pkg=""
        for pkg in "${desktop_packages[@]}"; do
            if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
                return 0
            fi
        done
    fi

    return 1
}

# Parse command line arguments
INSTALL_PATH=""
SKIP_PATH_UPDATE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --path)
            INSTALL_PATH="$2"
            shift 2
            ;;
        --desktop)
            INSTALL_PATH="$HOME/Desktop/dashboard/hooks"
            shift
            ;;
        --version)
            KODACHI_VERSION="$2"
            shift 2
            ;;
        --skip-path)
            SKIP_PATH_UPDATE=true
            shift
            ;;
        --help)
            echo "Kodachi Binary Installation Script (No Sudo Required)"
            echo ""
            echo "Usage:"
            echo "  curl -sSL $CDN_BASE/kodachi-binary-install.sh | bash"
            echo ""
            echo "Options:"
            echo "  --desktop       Install to ~/Desktop/dashboard/hooks"
            echo "  --path PATH     Install to custom path"
            echo "  --version VER   Specify version (default: $KODACHI_VERSION)"
            echo "  --skip-path     Don't add to PATH in .bashrc"
            echo "  --help          Show this help message"
            echo ""
            echo "After installation, run the dependency installer:"
            echo "  curl -sSL $CDN_BASE/kodachi-deps-install.sh | sudo bash"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Set default install path if not specified
if [[ -z "$INSTALL_PATH" ]]; then
    if [[ -x "$PWD/dashboard/hooks/kodachi-dashboard" ]]; then
        INSTALL_PATH="$PWD/dashboard/hooks"
    elif [[ -x "$HOME/k900/dashboard/hooks/kodachi-dashboard" ]]; then
        INSTALL_PATH="$HOME/k900/dashboard/hooks"
    else
        INSTALL_PATH="$HOME/dashboard/hooks"
    fi
fi

# Welcome message
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     Kodachi Binary Installation Script       ║${NC}"
echo -e "${CYAN}║            (No Sudo Required)                ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""

print_info "This script will install Kodachi binaries to: $INSTALL_PATH"
print_info "No sudo or root access is required."
echo ""

# Check for curl prerequisite
if ! command -v curl &>/dev/null; then
    print_error "curl is required but not found"
    print_info "This script requires curl to download packages"
    print_info "Install it with: sudo apt-get install curl"
    exit 1
fi

# ============================================================================
# TIME SYNCHRONIZATION - Critical for HTTPS certificate validation
# ============================================================================
print_step "Checking system time synchronization..."
if command -v timedatectl >/dev/null 2>&1; then
    ntp_status=$(timedatectl status 2>/dev/null | awk -F': ' '/System clock synchronized/ {print tolower($2)}' || true)
    if [[ "$ntp_status" == "yes" ]]; then
        print_success "System clock already synchronized"
    else
        print_warning "System clock not yet synchronized; run 'sudo timedatectl set-ntp true' after installing dependencies"
    fi
else
    print_warning "timedatectl not found; skipping automatic time sync check"
fi
echo ""

# Check if we can write to the installation path
if [[ -e "$INSTALL_PATH" ]] && [[ ! -w "$INSTALL_PATH" ]]; then
    print_error "Cannot write to $INSTALL_PATH"
    print_info "Please choose a different path or fix permissions"
    exit 1
fi

# Create temporary directory
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Function to download with retry, resume support, and stall detection
download_with_retry() {
    local url="$1"
    local output="$2"
    local max_retries=5
    local retry=0
    local backoff=2
    local curl_progress="--silent"

    # Show progress bar if running in a terminal
    if [ -t 1 ]; then
        curl_progress="--progress-bar"
    fi

    while [[ $retry -lt $max_retries ]]; do
        local exit_code=0
        curl --fail --location --show-error \
               $curl_progress \
               --connect-timeout 15 \
               --speed-limit 50000 --speed-time 30 \
               -C - \
               "$url" -o "$output" || exit_code=$?

        if [[ $exit_code -eq 0 ]]; then
            return 0
        fi

        retry=$((retry + 1))

        # Exit code 33 = range request not supported, restart without resume
        if [[ $exit_code -eq 33 ]]; then
            rm -f "$output"
        fi

        if [[ $retry -lt $max_retries ]]; then
            print_warning "Download failed (attempt $retry/$max_retries), retrying in ${backoff}s..."
            sleep "$backoff"
            backoff=$((backoff + retry + 1))
        fi
    done

    return 1
}

# Function to verify signature
verify_signature() {
    local binary_path="$1"
    local signature_dir="$2"
    local binary_name=$(basename "$binary_path")

    local sig_file=$(find "$signature_dir" -name "${binary_name}*.sig" -type f | head -n1)
    if [[ -z "$sig_file" ]]; then
        return 1
    fi

    local pub_key=$(find "$signature_dir/../config/signkeys" -name "public_key*.pem" -type f | head -n1)
    if [[ -z "$pub_key" ]]; then
        return 1
    fi

    if openssl dgst -sha256 -verify "$pub_key" -signature "$sig_file" "$binary_path" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to detect and stop permission-guard daemon
stop_permission_guard_if_running() {
    # Try to find permission-guard binary location
    local pg_binary=""
    if command -v permission-guard &>/dev/null; then
        pg_binary="permission-guard"
    elif [[ -f "$INSTALL_PATH/permission-guard" ]]; then
        pg_binary="$INSTALL_PATH/permission-guard"
    fi

    if [[ -z "$pg_binary" ]]; then
        # No binary found, skip check
        return 0
    fi

    # Check if daemon is actually running (handle multiple scenarios)
    daemon_running=false

    # Method 1: Try with sudo first (for root-owned daemons, non-interactive)
    if sudo -n $pg_binary --daemon-status --json 2>/dev/null | grep -q '"running":true'; then
        daemon_running=true
    # Method 2: Try without sudo (for user-owned daemons)
    elif $pg_binary --daemon-status --json 2>/dev/null | grep -q '"running":true'; then
        daemon_running=true
    # Method 3: Check for EPERM error (daemon running but no permission to check)
    elif $pg_binary --daemon-status --json 2>/dev/null | grep -q 'EPERM.*Operation not permitted'; then
        daemon_running=true
    # Method 4: Fallback to direct process check
    elif pgrep -f "permission-guard.*daemon" >/dev/null 2>&1; then
        daemon_running=true
    fi

    if [[ "$daemon_running" == "true" ]]; then
        print_warning "Detected running permission-guard daemon"
        print_step "Attempting to stop permission-guard daemon..."

        # Try to stop without sudo first
        if "$pg_binary" --stop-daemon &>/dev/null; then
            sleep 2  # Wait for daemon to fully stop

            # Verify it actually stopped (check with both sudo and non-sudo)
            if sudo -n $pg_binary --daemon-status --json 2>/dev/null | grep -q '"running":false'; then
                print_success "Successfully stopped permission-guard daemon"
                print_info "The daemon will automatically start again when you log in"
                return 0
            elif $pg_binary --daemon-status --json 2>/dev/null | grep -q '"running":false'; then
                print_success "Successfully stopped permission-guard daemon"
                print_info "The daemon will automatically start again when you log in"
                return 0
            elif ! pgrep -f "permission-guard.*daemon" >/dev/null 2>&1; then
                # Process check shows it stopped
                print_success "Successfully stopped permission-guard daemon"
                print_info "The daemon will automatically start again when you log in"
                return 0
            else
                print_error "Stop command succeeded but daemon is still running"
                print_info "This may require sudo privileges to stop"
                # Fall through to sudo instructions below
            fi
        fi

        # If we reach here, need sudo to stop
        print_error "Cannot stop permission-guard daemon - requires sudo privileges"
        echo ""

        # Non-interactive fallback (e.g., curl ... | bash with no TTY)
        if [[ ! -t 0 ]] && ! [[ -c /dev/tty ]]; then
            print_warning "Non-interactive mode: skipping permission-guard binary update"
            PERMISSION_GUARD_SKIPPED=true
            return 0
        fi

        local pg_attempts=0
        local pg_max_attempts=3

        while true; do
            echo ""
            print_highlight "ACTION REQUIRED: permission-guard daemon is still running"
            echo ""
            echo "  To stop it, open another terminal and run:"
            echo -e "    ${BOLD}sudo permission-guard --stop-daemon${NC}"
            echo -e "    ${BOLD}sudo $INSTALL_PATH/permission-guard --stop-daemon${NC}"
            echo ""

            if [[ $pg_attempts -ge $pg_max_attempts ]]; then
                # After max attempts, only offer skip or abort
                echo -e "  ${YELLOW}[1]${NC} Continue anyway - skip permission-guard binary"
                echo -e "  ${YELLOW}[2]${NC} Abort installation"
                echo ""
                echo -n "  Choose [1-2]: "
                local fallback_choice=""
                read -r fallback_choice < /dev/tty 2>/dev/null || fallback_choice="1"
                case "$fallback_choice" in
                    2)
                        print_error "Installation aborted by user"
                        exit 1
                        ;;
                    *)
                        print_warning "Skipping permission-guard binary update"
                        PERMISSION_GUARD_SKIPPED=true
                        return 0
                        ;;
                esac
            fi

            echo -e "  ${YELLOW}[1]${NC} I stopped it - verify and continue"
            echo -e "  ${YELLOW}[2]${NC} Continue anyway - skip permission-guard binary"
            echo -e "  ${YELLOW}[3]${NC} Abort installation"
            echo ""
            echo -n "  Choose [1-3]: "
            local pg_choice=""
            read -r pg_choice < /dev/tty 2>/dev/null || pg_choice="2"

            case "$pg_choice" in
                1)
                    pg_attempts=$((pg_attempts + 1))
                    print_step "Re-checking permission-guard status (attempt $pg_attempts/$pg_max_attempts)..."
                    sleep 1

                    # Re-verify using all 4 detection methods
                    local still_running=false
                    if sudo -n $pg_binary --daemon-status --json 2>/dev/null | grep -q '"running":true'; then
                        still_running=true
                    elif $pg_binary --daemon-status --json 2>/dev/null | grep -q '"running":true'; then
                        still_running=true
                    elif $pg_binary --daemon-status --json 2>/dev/null | grep -q 'EPERM.*Operation not permitted'; then
                        # Can't check via daemon-status (no sudo), fall back to pgrep
                        if pgrep -f "permission-guard.*daemon" >/dev/null 2>&1; then
                            still_running=true
                        fi
                    elif pgrep -f "permission-guard.*daemon" >/dev/null 2>&1; then
                        still_running=true
                    fi

                    if [[ "$still_running" == "false" ]]; then
                        print_success "permission-guard daemon is no longer running"
                        return 0
                    fi

                    print_error "permission-guard daemon is still running"
                    ;;
                2)
                    print_warning "Skipping permission-guard binary update"
                    PERMISSION_GUARD_SKIPPED=true
                    return 0
                    ;;
                3)
                    print_error "Installation aborted by user"
                    exit 1
                    ;;
                *)
                    print_warning "Invalid choice, please try again"
                    ;;
            esac
        done
    fi
}

# Collect running PIDs that are holding target binaries we are about to replace
collect_install_path_pids() {
    local pids=()
    local pid=""
    local exe=""
    local binary_file=""
    local binary_name=""
    local target=""
    local have_sudo=false
    local have_timeout=false
    local self_pid="$$"
    local parent_pid="${PPID:-0}"
    local targets=()
    local -A target_map=()
    local lsof_pids=""

    if sudo -n true 2>/dev/null; then
        have_sudo=true
    fi
    if command -v timeout &>/dev/null; then
        have_timeout=true
    fi

    for binary_file in "$EXTRACT_DIR/binaries/"*; do
        [[ -f "$binary_file" ]] || continue
        binary_name="$(basename "$binary_file")"
        # Skip permission-guard when user chose to keep it running
        if [[ "$PERMISSION_GUARD_SKIPPED" == "true" ]] && [[ "$binary_name" == "permission-guard" ]]; then
            continue
        fi
        target="$INSTALL_PATH/$binary_name"
        [[ -e "$target" ]] || continue
        targets+=("$target")
        target_map["$target"]=1
    done

    if [[ "${#targets[@]}" -eq 0 ]]; then
        return 0
    fi

    # Method 1: Open file handles for all target binaries (single call)
    if command -v lsof &>/dev/null; then
        if [[ "$have_timeout" == true ]]; then
            lsof_pids="$(timeout --signal=TERM 8s lsof -t -- "${targets[@]}" 2>/dev/null || true)"
        else
            lsof_pids="$(lsof -t -- "${targets[@]}" 2>/dev/null || true)"
        fi
        while IFS= read -r pid; do
            [[ -n "$pid" ]] && pids+=("$pid")
        done < <(printf '%s\n' "$lsof_pids" | sort -u || true)

        # Also inspect root-owned holders if non-interactive sudo is available
        if [[ "$have_sudo" == true ]]; then
            if [[ "$have_timeout" == true ]]; then
                lsof_pids="$(sudo -n timeout --signal=TERM 8s lsof -t -- "${targets[@]}" 2>/dev/null || true)"
            else
                lsof_pids="$(sudo -n lsof -t -- "${targets[@]}" 2>/dev/null || true)"
            fi
            while IFS= read -r pid; do
                [[ -n "$pid" ]] && pids+=("$pid")
            done < <(printf '%s\n' "$lsof_pids" | sort -u || true)
        fi
    fi

    # Method 2: Executable path points to one of target binaries (single /proc pass)
    for proc in /proc/[0-9]*; do
        pid="${proc##*/}"
        exe="$(readlink -f "$proc/exe" 2>/dev/null || true)"
        if [[ -n "$exe" ]] && [[ -n "${target_map[$exe]:-}" ]]; then
            pids+=("$pid")
        fi
    done

    # Print unique numeric PIDs excluding current shell and parent shell
    printf '%s\n' "${pids[@]}" \
        | awk '/^[0-9]+$/' \
        | awk -v self="$self_pid" -v parent="$parent_pid" '$1 != self && $1 != parent' \
        | sort -u
}

# Kill all processes using hooks path to prevent ETXTBSY during binary replacement
drain_install_path_processes() {
    print_step "Stopping processes using hooks binaries..."

    local pids=()
    local pid=""
    local survivors=()
    local count=0
    local have_sudo=false

    if sudo -n true 2>/dev/null; then
        have_sudo=true
    fi

    while IFS= read -r pid; do
        [[ -n "$pid" ]] && pids+=("$pid")
    done < <(collect_install_path_pids)

    count="${#pids[@]}"
    if [[ "$count" -eq 0 ]]; then
        print_success "No active processes are holding hooks binaries"
        return 0
    fi

    print_warning "Found $count active process(es) holding target binaries; terminating..."

    # Graceful stop first
    kill -TERM "${pids[@]}" 2>/dev/null || true
    if [[ "$have_sudo" == true ]]; then
        sudo -n kill -TERM "${pids[@]}" 2>/dev/null || true
    fi
    sleep 1

    # Force kill remaining PIDs
    kill -KILL "${pids[@]}" 2>/dev/null || true
    if [[ "$have_sudo" == true ]]; then
        sudo -n kill -KILL "${pids[@]}" 2>/dev/null || true
    fi
    sleep 0.5

    # Re-check to ensure drain succeeded
    while IFS= read -r pid; do
        [[ -n "$pid" ]] && survivors+=("$pid")
    done < <(collect_install_path_pids)

    if [[ "${#survivors[@]}" -gt 0 ]]; then
        print_warning "Some processes still hold old binaries: ${survivors[*]}"
        print_warning "Proceeding with atomic replacement; those processes may need restart."
        return 0
    fi

    print_success "Hooks path is clear; no process is holding binaries"
}

# Remove only target binaries (top-level files) before copying replacements
remove_old_hook_binaries() {
    print_step "Removing old hook binaries before copy..."

    local binary_file=""
    local binary_name=""
    local removed=0

    for binary_file in "$EXTRACT_DIR/binaries/"*; do
        if [[ -f "$binary_file" ]]; then
            binary_name="$(basename "$binary_file")"
            # Skip permission-guard when user chose to keep it running
            if [[ "$PERMISSION_GUARD_SKIPPED" == "true" ]] && [[ "$binary_name" == "permission-guard" ]]; then
                continue
            fi
            if [[ -f "$INSTALL_PATH/$binary_name" ]]; then
                rm -f "$INSTALL_PATH/$binary_name" 2>/dev/null || true
                if [[ -f "$INSTALL_PATH/$binary_name" ]] && sudo -n true 2>/dev/null; then
                    sudo -n rm -f "$INSTALL_PATH/$binary_name" 2>/dev/null || true
                fi
                if [[ ! -f "$INSTALL_PATH/$binary_name" ]]; then
                    removed=$((removed + 1))
                fi
            fi
        fi
    done

    print_success "Removed $removed old binary file(s) from hooks"
}

# Ensure hooks folder is safe for binary replacement
prepare_hooks_for_binary_replace() {
    # Lightweight re-check: pg may have restarted during download
    if [[ "$PERMISSION_GUARD_SKIPPED" != "true" ]]; then
        local pg_restarted=false
        if pgrep -f "permission-guard.*daemon" >/dev/null 2>&1; then
            pg_restarted=true
        fi
        if [[ "$pg_restarted" == "true" ]]; then
            print_warning "permission-guard daemon appears to have restarted during download"
            stop_permission_guard_if_running
        fi
    fi
    # Then drain all running processes using hooks path
    drain_install_path_processes
    # Finally remove old target binaries before writing new files
    remove_old_hook_binaries
}

# Early permission-guard check BEFORE downloading (avoid wasting download time)
stop_permission_guard_if_running

echo ""
print_highlight "======= Downloading Kodachi Binaries ======="
echo ""

# Step 1: Download package
print_step "Downloading Kodachi binaries package..."
PACKAGE_NAME="kodachi-binaries-v${KODACHI_VERSION}"
PACKAGE_URL="$CDN_BASE/${PACKAGE_NAME}.tar.gz"
PACKAGE_FILE="$TEMP_DIR/${PACKAGE_NAME}.tar.gz"

if ! download_with_retry "$PACKAGE_URL" "$PACKAGE_FILE"; then
    print_error "Failed to download package from $PACKAGE_URL"
    exit 1
fi
file_size=$(du -h "$PACKAGE_FILE" | cut -f1)
print_success "Package downloaded successfully ($file_size)"

# Step 2: Download and verify package signature
print_step "Downloading package signature..."
SIGNATURE_URL="${PACKAGE_URL}.sig"
SIGNATURE_FILE="$TEMP_DIR/${PACKAGE_NAME}.tar.gz.sig"
PUBLIC_KEY_URL="$CDN_BASE/public_key_v${KODACHI_VERSION}.pem"
PUBLIC_KEY_FILE="$TEMP_DIR/public_key_v${KODACHI_VERSION}.pem"

PACKAGE_VERIFIED=false
if download_with_retry "$SIGNATURE_URL" "$SIGNATURE_FILE"; then
    if download_with_retry "$PUBLIC_KEY_URL" "$PUBLIC_KEY_FILE"; then
        print_step "Verifying package signature..."
        if openssl dgst -sha256 -verify "$PUBLIC_KEY_FILE" -signature "$SIGNATURE_FILE" "$PACKAGE_FILE" >/dev/null 2>&1; then
            print_success "Package signature verified successfully"
            PACKAGE_VERIFIED=true
        else
            print_error "Package signature verification FAILED!"
            print_error "The downloaded package may be compromised or corrupted."
            print_error "Installation aborted for security reasons."
            exit 1
        fi
    else
        print_error "Public key not found - cannot verify package authenticity"
        print_error "Installation aborted for security reasons."
        exit 1
    fi
else
    print_error "Package signature not found - cannot verify package authenticity"
    print_error "Installation aborted for security reasons."
    exit 1
fi

# Step 3: Verify checksum
print_step "Verifying package checksum..."
CHECKSUM_URL="${PACKAGE_URL}.sha256"
CHECKSUM_FILE="$TEMP_DIR/${PACKAGE_NAME}.tar.gz.sha256"

if download_with_retry "$CHECKSUM_URL" "$CHECKSUM_FILE"; then
    cd "$TEMP_DIR"
    if sha256sum -c "$CHECKSUM_FILE" &>/dev/null; then
        print_success "Package checksum verified"
    else
        print_error "Package checksum verification FAILED!"
        print_error "The downloaded package is corrupted or has been tampered with."
        print_error "Installation aborted for security reasons."
        exit 1
    fi
else
    print_error "Checksum file not found - cannot verify package integrity"
    print_error "Installation aborted for security reasons."
    exit 1
fi

# Step 4: Extract package
print_step "Checking archive for unsafe paths..."
# Prevent path traversal attacks by checking for absolute paths or parent directory references
if tar -tzf "$PACKAGE_FILE" | grep -E '^/|(^|/)\.\.(/|$)' >/dev/null 2>&1; then
    print_error "Archive contains unsafe paths (absolute paths or parent directory references)"
    print_error "This could indicate a malicious archive."
    print_error "Installation aborted for security reasons."
    exit 1
fi
print_success "Archive path check passed"

print_step "Extracting package..."
cd "$TEMP_DIR"
# Use safe extraction flags to prevent ownership/permission issues
tar -xzf "$PACKAGE_FILE" --no-same-owner --no-same-permissions --numeric-owner
EXTRACT_DIR="$TEMP_DIR/$PACKAGE_NAME"

if [[ ! -d "$EXTRACT_DIR" ]]; then
    print_error "Failed to extract package"
    exit 1
fi
print_success "Package extracted successfully"

# Step 5: Create installation directory structure
print_step "Creating installation directories..."
mkdir -p "$INSTALL_PATH"/{config/signkeys,config/profiles,icons,logs,tmp,results/signatures,backups,others,sounds,flags,licenses,binaries-update-scripts,models,data}
print_success "Directory structure created"

# Step 5.5: Pre-copy safety drain for hooks binary replacement
prepare_hooks_for_binary_replace

# Step 5.6: Cleanup old global symlinks (if global-launcher exists)
echo ""
print_highlight "======= Cleaning Up Global Deployments ======="
echo ""

cleanup_global_symlinks() {
    # Check if global-launcher exists in installation path or is globally accessible
    local gl_binary=""
    if command -v global-launcher &>/dev/null; then
        gl_binary="global-launcher"
    elif [[ -f "$INSTALL_PATH/global-launcher" ]]; then
        gl_binary="$INSTALL_PATH/global-launcher"
    fi

    if [[ -z "$gl_binary" ]]; then
        print_info "global-launcher not found - skipping cleanup (first-time install)"
        return 0
    fi

    print_step "Found global-launcher - cleaning up old symlinks..."

    # Try cleanup with sudo (non-interactive)
    if sudo -n "$gl_binary" cleanup --yes --json &>/dev/null; then
        print_success "Successfully removed old global symlinks"
        return 0
    # Try without sudo (user-space deployment)
    elif "$gl_binary" cleanup --yes --json &>/dev/null; then
        print_success "Successfully removed old global symlinks"
        return 0
    else
        print_warning "Could not cleanup old symlinks (may require sudo)"
        print_info "This is non-fatal - installation will continue"
        print_info "You can manually cleanup later with: sudo global-launcher cleanup"
        return 0
    fi
}

cleanup_global_symlinks

# Step 6: Install binaries
print_step "Installing binaries..."
VERIFIED_COUNT=0
FAILED_COUNT=0
INSTALL_FAILED_COUNT=0
TOTAL_COUNT=0
FAILED_BINARIES=""
INSTALL_FAILED_BINARIES=""

for binary_file in "$EXTRACT_DIR/binaries/"*; do
    if [[ -f "$binary_file" ]]; then
        binary_name=$(basename "$binary_file")
        TOTAL_COUNT=$((TOTAL_COUNT + 1))

        # Skip permission-guard when user chose to keep it running
        if [[ "$PERMISSION_GUARD_SKIPPED" == "true" ]] && [[ "$binary_name" == "permission-guard" ]]; then
            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
            echo -e "  ${YELLOW}⊘${NC} $binary_name - SKIPPED (daemon still running)"
            continue
        fi

        # Verify signature BEFORE copying
        if verify_signature "$binary_file" "$EXTRACT_DIR/signatures"; then
            # Atomic replace avoids ETXTBSY on running binaries.
            tmp_target="$INSTALL_PATH/.${binary_name}.new.$$"
            if install -m 755 "$binary_file" "$tmp_target" && mv -f "$tmp_target" "$INSTALL_PATH/$binary_name"; then
                VERIFIED_COUNT=$((VERIFIED_COUNT + 1))
                echo -e "  ${GREEN}✓${NC} $binary_name - signature verified and installed"
            else
                rm -f "$tmp_target" 2>/dev/null || true
                INSTALL_FAILED_COUNT=$((INSTALL_FAILED_COUNT + 1))
                INSTALL_FAILED_BINARIES="${INSTALL_FAILED_BINARIES}    - ${binary_name}\n"
                echo -e "  ${RED}✗${NC} $binary_name - install failed (write/permission/busy)"
            fi
        else
            FAILED_COUNT=$((FAILED_COUNT + 1))
            FAILED_BINARIES="${FAILED_BINARIES}    - ${binary_name}\n"
            echo -e "  ${RED}✗${NC} $binary_name - signature verification FAILED"
        fi
    fi
done

# Check if any signatures failed
if [[ $FAILED_COUNT -gt 0 ]]; then
    echo ""
    print_error "Binary signature verification FAILED for $FAILED_COUNT binaries!"
    print_error "The following binaries could not be verified:"
    echo -e "${RED}${FAILED_BINARIES}${NC}"
    print_error "These binaries were NOT installed for security reasons."
    print_error "Installation aborted - the package may be compromised."

    # Clean up any partially installed files
    rm -rf "$INSTALL_PATH"
    exit 1
fi

print_success "Installed and verified $VERIFIED_COUNT binaries"

if [[ $INSTALL_FAILED_COUNT -gt 0 ]]; then
    echo ""
    print_error "Binary installation failed for $INSTALL_FAILED_COUNT binaries!"
    print_error "The following binaries could not be installed:"
    echo -e "${RED}${INSTALL_FAILED_BINARIES}${NC}"
    print_error "Please check permissions/process locks and re-run the installer."
    exit 1
fi

# Step 7: Copy configuration files
print_step "Installing configuration files..."
if [[ -d "$EXTRACT_DIR/config" ]]; then
    cp -r "$EXTRACT_DIR/config/"* "$INSTALL_PATH/config/" 2>/dev/null || true
    print_success "Configuration files installed"
fi

# Step 8: Copy other assets
if [[ -d "$EXTRACT_DIR/signatures" ]]; then
    cp -r "$EXTRACT_DIR/signatures/"* "$INSTALL_PATH/results/signatures/" 2>/dev/null || true
fi

if [[ -d "$EXTRACT_DIR/sounds" ]]; then
    cp -a "$EXTRACT_DIR/sounds/." "$INSTALL_PATH/sounds/" 2>/dev/null || true
fi

if [[ -d "$EXTRACT_DIR/flags" ]]; then
    cp -a "$EXTRACT_DIR/flags/." "$INSTALL_PATH/flags/" 2>/dev/null || true
fi

if [[ -d "$EXTRACT_DIR/icons" ]]; then
    cp -a "$EXTRACT_DIR/icons/." "$INSTALL_PATH/icons/" 2>/dev/null || true
fi

# Backward compatibility: older packages may only contain dashboard icon
# under config/icons and no top-level icons directory.
if [[ -d "$EXTRACT_DIR/config/icons" ]]; then
    if [[ -z "$(find "$INSTALL_PATH/icons" -maxdepth 1 -type f 2>/dev/null)" ]]; then
        cp -a "$EXTRACT_DIR/config/icons/." "$INSTALL_PATH/icons/" 2>/dev/null || true
    fi
fi

# Ensure runtime icon filename exists for dashboard/tray fallback logic.
# Package may contain only generic Kodachi icon names (e.g., kodachi.png).
if [[ ! -f "$INSTALL_PATH/icons/kodachi-dashboard.png" ]]; then
    for icon_candidate in \
        "$INSTALL_PATH/config/icons/kodachi-dashboard.png" \
        "$INSTALL_PATH/icons/kodachi.png" \
        "$INSTALL_PATH/icons/kodachi32.png" \
        "$INSTALL_PATH/icons/Kodachi_Green_big.png" \
        "$INSTALL_PATH/icons/Kodachi_White_big.png" \
        "$INSTALL_PATH/icons/Kodachi_Black_big.png"
    do
        if [[ -f "$icon_candidate" ]]; then
            cp -f "$icon_candidate" "$INSTALL_PATH/icons/kodachi-dashboard.png"
            break
        fi
    done
fi

if [[ -d "$EXTRACT_DIR/licenses" ]]; then
    cp -r "$EXTRACT_DIR/licenses/"* "$INSTALL_PATH/licenses/" 2>/dev/null || true
    if [[ -f "$INSTALL_PATH/licenses/LICENSE.md" ]]; then
        print_success "LICENSE.md installed"
    fi
fi

if [[ -d "$EXTRACT_DIR/binaries-update-scripts" ]]; then
    cp -r "$EXTRACT_DIR/binaries-update-scripts/"* "$INSTALL_PATH/binaries-update-scripts/" 2>/dev/null || true
    script_count=$(find "$INSTALL_PATH/binaries-update-scripts" -type f -name "*.sh" | wc -l)
    if [[ $script_count -gt 0 ]]; then
        print_success "Update scripts installed ($script_count scripts)"
        print_info "Scripts location: $INSTALL_PATH/binaries-update-scripts/"
    fi
fi

# Copy AI model files
if [[ -d "$EXTRACT_DIR/models" ]]; then
    cp -r "$EXTRACT_DIR/models/"* "$INSTALL_PATH/models/" 2>/dev/null || true
    model_count=$(find "$INSTALL_PATH/models" -type f | wc -l)
    if [[ $model_count -gt 0 ]]; then
        print_success "AI model files installed ($model_count files)"
    fi
fi

# Step 8.5: Install Conky assets and startup entry
install_conky_assets() {
    print_step "Installing Conky assets..."

    local conky_source=""
    local candidates=()

    # Preferred source: bundled package assets
    if [[ -n "${EXTRACT_DIR:-}" ]]; then
        candidates+=("$EXTRACT_DIR/conky")
    fi

    # Local development fallbacks
    candidates+=("$CONKY_PACKAGE_LOCAL_SOURCE" "$HOME/k900/livebuild-assets/conky")

    for candidate in "${candidates[@]}"; do
        if [[ -d "$candidate/configs" ]] && [[ -d "$candidate/scripts" ]]; then
            conky_source="$candidate"
            break
        fi
    done

    if [[ -z "$conky_source" ]]; then
        print_warning "Conky source not found in package or local assets. Skipping Conky setup."
        return 1
    fi

    mkdir -p "$(dirname "$CONKY_INSTALL_DIR")"
    rm -rf "$CONKY_INSTALL_DIR"
    cp -a "$conky_source" "$CONKY_INSTALL_DIR"

    if [[ -d "$CONKY_INSTALL_DIR/scripts" ]]; then
        find "$CONKY_INSTALL_DIR/scripts" -type f -name "*.sh" -exec chmod 755 {} + 2>/dev/null || true
    fi

    print_success "Conky assets installed: $CONKY_INSTALL_DIR"
    return 0
}

install_conky_autostart() {
    local watchdog_script="$CONKY_INSTALL_DIR/scripts/conky-watchdog.sh"
    local launcher="$CONKY_INSTALL_DIR/scripts/conky-launcher.sh"
    local systemd_service_file="$CONKY_CONFIG_BASE/systemd/user/conky-watchdog.service"
    local autostart_exec=""
    local autostart_tryexec=""

    if command -v systemctl >/dev/null 2>&1 && [[ -x "$watchdog_script" ]] && [[ -f "$systemd_service_file" ]]; then
        autostart_exec="/usr/bin/systemctl --user start conky-watchdog.service"
        autostart_tryexec="/usr/bin/systemctl"
    elif [[ -x "$launcher" ]]; then
        autostart_exec="$launcher --restart"
        autostart_tryexec="$launcher"
        print_warning "Conky watchdog is unavailable, falling back to launcher autostart."
    else
        print_warning "Conky launcher not found at $launcher. Skipping autostart setup."
        return 1
    fi

    mkdir -p "$(dirname "$CONKY_AUTOSTART_FILE")"
    cat > "$CONKY_AUTOSTART_FILE" << EOF
[Desktop Entry]
Type=Application
Name=Kodachi Conky
Comment=Kodachi 9 Desktop Status Panels
GenericName=System Monitor
Exec=$autostart_exec
TryExec=$autostart_tryexec
Terminal=false
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=5
Categories=System;Monitor;
Keywords=conky;monitor;system;status;privacy;security;
StartupNotify=false
EOF
    chmod 644 "$CONKY_AUTOSTART_FILE"

    print_success "Conky autostart enabled: $CONKY_AUTOSTART_FILE"
    if ! command -v conky &>/dev/null; then
        print_warning "Conky binary is not installed yet. Run kodachi-deps-install.sh to install conky-all."
    fi
    return 0
}

install_conky_watchdog() {
    local watchdog_script="$CONKY_INSTALL_DIR/scripts/conky-watchdog.sh"
    local launcher="$CONKY_INSTALL_DIR/scripts/conky-launcher.sh"
    local service_source="$CONKY_INSTALL_DIR/systemd/conky-watchdog.service"
    local systemd_user_dir="$CONKY_CONFIG_BASE/systemd/user"
    local service_file="$systemd_user_dir/conky-watchdog.service"
    local wants_dir="$systemd_user_dir/default.target.wants"

    if [[ ! -x "$watchdog_script" ]]; then
        if [[ ! -x "$launcher" ]]; then
            print_warning "Conky launcher not found at $launcher. Skipping watchdog setup."
            return 1
        fi

        print_warning "Conky watchdog script missing in assets. Creating compatibility watchdog."
        cat > "$watchdog_script" << EOF
#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="\${XDG_CACHE_HOME:-\$HOME/.cache}/kodachi"
LOG_FILE="\$LOG_DIR/conky-watchdog.log"
CHECK_INTERVAL="\${CONKY_WATCHDOG_INTERVAL:-5}"
EXPECTED_PANELS="\${CONKY_EXPECTED_PANELS:-4}"

mkdir -p "\$LOG_DIR"
export DISPLAY="\${DISPLAY:-:0}"
export XAUTHORITY="\${XAUTHORITY:-\$HOME/.Xauthority}"

count_conky() { pgrep -x conky 2>/dev/null | wc -l || true; }
restart_conky() { "$launcher" --restart >> "\$LOG_FILE" 2>&1 || true; }

if [[ "\$(count_conky)" -lt "\$EXPECTED_PANELS" ]]; then
    restart_conky
fi

while true; do
    if [[ "\$(count_conky)" -lt "\$EXPECTED_PANELS" ]]; then
        restart_conky
        sleep 2
    fi
    sleep "\$CHECK_INTERVAL"
done
EOF
        chmod 755 "$watchdog_script"
    fi

    mkdir -p "$systemd_user_dir" "$wants_dir"

    if [[ -f "$service_source" ]]; then
        cp -f "$service_source" "$service_file"
    else
        cat > "$service_file" << EOF
[Unit]
Description=Kodachi Conky Watchdog
After=graphical-session.target
Wants=graphical-session.target

[Service]
Type=simple
ExecStart=%h/.config/kodachi/conky/scripts/conky-watchdog.sh
Restart=always
RestartSec=3
Environment=DISPLAY=:0
Environment=XAUTHORITY=%h/.Xauthority

[Install]
WantedBy=default.target
EOF
    fi
    chmod 644 "$service_file"
    ln -sfn "$service_file" "$wants_dir/conky-watchdog.service"

    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user daemon-reload >/dev/null 2>&1 || true
        systemctl --user enable --now conky-watchdog.service >/dev/null 2>&1 || \
            systemctl --user start conky-watchdog.service >/dev/null 2>&1 || true
    fi

    print_success "Conky watchdog configured: $service_file"
    return 0
}

setup_conky() {
    # Check build variant marker file (written by build-iso.sh during ISO creation)
    local _build_variant=""
    if [[ -f /opt/kodachi-offline-packages/build-variant ]]; then
        _build_variant=$(tr -cd 'a-z-' < /opt/kodachi-offline-packages/build-variant)
    fi
    if [[ "$_build_variant" == "terminal" ]] || [[ "$_build_variant" == "minimal" ]]; then
        print_info "Build variant is '${_build_variant}'. Skipping Conky bootup setup."
        return 0
    fi
    if ! detect_gui_environment; then
        print_info "No GUI desktop detected (terminal/headless system). Skipping Conky setup."
        return 0
    fi

    if install_conky_assets; then
        install_conky_watchdog || true
        if install_conky_autostart; then
            CONKY_SETUP_DONE=true
        fi
    fi
}

setup_conky

# Step 9: Create desktop shortcuts
mark_desktop_file_trusted() {
    local desktop_file="$1"
    local checksum=""
    local trust_ok=false
    local uri="file://$desktop_file"

    _run_gio_set() {
        local target="$1"
        local key="$2"
        local value="$3"
        if gio set "$target" "$key" "$value" 2>/dev/null; then
            return 0
        fi
        if command -v dbus-launch &>/dev/null; then
            if dbus-launch gio set "$target" "$key" "$value" 2>/dev/null; then
                return 0
            fi
        fi
        if command -v dbus-run-session &>/dev/null; then
            if dbus-run-session -- gio set "$target" "$key" "$value" 2>/dev/null; then
                return 0
            fi
        fi
        return 1
    }

    if command -v sha256sum &>/dev/null; then
        checksum=$(sha256sum "$desktop_file" | awk '{print $1}')
    fi

    # GNOME/Nautilus and XFCE trust metadata (best-effort)
    if command -v gio &>/dev/null; then
        _run_gio_set "$desktop_file" metadata::trusted true || \
            _run_gio_set "$desktop_file" metadata::trusted yes || \
            _run_gio_set "$uri" metadata::trusted true || \
            _run_gio_set "$uri" metadata::trusted yes || true
        if [[ -n "$checksum" ]]; then
            _run_gio_set "$desktop_file" metadata::xfce-exe-checksum "$checksum" || \
                _run_gio_set "$uri" metadata::xfce-exe-checksum "$checksum" || true
        fi
    fi

    if command -v gvfs-set-attribute &>/dev/null; then
        gvfs-set-attribute -t string "$desktop_file" metadata::trusted "true" 2>/dev/null && trust_ok=true || true
        if [[ -n "$checksum" ]]; then
            gvfs-set-attribute -t string "$desktop_file" metadata::xfce-exe-checksum "$checksum" 2>/dev/null || true
        fi
    fi

    if command -v setfattr &>/dev/null; then
        setfattr -n user.xfce.executable -v true "$desktop_file" 2>/dev/null || true
    fi

    # Verify trust marker was really applied.
    if command -v gio &>/dev/null; then
        if gio info "$desktop_file" 2>/dev/null | grep -q "metadata::trusted: true"; then
            trust_ok=true
        fi
    fi

    if [[ "$trust_ok" != true ]]; then
        print_warning "Could not persist desktop trust metadata for: $desktop_file"
        print_warning "If XFCE shows untrusted prompt, right-click -> Allow Launching once."
    fi
}

create_desktop_shortcuts() {
    print_step "Creating desktop shortcuts..."

    local DESKTOP_DIR
    # Detect desktop directory (supports multiple languages)
    if [[ -d "$HOME/Desktop" ]]; then
        DESKTOP_DIR="$HOME/Desktop"
    elif [[ -d "$HOME/Escritorio" ]]; then
        DESKTOP_DIR="$HOME/Escritorio"
    elif [[ -d "$HOME/Bureau" ]]; then
        DESKTOP_DIR="$HOME/Bureau"
    elif [[ -d "$HOME/Schreibtisch" ]]; then
        DESKTOP_DIR="$HOME/Schreibtisch"
    elif command -v xdg-user-dir &>/dev/null; then
        DESKTOP_DIR="$(xdg-user-dir DESKTOP 2>/dev/null)"
    fi

    if [[ -z "$DESKTOP_DIR" ]] || [[ ! -d "$DESKTOP_DIR" ]]; then
        print_warning "Desktop directory not found, skipping shortcuts"
        return 0
    fi

    # Determine icon path (prefer hooks/icons first, then config/icons)
    local ICON_PATH="$INSTALL_PATH/icons/kodachi-dashboard.png"
    if [[ ! -f "$ICON_PATH" ]]; then
        ICON_PATH="$INSTALL_PATH/config/icons/kodachi-dashboard.png"
    fi
    if [[ ! -f "$ICON_PATH" ]]; then
        ICON_PATH="utilities-terminal"
    fi

    # Remove legacy launcher wrapper from older installer versions
    # (Desktop shortcut now uses direct Exec + Path)
    rm -f "$INSTALL_PATH/kodachi-dashboard-launcher.sh" 2>/dev/null || true

    # 1. Kodachi Dashboard shortcut
    # Match the proven Desktop-02 test style:
    # direct binary Exec + explicit Path to hooks directory.
    cat > "$DESKTOP_DIR/kodachi-dashboard.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Kodachi Dashboard
Comment=Kodachi Security Dashboard
Exec=$INSTALL_PATH/kodachi-dashboard
TryExec=$INSTALL_PATH/kodachi-dashboard
Path=$INSTALL_PATH
Icon=$ICON_PATH
Terminal=false
Categories=Security;System;
StartupNotify=true
StartupWMClass=kodachi-dashboard
X-XFCE-TrustedApplication=true
EOF
    chmod +x "$DESKTOP_DIR/kodachi-dashboard.desktop"
    mark_desktop_file_trusted "$DESKTOP_DIR/kodachi-dashboard.desktop"
    # Compatibility toggle for some XFCE/Thunar setups
    if command -v xfconf-query &>/dev/null; then
        xfconf-query -c thunar -p /misc-exec-shell-scripts-by-default -n -t bool -s true 2>/dev/null || true
    fi

    # 2. Kodachi Binaries folder shortcut
    # Match the proven Folder-02 style (thunar launcher).
    cat > "$DESKTOP_DIR/kodachi-binaries.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Kodachi Binaries
Comment=Open Kodachi binaries folder
Exec=thunar $INSTALL_PATH
Icon=folder-open
Terminal=false
Categories=Utility;
X-XFCE-TrustedApplication=true
EOF
    chmod +x "$DESKTOP_DIR/kodachi-binaries.desktop"
    mark_desktop_file_trusted "$DESKTOP_DIR/kodachi-binaries.desktop"

    # Ensure legacy folder symlink is removed; desktop shortcuts only.
    rm -f "$DESKTOP_DIR/kodachi-binaries" 2>/dev/null || true

    print_success "Desktop shortcuts created: kodachi-dashboard.desktop, kodachi-binaries.desktop"
}

# Create desktop shortcuts
create_desktop_shortcuts

# Step 10: Add to PATH in .bashrc with idempotent block management
if [[ "$SKIP_PATH_UPDATE" != "true" ]]; then
    print_step "Updating PATH in .bashrc..."

    # Use BEGIN/END markers for idempotent updates
    if ! grep -q "^# BEGIN KODACHI PATH$" "$HOME/.bashrc" 2>/dev/null; then
        # First time installation - add the block
        {
            echo ""
            echo "# BEGIN KODACHI PATH"
            echo "export KODACHI_HOME=\"$INSTALL_PATH\""
            echo "export PATH=\"\$KODACHI_HOME:\$PATH\""
            echo "# END KODACHI PATH"
        } >> "$HOME/.bashrc"
        print_success "Added Kodachi path block to .bashrc"
    else
        # Block exists - update the KODACHI_HOME value in place
        awk -v NEWHOME="$INSTALL_PATH" '
            BEGIN { inblk=0 }
            /^# BEGIN KODACHI PATH$/ {
                inblk=1
                print
                print "export KODACHI_HOME=\"" NEWHOME "\""
                print "export PATH=\"$KODACHI_HOME:$PATH\""
                next
            }
            /^# END KODACHI PATH$/ {
                inblk=0
                print
                next
            }
            { if (!inblk) print }
        ' "$HOME/.bashrc" > "$HOME/.bashrc.tmp" && mv "$HOME/.bashrc.tmp" "$HOME/.bashrc"
        print_success "Updated Kodachi path block in .bashrc"
    fi
fi

# Final summary
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║    Script #1 Complete - Binaries Installed!  ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
print_success "Kodachi binaries installed to: $INSTALL_PATH"
print_info "Binaries total: $TOTAL_COUNT"
print_info "Binaries installed: $VERIFIED_COUNT"
if [[ $SKIPPED_COUNT -gt 0 ]]; then
    print_warning "Binaries skipped: $SKIPPED_COUNT"
fi
print_info "Signatures verified: $VERIFIED_COUNT"
print_info "Desktop shortcuts: kodachi-dashboard, kodachi-binaries"
if [[ "$CONKY_SETUP_DONE" == "true" ]]; then
    print_info "Conky installed to: $CONKY_INSTALL_DIR"
    print_info "Conky startup file: $CONKY_AUTOSTART_FILE"
elif ! detect_gui_environment; then
    print_info "Conky: skipped (no GUI detected)"
fi

if [[ $FAILED_COUNT -gt 0 ]]; then
    print_warning "Signatures not verified: $FAILED_COUNT"
fi

if [[ "$PERMISSION_GUARD_SKIPPED" == "true" ]]; then
    echo ""
    echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  WARNING: permission-guard binary was NOT updated!         ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  To update it:"
    echo -e "    1. Stop the daemon:  ${BOLD}sudo permission-guard --stop-daemon${NC}"
    echo -e "    2. Re-run this script"
    echo ""
    echo -e "  The daemon will auto-restart on next login."
    echo ""
fi

echo ""
print_highlight "═══════════════════════════════════════════════════════════════"
print_highlight "  IMPORTANT: You Must Run Script #2 Next for Dashboard to Work"
print_highlight "═══════════════════════════════════════════════════════════════"
echo ""

# Function to check if user is in sudoers
check_sudoers_status() {
    local current_user=$(whoami)
    local in_sudo_group=false

    # Check if user is in sudo group
    if groups | grep -qw "sudo"; then
        in_sudo_group=true
    elif groups | grep -qw "wheel"; then
        in_sudo_group=true
    fi

    if [[ "$in_sudo_group" == "true" ]]; then
        print_success "User '$current_user' is in the sudoers group"
        echo ""
        print_highlight "Next Step - Script #2 (REQUIRED for Dashboard):"
        echo ""
        print_warning "The Dashboard and binaries won't work until you run the dependencies script!"
        echo ""
        echo -e "  ${CYAN}Download and run the dependencies installer:${NC}"
        echo -e "   ${BOLD}curl -sSL https://www.kodachi.cloud/apps/os/install/kodachi-deps-install.sh | sudo bash${NC}"
        echo ""
        echo -e "  ${CYAN}Or if you have it locally:${NC}"
        echo -e "   ${BOLD}sudo bash kodachi-deps-install.sh${NC}"
        echo ""
        print_info "This script installs system packages, configures sudoers for dashboard, and sets up DNS/Tor."
    else
        print_warning "User '$current_user' is NOT in the sudoers group"
        echo ""
        print_highlight "IMPORTANT: You need sudo access to run Script #2"
        echo ""
        print_highlight "To add yourself to the sudoers group:"
        echo ""
        echo "  1. Switch to root user:"
        echo -e "     ${BOLD}su -${NC}"
        echo ""
        echo "  2. Add your user to sudo group:"
        echo -e "     ${BOLD}usermod -aG sudo $current_user${NC}"
        echo ""
        echo "  3. Exit root session:"
        echo -e "     ${BOLD}exit${NC}"
        echo ""
        echo "  4. Log out and log back in for changes to take effect"
        echo ""
        print_highlight "After adding to sudoers, run Script #2:"
        echo ""
        print_warning "Dashboard won't work until you run the dependencies script!"
        echo ""
        echo -e "  ${CYAN}Script #2 - Dependencies Installer (REQUIRED):${NC}"
        echo -e "   ${BOLD}curl -sSL https://www.kodachi.cloud/apps/os/install/kodachi-deps-install.sh | sudo bash${NC}"
    fi
}

echo ""
# Check sudoers status and provide appropriate next steps
check_sudoers_status
echo ""
print_success "Binary installation complete! No sudo was required."
echo ""
