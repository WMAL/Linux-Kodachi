#!/bin/bash

# Kodachi Dependencies Installation Script (REQUIRES SUDO/ROOT)
# ==============================================================
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
# Features:
# =========
# - Automatic contrib/non-free repository enablement
# - Automatic DNS fix after systemd-resolved installation (dns-switch integration)
# - Per-package DNS testing for Privacy packages (detects which package breaks DNS)
# - DNS retry logic for GitHub downloads (handles network issues gracefully)
# - Verbose mode for detailed debugging output (--verbose or -v flag)
# - Multiple installation modes: full, minimal, interactive, proxy-only
# - Automatic architecture detection (amd64, ARM support)
# - Download retry with fallback mechanisms
# - Non-interactive package installation (prevents freezing)
#
# Description:
# This script installs all system package dependencies required for
# Kodachi security tools to function properly. Must be run as root or with sudo.
# Supports multiple installation modes: full (default), minimal, interactive, and proxy-only.
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
#   # Full automatic installation (default)
#   curl -sSL https://www.kodachi.cloud/apps/os/install/kodachi-deps-install.sh | sudo bash
#
#   # Interactive mode with prompts
#   curl -sSL https://www.kodachi.cloud/apps/os/install/kodachi-deps-install.sh -o kodachi-deps-install.sh && sudo bash kodachi-deps-install.sh --interactive
#
#   # Local execution
#   sudo bash kodachi-deps-install.sh [options]
#
# Options:
#   --minimal                    Install critical packages, networking, and proxy tools
#   --full                       Install all packages including optional ones (default)
#   --interactive                Interactive category-based installation with prompts
#   --proxy-only                 Install only proxy tools (v2ray, xray, hysteria2, mieru)
#   --auto                       Automatic mode - answer yes to all prompts (default)
#   --no-auto                    Disable automatic mode - require user confirmation
#   --forcegui, --force-gui      Force installation of GUI packages on terminal-based systems
#                                By default: GUI packages skipped if no desktop environment detected
#   --skipgui, --skip-gui        Skip GUI packages even on systems with desktop environments
#                                Use this for headless server installations on GUI systems
#   --force-kicksecure-ramwipe   Keep/Install Kicksecure RAM wipe (dracut + ram-wipe)
#                                By default: Removes dracut/ram-wipe, restores initramfs-tools
#                                Note: Kodachi has built-in RAM wipe via 'health-control memory-wipe'
#   --verbose, -v                Enable verbose mode - show detailed apt-get output and progress
#   --help                       Show help message

# Strict mode - will be disabled for interactive mode
set -eo pipefail
umask 022
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# CRITICAL FIX: Prevent job control signals from suspending apt-get processes
# Ignore SIGTSTP (Ctrl+Z), SIGTTIN (background read), SIGTTOU (background write)
trap '' SIGTSTP SIGTTIN SIGTTOU

# Disable job control globally to prevent suspend issues
set +m

# Security and reliability options
CURL_OPTS=(--fail --location --show-error --silent --connect-timeout 15 --max-time 120)
APT_RETRY_OPTS=(-o Acquire::Retries=3 -o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20)

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Verbose mode flag
VERBOSE_MODE=false

# Function to print colored output
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_step() { echo -e "${CYAN}[→]${NC} $1"; }
print_highlight() { echo -e "${MAGENTA}${BOLD}$1${NC}"; }
print_verbose() {
    if [[ "$VERBOSE_MODE" == "true" ]]; then
        local timestamp=$(date +"%H:%M:%S")
        echo -e "${CYAN}[VERBOSE ${timestamp}]${NC} $1"
    fi
}

# Function to apply fallback DNS servers (mimics dns-switch fix-dns behavior)
apply_fallback_dns() {
    print_step "Applying FALLBACK DNS fix (systemd-resolved + /etc/resolv.conf)..."

    # Step 1: Check if systemd-resolved is active and restart it if needed
    if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        print_verbose "systemd-resolved is active, restarting it..."
        systemctl restart systemd-resolved 2>/dev/null || true
        sleep 2
    else
        print_verbose "systemd-resolved not active, starting it..."
        systemctl start systemd-resolved 2>/dev/null || true
        sleep 2
    fi

    # Step 2: Fix /etc/resolv.conf symlink if needed
    if [[ -L "/etc/resolv.conf" ]]; then
        local target=$(readlink -f /etc/resolv.conf)
        if [[ "$target" != *"systemd"* ]]; then
            print_verbose "Fixing /etc/resolv.conf symlink to point to systemd-resolved..."
            ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf 2>/dev/null || true
        fi
    else
        print_verbose "/etc/resolv.conf is a regular file, converting to systemd symlink..."
        ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf 2>/dev/null || true
    fi

    # Step 3: Remove immutable attribute from /etc/resolv.conf (in case it's set)
    chattr -i /etc/resolv.conf 2>/dev/null || true

    # Step 4: Write fallback DNS servers directly to /etc/resolv.conf as backup
    # This ensures DNS works even if systemd-resolved fails
    print_verbose "Writing fallback DNS servers to /etc/resolv.conf..."
    cat > /etc/resolv.conf << 'EOF'
# Kodachi fallback DNS configuration
# Generated automatically after systemd-resolved installation
nameserver 1.1.1.1
nameserver 9.9.9.9
nameserver 149.112.112.112
nameserver 94.140.14.14
EOF

    # Step 5: Try to configure systemd-resolved via resolvectl if available
    if command -v resolvectl &>/dev/null; then
        print_verbose "Configuring systemd-resolved via resolvectl..."
        resolvectl dns 2>/dev/null || true
        resolvectl flush-caches 2>/dev/null || true
    fi

    print_success "Fallback DNS applied: 1.1.1.1, 9.9.9.9, 149.112.112.112, 94.140.14.14"
}

# Function to wait for DNS resolution to become available
# Retries DNS resolution with fallback DNS servers if needed
wait_for_dns() {
    local max_wait=30
    local waited=0

    print_step "Waiting for DNS resolution to become available..."

    while [[ $waited -lt $max_wait ]]; do
        # Test DNS with a lightweight lookup
        if timeout 3 getent hosts cloudflare.com >/dev/null 2>&1 || \
           timeout 3 getent hosts deb.debian.org >/dev/null 2>&1; then
            print_success "DNS resolution is working"
            return 0
        fi

        # Every 10 seconds, try applying fallback DNS
        if [[ $((waited % 10)) -eq 0 ]] && [[ $waited -gt 0 ]]; then
            print_verbose "DNS still not working after ${waited}s, reapplying fallback DNS..."
            apply_fallback_dns
        fi

        sleep 2
        waited=$((waited + 2))
    done

    # Final attempt: force fallback DNS
    print_warning "DNS not available after ${max_wait}s, forcing fallback DNS..."
    apply_fallback_dns
    sleep 2

    if timeout 5 getent hosts cloudflare.com >/dev/null 2>&1; then
        print_success "DNS resolution restored after fallback"
        return 0
    fi

    print_error "DNS resolution still unavailable after ${max_wait}s"
    return 1
}

# Function to configure sudoers for Kodachi binaries (NOPASSWD access)
configure_kodachi_sudoers() {
    print_step "Configuring sudoers for Kodachi binaries..."

    # Determine the actual user (not root) - SECURE method (no eval)
    local actual_user
    local real_user_home
    if [[ -n "$SUDO_USER" ]]; then
        # Validate SUDO_USER contains only valid username characters
        if [[ "$SUDO_USER" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            actual_user="$SUDO_USER"
            real_user_home=$(getent passwd "$SUDO_USER" | cut -d: -f6)
        else
            print_error "Invalid SUDO_USER detected"
            return 1
        fi
    else
        actual_user=$(whoami)
        real_user_home="$HOME"
    fi

    # Fallback if getent failed
    if [[ -z "$real_user_home" ]]; then
        real_user_home="/home/$actual_user"
    fi

    print_info "User: $actual_user"
    print_info "Home: $real_user_home"

    # Find dashboard location
    local dashboard_dir=""
    if [[ -d "$real_user_home/dashboard/hooks" ]]; then
        dashboard_dir="$real_user_home/dashboard/hooks"
    elif [[ -d "$real_user_home/Desktop/dashboard/hooks" ]]; then
        dashboard_dir="$real_user_home/Desktop/dashboard/hooks"
    fi

    if [[ -n "$dashboard_dir" ]]; then
        print_info "Dashboard found at: $dashboard_dir"
    else
        print_warning "Dashboard hooks directory not found, using /usr/local/bin only"
    fi

    # Get list of all executable binaries in hooks folder
    local binaries=()
    if [[ -n "$dashboard_dir" && -d "$dashboard_dir" ]]; then
        print_info "Scanning for Kodachi binaries in hooks directory..."
        while IFS= read -r -d '' binary; do
            local binary_name=$(basename "$binary")
            # Include ELF binaries
            if [[ -x "$binary" ]] && file "$binary" 2>/dev/null | grep -q "ELF"; then
                binaries+=("$binary_name")
            fi
        done < <(find "$dashboard_dir" -maxdepth 1 -type f -executable -print0 2>/dev/null)
    fi

    # Add common Kodachi binaries that might be missing or in /usr/local/bin
    local common_binaries=(
        "health-control"
        "tor-switch"
        "dns-switch"
        "routing-switch"
        "ip-fetch"
        "online-auth"
        "integrity-check"
        "dns-leak"
        "permission-guard"
        "logs-hook"
        "deps-checker"
        "oniux"
        "kodachi-dashboard"
        "global-launcher"
        "workflow-manager"
        "online-info-switch"
        "tun2socks-linux-amd64"
        # AI system binaries
        "ai-cmd"
        "ai-trainer"
        "ai-learner"
        "ai-admin"
        "ai-monitor"
        "ai-scheduler"
        "ai-discovery"
    )

    # Merge and deduplicate
    for common in "${common_binaries[@]}"; do
        if [[ ! " ${binaries[@]} " =~ " ${common} " ]]; then
            # Check if it exists in the directory or /usr/local/bin
            if [[ -f "$dashboard_dir/$common" ]] || [[ -f "/usr/local/bin/$common" ]]; then
                binaries+=("$common")
            else
                # Add anyway for future deployment
                binaries+=("$common")
            fi
        fi
    done

    # Remove duplicates and sort
    IFS=$'\n' binaries=($(printf '%s\n' "${binaries[@]}" | sort -u))
    unset IFS

    print_info "Found ${#binaries[@]} Kodachi binaries to configure"

    # Create sudoers.d directory if it doesn't exist
    mkdir -p /etc/sudoers.d

    # Backup existing sudoers file
    local sudoers_file="/etc/sudoers.d/kodachi-binaries"
    if [[ -f "$sudoers_file" ]]; then
        print_info "Backing up existing sudoers file..."
        cp "$sudoers_file" "${sudoers_file}.backup.$(date +%s)"
    fi

    # Create the kodachi-binaries sudoers file with ALL binaries for BOTH paths
    cat > "$sudoers_file" << EOF
# Kodachi System Binaries - Passwordless Sudo Access
# Generated: $(date)
# User: $actual_user
# Hooks Path: $dashboard_dir
# System Path: /usr/local/bin
#
# This file grants NOPASSWD sudo access to all Kodachi binaries
# deployed to /usr/local/bin/ and user's dashboard/hooks directory
#
# Security justification:
# - Full paths prevent PATH hijacking attacks
# - Binaries are cryptographically signed by Kodachi PKI
# - User already authenticated with password at login
# - Each binary has built-in permission guards and validation
# - Standard practice for system monitoring tools (htop, iotop, netdata)
#
# Syntax validation: visudo -c -f /etc/sudoers.d/kodachi-binaries
# Required permissions: 0440 (read-only, root:root)

# ============================================================
# Kodachi Binaries - Dual Path Configuration
# ============================================================
EOF

    # Add entries for each binary with BOTH paths
    for binary in "${binaries[@]}"; do
        if [[ -n "$dashboard_dir" ]]; then
            # Add hooks path entry
            echo "$actual_user ALL=(ALL) NOPASSWD: $dashboard_dir/$binary" >> "$sudoers_file"
        fi
        # Add /usr/local/bin path entry
        echo "$actual_user ALL=(ALL) NOPASSWD: /usr/local/bin/$binary" >> "$sudoers_file"
    done

    # Add system management commands
    cat >> "$sudoers_file" << EOF

# ============================================================
# System Power Management (menu options)
# ============================================================
$actual_user ALL=(ALL) NOPASSWD: /usr/sbin/reboot
$actual_user ALL=(ALL) NOPASSWD: /usr/sbin/shutdown
$actual_user ALL=(ALL) NOPASSWD: /usr/sbin/poweroff

# ============================================================
# Time Synchronization (welcome script)
# ============================================================
$actual_user ALL=(ALL) NOPASSWD: /usr/sbin/ntpdig
$actual_user ALL=(ALL) NOPASSWD: /usr/sbin/ntpdate
$actual_user ALL=(ALL) NOPASSWD: /usr/sbin/ntpd
$actual_user ALL=(ALL) NOPASSWD: /usr/bin/timedatectl

# End of Kodachi NOPASSWD rules
EOF

    # Dashboard TUI Terminal Tools (System Monitor tab)
    # Only add entries for tools that exist and aren't already in the file
    local tui_tools=("iftop" "nethogs" "lsof" "du")
    local tui_added=0
    for tui_bin in "${tui_tools[@]}"; do
        # Find the actual path of the binary
        local tui_path
        tui_path=$(command -v "$tui_bin" 2>/dev/null || true)
        if [[ -n "$tui_path" ]] && ! grep -q "$tui_path" "$sudoers_file" 2>/dev/null; then
            if [[ $tui_added -eq 0 ]]; then
                # Insert section header before "End of" marker
                sed -i '/# End of Kodachi NOPASSWD rules/i \\n# ============================================================\n# Dashboard TUI Terminal Tools (System Monitor tab)\n# ============================================================' "$sudoers_file"
                tui_added=1
            fi
            sed -i "/# End of Kodachi NOPASSWD rules/i $actual_user ALL=(ALL) NOPASSWD: $tui_path" "$sudoers_file"
        fi
    done
    if [[ $tui_added -gt 0 ]]; then
        print_info "Added NOPASSWD rules for Dashboard TUI tools"
    fi

    # Set correct permissions (0440 = read-only, root:root)
    chmod 0440 "$sudoers_file"
    chown root:root "$sudoers_file"

    # Validate sudoers file syntax
    if visudo -c -f "$sudoers_file" >/dev/null 2>&1; then
        local entry_count=$(grep -c "NOPASSWD" "$sudoers_file")
        print_success "Sudoers configured for user: $actual_user"
        print_info "Total NOPASSWD entries: $entry_count"
        print_info "Binaries configured: ${#binaries[@]}"
        if [[ -n "$dashboard_dir" ]]; then
            print_info "Paths: $dashboard_dir and /usr/local/bin"
        else
            print_info "Path: /usr/local/bin only"
        fi
        print_info "File: $sudoers_file"
        print_success "Kodachi binaries can now run with sudo without password (terminal and GUI)"
    else
        print_error "Sudoers file syntax validation failed!"
        print_warning "Removing invalid sudoers file for safety..."
        rm -f "$sudoers_file"
        # Restore backup if exists
        if [[ -f "${sudoers_file}.backup."* ]]; then
            local latest_backup=$(ls -t "${sudoers_file}.backup."* | head -1)
            cp "$latest_backup" "$sudoers_file"
            print_info "Restored previous backup: $latest_backup"
        fi
        return 1
    fi
}

# Install Conky assets and autostart profile for the real desktop user
install_kodachi_conky_for_user() {
    print_step "Configuring Kodachi Conky startup..."

    if [[ "${SKIP_GUI_INSTALL:-}" == "true" ]]; then
        print_info "GUI install skipped (--skipgui). Skipping Conky bootup setup."
        return 0
    fi
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

    local actual_user=""
    local real_user_home=""

    if [[ -n "${SUDO_USER:-}" ]] && [[ "$SUDO_USER" != "root" ]]; then
        actual_user="$SUDO_USER"
    elif [[ -n "${LOGNAME:-}" ]] && [[ "$LOGNAME" != "root" ]]; then
        actual_user="$LOGNAME"
    fi

    if [[ -z "$actual_user" ]] || [[ ! "$actual_user" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        print_warning "Could not determine target non-root user. Skipping Conky user setup."
        return 0
    fi

    real_user_home=$(getent passwd "$actual_user" | cut -d: -f6)
    if [[ -z "$real_user_home" ]]; then
        real_user_home="/home/$actual_user"
    fi

    local conky_source=""
    local candidates=(
        "/home/kodachi/k900/livebuild-assets/conky"
        "$real_user_home/k900/livebuild-assets/conky"
        "$real_user_home/dashboard/hooks/conky"
        "$real_user_home/Desktop/dashboard/hooks/conky"
        "/opt/kodachi/dashboard/hooks/conky"
    )

    for candidate in "${candidates[@]}"; do
        if [[ -d "$candidate/configs" ]] && [[ -d "$candidate/scripts" ]]; then
            conky_source="$candidate"
            break
        fi
    done

    if [[ -z "$conky_source" ]]; then
        # No source package found — check if Conky is already installed at destination
        local conky_dest="$real_user_home/.config/kodachi/conky"
        if [[ -d "$conky_dest/configs" ]] && [[ -d "$conky_dest/scripts" ]]; then
            print_success "Conky already installed at $conky_dest (no update source found)"
            return 0
        fi
        print_warning "Conky assets not found in known paths. Skipping Conky setup."
        return 0
    fi

    local conky_install_dir="$real_user_home/.config/kodachi/conky"
    local autostart_dir="$real_user_home/.config/autostart"
    local autostart_file="$autostart_dir/kodachi-conky.desktop"
    local launcher="$conky_install_dir/scripts/conky-launcher.sh"
    local watchdog_script="$conky_install_dir/scripts/conky-watchdog.sh"
    local service_source="$conky_install_dir/systemd/conky-watchdog.service"
    local systemd_user_dir="$real_user_home/.config/systemd/user"
    local service_file="$systemd_user_dir/conky-watchdog.service"
    local wants_dir="$systemd_user_dir/default.target.wants"
    local autostart_exec=""
    local autostart_tryexec=""

    mkdir -p "$(dirname "$conky_install_dir")" "$autostart_dir" "$systemd_user_dir" "$wants_dir"
    rm -rf "$conky_install_dir"
    cp -a "$conky_source" "$conky_install_dir"

    if [[ -d "$conky_install_dir/scripts" ]]; then
        find "$conky_install_dir/scripts" -type f -name "*.sh" -exec chmod 755 {} + 2>/dev/null || true
    fi

    if command -v systemctl >/dev/null 2>&1 && [[ -x "$watchdog_script" ]]; then
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
        autostart_exec="/usr/bin/systemctl --user start conky-watchdog.service"
        autostart_tryexec="/usr/bin/systemctl"
    elif [[ -x "$launcher" ]]; then
        autostart_exec="$launcher --restart"
        autostart_tryexec="$launcher"
        print_warning "Conky watchdog script missing at $watchdog_script. Falling back to launcher autostart."
    else
        print_warning "Conky launcher not found at $launcher. Skipping Conky setup."
        return 0
    fi

    cat > "$autostart_file" << EOF
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
    chmod 644 "$autostart_file"

    chown -R "$actual_user:$actual_user" "$conky_install_dir" 2>/dev/null || true
    chown "$actual_user:$actual_user" "$autostart_dir" 2>/dev/null || true
    chown "$actual_user:$actual_user" "$autostart_file" 2>/dev/null || true
    chown -R "$actual_user:$actual_user" "$systemd_user_dir" 2>/dev/null || true

    if command -v conky >/dev/null 2>&1; then
        if command -v systemctl >/dev/null 2>&1 && [[ -x "$watchdog_script" ]] && [[ -f "$service_file" ]]; then
            if command -v runuser >/dev/null 2>&1; then
                runuser -u "$actual_user" -- systemctl --user daemon-reload >/dev/null 2>&1 || true
                runuser -u "$actual_user" -- systemctl --user enable --now conky-watchdog.service >/dev/null 2>&1 || \
                    runuser -u "$actual_user" -- systemctl --user start conky-watchdog.service >/dev/null 2>&1 || true
            fi
            print_success "Conky configured for user $actual_user (watchdog enabled)"
        else
            print_warning "Conky watchdog script missing at $watchdog_script"
            print_success "Conky configured for user $actual_user (autostart enabled)"
        fi
    else
        print_warning "Conky binary not found. Install package 'conky-all' to run desktop panels."
    fi
}

# Function to download with retry logic for DNS failures
retry_download() {
    local url="$1"
    local output="$2"
    local max_attempts=3
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        print_verbose "Download attempt $attempt/$max_attempts: $url"

        if curl -LS --connect-timeout 30 --max-time 120 --progress-bar -o "$output" "$url" 2>&1; then
            if [[ -f "$output" ]] && [[ -s "$output" ]]; then
                print_verbose "Download successful on attempt $attempt"
                return 0
            else
                print_verbose "Downloaded file is empty or missing"
                rm -f "$output" 2>/dev/null || true
            fi
        fi

        local curl_exit=$?
        if [[ $curl_exit -eq 6 ]]; then
            print_verbose "DNS resolution failure detected (curl error 6)"
            if [[ $attempt -lt $max_attempts ]]; then
                print_info "Waiting for DNS to stabilize (attempt $attempt/$max_attempts)..."
                sleep 5
                wait_for_dns
            fi
        elif [[ $attempt -lt $max_attempts ]]; then
            print_verbose "Download failed with curl error $curl_exit, retrying in 3 seconds..."
            sleep 3
        fi

        attempt=$((attempt + 1))
    done

    print_error "Failed to download after $max_attempts attempts: $url"
    return 1
}

# Logging (file + console)
LOG_DIR="/var/log/kodachi"
LOG_FILE=""

setup_logging() {
    local ts
    ts=$(date +"%Y%m%d-%H%M%S")

    if mkdir -p "$LOG_DIR" 2>/dev/null; then
        chmod 700 "$LOG_DIR" 2>/dev/null || true
    else
        LOG_DIR="/tmp"
    fi

    LOG_FILE="$LOG_DIR/kodachi-deps-install-$ts.log"
    if ! touch "$LOG_FILE" 2>/dev/null; then
        LOG_FILE="/tmp/kodachi-deps-install-$ts.log"
        touch "$LOG_FILE" 2>/dev/null || true
    fi
    chmod 600 "$LOG_FILE" 2>/dev/null || true

    exec > >(tee -a "$LOG_FILE") 2>&1
    print_info "Logging to ${CYAN}$LOG_FILE${NC}"
    if [[ "$VERBOSE_MODE" == "true" ]]; then
        print_verbose "Verbose mode enabled - detailed output will be shown"
        print_verbose "Use 'tail -f $LOG_FILE' in another terminal to monitor progress"
    fi
}

# Version configuration
MIERU_VERSION="3.27.0"
HYSTERIA2_VERSION="2.7.0"
V2RAY_PLUGIN_VERSION="1.3.2"
DNSCRYPT_VERSION="2.1.15"
QRENCODE_VERSION="4.1.1"
KLOAK_VERSION="0.2"

# ============================================================================
# Version Comparison Functions
# ============================================================================

# Get installed version of a binary
get_installed_version() {
    local binary="$1"
    local version_flag="${2:---version}"  # Default flag

    if ! command -v "$binary" &>/dev/null; then
        echo ""
        return 1
    fi

    # Try different version extraction methods
    local version=""

    # Method 1: Direct version command
    version=$("$binary" $version_flag 2>&1 | grep -oP '([0-9]+\.)+[0-9]+' | head -1)

    # Method 2: For binaries that don't follow standard patterns
    if [[ -z "$version" ]]; then
        version=$("$binary" version 2>&1 | grep -oP '([0-9]+\.)+[0-9]+' | head -1)
    fi

    # Method 3: For dpkg packages
    if [[ -z "$version" ]] && dpkg -l "$binary" 2>/dev/null | grep -q "^ii"; then
        version=$(dpkg -l "$binary" | grep "^ii" | awk '{print $3}' | grep -oP '([0-9]+\.)+[0-9]+' | head -1)
    fi

    echo "$version"
}

# Compare two version strings
# Returns: 0 if v1 == v2, 1 if v1 > v2, 2 if v1 < v2
compare_versions() {
    local v1="$1"
    local v2="$2"

    # Remove 'v' prefix if present
    v1="${v1#v}"
    v2="${v2#v}"

    if [[ "$v1" == "$v2" ]]; then
        return 0  # Equal
    fi

    # Use sort -V for version comparison
    local sorted=$(printf '%s\n%s' "$v1" "$v2" | sort -V | head -1)

    if [[ "$sorted" == "$v1" ]]; then
        return 2  # v1 < v2
    else
        return 1  # v1 > v2
    fi
}

# Check if binary needs upgrade
needs_upgrade() {
    local binary="$1"
    local target_version="$2"
    local version_flag="${3:---version}"

    local installed_version=$(get_installed_version "$binary" "$version_flag")

    if [[ -z "$installed_version" ]]; then
        # Not installed
        return 0  # Needs install
    fi

    compare_versions "$installed_version" "$target_version"
    local result=$?

    if [[ $result -eq 2 ]]; then
        # Installed version < target version
        echo "upgrade|$installed_version|$target_version"
        return 0  # Needs upgrade
    elif [[ $result -eq 0 ]]; then
        # Versions are equal
        echo "current|$installed_version|$target_version"
        return 1  # No upgrade needed
    else
        # Installed version > target version (downgrade scenario)
        echo "newer|$installed_version|$target_version"
        return 1  # Don't downgrade
    fi
}

# Package categories - Reorganized for interactive installation
# Essential - Core system requirements
ESSENTIAL_PACKAGES="curl wget openssl ca-certificates coreutils findutils grep procps psmisc systemd sudo dmidecode lsof acl util-linux mount uuid-runtime inotify-tools ntpsec ntpsec-ntpdate isc-dhcp-client pass pwgen xkcdpass"

# Networking - Network and VPN tools
NETWORK_PACKAGES="tor torsocks obfs4proxy openvpn wireguard-tools iptables nftables arptables ebtables iproute2 iputils-ping net-tools nyx apt-transport-tor shadowsocks-libev redsocks microsocks haproxy"

# Security - Protection and hardening tools
SECURITY_PACKAGES="ufw macchanger firejail apparmor apparmor-utils apparmor-profiles aide lynis rkhunter chkrootkit usbguard ecryptfs-utils cryptsetup cryptsetup-initramfs cryptsetup-nuke-password fail2ban unattended-upgrades auditd libpam-pwquality libpam-google-authenticator secure-delete wipe nwipe"

# Privacy - DNS and anonymity tools
PRIVACY_PACKAGES="dnsutils bind9-dnsutils systemd-resolved"

# Advanced - Specialized tools and utilities (non-GUI)
ADVANCED_PACKAGES="jq git build-essential rng-tools-debian haveged ccze yamllint smartmontools lm-sensors hdparm htop iotop vnstat efibootmgr rfkill ethtool lsb-release pciutils"

# Monitoring - System and network monitoring tools for dashboard
MONITORING_PACKAGES="btop iftop nethogs ncdu nload iperf3 speedtest-cli"

# GUI-only packages - only installed on systems with desktop environments
GUI_PACKAGES="bleachbit kitty fontconfig fonts-noto-color-emoji conky-all alsa-utils pulseaudio pulseaudio-utils libnotify-bin xclip xsel mpv xterm network-manager"

# Packages that require contrib/non-free repositories
CONTRIB_PACKAGES="shadowsocks-v2ray-plugin v2ray"

# Separate resolvconf as it can conflict with systemd-resolved
RESOLVCONF_PACKAGE="resolvconf"

# Parse command line arguments
INSTALL_MODE="full"
AUTO_YES=true
INSTALL_KICKSECURE_RAMWIPE=false
FORCE_GUI_INSTALL=false
SKIP_GUI_INSTALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --minimal)
            INSTALL_MODE="minimal"
            shift
            ;;
        --full)
            INSTALL_MODE="full"
            shift
            ;;
        --interactive)
            INSTALL_MODE="interactive"
            AUTO_YES=false  # Interactive mode should not auto-answer
            shift
            ;;
        --proxy-only)
            INSTALL_MODE="proxy"
            shift
            ;;
        --auto)
            AUTO_YES=true
            shift
            ;;
        --no-auto)
            AUTO_YES=false
            shift
            ;;
        --force-kicksecure-ramwipe)
            INSTALL_KICKSECURE_RAMWIPE=true
            shift
            ;;
        --forcegui|--force-gui)
            FORCE_GUI_INSTALL=true
            shift
            ;;
        --skipgui|--skip-gui)
            SKIP_GUI_INSTALL=true
            shift
            ;;
        --verbose|-v)
            VERBOSE_MODE=true
            echo -e "${CYAN}[VERBOSE]${NC} Verbose mode enabled - showing detailed output"
            shift
            ;;
        --help)
            echo "Kodachi Dependencies Installation Script"
            echo ""
            echo "Usage:"
            echo "  curl -sSL .../kodachi-deps-install.sh | sudo bash"
            echo "  sudo bash kodachi-deps-install.sh [options]"
            echo ""
            echo "Options:"
            echo "  --minimal                    Install only critical packages"
            echo "  --full                       Install all packages (default)"
            echo "  --interactive                Interactive category-based installation"
            echo "  --proxy-only                 Install only proxy tools"
            echo "  --auto                       Automatic mode - answer yes to all prompts (default)"
            echo "  --no-auto                    Disable automatic mode - require user confirmation"
            echo "  --forcegui, --force-gui      Force installation of GUI packages on terminal-based systems"
            echo "                               By default: GUI packages skipped if no desktop environment detected"
            echo "  --skipgui, --skip-gui        Skip GUI packages even on systems with desktop environments"
            echo "                               Use this for headless server installations on GUI systems"
            echo "  --force-kicksecure-ramwipe   Keep/Install Kicksecure RAM wipe (dracut + ram-wipe)"
            echo "                               By default: Removes dracut/ram-wipe, restores initramfs-tools"
            echo "                               Note: Kodachi has built-in RAM wipe via 'health-control memory-wipe'"
            echo "  --verbose, -v                Enable verbose mode - show detailed output"
            echo "  --help                       Show this help message"
            echo ""
            echo "Examples:"
            echo "  sudo bash kodachi-deps-install.sh --full --auto"
            echo "  sudo bash kodachi-deps-install.sh --interactive"
            echo "  sudo bash kodachi-deps-install.sh --full --skipgui"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Function to check if systemd-resolved is managing DNS
check_systemd_resolved() {
    # Check if systemd-resolved is active
    if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        # Check if /etc/resolv.conf is a symlink to systemd-resolved
        if [[ -L "/etc/resolv.conf" ]] && [[ "$(readlink -f /etc/resolv.conf)" == *"systemd"* ]]; then
            return 0  # systemd-resolved is managing DNS
        fi
    fi
    return 1  # systemd-resolved is not managing DNS
}

# Function to detect if system has GUI/desktop environment
detect_gui_environment() {
    # Check for DISPLAY variable (X11 session)
    if [[ -n "$DISPLAY" ]] || [[ -n "$WAYLAND_DISPLAY" ]]; then
        return 0  # GUI detected
    fi

    # Check for running display managers
    local display_managers=(
        "lightdm" "gdm3" "gdm" "sddm" "kdm" "xdm" "lxdm" "slim"
        "nodm" "wdm" "entrance" "ly"
    )
    for dm in "${display_managers[@]}"; do
        if systemctl is-active --quiet "$dm" 2>/dev/null || pgrep -x "$dm" >/dev/null 2>&1; then
            return 0  # Display manager running
        fi
    done

    # Check systemd default target
    if systemctl get-default 2>/dev/null | grep -q "graphical.target"; then
        return 0  # System configured for graphical boot
    fi

    # Check for X11 or Wayland processes
    if pgrep -x "Xorg" >/dev/null 2>&1 || pgrep -x "X" >/dev/null 2>&1; then
        return 0  # X11 server running
    fi
    if pgrep -f "wayland" >/dev/null 2>&1 || [[ -n "$XDG_SESSION_TYPE" ]] && [[ "$XDG_SESSION_TYPE" == "wayland" ]]; then
        return 0  # Wayland session running
    fi

    # Check for installed desktop environments
    local desktop_packages=(
        "xfce4" "gnome-shell" "plasma-desktop" "lxde" "mate-desktop"
        "cinnamon" "budgie-desktop" "i3" "openbox"
    )
    for de in "${desktop_packages[@]}"; do
        if dpkg -l "$de" 2>/dev/null | grep -q "^ii"; then
            return 0  # Desktop environment installed
        fi
    done

    return 1  # No GUI detected
}

# Build GUI package list for current system.
# Conky is GUI-desktop-specific and should be skipped on terminal/headless systems.
get_gui_packages_for_install() {
    local packages="$GUI_PACKAGES"

    if ! detect_gui_environment; then
        packages=$(echo " $packages " | sed 's/ conky-all / /g' | xargs)
    fi

    echo "$packages"
}

# Function to install resolvconf with conflict handling
install_resolvconf_safe() {
    print_step "Checking resolvconf for WireGuard/OpenVPN support..."

    # First check if resolvconf has broken or partial installation
    local resolvconf_status=$(dpkg -l resolvconf 2>/dev/null | grep "^[ruihpF]" | awk '{print $1}')
    if [[ -n "$resolvconf_status" ]] && [[ "$resolvconf_status" != "ii" ]] && [[ "$resolvconf_status" != "un" ]]; then
        print_warning "Found broken resolvconf package (status: $resolvconf_status) - removing it"
        dpkg --remove --force-remove-reinstreq resolvconf 2>/dev/null || true
        dpkg --purge resolvconf 2>/dev/null || true
        apt-get clean 2>/dev/null || true
        dpkg --configure -a 2>/dev/null || true
    fi

    # Check if resolvconf is already properly installed
    if check_package "resolvconf"; then
        print_success "resolvconf is already installed"
        return 0
    fi

    # Check if resolvconf command exists (might be installed differently)
    if command -v resolvconf &>/dev/null; then
        print_success "resolvconf command is available"
        return 0
    fi

    # Check if WireGuard or OpenVPN is installed - they need resolvconf
    local need_resolvconf=false
    if check_package "wireguard-tools" || command -v wg-quick &>/dev/null; then
        print_info "WireGuard detected - needs resolvconf for DNS management"
        need_resolvconf=true
    fi
    if check_package "openvpn" || command -v openvpn &>/dev/null; then
        print_info "OpenVPN detected - may need resolvconf for DNS management"
        need_resolvconf=true
    fi

    # If VPN tools need resolvconf, try alternative solutions
    if [[ "$need_resolvconf" == "true" ]]; then
        print_warning "VPN tools need resolvconf functionality"

        # Option 1: Check DNS mode before installing openresolv
        if check_systemd_resolved; then
            # MODERN MODE: Do not install openresolv (conflicts with systemd-resolved)
            print_info "systemd-resolved detected - skipping openresolv (would conflict)"
            print_info "VPNs should use systemd-resolved's resolvectl for DNS updates"
        else
            # LEGACY MODE: Safe to install openresolv
            print_step "Installing openresolv as resolvconf alternative..."
            if apt-get install -y openresolv 2>&1 | tail -5; then
                if command -v resolvconf &>/dev/null; then
                    print_success "openresolv installed successfully - provides resolvconf command"
                    return 0
                fi
            fi
        fi

        # Option 2: Create a stub resolvconf script for WireGuard
        print_step "Creating resolvconf stub for WireGuard/OpenVPN..."
        cat > /tmp/resolvconf-stub << 'EOF'
#!/bin/bash
# Stub resolvconf for WireGuard/OpenVPN
# This prevents errors when VPNs try to update DNS

case "$1" in
    -a|-d)
        # Add or delete - just ignore for now
        # DNS is managed by dnscrypt-proxy/Pi-hole
        exit 0
        ;;
    *)
        # Other commands - ignore
        exit 0
        ;;
esac
EOF

        if [[ -f /tmp/resolvconf-stub ]]; then
            chmod +x /tmp/resolvconf-stub
            mv /tmp/resolvconf-stub /usr/local/bin/resolvconf
            print_success "Created resolvconf stub for VPN compatibility"
            print_info "Note: DNS updates from VPNs will be ignored - managed by dnscrypt-proxy/Pi-hole"
            return 0
        fi
    fi

    # If no VPN tools or alternatives worked, that's fine
    print_info "resolvconf not needed - DNS managed by dnscrypt-proxy/Pi-hole"
    print_info "If you use WireGuard/OpenVPN, DNS updates may need manual configuration"
    return 0
}

# Function to test and fix DNS after package installation
test_and_fix_dns() {
    local package_name="$1"

    print_step "Testing DNS after installing $package_name..."

    # Test if DNS is working by pinging a domain
    if timeout 5 ping -c 1 cloudflare.com >/dev/null 2>&1; then
        print_success "DNS is working correctly after $package_name install"
        return 0
    fi

    print_warning "DNS broken after installing $package_name - applying fixes..."

    # PRIMARY FIX: Try dns-switch fix-dns
    local dns_switch_binary=""

    # Detect real user's home directory (not root's home when using sudo) - secure method
    local real_user_home=""
    if [[ -n "$SUDO_USER" ]]; then
        real_user_home=$(getent passwd "$SUDO_USER" | cut -d: -f6)
        # Fallback if getent failed
        if [[ -z "$real_user_home" ]]; then
            real_user_home="/home/$SUDO_USER"
        fi
    else
        real_user_home="$HOME"
    fi

    # Try to find dns-switch using 'which' command first (searches PATH)
    dns_switch_binary=$(which dns-switch 2>/dev/null || true)

    # If not in PATH, check standard installation directories
    if [[ -z "$dns_switch_binary" ]]; then
        local possible_locations=(
            "$real_user_home/dashboard/hooks/dns-switch"           # Default installation
            "$real_user_home/Desktop/dashboard/hooks/dns-switch"   # Desktop installation
            "/opt/kodachi/dashboard/hooks/dns-switch"              # System-wide installation
            "/usr/local/bin/dns-switch"                            # System binary path
            "/usr/bin/dns-switch"                                  # System binary path
        )

        for location in "${possible_locations[@]}"; do
            if [[ -x "$location" ]]; then
                dns_switch_binary="$location"
                break
            fi
        done
    fi

    # Run dns-switch fix-dns if found (PRIMARY FIX)
    if [[ -n "$dns_switch_binary" ]]; then
        print_step "Applying PRIMARY DNS fix (dns-switch fix-dns)..."
        print_verbose "Using dns-switch from: $dns_switch_binary"

        if sudo "$dns_switch_binary" fix-dns 2>&1 | tail -5; then
            print_success "dns-switch fix-dns completed"
        else
            print_warning "dns-switch returned error, continuing anyway"
        fi

        # Give DNS a moment to stabilize
        sleep 2

        # Test DNS after primary fix
        if timeout 5 ping -c 1 cloudflare.com >/dev/null 2>&1; then
            print_success "DNS RESTORED after PRIMARY fix (dns-switch)!"
            return 0
        fi

        # Primary fix didn't work, try fallback
        print_warning "DNS still broken after primary fix, trying fallback..."
    else
        print_warning "dns-switch binary NOT FOUND in any location!"
        print_info "Searched: which dns-switch, $real_user_home/dashboard/hooks, /opt/kodachi/dashboard/hooks, /usr/local/bin, /usr/bin"
        print_info "Skipping primary fix, will use fallback method..."
    fi

    # FALLBACK FIX: Apply fallback DNS servers (only runs if primary failed or not found)
    apply_fallback_dns

    # Final test after fallback
    if timeout 5 ping -c 1 cloudflare.com >/dev/null 2>&1; then
        print_success "DNS RESTORED after FALLBACK fix!"
        return 0
    else
        print_error "DNS STILL BROKEN after all fixes - downloads will fail!"
        print_error "Please manually run: dns-switch fix-dns"
        return 1
    fi
}

# Function to install privacy packages one by one with DNS testing
install_privacy_packages_safe() {
    print_highlight "Installing Privacy packages (with DNS testing after each)..."
    echo ""

    # Install each package separately and test DNS after each
    local privacy_pkgs=("dnsutils" "bind9-dnsutils" "systemd-resolved")

    for pkg in "${privacy_pkgs[@]}"; do
        print_step "Installing $pkg..."

        if check_package "$pkg"; then
            print_success "$pkg is already installed"
        else
            print_step "Installing $pkg..."
            if timeout 600 apt-get install -y -o DPkg::Use-Pty=0 -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" < /dev/null "$pkg" 2>&1 | tail -10; then
                print_success "$pkg installed successfully"
            else
                print_error "Failed to install $pkg"
                continue
            fi
        fi

        # CRITICAL: Test and fix DNS after each package
        test_and_fix_dns "$pkg"
        echo ""
    done

    # Configure systemd-resolved after all packages are installed
    configure_systemd_resolved
}

# Function to configure systemd-resolved safely
configure_systemd_resolved() {
    print_step "Configuring systemd-resolved..."

    # CRITICAL: Always configure DNS immediately, don't wait for package checks
    # Create config directory
    mkdir -p /etc/systemd/resolved.conf.d

    # Check if dnscrypt-proxy or Pi-hole is active (they should handle DNS)
    if systemctl is-active --quiet dnscrypt-proxy 2>/dev/null; then
        print_info "dnscrypt-proxy is active - configuring systemd-resolved as fallback"
        # Disable systemd-resolved's DNS stub listener to avoid port 53 conflict
        # But keep fallback DNS servers for when DNSCrypt isn't available
        cat > /etc/systemd/resolved.conf.d/kodachi.conf << 'EOF'
# Kodachi configuration - dnscrypt-proxy handles DNS
[Resolve]
DNSStubListener=no
# Fallback DNS servers (privacy-focused, NO Google)
FallbackDNS=1.1.1.1 9.9.9.9 149.112.112.112 94.140.14.14
EOF
        # SECURITY FIX: Repoint /etc/resolv.conf when disabling stub listener
        ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
        systemctl restart systemd-resolved 2>/dev/null || true
        print_success "systemd-resolved configured (stub listener disabled, privacy-focused fallback DNS)"
        return 0
    fi

    # Check if Pi-hole is active
    if systemctl is-active --quiet pihole-FTL 2>/dev/null; then
        print_info "Pi-hole is active - configuring systemd-resolved as fallback"
        # Disable systemd-resolved's DNS stub listener to avoid port 53 conflict
        # But keep fallback DNS servers for when Pi-hole isn't available
        cat > /etc/systemd/resolved.conf.d/kodachi.conf << 'EOF'
# Kodachi configuration - Pi-hole handles DNS
[Resolve]
DNSStubListener=no
# Fallback DNS servers (privacy-focused, NO Google)
FallbackDNS=1.1.1.1 9.9.9.9 149.112.112.112 94.140.14.14
EOF
        # SECURITY FIX: Repoint /etc/resolv.conf when disabling stub listener
        ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
        systemctl restart systemd-resolved 2>/dev/null || true
        print_success "systemd-resolved configured (stub listener disabled, privacy-focused fallback DNS)"
        return 0
    fi

    # Neither DNSCrypt nor Pi-hole is active - use systemd-resolved as primary DNS
    print_info "Configuring systemd-resolved as primary DNS resolver (privacy-focused, NO Google)"
    cat > /etc/systemd/resolved.conf.d/kodachi.conf << 'EOF'
# Kodachi configuration - systemd-resolved as primary DNS
[Resolve]
# Primary DNS servers (privacy-focused: Cloudflare, Quad9, AdGuard - NO Google)
DNS=1.1.1.1 9.9.9.9 149.112.112.112 94.140.14.14
# Fallback DNS servers (Cloudflare IPv4 alt, Quad9 uncensored)
FallbackDNS=1.0.0.1 149.112.112.10
# Enable DNSSEC validation
DNSSEC=allow-downgrade
# Cache settings
Cache=yes
EOF

    # Enable and start systemd-resolved if not active
    if ! systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        print_step "Enabling systemd-resolved service..."
        systemctl enable systemd-resolved 2>/dev/null || true
        systemctl start systemd-resolved 2>/dev/null || true
    else
        # Restart to apply new configuration
        systemctl restart systemd-resolved 2>/dev/null || true
    fi

    print_success "systemd-resolved configured with privacy-focused DNS (NO Google)"

    # Wait for DNS service to stabilize
    print_verbose "Waiting 3 seconds for DNS service to stabilize..."
    sleep 3

    # CRITICAL FIX: Run dns-switch fix-dns to restore internet connectivity (PRIMARY METHOD)
    # After systemd-resolved installation, DNS often breaks and internet is lost
    # Dynamically locate dns-switch binary (NO HARDCODED PATHS)
    local dns_switch_binary=""

    # Try to find dns-switch in PATH first
    if command -v dns-switch &>/dev/null; then
        dns_switch_binary="dns-switch"
    else
        # Check standard installation directories dynamically using $HOME
        local possible_locations=(
            "$HOME/dashboard/hooks/dns-switch"           # Default installation
            "$HOME/Desktop/dashboard/hooks/dns-switch"   # Desktop installation
            "/opt/kodachi/dashboard/hooks/dns-switch"    # System-wide installation
            "/usr/local/bin/dns-switch"                  # System binary path
            "/usr/bin/dns-switch"                        # System binary path
        )

        for location in "${possible_locations[@]}"; do
            if [[ -x "$location" ]]; then
                dns_switch_binary="$location"
                break
            fi
        done
    fi

    # Run dns-switch fix-dns if found
    if [[ -n "$dns_switch_binary" ]]; then
        print_step "Running dns-switch fix-dns to restore internet connectivity..."
        print_verbose "Using dns-switch from: $dns_switch_binary"

        # Run with sudo since this script is already running as root
        if sudo "$dns_switch_binary" fix-dns 2>&1 | tail -5; then
            print_success "dns-switch fix-dns completed"
        else
            print_warning "dns-switch fix-dns returned error, continuing anyway"
        fi

        # Give DNS a moment to stabilize after fix
        sleep 2
    else
        print_warning "dns-switch binary not found in common locations"
        print_info "Searched locations: $HOME/dashboard/hooks/dns-switch, /opt/kodachi/dashboard/hooks/dns-switch"
        print_info "Skipping primary DNS fix, will use fallback method"
    fi

    # Test if DNS is working by pinging a domain
    print_step "Testing DNS resolution with ping..."
    if timeout 5 ping -c 1 cloudflare.com >/dev/null 2>&1; then
        print_success "DNS is working correctly - internet restored!"
    else
        print_warning "DNS test failed, applying fallback DNS fix..."
        # FALLBACK: Use wait_for_dns if primary method didn't work
        wait_for_dns

        # Test again after fallback
        if timeout 5 ping -c 1 cloudflare.com >/dev/null 2>&1; then
            print_success "DNS working after fallback fix"
        else
            print_error "DNS still not working after all fixes - downloads may fail"
            print_info "You may need to manually run: dns-switch fix-dns"
        fi
    fi
}

# Function to initialize iptables alternatives properly
initialize_iptables_alternatives() {
    print_step "Initializing iptables alternatives..."

    # Install arptables and ebtables if missing
    local missing_packages=""
    for pkg in arptables ebtables; do
        if ! check_package "$pkg"; then
            missing_packages="$missing_packages $pkg"
        fi
    done

    if [[ -n "$missing_packages" ]]; then
        print_info "Installing missing packages:$missing_packages"
        apt-get install -y $missing_packages 2>&1 | tail -5
    fi

    # Create the arptables alternatives group if missing (register both backends when present)
    if ! update-alternatives --query arptables >/dev/null 2>&1; then
        print_info "Registering arptables alternatives..."
        [ -x /usr/sbin/arptables-legacy ] && update-alternatives --install /usr/sbin/arptables arptables /usr/sbin/arptables-legacy 10
        [ -x /usr/sbin/arptables-nft ] && update-alternatives --install /usr/sbin/arptables arptables /usr/sbin/arptables-nft 20
    fi

    # Create the ebtables alternatives group if missing
    if ! update-alternatives --query ebtables >/dev/null 2>&1; then
        print_info "Registering ebtables alternatives..."
        [ -x /usr/sbin/ebtables-legacy ] && update-alternatives --install /usr/sbin/ebtables ebtables /usr/sbin/ebtables-legacy 10
        [ -x /usr/sbin/ebtables-nft ] && update-alternatives --install /usr/sbin/ebtables ebtables /usr/sbin/ebtables-nft 20
    fi

    # Optionally align arptables/ebtables to whichever iptables backend is active (safe no-op if unknown)
    local IPT=$(readlink -f /etc/alternatives/iptables 2>/dev/null || true)
    case "$IPT" in
        *iptables-legacy)
            [ -x /usr/sbin/arptables-legacy ] && update-alternatives --set arptables /usr/sbin/arptables-legacy 2>/dev/null || true
            [ -x /usr/sbin/ebtables-legacy ] && update-alternatives --set ebtables /usr/sbin/ebtables-legacy 2>/dev/null || true
            print_success "Aligned arptables/ebtables to legacy backend"
            ;;
        *iptables-nft)
            [ -x /usr/sbin/arptables-nft ] && update-alternatives --set arptables /usr/sbin/arptables-nft 2>/dev/null || true
            [ -x /usr/sbin/ebtables-nft ] && update-alternatives --set ebtables /usr/sbin/ebtables-nft 2>/dev/null || true
            print_success "Aligned arptables/ebtables to nft backend"
            ;;
        *)
            print_info "iptables backend unknown, skipping alignment"
            ;;
    esac

    print_success "iptables alternatives initialized"
}

# Function to check if contrib and non-free are enabled
check_contrib_nonfree() {
    local has_contrib=false
    local has_nonfree=false

    if grep -q "contrib" /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null; then
        has_contrib=true
    fi

    if grep -q "non-free" /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null; then
        has_nonfree=true
    fi

    if [[ "$has_contrib" == "true" ]] && [[ "$has_nonfree" == "true" ]]; then
        return 0  # Both are enabled
    else
        return 1  # One or both are missing
    fi
}

# Function to automatically enable contrib and non-free repositories
enable_contrib_nonfree() {
    print_step "Enabling contrib and non-free repositories..."

    # Backup sources.list
    cp /etc/apt/sources.list /etc/apt/sources.list.backup 2>/dev/null || true

    # Modify sources.list to add contrib non-free non-free-firmware
    # This works for any Debian-based distribution
    sed -i 's/main$/main contrib non-free non-free-firmware/' /etc/apt/sources.list 2>/dev/null || true
    sed -i 's/main contrib$/main contrib non-free non-free-firmware/' /etc/apt/sources.list 2>/dev/null || true
    sed -i 's/main non-free$/main contrib non-free non-free-firmware/' /etc/apt/sources.list 2>/dev/null || true

    # Update package lists
    print_step "Updating package lists after enabling repositories..."
    if apt-get update 2>&1 | tail -10; then
        print_success "Contrib and non-free repositories enabled and package lists updated"
        return 0
    else
        print_warning "Failed to update package lists, but repositories were modified"
        return 1
    fi
}

# Function to install DNSCrypt Proxy from GitHub
install_dnscrypt_github() {
    print_step "Checking DNSCrypt Proxy installation..."

    # Check if upgrade is needed
    local check_result=$(needs_upgrade "dnscrypt-proxy" "$DNSCRYPT_VERSION" "-version")
    local status=$(echo "$check_result" | cut -d'|' -f1)
    local installed=$(echo "$check_result" | cut -d'|' -f2)
    local target=$(echo "$check_result" | cut -d'|' -f3)

    if [[ "$status" == "current" ]]; then
        print_success "DNSCrypt Proxy is already up to date (v$installed)"

        # ALWAYS ensure config file exists
        setup_dnscrypt_config

        # Check if systemd service exists and is enabled
        if systemctl list-unit-files dnscrypt-proxy.service &>/dev/null 2>&1; then
            if systemctl is-enabled --quiet dnscrypt-proxy 2>/dev/null; then
                print_success "DNSCrypt Proxy service is already enabled"
            else
                print_info "DNSCrypt Proxy service exists but not enabled - enabling now..."
                if systemctl enable dnscrypt-proxy 2>/dev/null; then
                    print_success "DNSCrypt Proxy service enabled"
                else
                    print_warning "Failed to enable DNSCrypt Proxy service"
                fi
            fi
        else
            # Service file doesn't exist, create it
            print_info "DNSCrypt Proxy service file missing - creating now..."
            setup_dnscrypt_service "existing"
        fi

        return 0
    elif [[ "$status" == "newer" ]]; then
        print_success "DNSCrypt Proxy is already installed (v$installed, newer than target v$target)"

        # ALWAYS ensure config file exists
        setup_dnscrypt_config

        return 0
    elif [[ "$status" == "upgrade" ]]; then
        print_warning "DNSCrypt Proxy found (v$installed) - upgrading to v$target..."
    else
        print_step "Installing DNSCrypt Proxy v$DNSCRYPT_VERSION..."
    fi

    local arch=""
    case $(uname -m) in
        x86_64) arch="x86_64" ;;
        aarch64) arch="arm64" ;;
        armv7l) arch="arm" ;;
        *)
            print_error "Unsupported architecture for DNSCrypt Proxy: $(uname -m)"
            return 1
            ;;
    esac

    local url="https://github.com/DNSCrypt/dnscrypt-proxy/releases/download/${DNSCRYPT_VERSION}/dnscrypt-proxy-linux_${arch}-${DNSCRYPT_VERSION}.tar.gz"
    local temp_dir="/tmp/dnscrypt-proxy-install"
    local install_dir="/etc/dnscrypt-proxy"

    echo "Downloading DNSCrypt Proxy v${DNSCRYPT_VERSION}..."
    mkdir -p "$temp_dir"

    if retry_download "$url" "$temp_dir/dnscrypt-proxy.tar.gz"; then
        echo "Extracting DNSCrypt Proxy..."
        tar -xzf "$temp_dir/dnscrypt-proxy.tar.gz" -C "$temp_dir"

        # Find and install the binary
        local extracted_dir=$(find "$temp_dir" -name "linux-${arch}" -type d | head -1)
        if [[ -z "$extracted_dir" ]]; then
            # Try different naming pattern
            extracted_dir=$(find "$temp_dir" -name "*linux*${arch}*" -type d | head -1)
        fi

        if [[ -n "$extracted_dir" && -f "$extracted_dir/dnscrypt-proxy" ]]; then
            print_info "Installing DNSCrypt Proxy to $install_dir..."
            sudo mkdir -p "$install_dir"
            sudo cp -r "$extracted_dir"/* "$install_dir/"
            sudo chmod +x "$install_dir/dnscrypt-proxy"

            # Create symbolic link for system-wide access
            if [[ -f "/usr/local/bin/dnscrypt-proxy" ]]; then
                sudo rm -f "/usr/local/bin/dnscrypt-proxy"
            fi
            sudo ln -sf "$install_dir/dnscrypt-proxy" "/usr/local/bin/dnscrypt-proxy"

            rm -rf "$temp_dir"
            print_success "DNSCrypt Proxy installed successfully from GitHub"

            # Setup configuration file
            setup_dnscrypt_config

            # Setup systemd service
            setup_dnscrypt_service "github"

            return 0
        else
            print_error "Could not find DNSCrypt Proxy binary in archive"
            rm -rf "$temp_dir"
            return 1
        fi
    else
        print_error "Failed to download DNSCrypt Proxy from GitHub"
        rm -rf "$temp_dir"
        return 1
    fi
}

# Function to install QRencode with apt-first strategy
install_qrencode_github() {
    print_step "Checking QRencode installation..."

    # Check if upgrade is needed
    local check_result=$(needs_upgrade "qrencode" "$QRENCODE_VERSION" "--version")
    local status=$(echo "$check_result" | cut -d'|' -f1)
    local installed=$(echo "$check_result" | cut -d'|' -f2)
    local target=$(echo "$check_result" | cut -d'|' -f3)

    if [[ "$status" == "current" ]]; then
        print_success "QRencode is already up to date (v$installed)"
        return 0
    elif [[ "$status" == "newer" ]]; then
        print_success "QRencode is already installed (v$installed, newer than target v$target)"
        return 0
    elif [[ "$status" == "upgrade" ]]; then
        print_warning "QRencode found (v$installed) - upgrading to v$target..."
    else
        print_step "Installing QRencode v$QRENCODE_VERSION..."
    fi

    # QRencode Installation Strategy:
    # - APT first: Same version (4.1.1), pre-compiled, faster installation
    # - GitHub fallback: For systems without apt package or version mismatch
    # - Compilation avoided when possible to reduce dependencies and time
    # - Archive URL used instead of releases/download (which doesn't exist)
    
    local install_success=false

    # Try APT installation first (preferred method)
    print_info "Attempting APT installation first (faster, pre-compiled)..."
    if timeout 60 apt-get install -y -o DPkg::Use-Pty=0 -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" < /dev/null qrencode 2>/dev/null; then
        if command -v qrencode &>/dev/null; then
            print_success "QRencode installed successfully via APT"
            return 0
        fi
    fi

    # Fallback to GitHub compilation if APT fails (uses cmake — GitHub archives lack ./configure)
    print_warning "APT installation failed, falling back to GitHub compilation..."
    local url="https://github.com/fukuchi/libqrencode/archive/v${QRENCODE_VERSION}.tar.gz"
    local temp_dir="/tmp/qrencode-install-$$"

    echo "Installing build dependencies for compilation..."
    # Install build dependencies (cmake for build, libpng-dev for PNG QR output)
    apt-get update 2>/dev/null || true
    apt-get install -y build-essential cmake libpng-dev 2>&1 | tail -5

    echo "Downloading QRencode v${QRENCODE_VERSION} source..."
    mkdir -p "$temp_dir"
    cd "$temp_dir" || return 1

    # Download source from GitHub (using fixed archive URL)
    if curl -L --connect-timeout 30 --max-time 120 -O "$url" 2>/dev/null; then
        echo "Downloaded QRencode source from GitHub"

        # Extract and compile using cmake (GitHub archives don't include ./configure)
        if tar xf "v${QRENCODE_VERSION}.tar.gz" 2>/dev/null; then
            cd "libqrencode-${QRENCODE_VERSION}" || return 1
            mkdir -p build && cd build

            if cmake -DCMAKE_INSTALL_PREFIX=/usr/local -DCMAKE_POLICY_VERSION_MINIMUM=3.5 .. >/dev/null 2>&1 && \
               make >/dev/null 2>&1 && \
               make install >/dev/null 2>&1; then

                # Update library cache
                ldconfig 2>/dev/null || true

                # Verify installation
                if command -v qrencode &>/dev/null || [ -x /usr/local/bin/qrencode ]; then
                    print_success "QRencode compiled and installed successfully from GitHub (cmake)"
                    install_success=true
                fi
            fi
        fi
    fi

    # Cleanup
    cd / && rm -rf "$temp_dir"
    
    if [ "$install_success" = true ]; then
        return 0
    else
        print_error "Failed to install QRencode via both APT and GitHub compilation"
        return 1
    fi
}

# Function to install v2ray-plugin from GitHub
install_v2ray_plugin_github() {
    print_step "Checking v2ray-plugin installation..."

    # Check if upgrade is needed
    local check_result=$(needs_upgrade "v2ray-plugin" "$V2RAY_PLUGIN_VERSION" "--version")
    local status=$(echo "$check_result" | cut -d'|' -f1)
    local installed=$(echo "$check_result" | cut -d'|' -f2)
    local target=$(echo "$check_result" | cut -d'|' -f3)

    if [[ "$status" == "current" ]]; then
        print_success "v2ray-plugin is already up to date (v$installed)"
        return 0
    elif [[ "$status" == "newer" ]]; then
        print_success "v2ray-plugin is already installed (v$installed, newer than target v$target)"
        return 0
    elif [[ "$status" == "upgrade" ]]; then
        print_warning "v2ray-plugin found (v$installed) - upgrading to v$target..."
        # Remove old binary before installing new version
        rm -f /usr/local/bin/v2ray-plugin 2>/dev/null || true
        rm -f /usr/local/bin/ss-v2ray-plugin 2>/dev/null || true
    else
        print_step "Installing v2ray-plugin v$V2RAY_PLUGIN_VERSION..."
    fi

    local arch=""
    case $(uname -m) in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7l) arch="arm" ;;
        *)
            print_error "Unsupported architecture for v2ray-plugin: $(uname -m)"
            return 1
            ;;
    esac

    local url="https://github.com/shadowsocks/v2ray-plugin/releases/download/v${V2RAY_PLUGIN_VERSION}/v2ray-plugin-linux-${arch}-v${V2RAY_PLUGIN_VERSION}.tar.gz"
    local temp_dir="/tmp/v2ray-plugin-install"

    echo "Downloading v2ray-plugin v${V2RAY_PLUGIN_VERSION}..."
    mkdir -p "$temp_dir"

    if curl -LS --connect-timeout 30 --max-time 120 --progress-bar -o "$temp_dir/v2ray-plugin.tar.gz" "$url"; then
        echo "Extracting v2ray-plugin..."
        tar -xzf "$temp_dir/v2ray-plugin.tar.gz" -C "$temp_dir"

        # Find and install the binary
        if [ -f "$temp_dir/v2ray-plugin_linux_${arch}" ]; then
            mv "$temp_dir/v2ray-plugin_linux_${arch}" /usr/local/bin/v2ray-plugin
        elif [ -f "$temp_dir/v2ray-plugin" ]; then
            mv "$temp_dir/v2ray-plugin" /usr/local/bin/v2ray-plugin
        else
            print_error "Could not find v2ray-plugin binary in archive"
            rm -rf "$temp_dir"
            return 1
        fi

        chmod +x /usr/local/bin/v2ray-plugin
        rm -rf "$temp_dir"

        # Create symlink for shadowsocks compatibility
        ln -sf /usr/local/bin/v2ray-plugin /usr/local/bin/ss-v2ray-plugin 2>/dev/null || true

        print_success "v2ray-plugin installed successfully from GitHub"
        return 0
    else
        print_error "Failed to download v2ray-plugin from GitHub"
        rm -rf "$temp_dir"
        return 1
    fi
}

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
        print_info "You can run this script with: sudo bash $0"
    else
        print_warning "User '$current_user' is NOT in the sudoers group"
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
        print_info "After adding to sudoers, run: sudo bash $0"
    fi
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root or with sudo"
    echo ""

    # Check sudoers status and provide guidance
    check_sudoers_status

    exit 1
fi

# ============================================================================
# SYSTEM UPDATE - Upgrade all packages before installing dependencies
# ============================================================================
print_step "Updating system packages..."
print_info "Running apt-get update to refresh package lists..."

if apt-get update 2>&1 | tail -5; then
    print_success "Package lists updated successfully"
else
    print_warning "apt-get update had issues, continuing anyway..."
fi

echo ""
print_step "Upgrading installed packages..."
print_info "Running apt-get upgrade to ensure system is up-to-date..."

# Use DEBIAN_FRONTEND=noninteractive to avoid prompts
export DEBIAN_FRONTEND=noninteractive

if apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" 2>&1 | tail -20; then
    print_success "System packages upgraded successfully"
else
    print_warning "apt-get upgrade had issues, continuing anyway..."
fi

echo ""

# ============================================================================
# CHECK IF KODACHI BINARIES ARE INSTALLED (REQUIRED BEFORE RUNNING THIS SCRIPT)
# ============================================================================
print_step "Checking if Kodachi binaries are installed..."

# Detect real user's home directory (secure method - no eval)
if [[ -n "$SUDO_USER" ]]; then
    REAL_USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    # Fallback if getent failed
    if [[ -z "$REAL_USER_HOME" ]]; then
        REAL_USER_HOME="/home/$SUDO_USER"
    fi
else
    REAL_USER_HOME="$HOME"
fi

# Check for binaries in standard locations
BINARIES_FOUND=false
BINARIES_LOCATION=""

# Possible binary locations
BINARY_LOCATIONS=(
    "$REAL_USER_HOME/dashboard/hooks"
    "$REAL_USER_HOME/Desktop/dashboard/hooks"
    "/opt/kodachi/dashboard/hooks"
    "/usr/local/bin"
)

# Core binaries that must exist
REQUIRED_BINARIES=("health-control" "tor-switch" "dns-switch" "kodachi-dashboard")
FOUND_COUNT=0

for location in "${BINARY_LOCATIONS[@]}"; do
    if [[ -d "$location" ]]; then
        # Count how many required binaries exist in this location
        local_found=0
        for binary in "${REQUIRED_BINARIES[@]}"; do
            if [[ -x "$location/$binary" ]]; then
                local_found=$((local_found + 1))
            fi
        done

        # If we found at least 3 out of 4 required binaries, consider this the location
        if [[ $local_found -ge 3 ]]; then
            BINARIES_FOUND=true
            BINARIES_LOCATION="$location"
            FOUND_COUNT=$local_found
            break
        fi
    fi
done

if [[ "$BINARIES_FOUND" == "false" ]]; then
    echo ""
    print_error "Kodachi binaries NOT FOUND!"
    echo ""
    print_highlight "═══════════════════════════════════════════════════════════════"
    print_highlight "  IMPORTANT: This is Script #2 - Run AFTER Installing Binaries"
    print_highlight "═══════════════════════════════════════════════════════════════"
    echo ""
    print_warning "You must install Kodachi binaries FIRST using:"
    echo ""
    echo -e "  ${CYAN}Script #1 (Run First):${NC}"
    echo -e "  ${BOLD}curl -sSL https://www.kodachi.cloud/apps/os/install/kodachi-binary-install.sh | bash${NC}"
    echo ""
    echo -e "  ${CYAN}Script #2 (Run After):${NC}"
    echo -e "  ${BOLD}curl -sSL https://www.kodachi.cloud/apps/os/install/kodachi-deps-install.sh | sudo bash${NC}"
    echo ""
    print_info "The binaries script installs Kodachi tools to ~/dashboard/hooks"
    print_info "This deps script installs system dependencies and configures sudoers"
    echo ""
    print_error "Aborting installation - please run kodachi-binary-install.sh first"
    echo ""
    exit 1
else
    print_success "Kodachi binaries found in: $BINARIES_LOCATION"
    print_info "Found $FOUND_COUNT required binaries"
fi

echo ""

# ============================================================================
# CONFIGURE SUDOERS EARLY - Before any package installation that might fail
# ============================================================================
print_step "Configuring sudoers for Kodachi binaries (early setup)..."
configure_kodachi_sudoers
echo ""

# Start logging after confirming root access and binaries
setup_logging

# Welcome message
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   Kodachi Dependencies Installation Script   ║${NC}"
echo -e "${CYAN}║             (Requires Sudo/Root)             ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""

print_info "Installation mode: $INSTALL_MODE"
if [[ "$AUTO_YES" == "true" ]]; then
    print_info "Auto mode enabled: All prompts will default to YES"
fi
echo ""

# ============================================================================
# DETECT PRE-EXISTING SERVICE STATE - Important for updates!
# ============================================================================
print_step "Detecting pre-existing service states..."
echo ""

# Critical services that should NOT be stopped if already running (could break internet)
INITIAL_DNSCRYPT_RUNNING=false
INITIAL_TOR_RUNNING=false
INITIAL_PIHOLE_RUNNING=false
INITIAL_REDSOCKS_RUNNING=false

# Non-critical services (can be stopped even if running)
INITIAL_CUPS_RUNNING=false
INITIAL_AVAHI_RUNNING=false
INITIAL_NTP_RUNNING=false

if systemctl is-active --quiet dnscrypt-proxy 2>/dev/null; then
    INITIAL_DNSCRYPT_RUNNING=true
    print_info "DNSCrypt Proxy detected running (will be preserved)"
fi

if systemctl is-active --quiet tor 2>/dev/null || pgrep -x tor >/dev/null 2>&1; then
    INITIAL_TOR_RUNNING=true
    print_info "Tor detected running (will be preserved)"
fi

if systemctl is-active --quiet pihole-FTL 2>/dev/null; then
    INITIAL_PIHOLE_RUNNING=true
    print_info "Pi-hole detected running (will be preserved)"
fi

if systemctl is-active --quiet redsocks 2>/dev/null || pgrep -x redsocks >/dev/null 2>&1; then
    INITIAL_REDSOCKS_RUNNING=true
    print_info "Redsocks detected running (will be preserved)"
fi

if systemctl is-active --quiet cups 2>/dev/null || pgrep -x cupsd >/dev/null 2>&1; then
    INITIAL_CUPS_RUNNING=true
fi

if systemctl is-active --quiet avahi-daemon 2>/dev/null || pgrep -x avahi-daemon >/dev/null 2>&1; then
    INITIAL_AVAHI_RUNNING=true
fi

if pgrep -x ntpd >/dev/null 2>&1 || systemctl is-active --quiet ntp 2>/dev/null; then
    INITIAL_NTP_RUNNING=true
fi

echo ""
print_success "Service state detection complete"
echo ""

# ============================================================================
# TIME SYNCHRONIZATION - Critical for HTTPS certificate validation
# ============================================================================
print_step "Synchronizing system time..."
timedatectl set-ntp true 2>/dev/null || true
sleep 2
print_success "Time sync enabled"
echo ""

# Kill any stuck apt/dpkg processes
cleanup_apt() {
    if pgrep -x apt-get > /dev/null; then
        print_warning "Killing stuck apt-get processes..."
        killall -9 apt-get 2>/dev/null || true
        sleep 2
    fi

    if pgrep -x dpkg > /dev/null; then
        print_warning "Killing stuck dpkg processes..."
        killall -9 dpkg 2>/dev/null || true
        sleep 2
    fi

    # Clean up locks
    rm -f /var/lib/dpkg/lock-frontend 2>/dev/null || true
    rm -f /var/lib/dpkg/lock 2>/dev/null || true
    rm -f /var/cache/apt/archives/lock 2>/dev/null || true
    rm -f /var/lib/apt/lists/lock 2>/dev/null || true

    # Reconfigure dpkg if needed - more aggressive
    print_info "Running dpkg --configure -a to fix any interrupted installations..."
    dpkg --configure -a 2>&1 | tail -3 || true

    # Fix broken dependencies
    print_info "Fixing any broken dependencies..."
    apt-get install -f -y 2>&1 | tail -3 || true
}

# Function to wait for apt/dpkg to finish
wait_for_apt() {
    while fuser /var/lib/dpkg/lock >/dev/null 2>&1 || fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
        echo "Waiting for other package managers to finish..."
        sleep 2
    done
}

# Function to ensure dpkg is in a healthy state
ensure_dpkg_healthy() {
    local retry_count=0
    local max_retries=3

    while [[ $retry_count -lt $max_retries ]]; do
        # Kill stuck processes
        if pgrep -x apt-get > /dev/null; then
            print_warning "Killing stuck apt-get processes..."
            killall -9 apt-get 2>/dev/null || true
            sleep 2
        fi

        if pgrep -x dpkg > /dev/null; then
            print_warning "Killing stuck dpkg processes..."
            killall -9 dpkg 2>/dev/null || true
            sleep 2
        fi

        # Remove locks
        rm -f /var/lib/dpkg/lock-frontend 2>/dev/null || true
        rm -f /var/lib/dpkg/lock 2>/dev/null || true
        rm -f /var/cache/apt/archives/lock 2>/dev/null || true
        rm -f /var/lib/apt/lists/lock 2>/dev/null || true

        # Configure any pending packages
        print_info "Configuring pending packages..."
        if dpkg --configure -a 2>&1 | tail -3; then
            print_success "Package system is healthy"
            return 0
        else
            retry_count=$((retry_count + 1))
            if [[ $retry_count -lt $max_retries ]]; then
                print_warning "dpkg configuration failed, retry $retry_count/$max_retries..."
                sleep 3
            fi
        fi
    done

    print_error "Failed to configure dpkg after $max_retries attempts"
    return 1
}

# Function to generate random alphanumeric password
generate_pihole_password() {
    # Generate random password 12-16 characters, alphanumeric only
    local length=$((12 + RANDOM % 5))  # Random length between 12-16
    local password=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w $length | head -n 1)
    echo "$password"
}

# Clean up first
cleanup_apt

# Function to automatically remove Kicksecure RAM wipe and restore initramfs-tools
# Only runs if --force-kicksecure-ramwipe flag is NOT used
remove_kicksecure_ramwipe_and_restore_initramfs() {
    # Skip if user explicitly wants Kicksecure RAM wipe
    if [[ "$INSTALL_KICKSECURE_RAMWIPE" == "true" ]]; then
        return 0
    fi

    # Check if any Kicksecure ramwipe packages are installed
    local has_ramwipe=false
    local has_dracut=false
    local has_dracut_core=false
    local packages_to_remove=""

    if check_package_installed "ram-wipe"; then
        has_ramwipe=true
        packages_to_remove="$packages_to_remove ram-wipe"
    fi

    if check_package_installed "dracut"; then
        has_dracut=true
        packages_to_remove="$packages_to_remove dracut"
    fi

    if check_package_installed "dracut-core"; then
        has_dracut_core=true
        packages_to_remove="$packages_to_remove dracut-core"
    fi

    # If no packages found, nothing to do
    if [[ "$has_ramwipe" == "false" ]] && [[ "$has_dracut" == "false" ]] && [[ "$has_dracut_core" == "false" ]]; then
        return 0
    fi

    # Display removal notice
    echo ""
    print_step "Removing Kicksecure RAM Wipe Components"
    echo ""
    print_info "Kodachi has built-in RAM wipe via 'health-control memory-wipe'"
    print_info "Removing redundant Kicksecure packages:$packages_to_remove"
    echo ""
    print_warning "To keep Kicksecure RAM wipe, use: --force-kicksecure-ramwipe"
    echo ""

    # Purge the packages
    export DEBIAN_FRONTEND=noninteractive
    if apt-get purge -y$packages_to_remove 2>&1 | grep -E "(Removing|Purging)"; then
        print_success "Removed Kicksecure RAM wipe packages"
    else
        print_warning "Some packages may not have been installed"
    fi

    # Clean up dependencies
    print_step "Cleaning up unused dependencies..."
    if apt-get autoremove -y 2>&1 | grep -E "(Removing|freed)" | head -5; then
        print_success "Cleaned up dependencies"
    fi

    # CRITICAL: Restore initramfs-tools (dracut replacement)
    echo ""
    print_step "Restoring initramfs-tools (dracut replacement)..."
    print_warning "Installing initramfs-tools to ensure kernel updates work correctly"

    if apt-get install -y initramfs-tools 2>&1 | tail -5; then
        print_success "initramfs-tools installed successfully"
    else
        print_error "Failed to install initramfs-tools - kernel updates may fail!"
        print_warning "Please manually install: sudo apt-get install initramfs-tools"
    fi

    # Check if Kicksecure repository should be removed
    echo ""
    print_step "Checking Kicksecure repository usage..."

    local has_kicksecure_repo=false
    if [[ -f "/etc/apt/sources.list.d/kicksecure.list" ]]; then
        has_kicksecure_repo=true
    fi

    if [[ "$has_kicksecure_repo" == "true" ]]; then
        # Check if other Kicksecure packages are installed
        local other_packages=$(dpkg -l 2>/dev/null | grep -i "^ii" | grep -E "(kicksecure|whonix)" | grep -v -E "(ram-wipe|dracut)" | wc -l)

        # Also check for kloak specifically (may come from Whonix repo)
        local has_kloak=false
        if check_package_installed "kloak"; then
            # Check if kloak is from Kicksecure repo
            if apt-cache policy kloak 2>/dev/null | grep -q "deb.kicksecure.com"; then
                has_kloak=true
            fi
        fi

        if [[ $other_packages -eq 0 ]] && [[ "$has_kloak" == "false" ]]; then
            print_info "No other Kicksecure packages detected - removing repository"

            # Remove repository
            rm -f /etc/apt/sources.list.d/kicksecure.list 2>/dev/null || true
            rm -f /usr/share/keyrings/kicksecure.gpg 2>/dev/null || true

            print_success "Kicksecure repository removed"
        else
            print_info "Other Kicksecure packages detected - keeping repository"
            if [[ "$has_kloak" == "true" ]]; then
                print_info "  • kloak is using Kicksecure repository"
            fi
        fi
    fi

    echo ""
    print_success "Kicksecure RAM wipe removal completed"
    echo ""
}

# Helper function to check if package is installed (used by removal function)
check_package_installed() {
    local pkg="$1"
    if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
        return 0
    else
        return 1
    fi
}

# Run the removal function before any installations
remove_kicksecure_ramwipe_and_restore_initramfs

# Function to check if package is installed
check_package() {
    local pkg="$1"
    if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
        return 0
    else
        return 1
    fi
}

# Function to check if DNS tools are available
check_dns_tools() {
    # Check if any of the DNS tools are available
    if command -v dig &>/dev/null || command -v nslookup &>/dev/null || command -v host &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to install category with user confirmation
install_category_interactive() {
    local packages="$1"
    local category="$2"
    local description="$3"
    local manual_info="$4"
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    print_highlight "$category Installation"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Show description
    echo "$description"
    echo ""
    
    # Show packages that will be installed
    print_info "Packages to be installed:"
    echo ""
    
    # Format packages in columns
    local cols=3
    local i=0
    
    # Convert packages string to array safely
    read -ra pkg_array <<< "$packages"
    
    for pkg in "${pkg_array[@]}"; do
        printf "  %-25s" "$pkg"
        i=$((i + 1))
        if [[ $((i % cols)) -eq 0 ]]; then
            echo ""
        fi
    done
    
    if [[ $((i % cols)) -ne 0 ]]; then
        echo ""
    fi
    
    echo ""
    
    # Check for auto mode
    if [[ "$AUTO_YES" == "true" ]]; then
        print_info "Auto mode: Installing $category packages..."
        install_packages "$packages" "$category"
        return 0
    else
        # FIXED: Simple working input method (stdin already redirected via exec)
        echo -n "Do you want to install $category packages? (YES/no) [default: yes]: "
        read -r REPLY
        # Default to YES if empty
        if [[ -z "$REPLY" ]]; then
            REPLY="yes"
        fi
        echo ""
        
        if [[ $REPLY =~ ^[Yy]([Ee][Ss])?$ ]]; then
            install_packages "$packages" "$category"
            return 0
        else
            print_info "Skipping $category installation"
            echo ""
            print_highlight "To install $category packages manually:"
            echo ""
            echo "$manual_info"
            echo ""
            return 1
        fi
    fi
}

# Function to install packages with status display
install_packages() {
    local packages="$1"
    local category="$2"
    local to_install=""
    local failed_list=""

    print_step "Installing $category packages..."
    print_verbose "========== CATEGORY: $category =========="
    print_verbose "Packages to check: $packages"

    export DEBIAN_FRONTEND=noninteractive

    # Check and display status for each package
    for pkg in $packages; do
        # Special handling for dnsutils - check for actual commands
        if [[ "$pkg" == "dnsutils" ]]; then
            if check_dns_tools; then
                echo -e "  ${GREEN}✓${NC} $pkg - already installed (DNS tools available)"
            else
                to_install="$to_install $pkg"
                echo -e "  ${YELLOW}→${NC} $pkg - will install"
            fi
        elif check_package "$pkg"; then
            echo -e "  ${GREEN}✓${NC} $pkg - already installed"
        else
            to_install="$to_install $pkg"
            echo -e "  ${YELLOW}→${NC} $pkg - will install"
        fi
    done

    # Install missing packages if any
    if [[ -n "$to_install" ]]; then
        echo ""
        echo "Installing missing packages..."
        print_verbose "Missing packages to install: $to_install"

        # Handle rkhunter separately to prevent exim4 installation
        local rkhunter_separate=""
        local other_packages=""
        
        for pkg in $to_install; do
            if [[ "$pkg" == "rkhunter" ]]; then
                rkhunter_separate="$pkg"
            else
                other_packages="$other_packages $pkg"
            fi
        done

        # Install rkhunter with --no-install-recommends if needed
        if [[ -n "$rkhunter_separate" ]]; then
            echo "Installing rkhunter without recommended packages (prevents exim4)..."
            print_verbose "Installing rkhunter: $rkhunter_separate"
            if [[ "$VERBOSE_MODE" == "true" ]]; then
                timeout 600 apt-get install -y -o DPkg::Use-Pty=0 -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" --no-install-recommends $rkhunter_separate < /dev/null 2>&1 | cat
            else
                timeout 600 apt-get install -y -o DPkg::Use-Pty=0 -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" --no-install-recommends $rkhunter_separate < /dev/null 2>&1 | tail -10
            fi
            print_verbose "rkhunter installation completed"
        fi

        # Install other packages normally (600 second timeout for complex packages with triggers)
        # SECURITY FIX: Disable set -e temporarily to prevent premature exit on pipeline failure
        local install_result=true
        if [[ -n "$other_packages" ]]; then
            print_verbose "Installing packages: $other_packages"
            set +e
            if [[ "$VERBOSE_MODE" == "true" ]]; then
                # Verbose mode: show full output (pipe through cat to prevent job control issues)
                timeout 600 apt-get install -y -o DPkg::Use-Pty=0 -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" $other_packages < /dev/null 2>&1 | cat
            else
                # Normal mode: show only last 10 lines
                timeout 600 apt-get install -y -o DPkg::Use-Pty=0 -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" $other_packages < /dev/null 2>&1 | tail -10
            fi
            if [ ${PIPESTATUS[0]} -ne 0 ]; then
                install_result=false
            fi
            set -e
            print_verbose "Package installation completed with exit code: ${PIPESTATUS[0]}"
        fi

        if $install_result; then
            # Check which ones actually installed
            for pkg in $to_install; do
                # Special handling for dnsutils - check for actual DNS tools functionality
                if [[ "$pkg" == "dnsutils" ]]; then
                    if check_dns_tools; then
                        echo -e "  ${GREEN}✓${NC} $pkg - DNS tools available"
                    else
                        echo -e "  ${RED}✗${NC} $pkg - failed to install"
                        failed_list="$failed_list $pkg"
                    fi
                elif check_package "$pkg"; then
                    echo -e "  ${GREEN}✓${NC} $pkg - installed successfully"
                else
                    echo -e "  ${RED}✗${NC} $pkg - failed to install"
                    failed_list="$failed_list $pkg"
                fi
            done
        else
            print_warning "Installation command had issues"

            # Try to fix dpkg state and retry
            print_info "Attempting to fix package system..."
            ensure_dpkg_healthy

            # Retry installation once (600 second timeout for complex packages)
            print_info "Retrying installation..."
            print_verbose "Retrying packages: $to_install"
            if [[ "$VERBOSE_MODE" == "true" ]]; then
                timeout 600 apt-get install -y -o DPkg::Use-Pty=0 -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" $to_install < /dev/null 2>&1 | cat
            else
                timeout 600 apt-get install -y -o DPkg::Use-Pty=0 -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" $to_install < /dev/null 2>&1 | tail -10
            fi
            if [ ${PIPESTATUS[0]} -eq 0 ]; then
                print_success "Retry successful"
            fi
            print_verbose "Retry completed with exit code: ${PIPESTATUS[0]}"

            # Check what got installed after retry
            for pkg in $to_install; do
                # Special handling for dnsutils - check for actual DNS tools functionality
                if [[ "$pkg" == "dnsutils" ]]; then
                    if check_dns_tools; then
                        echo -e "  ${GREEN}✓${NC} $pkg - DNS tools available after retry"
                    else
                        echo -e "  ${RED}✗${NC} $pkg - failed to install"
                        failed_list="$failed_list $pkg"
                    fi
                elif check_package "$pkg"; then
                    echo -e "  ${GREEN}✓${NC} $pkg - installed after retry"
                else
                    echo -e "  ${RED}✗${NC} $pkg - failed to install"
                    failed_list="$failed_list $pkg"
                fi
            done
        fi

        if [[ -n "$failed_list" ]]; then
            print_warning "Failed to install:$failed_list"
            # One final dpkg configure to ensure system is clean for next batch
            dpkg --configure -a 2>/dev/null || true
        fi
    else
        print_success "All $category packages already installed"
    fi

    echo ""
}

# Function to handle contrib/non-free packages
install_contrib_packages() {
    print_step "Checking contrib/non-free package requirements..."

    local v2ray_plugin_installed=false
    local v2ray_installed=false
    local show_repo_warning=false

    # Check if packages are already installed
    if check_package "shadowsocks-v2ray-plugin" || command -v v2ray-plugin &>/dev/null; then
        v2ray_plugin_installed=true
        print_success "v2ray-plugin is already installed"
    fi

    if check_package "v2ray" || command -v v2ray &>/dev/null; then
        v2ray_installed=true
        print_success "v2ray is already installed"
    fi

    # Check if contrib and non-free are enabled
    if check_contrib_nonfree; then
        print_success "Contrib and non-free repositories are enabled"

        # Try to install shadowsocks-v2ray-plugin if not already installed
        if ! $v2ray_plugin_installed; then
            print_step "Installing shadowsocks-v2ray-plugin from apt..."
            if timeout 60 apt-get install -y -o DPkg::Use-Pty=0 -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" < /dev/null shadowsocks-v2ray-plugin 2>&1 | tail -5; then
                print_success "shadowsocks-v2ray-plugin installed via apt"
                v2ray_plugin_installed=true
            else
                print_warning "Failed to install shadowsocks-v2ray-plugin via apt, trying GitHub..."
                if install_v2ray_plugin_github; then
                    v2ray_plugin_installed=true
                fi
            fi
        fi

        # Try to install v2ray if not already installed
        if ! $v2ray_installed; then
            print_step "Installing v2ray from apt..."
            if timeout 60 apt-get install -y -o DPkg::Use-Pty=0 -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" < /dev/null v2ray 2>&1 | tail -5; then
                print_success "v2ray installed via apt"
                v2ray_installed=true
            else
                print_warning "Failed to install v2ray via apt"
                print_info "v2ray may require manual installation or is not available in your distribution"
            fi
        fi
    else
        # Repositories not enabled - AUTOMATICALLY ENABLE THEM
        print_warning "Contrib and/or non-free repositories are NOT enabled!"
        echo ""

        # Automatically enable the repositories
        if enable_contrib_nonfree; then
            # Repositories now enabled, try installing packages again
            print_step "Retrying package installations after enabling repositories..."

            # Try to install shadowsocks-v2ray-plugin if not already installed
            if ! $v2ray_plugin_installed; then
                print_step "Installing shadowsocks-v2ray-plugin from apt..."
                if timeout 60 apt-get install -y -o DPkg::Use-Pty=0 -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" < /dev/null shadowsocks-v2ray-plugin 2>&1 | tail -5; then
                    print_success "shadowsocks-v2ray-plugin installed via apt"
                    v2ray_plugin_installed=true
                else
                    print_warning "Failed to install shadowsocks-v2ray-plugin via apt, trying GitHub..."
                    if install_v2ray_plugin_github; then
                        v2ray_plugin_installed=true
                    fi
                fi
            fi

            # Try to install v2ray if not already installed
            if ! $v2ray_installed; then
                print_step "Installing v2ray from apt..."
                if timeout 60 apt-get install -y -o DPkg::Use-Pty=0 -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" < /dev/null v2ray 2>&1 | tail -5; then
                    print_success "v2ray installed via apt"
                    v2ray_installed=true
                else
                    print_warning "Failed to install v2ray via apt"
                    print_info "v2ray may require manual installation or is not available in your distribution"
                fi
            fi
        else
            print_error "Failed to enable contrib/non-free repositories automatically"
            print_info "You may need to manually edit /etc/apt/sources.list"
        fi

        # Install v2ray-plugin from GitHub if not already installed
        if ! $v2ray_plugin_installed; then
            print_step "Installing v2ray-plugin from GitHub (fallback)..."
            if install_v2ray_plugin_github; then
                v2ray_plugin_installed=true
            fi
        fi

        # Only show v2ray warning if it's actually missing
        if ! $v2ray_installed; then
            print_warning "v2ray package cannot be installed without contrib/non-free repositories"
        fi
    fi
}

# Function to install v2ray
install_v2ray() {
    print_step "Installing v2ray..."

    if command -v v2ray &>/dev/null; then
        print_success "v2ray is already installed"
        return 0
    fi

    # First try apt if contrib/non-free are enabled
    if check_contrib_nonfree; then
        echo "Attempting to install v2ray from apt..."
        if timeout 60 apt-get install -y -o DPkg::Use-Pty=0 -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" < /dev/null v2ray 2>&1 | tail -5; then
            if command -v v2ray &>/dev/null; then
                print_success "v2ray installed via apt"
                return 0
            fi
        fi
    fi

    # Fallback to GitHub installation
    echo "Installing v2ray from GitHub..."
    # Download and execute the v2ray installer script
    if retry_download "https://github.com/v2fly/fhs-install-v2ray/raw/master/install-release.sh" "/tmp/v2ray-install.sh"; then
        if timeout 120 bash /tmp/v2ray-install.sh; then
            rm -f /tmp/v2ray-install.sh
            if command -v v2ray &>/dev/null; then
                print_success "v2ray installed successfully from GitHub"
                return 0
            fi
        else
            rm -f /tmp/v2ray-install.sh
        fi
    fi

    print_error "Failed to install v2ray"
    print_info "You can try manual installation from: https://github.com/v2fly/v2ray-core"
}

# Function to install xray
install_xray() {
    print_step "Installing xray..."

    if command -v xray &>/dev/null; then
        print_success "xray is already installed"
        return 0
    fi

    echo "Downloading and installing xray..."

    # SECURITY FIX: Download script to temp file and verify before execution
    local xray_script="/tmp/xray-install-$$.sh"
    if retry_download "https://github.com/XTLS/Xray-install/raw/main/install-release.sh" "$xray_script"; then
        # Basic sanity check: verify it's a bash script
        if head -1 "$xray_script" | grep -q "^#!.*bash"; then
            # Display script hash for verification (admin can compare with known good hash)
            local script_hash=$(sha256sum "$xray_script" | cut -d' ' -f1)
            echo -e "${BLUE}[INFO]${NC} xray installer script SHA256: ${CYAN}${script_hash}${NC}"

            # Execute the verified script
            if timeout 120 bash "$xray_script" install -u root; then
                print_success "xray installed successfully"
                rm -f "$xray_script"
                return 0
            else
                print_error "Failed to install xray"
                rm -f "$xray_script"
                return 1
            fi
        else
            print_error "Downloaded xray installer is not a valid bash script"
            rm -f "$xray_script"
            return 1
        fi
    else
        print_error "Failed to download xray installer"
        return 1
    fi
}

# Function to install mieru
install_mieru() {
    print_step "Checking mieru installation..."

    # Check if upgrade is needed
    local check_result=$(needs_upgrade "mieru" "$MIERU_VERSION" "--version")
    local status=$(echo "$check_result" | cut -d'|' -f1)
    local installed=$(echo "$check_result" | cut -d'|' -f2)
    local target=$(echo "$check_result" | cut -d'|' -f3)

    if [[ "$status" == "current" ]]; then
        print_success "mieru is already up to date (v$installed)"
        return 0
    elif [[ "$status" == "newer" ]]; then
        print_success "mieru is already installed (v$installed, newer than target v$target)"
        return 0
    elif [[ "$status" == "upgrade" ]]; then
        print_warning "mieru found (v$installed) - upgrading to v$target..."
        # Old version will be removed after successful download (not before)
    else
        print_step "Installing mieru v$MIERU_VERSION..."
    fi

    # SECURITY FIX: Detect architecture dynamically instead of hardcoding amd64
    local arch=$(dpkg --print-architecture 2>/dev/null || echo "amd64")
    local temp_file="/tmp/mieru_${MIERU_VERSION}_${arch}.deb"
    local url="https://github.com/enfein/mieru/releases/download/v${MIERU_VERSION}/mieru_${MIERU_VERSION}_${arch}.deb"

    echo "Downloading mieru client..."
    if retry_download "$url" "$temp_file"; then
        echo "Installing mieru client package..."

        # Make sure no apt is running
        cleanup_apt

        # Remove old version only after download succeeds (safe upgrade)
        apt-get remove -y mieru 2>/dev/null || true

        # Install with dpkg then fix dependencies
        if dpkg -i "$temp_file"; then
            rm -f "$temp_file"
            print_success "mieru client installed successfully"
        else
            echo "Fixing dependencies..."
            apt-get install -f -y
            rm -f "$temp_file"

            if command -v mieru &>/dev/null; then
                print_success "mieru client installed with dependency fixes"
            else
                print_error "Failed to install mieru client"
            fi
        fi
    else
        print_error "Failed to download mieru client"
    fi
}

# Function to install hysteria2
install_hysteria2() {
    print_step "Checking hysteria2 installation..."

    # Check if upgrade is needed
    local check_result=$(needs_upgrade "hysteria" "$HYSTERIA2_VERSION" "version")
    local status=$(echo "$check_result" | cut -d'|' -f1)
    local installed=$(echo "$check_result" | cut -d'|' -f2)
    local target=$(echo "$check_result" | cut -d'|' -f3)

    if [[ "$status" == "current" ]]; then
        print_success "hysteria2 is already up to date (v$installed)"
        return 0
    elif [[ "$status" == "newer" ]]; then
        print_success "hysteria2 is already installed (v$installed, newer than target v$target)"
        return 0
    elif [[ "$status" == "upgrade" ]]; then
        print_warning "hysteria2 found (v$installed) - upgrading to v$target..."
    else
        print_step "Installing hysteria2 v$HYSTERIA2_VERSION..."
    fi

    local arch=""
    case $(uname -m) in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7l) arch="armv7" ;;
        *)
            print_error "Unsupported architecture: $(uname -m)"
            return 1
            ;;
    esac

    # Fetch API response to variable first to prevent broken pipe errors
    local api_response=$(curl -s --connect-timeout 10 --max-time 30 https://api.github.com/repos/apernet/hysteria/releases/latest 2>/dev/null)
    local version=$(echo "$api_response" | grep -Po '"tag_name": "app/\K[^"]*' 2>/dev/null || echo "$HYSTERIA2_VERSION")
    local url="https://github.com/apernet/hysteria/releases/download/app%2F${version}/hysteria-linux-${arch}"

    echo "Downloading hysteria2..."
    if retry_download "$url" "/tmp/hysteria"; then
        mv /tmp/hysteria /usr/local/bin/hysteria
        chmod +x /usr/local/bin/hysteria
        print_success "hysteria2 installed successfully"
    else
        print_error "Failed to download hysteria2"
        rm -f /tmp/hysteria 2>/dev/null || true
    fi
}

# Function to install kloak (keystroke anonymization)
install_kloak() {
    print_step "Checking kloak installation..."

    # Special handling for kloak - it doesn't support version reporting
    # kloak v0.2 has no --version flag, so we just check if binary exists
    if command -v kloak &>/dev/null; then
        print_success "kloak is already installed (v$KLOAK_VERSION assumed - no version reporting)"
        setup_kloak_service
        return 0
    fi

    print_step "Installing kloak v$KLOAK_VERSION..."

    # Try compilation first (preferred method for control)
    print_info "Attempting to compile kloak from source..."
    if install_kloak_from_source; then
        setup_kloak_service "compiled"
        return 0
    else
        print_warning "Compilation failed, trying Whonix repository as fallback..."
        if install_kloak_from_repository; then
            setup_kloak_service "repository"
            return 0
        else
            print_error "Failed to install kloak via both compilation and repository"
            return 1
        fi
    fi
}

# Function to compile kloak from source
install_kloak_from_source() {
    print_step "Compiling kloak from source..."
    
    local temp_dir="/tmp/kloak-install-$$"
    
    # Install build dependencies
    print_info "Installing build dependencies..."
    apt-get update 2>/dev/null || true
    if ! apt-get install -y make pkgconf libsodium-dev libevdev-dev libevdev2 build-essential 2>&1 | tail -5; then
        print_error "Failed to install build dependencies for kloak"
        return 1
    fi
    
    # Download source
    print_info "Downloading kloak v${KLOAK_VERSION} source..."
    mkdir -p "$temp_dir"
    cd "$temp_dir" || return 1
    
    if retry_download "https://github.com/vmonaco/kloak/archive/v${KLOAK_VERSION}.tar.gz" "kloak.tar.gz"; then
        print_info "Downloaded kloak source from GitHub"
        
        # Extract and compile
        if tar xf kloak.tar.gz 2>/dev/null; then
            cd "kloak-${KLOAK_VERSION}" || return 1
            
            print_info "Compiling kloak..."
            if make all >/dev/null 2>&1; then
                # Install binary
                if [[ -f kloak ]]; then
                    mv kloak /usr/local/bin/kloak
                    chmod +x /usr/local/bin/kloak
                    print_success "kloak compiled and installed successfully"
                    cd / && rm -rf "$temp_dir"
                    return 0
                else
                    print_error "kloak binary not found after compilation"
                fi
            else
                print_error "Failed to compile kloak"
            fi
        else
            print_error "Failed to extract kloak source"
        fi
    else
        print_error "Failed to download kloak source"
    fi
    
    # Cleanup
    cd / && rm -rf "$temp_dir"
    return 1
}

# Function to install kloak from Whonix repository
install_kloak_from_repository() {
    print_step "Installing kloak from Whonix repository..."
    
    # Check if Whonix repository is already configured
    if [[ -f "/etc/apt/sources.list.d/whonix.list" ]] && [[ -f "/etc/apt/trusted.gpg.d/whonix.gpg" ]]; then
        print_info "Whonix repository already configured"
    else
        print_step "Adding Whonix repository for kloak..."
        
        # Create trusted keyrings directory
        install -d -m 0755 /etc/apt/trusted.gpg.d
        
        # Import Whonix signing key
        print_info "Importing Whonix repository key..."
        if curl -fsSL https://www.whonix.org/patrick.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/whonix.gpg; then
            print_success "Repository key imported successfully"
        else
            print_error "Failed to import repository key"
            return 1
        fi
        
        # Add repository
        print_info "Adding Whonix repository..."
        echo 'deb https://deb.whonix.org bullseye main contrib non-free' | tee /etc/apt/sources.list.d/whonix.list
        
        # Update package lists
        print_info "Updating package lists..."
        if apt-get update 2>&1 | tail -5; then
            print_success "Package lists updated"
        else
            print_warning "Failed to update package lists completely"
            return 1
        fi
    fi
    
    # Install kloak from repository
    if apt-get install -y kloak 2>&1 | tail -5; then
        print_success "kloak installed successfully from repository"
        return 0
    else
        return 1
    fi
}

# Function to setup kloak systemd service
setup_kloak_service() {
    local install_method="$1"
    
    print_step "Setting up kloak service..."
    
    # Check if systemd service already exists
    if systemctl list-unit-files kloak.service &>/dev/null; then
        print_info "kloak service file already exists"
    else
        # Create systemd service file for compiled version
        print_info "Creating kloak systemd service file..."
        create_kloak_service_file
    fi
    
    # Enable service but do not start it
    print_info "Enabling kloak service (not starting)..."
    if systemctl enable kloak 2>/dev/null; then
        print_success "kloak service enabled (use 'systemctl start kloak' to activate)"
    else
        print_warning "Failed to enable kloak service"
    fi
    
    print_info "kloak service is ready but not active - user can start when needed"
}

# Function to create kloak systemd service file
create_kloak_service_file() {
    cat > /etc/systemd/system/kloak.service << 'EOF'
[Unit]
Description=Kloak - Keystroke Anonymization
Documentation=https://github.com/vmonaco/kloak
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/local/bin/kloak
Restart=on-failure
RestartSec=5
User=root
Group=root

# Security settings
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd to recognize new service
    systemctl daemon-reload
    print_success "kloak service file created"
}

# Function to setup DNSCrypt Proxy configuration file
setup_dnscrypt_config() {
    local install_dir="/etc/dnscrypt-proxy"
    local config_file="$install_dir/dnscrypt-proxy.toml"
    local example_config="$install_dir/example-dnscrypt-proxy.toml"

    print_step "Setting up DNSCrypt Proxy configuration..."

    # Check if install directory exists
    if [[ ! -d "$install_dir" ]]; then
        print_error "DNSCrypt Proxy directory not found: $install_dir"
        return 1
    fi

    # Check if config file already exists
    if [[ -f "$config_file" ]]; then
        print_success "DNSCrypt Proxy config file already exists"
        return 0
    fi

    # Check if example config exists
    if [[ ! -f "$example_config" ]]; then
        print_error "Example config file not found: $example_config"
        print_info "Cannot create DNSCrypt Proxy configuration"
        return 1
    fi

    # Copy example config to actual config
    print_info "Creating config file from example..."
    if cp "$example_config" "$config_file"; then
        # Set proper permissions
        chmod 644 "$config_file"
        print_success "DNSCrypt Proxy config file created: $config_file"
        print_info "Config uses default settings - you can customize it later"
        return 0
    else
        print_error "Failed to create config file"
        return 1
    fi
}

# Function to setup DNSCrypt Proxy systemd service
setup_dnscrypt_service() {
    local install_method="$1"

    print_step "Setting up DNSCrypt Proxy service..."

    # ALWAYS ensure config file exists before setting up service
    setup_dnscrypt_config

    # Check if systemd service already exists
    if systemctl list-unit-files dnscrypt-proxy.service &>/dev/null; then
        print_info "DNSCrypt Proxy service file already exists"
    else
        # Create systemd service file
        print_info "Creating DNSCrypt Proxy systemd service file..."
        create_dnscrypt_service_file
    fi

    # Enable service but do not start it
    print_info "Enabling DNSCrypt Proxy service (not starting)..."
    if systemctl enable dnscrypt-proxy 2>/dev/null; then
        print_success "DNSCrypt Proxy service enabled (use 'systemctl start dnscrypt-proxy' to activate)"
    else
        print_warning "Failed to enable DNSCrypt Proxy service"
    fi

    print_info "DNSCrypt Proxy service is ready but not active - user can start when needed"
}

# Function to create DNSCrypt Proxy systemd service file
create_dnscrypt_service_file() {
    cat > /etc/systemd/system/dnscrypt-proxy.service << 'EOF'
[Unit]
Description=DNSCrypt Proxy
Documentation=https://github.com/DNSCrypt/dnscrypt-proxy/wiki
After=network-online.target
Before=nss-lookup.target
Wants=network-online.target nss-lookup.target

[Service]
Type=simple
ExecStart=/usr/local/bin/dnscrypt-proxy -config /etc/dnscrypt-proxy/dnscrypt-proxy.toml
WorkingDirectory=/etc/dnscrypt-proxy
Restart=on-failure
RestartSec=10
User=root
Group=root

# CRITICAL: Allow binding to port 53 (privileged port)
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

# Security settings
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/etc/dnscrypt-proxy
PrivateTmp=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
SystemCallArchitectures=native
LockPersonality=true
RestrictRealtime=true
RestrictNamespaces=true

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd to recognize new service
    systemctl daemon-reload
    print_success "DNSCrypt Proxy service file created"
}

# Function to generate Pi-hole setupVars.conf for unattended installation
generate_pihole_setupvars() {
    print_step "Generating Pi-hole configuration for unattended installation..."

    # Create /etc/pihole directory if it doesn't exist
    mkdir -p /etc/pihole

    # Detect primary network interface with multiple fallback methods
    local interface=""
    local ipv4_address=""

    # Method 1: Try default route (most reliable when available)
    interface=$(ip route | grep '^default' | head -1 | awk '{print $5}')
    if [[ -n "$interface" ]]; then
        ipv4_address=$(ip -4 addr show "$interface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    fi

    # Method 2: Try interface with active IPv4 (if Method 1 failed)
    if [[ -z "$interface" ]] || [[ -z "$ipv4_address" ]]; then
        local addr_line=$(ip -4 -o addr show | grep -v "127.0.0.1" | head -1)
        if [[ -n "$addr_line" ]]; then
            interface=$(echo "$addr_line" | awk '{print $2}')
            ipv4_address=$(echo "$addr_line" | awk '{print $4}' | cut -d'/' -f1)
        fi
    fi

    # Method 3: Try first UP interface (last resort)
    if [[ -z "$interface" ]] || [[ -z "$ipv4_address" ]]; then
        interface=$(ip -o link show | grep "state UP" | grep -v "lo" | head -1 | awk '{print $2}' | sed 's/:$//')
        if [[ -n "$interface" ]]; then
            ipv4_address=$(ip -4 addr show "$interface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
        fi
    fi

    # Clean interface name (remove @ifXX suffixes if present)
    interface=$(echo "$interface" | cut -d'@' -f1)

    # Debug output
    print_info "Detected interface: ${interface:-NONE}"
    print_info "Detected IPv4: ${ipv4_address:-NONE}"

    # Validation
    if [[ -z "$interface" ]] || [[ -z "$ipv4_address" ]]; then
        print_error "Could not detect network interface or IP address"
        print_info "Available interfaces:"
        ip -o link show | grep -v "lo:" 2>/dev/null || echo "  No interfaces found"
        print_info "Please configure network first or run Pi-hole installer manually"
        return 1
    fi

    print_info "Using interface: $interface"
    print_info "Using IPv4: $ipv4_address"

    # Generate random web password
    local web_password=$(generate_pihole_password)

    # Double-hash the password for Pi-hole (SHA256 twice with newline)
    local hashed_password=$(printf "%s" "$web_password" | sha256sum | awk '{print $1}')
    hashed_password=$(printf "%s" "$hashed_password" | sha256sum | awk '{print $1}')

    # Create setupVars.conf with all required settings
    cat > /etc/pihole/setupVars.conf <<EOF
# Pi-hole Configuration - Auto-generated for Kodachi
PIHOLE_INTERFACE=$interface
IPV4_ADDRESS=${ipv4_address}/24
QUERY_LOGGING=true
INSTALL_WEB_SERVER=true
INSTALL_WEB_INTERFACE=true
LIGHTTPD_ENABLED=true
CACHE_SIZE=10000
DNS_FQDN_REQUIRED=true
DNS_BOGUS_PRIV=true
DNSMASQ_LISTENING=local
BLOCKING_ENABLED=true
DNSSEC=false
REV_SERVER=false
PIHOLE_DNS_1=9.9.9.10
PIHOLE_DNS_2=149.112.112.10
WEBPASSWORD=$hashed_password
# Run Pi-hole on port 5353 to avoid conflict with DNSCrypt Proxy (port 53)
FTLCONF_LOCAL_PORT=5353
FTLCONF_dns_port=5353
EOF

    if [[ -f /etc/pihole/setupVars.conf ]]; then
        print_success "Pi-hole configuration created at /etc/pihole/setupVars.conf"
        print_info "Web password: $web_password (save this!)"
        echo "$web_password" > /etc/pihole/.webpassword_initial
        chmod 600 /etc/pihole/.webpassword_initial
        return 0
    else
        print_error "Failed to create Pi-hole configuration"
        return 1
    fi
}

# Function to configure Pi-hole to use port 5353
configure_pihole_port() {
    print_step "Configuring Pi-hole to use port 5353..."

    local pihole_config="/etc/pihole/pihole.toml"
    local pihole_ftl_config="/etc/pihole/pihole-FTL.conf"

    # Check if Pi-hole is installed
    if ! command -v pihole &>/dev/null; then
        print_warning "Pi-hole is not installed, skipping port configuration"
        return 1
    fi

    # Modern Pi-hole uses pihole.toml (v6.x)
    if [[ -f "$pihole_config" ]]; then
        print_info "Updating Pi-hole TOML configuration for port 5353..."

        # Check if file is protected (immutable attribute)
        local was_protected=false
        if lsattr "$pihole_config" 2>/dev/null | grep -q '^....i'; then
            was_protected=true
            chattr -i "$pihole_config" 2>/dev/null || true
        fi

        # The DNS port setting is between "cnameRecords = []" and "# Reverse server"
        # We need to match the exact pattern: line with "  port = 53" (2 spaces, no quotes)
        # that comes after "# Port used by the DNS server" comment
        if grep -q "# Port used by the DNS server" "$pihole_config"; then
            # Create backup
            cp "$pihole_config" "${pihole_config}.bak" 2>/dev/null || true

            # Use awk for precise line matching and replacement
            awk '
                /# Port used by the DNS server/ { print; found=1; next }
                found && /^  port = [0-9]+$/ {
                    print "  port = 5353"
                    found=0
                    next
                }
                { print }
            ' "$pihole_config" > "${pihole_config}.tmp" && mv "${pihole_config}.tmp" "$pihole_config"

            print_success "Updated DNS port to 5353 in $pihole_config"
        elif grep -q "^  port = 53$" "$pihole_config"; then
            # Fallback: update first occurrence of "  port = 53" (exact match)
            sed -i '0,/^  port = 53$/s//  port = 5353/' "$pihole_config"
            print_success "Updated port to 5353 in $pihole_config"
        else
            # Add port setting after [dns] section with proper indentation
            if grep -q "^\[dns\]" "$pihole_config"; then
                sed -i '/^\[dns\]/a \  # Port used by the DNS server\n  port = 5353' "$pihole_config"
                print_success "Added port = 5353 to [dns] section in $pihole_config"
            else
                # Add entire dns section
                echo "" >> "$pihole_config"
                echo "[dns]" >> "$pihole_config"
                echo "  # Port used by the DNS server" >> "$pihole_config"
                echo "  port = 5353" >> "$pihole_config"
                print_success "Added [dns] section with port = 5353 to $pihole_config"
            fi
        fi

        # Restore protection if it was originally protected
        if [ "$was_protected" = true ]; then
            chattr +i "$pihole_config" 2>/dev/null || true
        fi
    fi

    # Legacy Pi-hole uses pihole-FTL.conf (v5.x and earlier)
    if [[ -f "$pihole_ftl_config" ]]; then
        print_info "Updating legacy Pi-hole FTL configuration for port 5353..."

        # Check if file is protected (immutable attribute)
        local was_ftl_protected=false
        if lsattr "$pihole_ftl_config" 2>/dev/null | grep -q '^....i'; then
            was_ftl_protected=true
            chattr -i "$pihole_ftl_config" 2>/dev/null || true
        fi

        if grep -q "^LOCAL_PORT=" "$pihole_ftl_config"; then
            sed -i 's/^LOCAL_PORT=.*/LOCAL_PORT=5353/' "$pihole_ftl_config"
        else
            echo "LOCAL_PORT=5353" >> "$pihole_ftl_config"
        fi

        # Restore protection if it was originally protected
        if [ "$was_ftl_protected" = true ]; then
            chattr +i "$pihole_ftl_config" 2>/dev/null || true
        fi

        print_success "Set LOCAL_PORT=5353 in $pihole_ftl_config"
    fi

    # Restart Pi-hole service to apply changes
    print_info "Restarting Pi-hole service..."
    if systemctl restart pihole-FTL 2>/dev/null; then
        print_success "Pi-hole restarted successfully on port 5353"

        # Verify port
        sleep 2
        if ss -tlnp 2>/dev/null | grep -q ":5353.*pihole-FTL\|:5353.*dnsmasq"; then
            print_success "Verified: Pi-hole is listening on port 5353"
        else
            print_warning "Could not verify Pi-hole port (may need manual check)"
        fi
    else
        print_warning "Failed to restart Pi-hole - you may need to restart manually"
    fi

    print_info "Pi-hole configured to avoid port conflict with DNSCrypt Proxy"
    return 0
}

# Function to check DNS service coordination (DNSCrypt + Pi-hole)
check_dns_services() {
    print_step "Checking DNS service coordination..."

    local dnscrypt_port_53=false
    local pihole_port_5353=false
    local port_conflicts=false

    # Check if DNSCrypt is running on port 53
    if command -v dnscrypt-proxy &>/dev/null; then
        if systemctl is-active --quiet dnscrypt-proxy 2>/dev/null; then
            if ss -tlnp 2>/dev/null | grep -q ":53.*dnscrypt"; then
                dnscrypt_port_53=true
                print_success "DNSCrypt Proxy running on port 53"
            else
                print_warning "DNSCrypt Proxy service active but not listening on port 53"
            fi
        else
            print_info "DNSCrypt Proxy not running (service not started)"
        fi
    else
        print_info "DNSCrypt Proxy not installed"
    fi

    # Check if Pi-hole is running on port 5353
    if command -v pihole &>/dev/null; then
        if systemctl is-active --quiet pihole-FTL 2>/dev/null; then
            if ss -tlnp 2>/dev/null | grep -q ":5353.*pihole-FTL\|:5353.*dnsmasq"; then
                pihole_port_5353=true
                print_success "Pi-hole running on port 5353"
            elif ss -tlnp 2>/dev/null | grep -q ":53.*pihole-FTL\|:53.*dnsmasq"; then
                print_error "Pi-hole running on port 53 - PORT CONFLICT DETECTED!"
                print_warning "Pi-hole must use port 5353 to avoid conflict with DNSCrypt"
                port_conflicts=true
            else
                print_warning "Pi-hole service active but not listening on expected ports"
            fi
        else
            print_info "Pi-hole not running (service not started)"
        fi
    else
        print_info "Pi-hole not installed"
    fi

    # Check for any port conflicts
    if [[ "$port_conflicts" == "true" ]]; then
        print_error "DNS port conflict detected - services cannot coexist"
        print_info "Run 'configure_pihole_port' to fix Pi-hole configuration"
        return 1
    fi

    # Summary
    echo ""
    if [[ "$dnscrypt_port_53" == "true" && "$pihole_port_5353" == "true" ]]; then
        print_success "✓ DNS services properly coordinated - no conflicts"
        print_info "  → DNSCrypt Proxy on port 53 (system DNS)"
        print_info "  → Pi-hole on port 5353 (ad-blocking DNS)"
    elif [[ "$dnscrypt_port_53" == "true" || "$pihole_port_5353" == "true" ]]; then
        print_info "DNS services partially configured"
    else
        print_info "DNS services not active"
    fi

    return 0
}

# Function to install Pi-hole
# To uninstall Pi-hole, run: echo -e "yes\nno\nno\nno\nno\nno\nno\nno\nno\nno" | sudo pihole uninstall
install_pihole() {
    print_step "Installing Pi-hole..."

    # Check if Pi-hole is already installed
    if systemctl status pihole-FTL &>/dev/null || command -v pihole &>/dev/null; then
        print_success "Pi-hole is already installed"

        # Try to get Pi-hole status
        if command -v pihole &>/dev/null; then
            pihole status &>/dev/null | head -5 || true
        fi

        # Ensure Pi-hole is configured for port 5353
        configure_pihole_port

        return 0
    fi

    echo "Pi-hole is not installed. Installing now..."
    echo ""

    if [[ "$AUTO_YES" == "true" ]]; then
        print_info "Auto mode: Installing Pi-hole with default settings (Quad9 Unfiltered DNS)..."

        # Generate setupVars.conf for unattended installation
        if generate_pihole_setupvars; then
            # SECURITY FIX: Download Pi-hole installer to temp file and verify before execution
            local pihole_script="/tmp/pihole-install-$$.sh"
            if curl -sSL -o "$pihole_script" https://install.pi-hole.net 2>/tmp/pihole-install.err; then
                # Basic sanity check: verify it's a bash script
                if head -1 "$pihole_script" | grep -q "^#!.*bash"; then
                    # Display script hash for verification
                    local script_hash=$(sha256sum "$pihole_script" | cut -d' ' -f1)
                    echo -e "${BLUE}[INFO]${NC} Pi-hole installer script SHA256: ${CYAN}${script_hash}${NC}"

                    # Run Pi-hole installer in unattended mode
                    if bash "$pihole_script" --unattended 2>>/tmp/pihole-install.err; then
                        print_success "Pi-hole installed successfully in unattended mode"

                        # Display saved password if available
                        if [[ -f /etc/pihole/.webpassword_initial ]]; then
                            local saved_password=$(cat /etc/pihole/.webpassword_initial)
                            print_info "Pi-hole Web Interface Password: $saved_password"
                            print_warning "Password saved to: /etc/pihole/.webpassword_initial"
                        fi
                        rm -f "$pihole_script"
                    else
                        print_error "Pi-hole unattended installation failed"
                        rm -f "$pihole_script"
                        return 1
                    fi
                else
                    print_error "Downloaded Pi-hole installer is not a valid bash script"
                    rm -f "$pihole_script"
                    return 1
                fi
            else
                print_error "Failed to download Pi-hole installer"
                return 1
            fi
        else
            print_error "Failed to generate Pi-hole configuration"
            return 1
        fi
    else
        print_warning "Pi-hole installer will run interactively."
        print_info "You'll need to configure Pi-hole settings during installation."
        echo ""

        # SECURITY FIX: Download and verify Pi-hole installer before interactive execution
        local pihole_script="/tmp/pihole-install-interactive-$$.sh"
        if curl -sSL -o "$pihole_script" https://install.pi-hole.net 2>/tmp/pihole-install.err; then
            if head -1 "$pihole_script" | grep -q "^#!.*bash"; then
                local script_hash=$(sha256sum "$pihole_script" | cut -d' ' -f1)
                echo -e "${BLUE}[INFO]${NC} Pi-hole installer script SHA256: ${CYAN}${script_hash}${NC}"
                bash "$pihole_script" 2>>/tmp/pihole-install.err
                rm -f "$pihole_script"
            else
                print_error "Downloaded Pi-hole installer is not a valid bash script"
                rm -f "$pihole_script"
                return 1
            fi
        else
            print_error "Failed to download Pi-hole installer"
            return 1
        fi
    fi

    # Wait for any background processes from Pi-hole installer to complete
    echo ""
    print_step "Waiting for Pi-hole installer to fully complete..."
    sleep 3

    # Clean up any orphaned curl processes from Pi-hole installation
    if pgrep -f "curl.*pi-hole\|curl.*pihole" &>/dev/null; then
        print_info "Cleaning up Pi-hole installer background processes..."
        pkill -9 -f "curl.*pi-hole\|curl.*pihole" 2>/dev/null || true
        sleep 1
    fi

    # Check installation result
    if command -v pihole &>/dev/null || systemctl is-active --quiet pihole-FTL 2>/dev/null; then
        print_success "Pi-hole installed successfully"

        # Configure Pi-hole to use port 5353 (avoid conflict with DNSCrypt)
        echo ""
        configure_pihole_port
        echo ""

        # Check if service is running
        if systemctl is-active --quiet pihole-FTL; then
            print_success "Pi-hole FTL service is running"
        else
            print_warning "Pi-hole FTL service is not running. You may need to start it manually."
            print_info "Run: sudo systemctl start pihole-FTL"
        fi

        # Show web interface info if available
        if command -v pihole &>/dev/null; then
            echo ""
            print_info "Pi-hole Web Interface:"
            echo "  URL: http://$(hostname -I | awk '{print $1}')/admin"
            if [[ -f /etc/pihole/.webpassword_initial ]]; then
                echo "  Password: $(cat /etc/pihole/.webpassword_initial)"
            else
                echo "  Password: Set during installation or run 'pihole -a -p' to set"
            fi
        fi
    else
        print_error "Failed to install Pi-hole"
        print_info "You can try manual installation later with:"
        echo "  curl -sSL https://install.pi-hole.net | bash"
    fi
}

# Function to install Kicksecure RAM wipe (dracut + ram-wipe)
# Only called when --force-kicksecure-ramwipe is specified
install_kicksecure_ram_wipe() {
    print_step "Kicksecure RAM Wipe Installation"
    echo ""
    print_warning "Installing Kicksecure RAM wipe components:"
    echo ""
    echo -e "  ${BOLD}RAM Wipe Tools:${NC}"
    echo -e "    ${BOLD}dracut${NC} - Initramfs infrastructure for secure boot operations"
    echo -e "    ${BOLD}dracut-core${NC} - Core components for dracut framework"
    echo -e "    ${BOLD}ram-wipe${NC} - Securely wipes RAM contents on shutdown/reboot"
    echo ""
    print_highlight "These tools provide:"
    echo "  • Protection against cold boot attacks"
    echo "  • Secure erasure of sensitive data from RAM"
    echo "  • Enhanced privacy when shutting down the system"
    echo ""
    print_warning "RAM wiping may slow down shutdown/reboot processes."
    print_info "Note: Kodachi also has built-in RAM wipe via 'health-control memory-wipe'"
    echo ""

    print_info "Installing Kicksecure RAM wipe packages..."

    # First install dracut packages from standard repos
    print_step "Installing dracut packages..."
    if apt-get install -y dracut dracut-core 2>&1 | tail -5; then
        print_success "dracut packages installed successfully"
    else
        print_warning "Failed to install some dracut packages"
    fi

    # Check if Kicksecure repository exists
    if [[ -f "/etc/apt/sources.list.d/kicksecure.list" ]]; then
        print_info "Kicksecure repository detected - refreshing GPG key..."

        # Create keyrings directory if missing
        install -d -m 0755 /usr/share/keyrings

        # Download and convert key from Kicksecure website (most reliable method)
        print_info "Fetching latest Kicksecure repository key..."
        if curl --tlsv1.3 -fsSL https://www.kicksecure.com/keys/derivative.asc 2>/dev/null | gpg --yes --dearmor -o /usr/share/keyrings/kicksecure.gpg 2>/dev/null && \
           [ -s /usr/share/keyrings/kicksecure.gpg ]; then
            print_success "Repository key downloaded and converted successfully"

            # Normalize sources.list to use correct key path if needed
            if ! grep -q "signed-by=/usr/share/keyrings/kicksecure.gpg" /etc/apt/sources.list.d/kicksecure.list; then
                print_info "Normalizing repository configuration to use correct key path..."
                sed 's|signed-by=/usr/share/keyrings/[^]]*|signed-by=/usr/share/keyrings/kicksecure.gpg|g' /etc/apt/sources.list.d/kicksecure.list > /tmp/kicksecure.list.fixed
                cat /tmp/kicksecure.list.fixed | tee /etc/apt/sources.list.d/kicksecure.list > /dev/null
                print_success "Repository configuration normalized"
            fi
        else
            print_error "Failed to download repository key"
            return 1
        fi

        # Verify repository works
        print_info "Verifying Kicksecure repository..."
        if apt-get update -o Dir::Etc::sourcelist="/etc/apt/sources.list.d/kicksecure.list" -o Dir::Etc::sourceparts="-" 2>&1 | tail -5; then
            print_success "Kicksecure repository verified successfully"
        else
            print_warning "Repository verification had warnings (may still work)"
        fi
    else
        # Repository doesn't exist - add it for ram-wipe installation
        print_step "Adding Kicksecure repository for ram-wipe..."

        # Create keyrings directory
        install -d -m 0755 /usr/share/keyrings

        # Download and convert key from Kicksecure website (most reliable method)
        print_info "Importing Kicksecure repository key..."
        if curl --tlsv1.3 -fsSL https://www.kicksecure.com/keys/derivative.asc 2>/dev/null | gpg --yes --dearmor -o /usr/share/keyrings/kicksecure.gpg 2>/dev/null && \
           [ -s /usr/share/keyrings/kicksecure.gpg ]; then
            print_success "Repository key imported successfully"
        else
            print_error "Failed to import repository key"
            return 1
        fi

        # Add repository
        print_info "Adding Kicksecure repository..."
        echo 'deb [signed-by=/usr/share/keyrings/kicksecure.gpg] https://deb.kicksecure.com bookworm main' | tee /etc/apt/sources.list.d/kicksecure.list

        # Update package lists
        print_info "Updating package lists..."
        if apt-get update 2>&1 | tail -5; then
            print_success "Package lists updated"
        else
            print_warning "Failed to update package lists completely"
        fi
    fi

    # Install ram-wipe
    print_step "Installing ram-wipe from Kicksecure repository..."
    # Refresh all package lists to ensure dependencies are available
    print_info "Refreshing package lists..."
    apt-get update >/dev/null 2>&1
    if apt-get install -y ram-wipe 2>&1 | tail -5; then
        print_success "ram-wipe installed successfully"
        echo ""
        print_info "Kicksecure RAM wipe is now configured and will activate on shutdown/reboot"
        print_info "To check status: sudo systemctl status ram-wipe"
    else
        print_error "Failed to install ram-wipe"
        print_info "You may need to troubleshoot the Kicksecure repository"
    fi
}

# Function to install advanced security tools (kloak only)
# Note: Kodachi has built-in RAM wipe via 'health-control memory-wipe'
# For Kicksecure RAM wipe, use --force-kicksecure-ramwipe flag
install_advanced_security_tools() {
    print_step "Advanced Security Tools Installation"
    echo ""
    print_info "Kodachi includes built-in RAM wipe via 'health-control memory-wipe'"
    print_info "For Kicksecure RAM wipe (dracut + ram-wipe), use --force-kicksecure-ramwipe flag"
    echo ""
    print_warning "The following advanced security tool will be installed:"
    echo ""
    echo -e "  ${BOLD}Keystroke Anonymization:${NC}"
    echo -e "    ${BOLD}kloak${NC} - Obfuscates typing behavior to prevent keystroke biometrics"
    echo ""
    print_highlight "This tool provides:"
    echo "  • Keystroke timing anonymization to prevent typing fingerprinting"
    echo "  • Protection against keystroke biometric analysis"
    echo ""
    print_warning "Kloak service will be enabled but not started (manual activation required)."
    echo ""

    # Ask for user confirmation
    if [[ "$AUTO_YES" == "true" ]]; then
        print_info "Auto mode: Installing keystroke anonymization tool..."
        REPLY="yes"
    else
        # FIXED: Simple working input method (stdin already redirected via exec)
        echo -n "Do you want to install kloak (keystroke anonymization)? (YES/no) [default: yes]: "
        read -r REPLY
        # Default to YES if empty
        if [[ -z "$REPLY" ]]; then
            REPLY="yes"
        fi
        echo ""
    fi

    if [[ $REPLY =~ ^[Yy]([Ee][Ss])?$ ]]; then
        # Install kloak (keystroke anonymization)
        print_step "Installing kloak (keystroke anonymization)..."
        install_kloak
        
    else
        print_info "Skipping keystroke anonymization tool installation"
        echo ""
        print_highlight "To install kloak (keystroke anonymization) manually:"
        echo ""
        echo -e "  ${BOLD}Option 1: Compile from source${NC}"
        echo -e "    ${BOLD}sudo apt-get install make libevdev-dev build-essential${NC}"
        echo -e "    ${BOLD}curl -L https://github.com/vmonaco/kloak/archive/v0.2.tar.gz | tar xz${NC}"
        echo -e "    ${BOLD}cd kloak-0.2 && make all && sudo mv kloak /usr/local/bin/${NC}"
        echo ""
        echo -e "  ${BOLD}Option 2: Install from Whonix repository${NC}"
        echo -e "    ${BOLD}curl -fsSL https://www.whonix.org/patrick.asc | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/whonix.gpg${NC}"
        echo -e "    ${BOLD}echo 'deb https://deb.whonix.org bullseye main' | sudo tee /etc/apt/sources.list.d/whonix.list${NC}"
        echo -e "    ${BOLD}sudo apt-get update && sudo apt-get install kloak${NC}"
        echo ""
        print_info "For Kicksecure RAM wipe, run: sudo bash kodachi-deps-install.sh --force-kicksecure-ramwipe"
        print_info "Kodachi has built-in RAM wipe: sudo health-control memory-wipe"
        echo ""
    fi
}

# Function to install GRUB tools for health-control RAM wipe support
install_grub_tools() {
    print_step "GRUB Tools Installation"
    echo ""

    # Check if GRUB is already configured with tools
    if command -v update-grub &>/dev/null || command -v grub-mkconfig &>/dev/null; then
        print_success "GRUB tools already installed"
        return 0
    fi

    print_info "GRUB tools not found - detecting bootloader..."

    # Detect GRUB2 vs GRUB legacy
    if [ -d "/boot/grub2" ] || [ -f "/boot/grub2/grub.cfg" ]; then
        print_info "Detected GRUB2 installation"
        if timeout 60 apt-get install -y -o DPkg::Use-Pty=0 -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" < /dev/null grub-common grub2-common 2>&1 | tail -5; then
            print_success "GRUB2 tools installed (grub-common + grub2-common)"
        else
            print_warning "Failed to install GRUB2 tools - RAM wipe will still work"
        fi
    elif [ -d "/boot/grub" ] || [ -f "/boot/grub/grub.cfg" ]; then
        print_info "Detected GRUB bootloader"
        if timeout 60 apt-get install -y -o DPkg::Use-Pty=0 -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" < /dev/null grub-pc 2>&1 | tail -5; then
            print_success "GRUB tools installed (grub-pc)"
        else
            print_warning "Failed to install GRUB tools - RAM wipe will still work"
        fi
    else
        print_warning "No GRUB installation detected - skipping GRUB tools"
        print_info "This is normal for live systems or non-GRUB bootloaders"
        print_info "RAM wipe will still function correctly without GRUB tools"
    fi

    echo ""
    print_info "Note: GRUB tools enable 'init_on_free=1' kernel parameter for extra security"
    print_info "RAM wipe hooks are installed regardless and will execute on shutdown"
}

# Update package lists
print_step "Updating package lists..."
export DEBIAN_FRONTEND=noninteractive
if timeout 60 apt-get update; then
    print_success "Package lists updated"
else
    print_warning "Failed to update package lists completely"
fi
echo ""

# Fix stdin for interactive mode when run with sudo
if [[ "$INSTALL_MODE" == "interactive" ]]; then
    # Disable strict mode for interactive input
    set +e +o pipefail
    
    # Redirect stdin if needed
    if [[ ! -t 0 ]]; then
        exec < /dev/tty 2>/dev/null || exec < /dev/console 2>/dev/null || true
    fi
fi

# Install packages based on mode
if [[ "$INSTALL_MODE" == "proxy" ]]; then
    print_highlight "Installing Proxy Tools Only"
    echo ""
    install_v2ray
    install_xray
    install_hysteria2
    install_mieru

elif [[ "$INSTALL_MODE" == "interactive" ]]; then
    print_highlight "Interactive Category-Based Installation"
    echo ""
    print_info "You will be prompted to install each category of packages"
    echo ""
    
    # Essential packages
    ESSENTIAL_DESC="Core system utilities required for basic functionality:
  • Network tools: curl, wget, openssl, dhclient
  • System utilities: sudo, systemd, mount
  • File operations: coreutils, findutils, grep
  • Password tools: pass, pwgen, xkcdpass"
    
    ESSENTIAL_MANUAL="  sudo apt-get install curl wget openssl ca-certificates coreutils findutils grep \\
    procps psmisc systemd sudo dmidecode lsof acl util-linux mount \\
    uuid-runtime inotify-tools isc-dhcp-client pass pwgen xkcdpass"
    
    install_category_interactive "$ESSENTIAL_PACKAGES" "Essential" "$ESSENTIAL_DESC" "$ESSENTIAL_MANUAL"
    ensure_dpkg_healthy
    
    # Networking packages
    NETWORK_DESC="Network and VPN connectivity tools:
  • Anonymity: Tor network and configuration
  • VPN support: OpenVPN, WireGuard
  • Firewall: iptables, nftables
  • Proxy tools: Shadowsocks, Redsocks, Microsocks, HAProxy"
    
    NETWORK_MANUAL="  sudo apt-get install tor openvpn wireguard-tools iptables nftables \\
    arptables ebtables iproute2 iputils-ping net-tools nyx apt-transport-tor \\
    shadowsocks-libev redsocks microsocks haproxy"
    
    if install_category_interactive "$NETWORK_PACKAGES" "Networking" "$NETWORK_DESC" "$NETWORK_MANUAL"; then
        # Initialize iptables alternatives after network packages
        initialize_iptables_alternatives
    fi
    ensure_dpkg_healthy
    
    # Security packages
    SECURITY_DESC="System hardening and protection tools:
  • Access control: AppArmor, Firejail
  • System integrity: AIDE, Lynis, rkhunter
  • USB protection: USBGuard
  • Encryption: eCryptfs utilities
  • Authentication: fail2ban, PAM modules"
    
    SECURITY_MANUAL="  sudo apt-get install ufw macchanger firejail apparmor apparmor-utils \\
    apparmor-profiles aide lynis rkhunter chkrootkit usbguard ecryptfs-utils \\
  cryptsetup-nuke-password fail2ban unattended-upgrades auditd \\
    libpam-pwquality libpam-google-authenticator secure-delete wipe nwipe"
    
    install_category_interactive "$SECURITY_PACKAGES" "Security" "$SECURITY_DESC" "$SECURITY_MANUAL"
    ensure_dpkg_healthy
    
    # Privacy packages
    PRIVACY_DESC="DNS security and privacy tools:
  • DNS encryption: DNSCrypt Proxy v${DNSCRYPT_VERSION} (from GitHub)
  • QR code generation: QRencode v${QRENCODE_VERSION} (compiled from GitHub)
  • DNS utilities: dig, nslookup, host
  • Network-wide ad blocking: Pi-hole (interactive setup)"
    
    PRIVACY_MANUAL="  # Install DNS utilities
  sudo apt-get install dnsutils
  
  # Install DNSCrypt Proxy from GitHub
  curl -L https://github.com/DNSCrypt/dnscrypt-proxy/releases/download/${DNSCRYPT_VERSION}/dnscrypt-proxy-linux_x86_64-${DNSCRYPT_VERSION}.tar.gz
  
  # Install QRencode from GitHub (compile from source)
  curl -L https://github.com/fukuchi/libqrencode/releases/download/v${QRENCODE_VERSION}/qrencode-${QRENCODE_VERSION}.tar.gz
  
  # For Pi-hole:
  curl -sSL https://install.pi-hole.net | bash"
    
    if install_category_interactive "$PRIVACY_PACKAGES" "Privacy" "$PRIVACY_DESC" "$PRIVACY_MANUAL"; then
        # CRITICAL: Configure systemd-resolved IMMEDIATELY after installation
        # This ensures DNS works before any GitHub downloads are attempted
        echo ""
        configure_systemd_resolved

        # Install DNSCrypt Proxy from GitHub with apt fallback
        echo ""
        print_step "Installing DNSCrypt Proxy from GitHub..."
        if ! install_dnscrypt_github; then
            print_warning "GitHub installation failed, trying apt package..."
            if timeout 60 apt-get install -y -o DPkg::Use-Pty=0 -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" < /dev/null dnscrypt-proxy 2>&1 | tail -5; then
                print_success "DNSCrypt Proxy installed via apt"
                setup_dnscrypt_service "apt"
            else
                print_error "Failed to install DNSCrypt Proxy from both GitHub and apt"
            fi
        fi
        # Install QRencode (APT first, GitHub fallback)
        echo ""
        install_qrencode_github
        # Try to install resolvconf (optional)
        install_resolvconf_safe
        ensure_dpkg_healthy
        # Offer Pi-hole installation
        echo ""
        if [[ "$AUTO_YES" == "true" ]]; then
            print_info "Auto mode: Installing Pi-hole..."
            REPLY="yes"
        else
            # FIXED: Simple working input method (stdin already redirected via exec)
            echo -n "Do you want to install Pi-hole for network-wide ad blocking? (YES/no) [default: yes]: "
            read -r REPLY
            # Default to YES if empty
            if [[ -z "$REPLY" ]]; then
                REPLY="yes"
            fi
            echo ""
        fi
        if [[ $REPLY =~ ^[Yy]([Ee][Ss])?$ ]]; then
            install_pihole
        fi
    fi
    ensure_dpkg_healthy
    
    # Advanced packages (non-GUI)
    ADVANCED_DESC="Additional tools and utilities (non-GUI):
  • Development: git, build-essential
  • System monitoring: htop, iotop, sensors
  • Hardware tools: smartmontools, rfkill
  • Utilities: jq, yamllint, haveged"

    ADVANCED_MANUAL="  sudo apt-get install jq git build-essential rng-tools-debian \\
    haveged ccze yamllint smartmontools lm-sensors hdparm \\
    htop iotop vnstat efibootmgr rfkill"

    install_category_interactive "$ADVANCED_PACKAGES" "Advanced" "$ADVANCED_DESC" "$ADVANCED_MANUAL"
    ensure_dpkg_healthy

    # Monitoring packages
    MONITORING_DESC="System and network monitoring tools for the dashboard:
  • Resource monitoring: btop (modern TUI resource monitor)
  • Network monitoring: iftop, nethogs, nload
  • Disk usage: ncdu (NCurses Disk Usage)
  • Speed testing: iperf3, speedtest-cli"

    MONITORING_MANUAL="  sudo apt-get install btop iftop nethogs ncdu nload iperf3 speedtest-cli"

    install_category_interactive "$MONITORING_PACKAGES" "Monitoring" "$MONITORING_DESC" "$MONITORING_MANUAL"
    ensure_dpkg_healthy

    # GUI packages (only if desktop environment detected or forced, unless explicitly skipped)
    if [[ "$SKIP_GUI_INSTALL" == "true" ]]; then
        print_info "Skipping GUI packages (--skipgui specified by user)."
    elif detect_gui_environment || [[ "$FORCE_GUI_INSTALL" == "true" ]]; then
        if [[ "$FORCE_GUI_INSTALL" == "true" ]] && ! detect_gui_environment; then
            print_warning "No desktop environment detected, but --forcegui specified"
        fi

        GUI_DESC="GUI-specific packages for desktop environments:
  • Terminal: kitty, xterm terminal emulators
  • Desktop panels: Conky status widgets
  • Fonts: fontconfig, emoji support
  • Audio: PulseAudio, ALSA utilities, mpv
  • Desktop tools: bleachbit, notifications
  • Clipboard: xclip, xsel
  • Network: NetworkManager (nmcli)"

        GUI_PACKAGES_TO_INSTALL="$(get_gui_packages_for_install)"
        if [[ "$GUI_PACKAGES_TO_INSTALL" == *"conky-all"* ]]; then
            GUI_MANUAL="  sudo apt-get install bleachbit kitty fontconfig fonts-noto-color-emoji conky-all \\
    alsa-utils pulseaudio pulseaudio-utils libnotify-bin xclip xsel mpv xterm network-manager"
        else
            print_info "Terminal/headless mode detected: skipping Conky package (conky-all)."
            GUI_MANUAL="  sudo apt-get install bleachbit kitty fontconfig fonts-noto-color-emoji \\
    alsa-utils pulseaudio pulseaudio-utils libnotify-bin xclip xsel mpv xterm network-manager"
        fi

        install_category_interactive "$GUI_PACKAGES_TO_INSTALL" "GUI" "$GUI_DESC" "$GUI_MANUAL"
        ensure_dpkg_healthy
    else
        print_warning "Skipping GUI packages (no desktop environment detected). Use --forcegui to install them anyway."
    fi

    # Contrib/non-free packages
    echo ""
    if [[ "$AUTO_YES" == "true" ]]; then
        print_info "Auto mode: Installing contrib/non-free packages..."
        REPLY="yes"
    else
        # FIXED: Simple working input method (stdin already redirected via exec)
        echo -n "Do you want to install packages that require contrib/non-free repositories? (YES/no) [default: yes]: "
        read -r REPLY
        # Default to YES if empty
        if [[ -z "$REPLY" ]]; then
            REPLY="yes"
        fi
        echo ""
    fi
    if [[ $REPLY =~ ^[Yy]([Ee][Ss])?$ ]]; then
        install_contrib_packages
        ensure_dpkg_healthy
    fi
    
    # Proxy tools
    echo ""
    if [[ "$AUTO_YES" == "true" ]]; then
        print_info "Auto mode: Installing proxy tools..."
        REPLY="yes"
    else
        # FIXED: Simple working input method (stdin already redirected via exec)
        echo -n "Do you want to install proxy tools (v2ray, xray, hysteria2, mieru)? (YES/no) [default: yes]: "
        read -r REPLY
        # Default to YES if empty
        if [[ -z "$REPLY" ]]; then
            REPLY="yes"
        fi
        echo ""
    fi
    if [[ $REPLY =~ ^[Yy]([Ee][Ss])?$ ]]; then
        install_v2ray
        install_xray
        install_hysteria2
        install_mieru
    else
        print_info "To install proxy tools manually:"
        echo "  • v2ray: https://github.com/v2fly/v2ray-core"
        echo "  • xray: bash -c \"\$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)\" @ install"
        echo "  • hysteria2: Download from https://github.com/apernet/hysteria/releases"
        echo "  • mieru: Download .deb from https://github.com/enfein/mieru/releases"
    fi
    
    # Advanced security tools (keystroke anonymization)
    echo ""
    install_advanced_security_tools

    # GRUB tools for health-control RAM wipe support (interactive prompt)
    echo ""
    print_step "GRUB Tools Installation (for health-control RAM wipe)"
    echo ""
    print_info "GRUB bootloader tools enable the 'init_on_free=1' kernel parameter"
    print_info "for additional RAM security. Not required for RAM wipe to function."
    echo ""

    if [[ "$AUTO_YES" == "true" ]]; then
        print_info "Auto mode: Installing GRUB tools..."
        install_grub_tools
    else
        echo -n "Do you want to install GRUB tools? (YES/no) [default: yes]: "
        read -r REPLY
        if [[ -z "$REPLY" ]]; then
            REPLY="yes"
        fi
        echo ""

        if [[ $REPLY =~ ^[Yy]([Ee][Ss])?$ ]]; then
            install_grub_tools
        else
            print_info "Skipping GRUB tools installation"
            print_warning "health-control RAM wipe will still work, but won't configure init_on_free=1"
            echo ""
        fi
    fi

    # Kicksecure RAM wipe (only if explicitly requested)
    if [[ "$INSTALL_KICKSECURE_RAMWIPE" == "true" ]]; then
        echo ""
        install_kicksecure_ram_wipe
    fi

elif [[ "$INSTALL_MODE" == "minimal" ]]; then
    print_highlight "Installing Minimal Package Set"
    echo ""
    install_packages "$ESSENTIAL_PACKAGES" "Essential"
    ensure_dpkg_healthy
    install_packages "$NETWORK_PACKAGES" "Network"
    ensure_dpkg_healthy
    # Initialize iptables alternatives after network packages
    initialize_iptables_alternatives
    # Handle contrib/non-free packages
    install_contrib_packages
    ensure_dpkg_healthy
    # Install DNS packages one by one with DNS testing after each
    install_privacy_packages_safe
    ensure_dpkg_healthy
    # Install DNSCrypt Proxy from GitHub with apt fallback
    echo ""
    print_step "Installing DNSCrypt Proxy from GitHub..."
    if ! install_dnscrypt_github; then
        print_warning "GitHub installation failed, trying apt package..."
        if timeout 60 apt-get install -y dnscrypt-proxy 2>&1 | tail -5; then
            print_success "DNSCrypt Proxy installed via apt"
        else
            print_error "Failed to install DNSCrypt Proxy from both GitHub and apt"
        fi
    fi
    # Install QRencode (APT first, GitHub fallback)
    echo ""
    install_qrencode_github
    # Try to install resolvconf (optional, won't break on failure)
    install_resolvconf_safe
    # Configure systemd-resolved for DNS caching and conflict avoidance
    configure_systemd_resolved
    ensure_dpkg_healthy
    # Install Pi-hole
    install_pihole
    ensure_dpkg_healthy
    
    # Install proxy tools in minimal mode
    echo ""
    print_highlight "Installing Proxy Tools"
    echo ""
    install_v2ray
    install_xray
    install_hysteria2
    install_mieru

    # Install monitoring packages
    echo ""
    print_highlight "Installing Monitoring Tools"
    echo ""
    install_packages "$MONITORING_PACKAGES" "Monitoring"
    ensure_dpkg_healthy

    # GRUB tools for health-control RAM wipe support
    echo ""
    install_grub_tools

elif [[ "$INSTALL_MODE" == "full" ]]; then
    print_highlight "Installing Full Package Set"
    echo ""
    install_packages "$ESSENTIAL_PACKAGES" "Essential"
    ensure_dpkg_healthy
    wait_for_apt
    install_packages "$NETWORK_PACKAGES" "Network"
    ensure_dpkg_healthy
    wait_for_apt
    # Initialize iptables alternatives after network packages
    initialize_iptables_alternatives
    # Handle contrib/non-free packages
    install_contrib_packages
    ensure_dpkg_healthy
    wait_for_apt
    # Install DNS packages one by one with DNS testing after each
    install_privacy_packages_safe
    ensure_dpkg_healthy
    wait_for_apt
    # Install DNSCrypt Proxy from GitHub with apt fallback
    echo ""
    print_step "Installing DNSCrypt Proxy from GitHub..."
    if ! install_dnscrypt_github; then
        print_warning "GitHub installation failed, trying apt package..."
        if timeout 60 apt-get install -y dnscrypt-proxy 2>&1 | tail -5; then
            print_success "DNSCrypt Proxy installed via apt"
        else
            print_error "Failed to install DNSCrypt Proxy from both GitHub and apt"
        fi
    fi
    # Install QRencode (APT first, GitHub fallback)
    echo ""
    install_qrencode_github
    # Try to install resolvconf (optional, won't break on failure)
    install_resolvconf_safe
    # Configure systemd-resolved for DNS caching and conflict avoidance
    configure_systemd_resolved
    ensure_dpkg_healthy
    wait_for_apt
    # Install Pi-hole after DNS packages
    install_pihole
    ensure_dpkg_healthy
    wait_for_apt
    install_packages "$SECURITY_PACKAGES" "Security"
    ensure_dpkg_healthy
    wait_for_apt
    install_packages "$ADVANCED_PACKAGES" "Advanced"
    ensure_dpkg_healthy
    wait_for_apt

    # Install monitoring packages
    echo ""
    print_highlight "Installing Monitoring Tools"
    echo ""
    install_packages "$MONITORING_PACKAGES" "Monitoring"
    ensure_dpkg_healthy
    wait_for_apt

    # Install GUI packages if desktop environment detected or forced, unless explicitly skipped
    echo ""
    if [[ "$SKIP_GUI_INSTALL" == "true" ]]; then
        print_info "Skipping GUI packages (--skipgui specified by user)."
    elif detect_gui_environment || [[ "$FORCE_GUI_INSTALL" == "true" ]]; then
        if [[ "$FORCE_GUI_INSTALL" == "true" ]] && ! detect_gui_environment; then
            print_warning "No desktop environment detected, but --forcegui specified"
            print_info "Installing GUI packages anyway (Conky will be skipped)."
        fi
        GUI_PACKAGES_TO_INSTALL="$(get_gui_packages_for_install)"
        if [[ "$GUI_PACKAGES_TO_INSTALL" != *"conky-all"* ]]; then
            print_info "Terminal/headless mode detected: skipping Conky package (conky-all)."
        fi
        install_packages "$GUI_PACKAGES_TO_INSTALL" "GUI"
        ensure_dpkg_healthy
        wait_for_apt
    else
        print_warning "Skipping GUI packages (no desktop environment detected). Use --forcegui to install them anyway."
    fi

    # Also install proxy tools
    echo ""
    print_highlight "Installing Proxy Tools"
    echo ""
    install_v2ray
    install_xray
    install_hysteria2
    install_mieru

    # Install advanced security tools (keystroke anonymization)
    echo ""
    install_advanced_security_tools

    # GRUB tools for health-control RAM wipe support
    echo ""
    install_grub_tools

    # Kicksecure RAM wipe (only if explicitly requested)
    if [[ "$INSTALL_KICKSECURE_RAMWIPE" == "true" ]]; then
        echo ""
        install_kicksecure_ram_wipe
    fi

else
    # Normal mode - install recommended packages
    print_highlight "Installing Recommended Package Set"
    echo ""
    install_packages "$ESSENTIAL_PACKAGES" "Essential"
    ensure_dpkg_healthy
    wait_for_apt
    install_packages "$NETWORK_PACKAGES" "Network"
    ensure_dpkg_healthy
    wait_for_apt
    # Initialize iptables alternatives after network packages
    initialize_iptables_alternatives
    # Handle contrib/non-free packages
    install_contrib_packages
    ensure_dpkg_healthy
    wait_for_apt
    # Install DNS packages one by one with DNS testing after each
    install_privacy_packages_safe
    ensure_dpkg_healthy
    wait_for_apt
    # Install DNSCrypt Proxy from GitHub with apt fallback
    echo ""
    print_step "Installing DNSCrypt Proxy from GitHub..."
    if ! install_dnscrypt_github; then
        print_warning "GitHub installation failed, trying apt package..."
        if timeout 60 apt-get install -y dnscrypt-proxy 2>&1 | tail -5; then
            print_success "DNSCrypt Proxy installed via apt"
        else
            print_error "Failed to install DNSCrypt Proxy from both GitHub and apt"
        fi
    fi
    # Install QRencode (APT first, GitHub fallback)
    echo ""
    install_qrencode_github
    # Try to install resolvconf (optional, won't break on failure)
    install_resolvconf_safe
    # Configure systemd-resolved for DNS caching and conflict avoidance
    configure_systemd_resolved
    ensure_dpkg_healthy
    wait_for_apt
    # Install Pi-hole after DNS packages
    install_pihole
    ensure_dpkg_healthy
    wait_for_apt
    install_packages "$SECURITY_PACKAGES" "Security"
    ensure_dpkg_healthy
    wait_for_apt
    install_packages "$ADVANCED_PACKAGES" "Advanced"
    ensure_dpkg_healthy
    wait_for_apt

    # Install monitoring packages
    echo ""
    print_highlight "Installing Monitoring Tools"
    echo ""
    install_packages "$MONITORING_PACKAGES" "Monitoring"
    ensure_dpkg_healthy
    wait_for_apt

    # Install GUI packages if desktop environment detected or forced, unless explicitly skipped
    echo ""
    if [[ "$SKIP_GUI_INSTALL" == "true" ]]; then
        print_info "Skipping GUI packages (--skipgui specified by user)."
    elif detect_gui_environment || [[ "$FORCE_GUI_INSTALL" == "true" ]]; then
        if [[ "$FORCE_GUI_INSTALL" == "true" ]] && ! detect_gui_environment; then
            print_warning "No desktop environment detected, but --forcegui specified"
            print_info "Installing GUI packages anyway (Conky will be skipped)."
        fi
        GUI_PACKAGES_TO_INSTALL="$(get_gui_packages_for_install)"
        if [[ "$GUI_PACKAGES_TO_INSTALL" != *"conky-all"* ]]; then
            print_info "Terminal/headless mode detected: skipping Conky package (conky-all)."
        fi
        install_packages "$GUI_PACKAGES_TO_INSTALL" "GUI"
        ensure_dpkg_healthy
        wait_for_apt
    else
        print_warning "Skipping GUI packages (no desktop environment detected). Use --forcegui to install them anyway."
    fi

    # Also install proxy tools
    echo ""
    print_highlight "Installing Proxy Tools"
    echo ""
    install_v2ray
    install_xray
    install_hysteria2
    install_mieru

    # GRUB tools for health-control RAM wipe support
    echo ""
    install_grub_tools
fi

# Function to disable UFW if installed
disable_ufw() {
    print_step "Checking UFW (Uncomplicated Firewall) status..."

    if command -v ufw &>/dev/null; then
        print_info "UFW is installed - checking status..."

        # Get UFW status
        local ufw_status=$(ufw status 2>/dev/null | grep -i "^Status:" | awk '{print $2}')

        if [[ "$ufw_status" == "active" ]]; then
            print_warning "UFW is currently active - disabling it to prevent conflicts with Kodachi's firewall"

            # Disable UFW
            if ufw --force disable 2>/dev/null; then
                print_success "UFW has been disabled"
            else
                print_error "Failed to disable UFW - you may need to disable it manually"
                print_info "Run: sudo ufw disable"
            fi

            # Also disable UFW service from starting at boot
            if systemctl is-enabled ufw &>/dev/null; then
                print_info "Disabling UFW service from starting at boot..."
                systemctl disable ufw 2>/dev/null || true
                print_success "UFW service disabled at boot"
            fi
        else
            print_success "UFW is already inactive"

            # Still disable service to prevent auto-start
            if systemctl is-enabled ufw &>/dev/null; then
                print_info "Disabling UFW service from starting at boot..."
                systemctl disable ufw 2>/dev/null || true
                print_success "UFW service disabled at boot"
            fi
        fi

        print_info "Note: Kodachi uses custom iptables/nftables rules for advanced security"
    else
        print_info "UFW is not installed"
    fi
}

# Disable UFW to prevent conflicts with Kodachi's firewall rules
disable_ufw
echo ""

# Final check
echo ""
print_highlight "Installation Summary"
echo ""

# Check critical tools
print_step "Checking critical tools..."
for tool in curl wget openssl tor openvpn; do
    if command -v "$tool" &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $tool - installed"
    else
        echo -e "  ${RED}✗${NC} $tool - missing"
    fi
done

# Check DNS tools
echo ""
print_step "Checking DNS tools..."
if command -v dig &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} dig - installed"
else
    echo -e "  ${YELLOW}!${NC} dig - not found"
fi

if command -v nslookup &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} nslookup - installed"
else
    echo -e "  ${YELLOW}!${NC} nslookup - not found"
fi

if command -v host &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} host - installed"
else
    echo -e "  ${YELLOW}!${NC} host - not found"
fi

if check_dns_tools; then
    echo -e "  ${GREEN}✓${NC} DNS utilities - available"
else
    echo -e "  ${RED}✗${NC} DNS utilities - missing (install dnsutils package)"
fi

# Check proxy tools
echo ""
print_step "Checking proxy tools..."

if command -v v2ray &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} v2ray - installed"
else
    echo -e "  ${RED}✗${NC} v2ray - FAILED (required)"
fi

if command -v v2ray-plugin &>/dev/null || command -v ss-v2ray-plugin &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} v2ray-plugin (shadowsocks) - installed"
else
    echo -e "  ${YELLOW}!${NC} v2ray-plugin - not found (optional)"
fi

if command -v xray &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} xray - installed"
else
    echo -e "  ${RED}✗${NC} xray - FAILED (required)"
fi

if command -v mieru &>/dev/null || dpkg -l mieru 2>/dev/null | grep -q "^ii"; then
    echo -e "  ${GREEN}✓${NC} mieru client - installed"
else
    echo -e "  ${RED}✗${NC} mieru client - FAILED (required)"
fi

if command -v hysteria &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} hysteria2 - installed"
else
    echo -e "  ${RED}✗${NC} hysteria2 - FAILED (required)"
fi

if command -v kloak &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} kloak (keystroke anonymization) - installed"
else
    echo -e "  ${YELLOW}!${NC} kloak - not found (advanced privacy tool)"
fi

# Check network tools
echo ""
print_step "Checking network tools..."
for tool in wireguard-tools shadowsocks-libev redsocks microsocks iptables nftables; do
    # Handle special cases
    if [[ "$tool" == "wireguard-tools" ]]; then
        if command -v wg &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $tool - installed"
        else
            echo -e "  ${YELLOW}!${NC} $tool - not found"
        fi
    elif [[ "$tool" == "shadowsocks-libev" ]]; then
        if command -v ss-local &>/dev/null || command -v ss-server &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $tool - installed"
        else
            echo -e "  ${YELLOW}!${NC} $tool - not found"
        fi
    elif [[ "$tool" == "nftables" ]]; then
        # nft might be in /usr/sbin which isn't always in PATH
        if command -v nft &>/dev/null || [[ -x /usr/sbin/nft ]] || [[ -x /sbin/nft ]]; then
            echo -e "  ${GREEN}✓${NC} $tool - installed"
        else
            echo -e "  ${YELLOW}!${NC} $tool - not found"
        fi
    else
        if command -v "$tool" &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $tool - installed"
        else
            echo -e "  ${YELLOW}!${NC} $tool - not found"
        fi
    fi
done

# Check security tools
echo ""
print_step "Checking security tools..."
for tool in ufw macchanger firejail apparmor; do
    if [[ "$tool" == "apparmor" ]]; then
        # AppArmor has apparmor_status command, not apparmor
        if command -v apparmor_status &>/dev/null || command -v aa-status &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $tool - installed"
        else
            echo -e "  ${YELLOW}!${NC} $tool - not found"
        fi
    elif [[ "$tool" == "ufw" ]]; then
        # Check UFW installation and status
        if command -v ufw &>/dev/null; then
            ufw_status=$(ufw status 2>/dev/null | grep -i "^Status:" | awk '{print $2}')
            if [[ "$ufw_status" == "inactive" ]]; then
                echo -e "  ${GREEN}✓${NC} $tool - installed (disabled - correct for Kodachi)"
            elif [[ "$ufw_status" == "active" ]]; then
                echo -e "  ${YELLOW}!${NC} $tool - installed but ACTIVE (should be disabled)"
            else
                echo -e "  ${GREEN}✓${NC} $tool - installed"
            fi
        else
            echo -e "  ${YELLOW}!${NC} $tool - not found"
        fi
    else
        if command -v "$tool" &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $tool - installed"
        else
            echo -e "  ${YELLOW}!${NC} $tool - not found"
        fi
    fi
done

# Check DNS security
echo ""
print_step "Checking DNS security tools..."
if command -v dnscrypt-proxy &>/dev/null; then
    dnscrypt_version=$(dnscrypt-proxy -version 2>/dev/null | head -1 | awk '{print $1}' || echo "unknown")
    echo -e "  ${GREEN}✓${NC} dnscrypt-proxy - installed (version: $dnscrypt_version)"
    if [[ "$dnscrypt_version" == "$DNSCRYPT_VERSION" ]]; then
        echo -e "      ${GREEN}→ Correct version v${DNSCRYPT_VERSION} from GitHub${NC}"
    elif [[ "$dnscrypt_version" != "unknown" ]]; then
        echo -e "      ${YELLOW}→ Version $dnscrypt_version (expected: v${DNSCRYPT_VERSION})${NC}"
    fi
else
    echo -e "  ${YELLOW}!${NC} dnscrypt-proxy - not found"
fi

if command -v qrencode &>/dev/null; then
    qrencode_version=$(qrencode -V 2>/dev/null | head -1 | awk '{print $3}' || echo "unknown")
    echo -e "  ${GREEN}✓${NC} qrencode - installed (version: $qrencode_version)"
    if [[ "$qrencode_version" == "$QRENCODE_VERSION" ]]; then
        echo -e "      ${GREEN}→ Version v${QRENCODE_VERSION} installed${NC}"
    elif [[ "$qrencode_version" != "unknown" ]]; then
        echo -e "      ${YELLOW}→ Version $qrencode_version (expected: v${QRENCODE_VERSION})${NC}"
    fi
else
    echo -e "  ${YELLOW}!${NC} qrencode - not found"
fi

if command -v resolvconf &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} resolvconf - installed (for VPN DNS management)"
else
    # Check if VPN tools are installed that might need it
    if command -v wg-quick &>/dev/null || command -v openvpn &>/dev/null; then
        echo -e "  ${YELLOW}!${NC} resolvconf - missing (needed for WireGuard/OpenVPN DNS)"
        echo -e "      ${CYAN}→ Run the installer again to fix VPN DNS support${NC}"
    else
        echo -e "  ${CYAN}○${NC} resolvconf - not needed (no VPN tools requiring it)"
    fi
fi

# Check Pi-hole
echo ""
print_step "Checking Pi-hole..."
PIHOLE_INSTALLED=false
if systemctl is-active --quiet pihole-FTL 2>/dev/null || command -v pihole &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Pi-hole - installed"
    PIHOLE_INSTALLED=true
    if systemctl is-active --quiet pihole-FTL 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Pi-hole FTL service - running"
    else
        echo -e "  ${YELLOW}!${NC} Pi-hole FTL service - not running"
    fi
else
    echo -e "  ${YELLOW}!${NC} Pi-hole - not installed (optional DNS filtering)"
fi

# Check critical system utilities
echo ""
print_step "Checking system utilities..."
for tool in sudo systemd jq git haproxy rfkill; do
    if [[ "$tool" == "systemd" ]]; then
        # systemd has systemctl command, not systemd
        if command -v systemctl &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $tool - installed"
        else
            echo -e "  ${YELLOW}!${NC} $tool - not found"
        fi
    elif [[ "$tool" == "rfkill" ]]; then
        # rfkill for managing wireless devices
        if command -v rfkill &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $tool - installed (wireless device control)"
        else
            echo -e "  ${YELLOW}!${NC} $tool - not found (needed for wireless management)"
        fi
    else
        if command -v "$tool" &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $tool - installed"
        else
            echo -e "  ${YELLOW}!${NC} $tool - not found"
        fi
    fi
done

# Check RAM wipe security tools (Kicksecure - optional)
echo ""
print_step "Checking Kicksecure RAM wipe tools (optional)..."
print_info "Note: Kodachi has built-in RAM wipe via 'health-control memory-wipe'"
if check_package "ram-wipe"; then
    echo -e "  ${GREEN}✓${NC} ram-wipe - installed (Kicksecure)"
else
    echo -e "  ${BLUE}ℹ${NC} ram-wipe - not installed (optional, use --force-kicksecure-ramwipe to install)"
fi

if check_package "dracut"; then
    echo -e "  ${GREEN}✓${NC} dracut - installed"
else
    echo -e "  ${BLUE}ℹ${NC} dracut - not installed (optional, needed for Kicksecure RAM wipe)"
fi

if check_package "dracut-core"; then
    echo -e "  ${GREEN}✓${NC} dracut-core - installed"
else
    echo -e "  ${BLUE}ℹ${NC} dracut-core - not installed (optional, needed for Kicksecure RAM wipe)"
fi

# Cleanup unused packages
echo ""
print_step "Cleaning up unused packages..."
export DEBIAN_FRONTEND=noninteractive
if apt autoremove -y 2>&1 | tail -5; then
    print_success "Cleanup completed - removed unused packages"
else
    print_warning "Cleanup had some issues but continuing..."
fi

# ============================================================================
# SERVICE CLEANUP - Stop services and kill processes
# ============================================================================

echo ""
print_highlight "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_highlight "Service Cleanup and Hardening"
print_highlight "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

print_info "Stopping unnecessary services and processes for security..."
echo ""

# Detect if running in chroot environment (live-build)
is_chroot_environment() {
    # Check for live-build indicator files
    if [ -f "/.debian-live-build" ] || [ -f "/tmp/live-build-chroot" ]; then
        return 0
    fi
    # Check if we're in a chroot by comparing root inode
    if [ "$(stat -c %d:%i / 2>/dev/null)" != "$(stat -c %d:%i /proc/1/root 2>/dev/null)" ]; then
        return 0
    fi
    # Check if /proc/1/cmdline contains typical init processes
    if [ -f /proc/1/cmdline ]; then
        local init_cmd
        init_cmd=$(tr '\0' ' ' < /proc/1/cmdline 2>/dev/null)
        # In chroot, PID 1 might be something unusual
        if [[ ! "$init_cmd" =~ (systemd|init|/sbin/init) ]]; then
            return 0
        fi
    fi
    return 1
}

# Function to stop, disable service and kill processes (chroot-aware)
stop_and_disable_service() {
    local service_name="$1"
    local service_display="$2"
    local process_name="$3"  # Process name to kill
    local in_chroot=false

    # Detect chroot environment
    if is_chroot_environment; then
        in_chroot=true
        echo -e "  ${CYAN}[CHROOT]${NC} Processing ${service_display}..."
    else
        print_step "Processing ${service_display}..."
    fi

    local stopped_service=false
    local disabled_service=false
    local killed_process=false

    # In chroot, prioritize process killing since systemctl may not work
    if [ "$in_chroot" = true ]; then
        # Kill process first in chroot
        if [[ -n "$process_name" ]]; then
            if pgrep -x "$process_name" >/dev/null 2>&1; then
                echo -e "  ${YELLOW}!${NC} Found running process: $process_name"

                # Force kill immediately in chroot (no grace period needed)
                if pkill -9 "$process_name" 2>/dev/null; then
                    echo -e "  ${GREEN}✓${NC} Force killed $process_name"
                    sleep 1
                fi

                # Verify stopped
                if ! pgrep -x "$process_name" >/dev/null 2>&1; then
                    echo -e "  ${GREEN}✓${NC} Process $process_name stopped successfully"
                    killed_process=true
                else
                    echo -e "  ${RED}✗${NC} Failed to stop $process_name"
                fi
            else
                echo -e "  ${BLUE}ℹ${NC} No $process_name processes found"
                killed_process=true
            fi
        fi

        # Try systemctl but don't rely on it in chroot
        if command -v systemctl >/dev/null 2>&1; then
            echo -e "  ${BLUE}ℹ${NC} Skipping systemctl disable for ${service_name} (chroot environment)"
        fi
    else
        # Normal system: use systemctl properly
        if systemctl list-unit-files 2>/dev/null | grep -q "^${service_name}"; then
            if systemctl is-active --quiet "$service_name" 2>/dev/null; then
                if systemctl stop "$service_name" 2>/dev/null; then
                    echo -e "  ${GREEN}✓${NC} Stopped systemd service: ${service_name}"
                    stopped_service=true
                else
                    echo -e "  ${RED}✗${NC} Failed to stop ${service_name}"
                fi
            else
                echo -e "  ${BLUE}ℹ${NC} Service not running: ${service_name}"
                stopped_service=true
            fi

            # Disable the service
            if systemctl is-enabled --quiet "$service_name" 2>/dev/null; then
                if systemctl disable "$service_name" 2>/dev/null; then
                    echo -e "  ${GREEN}✓${NC} Disabled ${service_display}"
                    disabled_service=true
                else
                    echo -e "  ${RED}✗${NC} Failed to disable ${service_name}"
                fi
            else
                echo -e "  ${BLUE}ℹ${NC} Service not enabled: ${service_name}"
                disabled_service=true
            fi
        fi

        # Kill any remaining processes (fallback for non-systemd services)
        if [[ -n "$process_name" ]]; then
            if pgrep -x "$process_name" >/dev/null 2>&1; then
                echo -e "  ${YELLOW}!${NC} Found running process: $process_name"

                # Try graceful termination first
                if pkill -TERM "$process_name" 2>/dev/null; then
                    echo -e "  ${GREEN}✓${NC} Sent TERM signal to $process_name"
                    sleep 2
                fi

                # Force kill if still running
                if pgrep -x "$process_name" >/dev/null 2>&1; then
                    if pkill -9 "$process_name" 2>/dev/null; then
                        echo -e "  ${GREEN}✓${NC} Force killed $process_name processes"
                    fi
                fi

                # Verify stopped
                sleep 1
                if ! pgrep -x "$process_name" >/dev/null 2>&1; then
                    echo -e "  ${GREEN}✓${NC} Process $process_name successfully stopped"
                    killed_process=true
                else
                    echo -e "  ${RED}✗${NC} Warning: $process_name may still be running"
                fi
            else
                echo -e "  ${BLUE}ℹ${NC} No $process_name processes found"
                killed_process=true
            fi
        fi
    fi
}

# Stop and disable CUPS (printing service) - not needed on Kodachi
# Must stop socket/path units first to prevent auto-restart
stop_and_disable_service "cups.socket" "CUPS Socket" ""
stop_and_disable_service "cups.path" "CUPS Path" ""
stop_and_disable_service "cups.service" "CUPS Printing Service" "cupsd"
stop_and_disable_service "cups-browsed.service" "CUPS Browser Service" "cups-browsed"

# Stop and disable Tor - will be managed by Kodachi tor-switch service
echo ""
print_step "Processing Tor (will be managed by Kodachi)..."

# In chroot, FORCE stop regardless of initial state (for ISO builds)
if is_chroot_environment; then
    echo -e "  ${CYAN}Note:${NC} Chroot build detected - forcing Tor stop for clean ISO"
    stop_and_disable_service "tor.service" "Tor Service" "tor"
    stop_and_disable_service "tor@default.service" "Tor Default Instance" ""
elif [[ "$INITIAL_TOR_RUNNING" == "true" ]]; then
    echo -e "  ${YELLOW}⚠${NC}  Tor was running before script - ${BOLD}PRESERVED${NC}"
    echo -e "  ${CYAN}Note:${NC} Stopping it could break your anonymized connection during update"
    echo -e "  ${CYAN}To stop manually after script:${NC}"
    echo -e "      sudo systemctl stop tor"
    echo -e "      sudo systemctl disable tor"
else
    echo -e "  ${CYAN}Note:${NC} Tor will be controlled by Kodachi's tor-switch service"
    stop_and_disable_service "tor.service" "Tor Service" "tor"
    stop_and_disable_service "tor@default.service" "Tor Default Instance" ""
fi

# Stop and disable Shadowsocks server - will be managed by routing-switch
echo ""
print_step "Processing Shadowsocks (routing-switch control)..."
if is_chroot_environment; then
    echo -e "  ${CYAN}Note:${NC} Chroot build detected - forcing Shadowsocks stop for clean ISO"
else
    echo -e "  ${CYAN}Note:${NC} Shadowsocks will be managed by routing-switch"
fi
stop_and_disable_service "shadowsocks-libev.service" "Shadowsocks Server" "ss-server"
stop_and_disable_service "shadowsocks-libev-local.service" "Shadowsocks Local" "ss-local"
stop_and_disable_service "shadowsocks-libev-redir.service" "Shadowsocks Redir" "ss-redir"
stop_and_disable_service "shadowsocks-libev-server.service" "Shadowsocks Server Instance" ""

# Stop and disable Redsocks - will be managed by routing-switch
echo ""
print_step "Processing Redsocks (routing-switch control)..."

# In chroot, FORCE stop regardless of initial state (for ISO builds)
if is_chroot_environment; then
    echo -e "  ${CYAN}Note:${NC} Chroot build detected - forcing Redsocks stop for clean ISO"
    stop_and_disable_service "redsocks.service" "Redsocks Transparent Proxy" "redsocks"
elif [[ "$INITIAL_REDSOCKS_RUNNING" == "true" ]]; then
    echo -e "  ${YELLOW}⚠${NC}  Redsocks was running before script - ${BOLD}PRESERVED${NC}"
    echo -e "  ${CYAN}Note:${NC} Stopping it could break your transparent proxy during update"
    echo -e "  ${CYAN}To stop manually after script:${NC}"
    echo -e "      sudo systemctl stop redsocks"
    echo -e "      sudo systemctl disable redsocks"
else
    echo -e "  ${CYAN}Note:${NC} Redsocks will be managed by routing-switch"
    stop_and_disable_service "redsocks.service" "Redsocks Transparent Proxy" "redsocks"
fi

# Stop and disable Microsocks - will be managed by routing-switch
echo ""
print_step "Processing Microsocks (routing-switch control)..."
echo -e "  ${CYAN}Note:${NC} Microsocks will be managed by routing-switch"
stop_and_disable_service "microsocks.service" "Microsocks SOCKS5 Proxy" "microsocks"

# Stop and disable Avahi daemon - privacy leak (broadcasts hostname/services)
echo ""
print_step "Processing Avahi daemon (mDNS service discovery)..."
echo -e "  ${CYAN}Note:${NC} Avahi broadcasts hostname and services - privacy leak"
stop_and_disable_service "avahi-daemon.service" "Avahi Daemon" "avahi-daemon"
stop_and_disable_service "avahi-daemon.socket" "Avahi Daemon Socket" ""

# Stop and disable DNSCrypt Proxy - will be managed by dns-switch
echo ""
print_step "Processing DNSCrypt Proxy (dns-switch control)..."

# In chroot, FORCE stop regardless of initial state (for ISO builds)
if is_chroot_environment; then
    echo -e "  ${CYAN}Note:${NC} Chroot build detected - forcing DNSCrypt stop for clean ISO"
    stop_and_disable_service "dnscrypt-proxy.service" "DNSCrypt Proxy" "dnscrypt-proxy"
    stop_and_disable_service "dnscrypt-proxy.socket" "DNSCrypt Proxy Socket" ""
elif [[ "$INITIAL_DNSCRYPT_RUNNING" == "true" ]]; then
    echo -e "  ${YELLOW}⚠${NC}  DNSCrypt Proxy was running before script - ${BOLD}PRESERVED${NC}"
    echo -e "  ${CYAN}Note:${NC} Stopping it could break your internet connection during update"
    echo -e "  ${CYAN}To stop manually after script:${NC}"
    echo -e "      sudo systemctl stop dnscrypt-proxy"
    echo -e "      sudo systemctl disable dnscrypt-proxy"
else
    echo -e "  ${CYAN}Note:${NC} DNSCrypt Proxy will be managed by dns-switch"
    stop_and_disable_service "dnscrypt-proxy.service" "DNSCrypt Proxy" "dnscrypt-proxy"
    stop_and_disable_service "dnscrypt-proxy.socket" "DNSCrypt Proxy Socket" ""
fi

# NTP time sync services - ENABLED for proper time synchronization
# NOTE: Previously disabled due to fingerprinting concerns, but this caused critical issues:
# - Physical hardware boots with incorrect clock (VMware syncs to host, USB media does not)
# - SSL/TLS certificates appear invalid until the user fixes time manually
# - curl/HTTPS requests and time-based authentication tokens fail on first boot
# - An obviously wrong clock is itself a fingerprinting risk
# DECISION: Leave NTP services managed by systemd presets so the clock syncs automatically.
# Users who want to disable NTP can still do so manually after boot:
#   sudo systemctl disable systemd-timesyncd.service
# echo ""
# print_step "Processing NTP services (time synchronization)..."
# echo -e "  ${CYAN}Note:${NC} NTP enabled for proper time synchronization (required for SSL/TLS)"
# NTP services are now managed by systemd preset: /etc/systemd/system-preset/90-kodachi-services.preset
# systemd-timesyncd.service is ENABLED by default for automatic time synchronization

# Stop and disable kloak - keystroke anonymization (manual start when needed)
echo ""
print_step "Processing kloak (keystroke anonymization)..."
echo -e "  ${CYAN}Note:${NC} kloak will be disabled for manual activation when needed"

# Stop kloak service
if systemctl is-active --quiet kloak.service 2>/dev/null; then
    if systemctl stop kloak.service 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Stopped kloak service"
    else
        echo -e "  ${YELLOW}!${NC} Failed to stop kloak service"
    fi
else
    echo -e "  ${BLUE}ℹ${NC} kloak service not running"
fi

# Disable kloak service
if systemctl is-enabled --quiet kloak.service &>/dev/null; then
    if systemctl disable kloak.service 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Disabled kloak service"
    else
        echo -e "  ${YELLOW}!${NC} Failed to disable kloak service"
    fi
else
    echo -e "  ${BLUE}ℹ${NC} kloak service already disabled"
fi

# Verify kloak is disabled
if systemctl is-enabled kloak.service &>/dev/null; then
    echo -e "  ${RED}✗${NC} Warning: kloak service is still enabled"
else
    echo -e "  ${GREEN}✓${NC} Verified: kloak service is disabled"
fi

# Stop and disable ram-wipe-kexec-prepare - RAM wipe preparation (manual start when needed)
echo ""
print_step "Processing ram-wipe-kexec-prepare (RAM wipe preparation)..."
echo -e "  ${CYAN}Note:${NC} ram-wipe-kexec-prepare will be disabled for manual activation when needed"

# Stop ram-wipe-kexec-prepare service
if systemctl is-active --quiet ram-wipe-kexec-prepare.service 2>/dev/null; then
    if systemctl stop ram-wipe-kexec-prepare.service 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Stopped ram-wipe-kexec-prepare service"
    else
        echo -e "  ${YELLOW}!${NC} Failed to stop ram-wipe-kexec-prepare service"
    fi
else
    echo -e "  ${BLUE}ℹ${NC} ram-wipe-kexec-prepare service not running"
fi

# Disable ram-wipe-kexec-prepare service
if systemctl is-enabled --quiet ram-wipe-kexec-prepare.service &>/dev/null; then
    if systemctl disable ram-wipe-kexec-prepare.service 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Disabled ram-wipe-kexec-prepare service"
    else
        echo -e "  ${YELLOW}!${NC} Failed to disable ram-wipe-kexec-prepare service"
    fi
else
    echo -e "  ${BLUE}ℹ${NC} ram-wipe-kexec-prepare service already disabled"
fi

# Verify ram-wipe-kexec-prepare is disabled
if systemctl is-enabled ram-wipe-kexec-prepare.service &>/dev/null; then
    echo -e "  ${RED}✗${NC} Warning: ram-wipe-kexec-prepare service is still enabled"
else
    echo -e "  ${GREEN}✓${NC} Verified: ram-wipe-kexec-prepare service is disabled"
fi

# Handle Pi-hole based on installation mode and user preference
echo ""
print_step "Processing Pi-hole..."
PIHOLE_KEEP=false  # Default: stop Pi-hole for security

# Check if Pi-hole is installed
if command -v pihole &>/dev/null || systemctl list-unit-files 2>/dev/null | grep -q "^pihole-FTL"; then
    echo -e "  ${GREEN}✓${NC} Pi-hole is installed"

    # In interactive or non-auto mode, ask user
    if [[ "$INSTALL_MODE" == "interactive" ]] || [[ "$AUTO_YES" == "false" ]]; then
        echo ""
        print_info "Pi-hole provides network-wide DNS filtering and ad blocking."
        print_info "It's currently running on ports 53 (DNS), 80 (HTTP), and 443 (HTTPS)."
        echo ""

        read -p "$(echo -e ${CYAN}"Do you want to keep Pi-hole running? [Y/n]: "${NC})" -n 1 -r
        echo ""

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            PIHOLE_KEEP=true
        fi
    else
        # In auto mode, stop Pi-hole by default
        echo -e "  ${CYAN}Note:${NC} Pi-hole will be stopped (ports 53, 80, 443 closed)"
        echo -e "  ${CYAN}To keep it running:${NC} Use --interactive mode and answer 'Y'"
    fi

    if [[ "$PIHOLE_KEEP" == "false" ]]; then
        print_step "Stopping Pi-hole as requested..."
        stop_and_disable_service "pihole-FTL.service" "Pi-hole FTL Service" "pihole-FTL"
        echo -e "  ${YELLOW}ℹ${NC} To remove Pi-hole completely, run: pihole uninstall"
    else
        echo -e "  ${GREEN}✓${NC} Pi-hole will remain active"
    fi
else
    echo -e "  ${BLUE}ℹ${NC} Pi-hole not installed"
fi

# ============================================================================
# EXIM4 COMPLETE REMOVAL
# ============================================================================

echo ""
print_highlight "Removing Exim4 Mail Transfer Agent..."
echo ""

print_info "Exim4 is not needed for Kodachi and opens port 25 unnecessarily"

# Check if exim4 processes are running (regardless of package status)
if pgrep -x "exim4" >/dev/null 2>&1; then
    print_step "Killing exim4 processes..."
    pkill -9 exim4 2>/dev/null || true
    sleep 1
    if ! pgrep -x "exim4" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} Killed all exim4 processes"
    else
        echo -e "  ${YELLOW}!${NC} Some exim4 processes may still be running"
    fi
fi

# Check if exim4 packages are installed
if dpkg -l 2>/dev/null | grep -q "^ii.*exim4"; then
    print_step "Removing exim4 packages..."

    # Stop exim4 service if running
    systemctl stop exim4 2>/dev/null || true
    systemctl disable exim4 2>/dev/null || true

    # Purge all exim4 packages
    if DEBIAN_FRONTEND=noninteractive apt-get purge -y exim4 exim4-base exim4-config exim4-daemon-light 2>&1 | grep -E "(Removing|Purging)"; then
        echo -e "  ${GREEN}✓${NC} Removed exim4 packages"

        # Clean up dependencies
        print_step "Cleaning up unused dependencies..."
        if apt-get autoremove -y 2>&1 | grep -E "(Removing|freed)"; then
            echo -e "  ${GREEN}✓${NC} Cleaned up dependencies"
        fi
    else
        echo -e "  ${YELLOW}!${NC} exim4 removal encountered issues"
    fi

    # Kill any remaining exim4 processes
    if pgrep -x "exim4" >/dev/null 2>&1; then
        echo -e "  ${YELLOW}!${NC} Found remaining exim4 processes - killing..."
        pkill -9 "exim4" 2>/dev/null || true
        sleep 1
        if ! pgrep -x "exim4" >/dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} Killed all exim4 processes"
        fi
    fi

    # Verify exim4 is gone
    if ! dpkg -l 2>/dev/null | grep -q "^ii.*exim4" && ! pgrep -x "exim4" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} exim4 completely removed"
    fi
else
    # Check if process is running without package
    if pgrep -x "exim4" >/dev/null 2>&1; then
        echo -e "  ${YELLOW}!${NC} exim4 process running but package not installed (killed above)"
    else
        echo -e "  ${GREEN}✓${NC} exim4 not installed (good!)"
    fi
fi

# ============================================================================
# CLEANUP SUMMARY AND VERIFICATION
# ============================================================================

echo ""
print_highlight "Service Cleanup Summary"
print_highlight "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Show preserved services first (if any)
PRESERVED_SERVICES=()
if [[ "$INITIAL_DNSCRYPT_RUNNING" == "true" ]]; then
    PRESERVED_SERVICES+=("DNSCrypt Proxy (DNS resolver)")
fi
if [[ "$INITIAL_TOR_RUNNING" == "true" ]]; then
    PRESERVED_SERVICES+=("Tor (anonymized connection)")
fi
if [[ "$INITIAL_REDSOCKS_RUNNING" == "true" ]]; then
    PRESERVED_SERVICES+=("Redsocks (transparent proxy)")
fi
if [[ "$INITIAL_PIHOLE_RUNNING" == "true" ]] && [[ "$PIHOLE_KEEP" != "false" ]]; then
    PRESERVED_SERVICES+=("Pi-hole (DNS filtering)")
fi

if [[ ${#PRESERVED_SERVICES[@]} -gt 0 ]]; then
    print_warning "Services PRESERVED (were running before script - NOT stopped):"
    for service in "${PRESERVED_SERVICES[@]}"; do
        echo "  ⚠  $service"
    done
    echo ""
    print_info "These services were kept running to avoid breaking your internet during update"
    print_info "To stop them manually, see the commands shown earlier in the output"
    echo ""
fi

print_info "Services stopped and disabled (NOT masked - Kodachi binaries can re-enable):"
if [[ "$INITIAL_CUPS_RUNNING" != "true" ]] || [[ "$INITIAL_CUPS_RUNNING" == "true" ]]; then
    echo "  • CUPS (printing) - not needed"
fi
echo "  • Avahi daemon (mDNS) - privacy leak (broadcasts hostname/services)"
if [[ "$INITIAL_DNSCRYPT_RUNNING" != "true" ]]; then
    echo "  • DNSCrypt Proxy - will be managed by Kodachi dns-switch"
fi
echo "  • NTP/time sync (ntpd/systemd-timesyncd) - fingerprinting risk"
if [[ "$INITIAL_TOR_RUNNING" != "true" ]]; then
    echo "  • Tor - will be managed by Kodachi tor-switch"
fi
echo "  • Shadowsocks - will be managed by routing-switch"
if [[ "$INITIAL_REDSOCKS_RUNNING" != "true" ]]; then
    echo "  • Redsocks - will be managed by routing-switch"
fi
echo "  • Microsocks - will be managed by routing-switch"
echo "  • kloak (keystroke anonymization) - disabled for manual activation"
if check_package "ram-wipe"; then
    echo "  • ram-wipe-kexec-prepare (Kicksecure RAM wipe) - disabled for manual activation"
fi
if [[ "$PIHOLE_KEEP" == "false" ]]; then
    echo "  • Pi-hole - stopped as requested"
fi
echo ""

print_info "Packages removed:"
echo "  • exim4 (mail transfer agent) - security hardening"
echo ""

# Verify processes are stopped
echo ""
print_step "Verifying processes are stopped..."
STILL_RUNNING=()
for proc in cupsd tor ss-server ss-local ss-redir redsocks microsocks exim4 avahi-daemon dnscrypt-proxy ntpd systemd-timesyncd pihole-FTL; do
    if pgrep -x "$proc" >/dev/null 2>&1; then
        STILL_RUNNING+=("$proc")
    fi
done

if [[ ${#STILL_RUNNING[@]} -eq 0 ]]; then
    echo -e "  ${GREEN}✓${NC} All targeted processes successfully stopped"
else
    echo -e "  ${YELLOW}!${NC} Warning: Some processes still running: ${STILL_RUNNING[*]}"
fi

echo ""
print_success "Service cleanup completed!"
echo ""

print_info "To re-enable a service if needed (Kodachi binaries can also do this):"
echo -e "  ${CYAN}sudo systemctl enable <service>${NC}"
echo -e "  ${CYAN}sudo systemctl start <service>${NC}"
echo ""

# Clean up any orphaned background processes before port check
print_step "Cleaning up orphaned background processes..."
# Kill any remaining curl processes that might be from installations
if pgrep -f "curl.*install\|curl.*github\|curl.*pi-hole" &>/dev/null; then
    pkill -9 -f "curl.*install\|curl.*github\|curl.*pi-hole" 2>/dev/null || true
    sleep 1
    echo -e "  ${GREEN}✓${NC} Cleaned up orphaned curl processes"
else
    echo -e "  ${GREEN}✓${NC} No orphaned processes found"
fi
echo ""

# ============================================================================
# GLOBAL LAUNCHER DEPLOYMENT
# ============================================================================

echo ""
print_highlight "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_highlight "Global Launcher Deployment"
print_highlight "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Try to find the global-launcher binary
HOOKS_DIR=""
GLOBAL_LAUNCHER_PATH=""

# Search for hooks directory in common locations
for search_dir in \
    "/home/*/k900/dashboard/hooks" \
    "/home/*/dashboard/hooks" \
    "/home/*/Desktop/k900/dashboard/hooks" \
    "$HOME/k900/dashboard/hooks" \
    "$HOME/dashboard/hooks" \
    "$HOME/Desktop/k900/dashboard/hooks"; do

    # Expand glob pattern
    for dir in $search_dir; do
        if [[ -d "$dir" ]] && [[ -f "$dir/global-launcher" ]]; then
            HOOKS_DIR="$dir"
            GLOBAL_LAUNCHER_PATH="$dir/global-launcher"
            break 2
        fi
    done
done

# If not found, check current directory
if [[ -z "$GLOBAL_LAUNCHER_PATH" ]] && [[ -f "./global-launcher" ]]; then
    HOOKS_DIR="$(pwd)"
    GLOBAL_LAUNCHER_PATH="./global-launcher"
fi

if [[ -n "$GLOBAL_LAUNCHER_PATH" ]] && [[ -x "$GLOBAL_LAUNCHER_PATH" ]]; then
    print_step "Found global-launcher at: $HOOKS_DIR"

    # Deploy global launcher
    print_step "Deploying Kodachi binaries to /usr/local/bin..."

    # Change to hooks directory for deployment
    pushd "$HOOKS_DIR" > /dev/null 2>&1

    if ./global-launcher deploy 2>&1; then
        echo -e "  ${GREEN}✓${NC} Global launcher deployed successfully"

        # Verify deployment
        print_step "Verifying deployment..."
        if ./global-launcher verify 2>&1 | grep -q "SUCCESS"; then
            VERIFY_OUTPUT=$(./global-launcher verify 2>&1)
            echo -e "  ${GREEN}✓${NC} $VERIFY_OUTPUT"
        else
            echo -e "  ${YELLOW}!${NC} Verification completed with warnings"
        fi
    else
        echo -e "  ${YELLOW}!${NC} Global launcher deployment failed (non-critical)"
        print_info "You can manually deploy later with: sudo $GLOBAL_LAUNCHER_PATH deploy"
    fi

    popd > /dev/null 2>&1

else
    print_info "Global launcher not found - skipping deployment"
    print_info "This is normal if Kodachi binaries are not yet compiled"
    print_info "To deploy later:"
    echo -e "  ${CYAN}1. Build Kodachi binaries: cd dashboard/hooks/rust && cargo build --release${NC}"
    echo -e "  ${CYAN}2. Deploy global launcher: cd dashboard/hooks && sudo ./global-launcher deploy${NC}"
fi

echo ""

# =============================================================================
# Install Kodachi Welcome Commands
# =============================================================================
# This function installs the Kodachi welcome script and commands system-wide
# to match the live ISO behavior. It handles version comparison and ensures
# no conflicts when the deps installer runs during ISO build.
#
# Installed files:
#   - /etc/profile.d/kodachi-welcome.sh (profile.d script with skip logic)
#   - /usr/local/bin/welcome (wrapper script)
#   - /usr/local/bin/kodachi (symlink to welcome)
#   - /usr/local/bin/Kodachi (symlink to welcome)
# =============================================================================

install_welcome_commands() {
    echo ""
    print_highlight "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_highlight "Installing Kodachi Welcome Commands"
    print_highlight "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Search for packaged scripts in multiple locations
    local PROFILE_SCRIPT=""
    local WRAPPER_SCRIPT=""

    # Search paths in priority order
    local search_paths=(
        "$HOOKS_DIR/binaries-update-scripts"
        "$HOME/dashboard/hooks/binaries-update-scripts"
    )

    # Add glob pattern for other users' dashboard/hooks
    for user_home in /home/*; do
        if [[ -d "$user_home/dashboard/hooks/binaries-update-scripts" ]]; then
            search_paths+=("$user_home/dashboard/hooks/binaries-update-scripts")
        fi
    done

    # Find the scripts
    for base_dir in "${search_paths[@]}"; do
        if [[ -f "$base_dir/kodachi-welcome.sh" ]]; then
            PROFILE_SCRIPT="$base_dir/kodachi-welcome.sh"
            WRAPPER_SCRIPT="$base_dir/welcome"
            break
        fi
    done

    if [[ -z "$PROFILE_SCRIPT" ]]; then
        print_warning "Welcome scripts not found in package, skipping..."
        return 0
    fi

    # Extract version from new script
    local NEW_BUILD_NUM=$(grep '^BUILD_NUM=' "$PROFILE_SCRIPT" 2>/dev/null | cut -d'"' -f2)
    local NEW_VERSION=$(grep '^BUILD_VERSION=' "$PROFILE_SCRIPT" 2>/dev/null | cut -d'"' -f2)

    # Check existing installation
    local INSTALLED_SCRIPT="/etc/profile.d/kodachi-welcome.sh"
    local SHOULD_INSTALL=true

    if [[ -f "$INSTALLED_SCRIPT" ]]; then
        local INSTALLED_BUILD_NUM=$(grep '^BUILD_NUM=' "$INSTALLED_SCRIPT" 2>/dev/null | cut -d'"' -f2)

        if [[ -n "$NEW_BUILD_NUM" ]] && [[ -n "$INSTALLED_BUILD_NUM" ]]; then
            if (( NEW_BUILD_NUM > INSTALLED_BUILD_NUM )); then
                print_info "Updating Kodachi welcome script ($NEW_VERSION.$INSTALLED_BUILD_NUM → $NEW_VERSION.$NEW_BUILD_NUM)..."
            elif (( NEW_BUILD_NUM == INSTALLED_BUILD_NUM )); then
                print_info "Kodachi welcome script already current (version $NEW_VERSION.$NEW_BUILD_NUM), verifying commands..."
                SHOULD_INSTALL=false
            else
                print_info "Installed version ($INSTALLED_BUILD_NUM) is newer than package ($NEW_BUILD_NUM), skipping..."
                SHOULD_INSTALL=false
            fi
        fi
    else
        print_info "Installing Kodachi welcome commands (version $NEW_VERSION.$NEW_BUILD_NUM)..."
    fi

    # Install profile.d script if needed
    if [[ "$SHOULD_INSTALL" == true ]]; then
        cp "$PROFILE_SCRIPT" "$INSTALLED_SCRIPT"
        chmod 644 "$INSTALLED_SCRIPT"
    fi

    # Always verify/recreate wrapper and symlinks (idempotent)
    if [[ -f "$WRAPPER_SCRIPT" ]]; then
        cp "$WRAPPER_SCRIPT" /usr/local/bin/welcome
        chmod 755 /usr/local/bin/welcome
    else
        # Fallback: create wrapper if not in package
        cat > /usr/local/bin/welcome << 'EOF'
#!/bin/bash
# Kodachi Welcome Command Wrapper
export KODACHI_SKIP_WELCOME=0

if [[ -f /etc/profile.d/kodachi-welcome.sh ]]; then
    source /etc/profile.d/kodachi-welcome.sh
else
    echo "Error: Kodachi welcome script not found at /etc/profile.d/kodachi-welcome.sh" >&2
    exit 1
fi
EOF
        chmod 755 /usr/local/bin/welcome
    fi

    # Create symlinks (force to handle existing)
    ln -sf /usr/local/bin/welcome /usr/local/bin/kodachi
    ln -sf /usr/local/bin/welcome /usr/local/bin/Kodachi

    print_success "Kodachi commands verified: kodachi, welcome, Kodachi"
    echo ""
}

# Call the installation function
if [[ "$EUID" -eq 0 ]]; then
    install_welcome_commands
else
    print_warning "Skipping welcome commands installation (requires sudo)"
    print_info "Run with sudo to install system-wide welcome commands"
fi

echo ""

# Final port check
print_step "Checking open ports after cleanup..."
echo ""
if command -v ss &>/dev/null; then
    PORT_COUNT=$(ss -tlnp 2>/dev/null | grep LISTEN 2>/dev/null | wc -l)
    PORT_COUNT=${PORT_COUNT:-0}
    if [[ "$PORT_COUNT" -eq 0 ]]; then
        echo -e "  ${GREEN}✓${NC} No listening ports found - system is secure!"
    else
        echo -e "  ${YELLOW}!${NC} Found $PORT_COUNT listening port(s):"
        echo ""
        echo -e "${CYAN}Currently listening ports:${NC}"
        ss -tlnp 2>/dev/null | grep LISTEN | awk '{print "  " $4 " - " $NF}' | sort -u | head -20
        echo ""
        if [[ "$PIHOLE_KEEP" == "true" ]]; then
            echo -e "  ${CYAN}Note:${NC} If Pi-hole is running, ports 80/443/5353 are expected"
        fi
        echo -e "  ${CYAN}Note:${NC} All other services should be stopped unless explicitly kept"
    fi
    echo ""
fi

# Display Pi-hole configuration if installed and running
if systemctl is-active --quiet pihole-FTL 2>/dev/null && command -v pihole &>/dev/null; then
    print_step "Checking Pi-hole..."
    echo -e "  ${GREEN}✓${NC} Pi-hole - installed"
    echo -e "  ${GREEN}✓${NC} Pi-hole FTL service - running"
    echo ""
    print_info "Pi-hole Configuration:"
    
    # Get Pi-hole IP address
    pihole_ip=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "unknown")
    if [[ "$pihole_ip" != "unknown" && -n "$pihole_ip" ]]; then
        echo -e "      ${CYAN}DNS Server (IPv4):${NC} $pihole_ip"
        echo -e "      ${CYAN}Web Interface:${NC} http://$pihole_ip/admin or http://pi.hole/admin"
    fi
    
    # Generate and set new password
    print_info "Generating new Pi-hole web interface password..."
    if command -v pihole &>/dev/null; then
        # Generate random password and set it with confirmation
        new_pihole_password=$(generate_pihole_password)
        if [[ -n "$new_pihole_password" ]]; then
            # Set password with double confirmation (Pi-hole requires confirmation)
            # Redirect all output to prevent background curl errors
            if printf "%s\n%s\n" "$new_pihole_password" "$new_pihole_password" | pihole setpassword &>/dev/null; then
                echo -e "      ${CYAN}Web Interface password:${NC} $new_pihole_password"
                echo -e "      ${YELLOW}Password has been set - please save this password!${NC}"
            else
                echo -e "      ${YELLOW}Password:${NC} Failed to set new password"
                echo -e "      ${YELLOW}To set manually:${NC} pihole setpassword"
            fi
        else
            echo -e "      ${YELLOW}Password:${NC} Could not generate password"
        fi
    else
        echo -e "      ${YELLOW}Password:${NC} Pi-hole command not available"
    fi
    
    echo -e "      ${CYAN}CLI Usage:${NC} pihole -h for help"
    echo -e "      ${CYAN}Documentation:${NC} https://docs.pi-hole.net/main/post-install/"
    echo ""

    # Clean up any curl processes spawned by pihole commands
    sleep 1
    pkill -9 -f "curl.*pi-hole|curl.*pihole|curl.*ftl" 2>/dev/null || true
fi

# Final check for Pi-hole installation
if ! systemctl is-active --quiet pihole-FTL 2>/dev/null && ! command -v pihole &>/dev/null; then
    echo ""
    print_warning "IMPORTANT: Pi-hole was not installed!"
    echo ""
    print_info "Pi-hole provides DNS-level ad blocking and network monitoring."
    print_info "You may have exited the installation window or it failed to install."
    echo ""
    print_highlight "To install Pi-hole manually, run:"
    echo -e "  ${CYAN}curl -sSL https://install.pi-hole.net | sudo bash${NC}"
    echo ""
    print_info "This will start the interactive Pi-hole installer where you can configure:"
    echo "  • Network interface selection"
    echo "  • Upstream DNS providers"
    echo "  • Block lists"
    echo "  • Web interface settings"
    echo ""
fi

# =========================================================================
# GLOBAL BINARY DEPLOYMENT (requires sudo)
# =========================================================================

deploy_kodachi_binaries_globally() {
    echo ""
    print_highlight "======= Deploying Kodachi Binaries Globally ======="
    echo ""

    local candidates=()
    if [[ -n "$SUDO_USER" ]]; then
        local sudo_home
        sudo_home=$(getent passwd "$SUDO_USER" | cut -d: -f6)
        if [[ -n "$sudo_home" ]]; then
            candidates+=("$sudo_home/dashboard/hooks" "$sudo_home/Desktop/dashboard/hooks")
        fi
    fi
    # Use $HOME as fallback (no hardcoded usernames)
    candidates+=("$HOME/dashboard/hooks" "$HOME/Desktop/dashboard/hooks")

    local install_path=""
    for path in "${candidates[@]}"; do
        if [[ -x "$path/global-launcher" ]]; then
            install_path="$path"
            break
        fi
    done

    if [[ -z "$install_path" ]]; then
        print_warning "Kodachi binaries not found; skipping global deployment"
        return 0
    fi

    if [[ -f "/tmp/live-build-chroot" ]]; then
        print_info "Live-build chroot detected - deferring deployment to first boot"
        print_info "Binaries staged at $install_path"
        return 0
    fi

    if [[ -d "/usr/lib/live" ]] || [[ -n "${LB_BASE:-}" ]]; then
        print_info "Live-build environment detected - skipping global deployment"
        print_info "Binaries staged at $install_path"
        return 0
    fi

    local root_stat=$(stat -c %d:%i / 2>/dev/null)
    local proc_stat=$(stat -c %d:%i /proc/1/root/. 2>/dev/null)
    if [[ -n "$root_stat" && -n "$proc_stat" && "$root_stat" != "$proc_stat" ]]; then
        print_info "Chroot environment detected - skipping global deployment"
        print_info "Binaries staged at $install_path"
        return 0
    fi

    local gl_binary="$install_path/global-launcher"

    print_step "Deploying binaries from $install_path to /usr/local/bin..."

    local deploy_output
    if deploy_output=$("$gl_binary" deploy --force --json 2>&1); then
        print_success "Successfully deployed binaries globally"

        local symlink_count
        symlink_count=$(echo "$deploy_output" | grep -o '"symlinks_created":[0-9]*' | grep -o '[0-9]*' || echo "0")
        if [[ "$symlink_count" -gt 0 ]]; then
            print_info "Created $symlink_count symlink(s) in /usr/local/bin"
        fi

        print_step "Verifying global deployment..."
        if "$gl_binary" verify --json &>/dev/null; then
            print_success "Global deployment verified successfully"
        else
            print_warning "Verification reported warnings"
            print_info "Run '$gl_binary verify --detailed' for more information"
        fi
    else
        print_error "Global deployment failed"
        echo "$deploy_output" | head -5
        print_warning "Binaries remain available in $install_path"
        print_info "You can retry later with: $gl_binary deploy --force"
    fi
}

deploy_kodachi_binaries_globally
install_kodachi_conky_for_user

# ============================================================================
# FIX /usr/sbin PATH FOR NON-ROOT USERS
# ============================================================================
# Debian Trixie removed /usr/sbin from non-root user PATH by default.
# Tools like iftop, nethogs, nft, arptables are installed to /usr/sbin
# and become invisible to 'which' and direct invocation without this fix.

ensure_sbin_in_path() {
    # --- Method 1: profile.d for login shells (only create if missing) ---
    local profile_file="/etc/profile.d/kodachi-path.sh"
    if [[ -f "$profile_file" ]] || [[ -f "/etc/profile.d/10-kodachi-path.sh" ]]; then
        print_info "/usr/sbin PATH fix already installed (profile.d)"
    else
        print_step "Ensuring /usr/sbin is in user PATH (Debian Trixie fix)..."
        cat > "$profile_file" << 'SBIN_PATH_EOF'
#!/bin/sh
# Kodachi OS - Add admin directories to PATH
# Required for: iftop, nethogs, nft, arptables, ebtables, and other sbin tools
# Debian Trixie removed /usr/sbin from non-root PATH by default
case ":${PATH}:" in
    *:/usr/sbin:*) ;;
    *) export PATH="/usr/sbin:/sbin:${PATH}" ;;
esac
SBIN_PATH_EOF
        chmod 644 "$profile_file"
        print_success "/usr/sbin added to PATH for all users (via $profile_file)"
    fi

    # --- Method 2: Symlinks in /usr/local/bin for sbin tools (always runs, idempotent) ---
    local sbin_tools="iftop nethogs nft arptables ebtables ethtool"
    local symlink_count=0
    for tool in $sbin_tools; do
        if command -v "$tool" &>/dev/null; then
            continue
        fi
        local tool_path=""
        if [[ -x "/usr/sbin/$tool" ]]; then
            tool_path="/usr/sbin/$tool"
        elif [[ -x "/sbin/$tool" ]]; then
            tool_path="/sbin/$tool"
        fi
        if [[ -n "$tool_path" ]]; then
            ln -sf "$tool_path" "/usr/local/bin/$tool" 2>/dev/null && symlink_count=$((symlink_count + 1))
        fi
    done
    if [[ $symlink_count -gt 0 ]]; then
        print_success "Created $symlink_count symlink(s) in /usr/local/bin for sbin tools"
    fi

    # --- Method 3: /etc/bash.bashrc for non-login interactive shells (guarded by marker) ---
    local bashrc_file="/etc/bash.bashrc"
    if [[ -f "$bashrc_file" ]] && ! grep -q "kodachi-sbin-path" "$bashrc_file" 2>/dev/null; then
        cat >> "$bashrc_file" << 'BASHRC_PATH_EOF'

# kodachi-sbin-path: Add /usr/sbin to PATH for non-login shells (Debian Trixie fix)
case ":${PATH}:" in
    *:/usr/sbin:*) ;;
    *) export PATH="/usr/sbin:/sbin:${PATH}" ;;
esac
BASHRC_PATH_EOF
        print_success "Added /usr/sbin PATH fix to $bashrc_file"
    fi

    print_info "Takes effect on next login/terminal. For current session: export PATH=\"/usr/sbin:\$PATH\""
}

ensure_sbin_in_path

# ============================================================================
# RE-RUN SUDOERS SETUP (post-install pass)
# ============================================================================
# The first call at script start ran BEFORE apt installed packages, so TUI tools
# (iftop, nethogs) were missing from the system and got skipped by command -v.
# Now that all packages and sbin symlinks are in place, re-run to pick them up.
print_step "Updating sudoers with newly installed tools..."
configure_kodachi_sudoers

# ============================================================================
# CLEANUP TEMPORARY FILES
# ============================================================================

# Clean up any remaining temporary files from GitHub downloads
cleanup_github_temp_files() {
    print_step "Cleaning up temporary files..."

    local cleaned_files=0
    local temp_files=(
        "/tmp/hysteria"
        "/tmp/v2ray-install.sh"
        "/tmp/dnscrypt-proxy-install"
        "/tmp/v2ray-plugin-install"
        "/tmp/qrencode-install-"*
        "/tmp/kloak-install-"*
        "/tmp/mieru_"*.deb
    )

    for file_pattern in "${temp_files[@]}"; do
        if ls ${file_pattern} 2>/dev/null 1>&2; then
            rm -rf ${file_pattern} 2>/dev/null && cleaned_files=$((cleaned_files + 1))
        fi
    done

    # SECURITY FIX: Clean up only Kodachi-specific temp files (not generic wildcards)
    # Use specific patterns to avoid deleting unrelated user files
    local kodachi_patterns=(
        "kodachi-*"
        "mieru_*"
        "dnscrypt-proxy-*"
        "xray-*"
        "v2ray-*"
        "hysteria-*"
        "pihole-*"
    )

    for pattern in "${kodachi_patterns[@]}"; do
        find /tmp -maxdepth 1 -name "$pattern" 2>/dev/null | while read temp_file; do
            if [[ -f "$temp_file" ]] || [[ -d "$temp_file" ]]; then
                rm -rf "$temp_file" 2>/dev/null && cleaned_files=$((cleaned_files + 1))
            fi
        done
    done

    if [[ $cleaned_files -gt 0 ]]; then
        print_success "Cleaned up $cleaned_files temporary files"
    else
        print_info "No temporary files to clean up"
    fi
}

echo ""
cleanup_github_temp_files

# ============================================================================
# BINARY DETECTION AND EMOJI SUPPORT
# ============================================================================

# Check if binaries are installed - verify at least 3 core binaries exist
echo ""
BINARY_COUNT=0
# Build locations list: real user's home (via SUDO_USER), $HOME fallback, and /usr/local/bin
INSTALL_LOCATIONS=()
if [[ -n "$SUDO_USER" ]]; then
    _real_home=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    if [[ -n "$_real_home" ]]; then
        INSTALL_LOCATIONS+=("$_real_home/dashboard/hooks" "$_real_home/Desktop/dashboard/hooks")
    fi
fi
INSTALL_LOCATIONS+=("$HOME/dashboard/hooks" "$HOME/Desktop/dashboard/hooks" "/usr/local/bin")
CORE_BINARIES=("ip-fetch" "health-control" "tor-switch")
FOUND_LOCATION=""

for location in "${INSTALL_LOCATIONS[@]}"; do
    if [ -d "$location" ]; then
        local_count=0
        for binary in "${CORE_BINARIES[@]}"; do
            if [ -f "$location/$binary" ]; then
                local_count=$((local_count + 1))
            fi
        done
        if [ $local_count -gt 0 ]; then
            BINARY_COUNT=$local_count
            FOUND_LOCATION="$location"
            break  # Found install location, stop checking
        fi
    fi
done

if [ $BINARY_COUNT -ge 3 ]; then
    print_success "Kodachi binaries are installed ($BINARY_COUNT/3 core binaries found)"
    echo ""
    print_info "Installation location: $FOUND_LOCATION"
    echo ""
    if ! command -v ip-fetch &>/dev/null 2>&1; then
        print_info "Binaries installed but not in PATH yet. To add to PATH:"
        echo "  source ~/.bashrc"
        echo ""
        print_info "Or logout and login again for PATH to update automatically"
    else
        print_info "Binaries are in PATH and ready to use!"
    fi
elif [ $BINARY_COUNT -gt 0 ]; then
    print_warning "Partial installation detected ($BINARY_COUNT/3 core binaries found)"
    echo ""
    print_info "Please reinstall binaries:"
    echo "  curl -sSL https://www.kodachi.cloud/apps/os/install/kodachi-binary-install.sh | bash"
else
    print_warning "Kodachi binaries not detected"
    echo ""
    print_info "To install binaries, run:"
    echo "  curl -sSL https://www.kodachi.cloud/apps/os/install/kodachi-binary-install.sh | bash"
fi

echo ""
print_highlight "Emoji Flag Support in ip-fetch:"
print_success "Kitty terminal is already installed!"
echo ""
print_info "To launch Kitty and see emoji flags:"
echo "  1. From menu: Applications → System → Kitty"
echo "  2. Or in terminal: type 'kitty' to launch it"
echo "  3. In Kitty, run: ip-fetch (from hooks folder or if in PATH)"
echo ""
print_info "Alternatively, in this session just type: kitty"
echo "  Then run: cd ~/dashboard/hooks && ./ip-fetch"
echo ""

# ============================================================================
# FINAL MESSAGE
# ============================================================================

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Dependency Installation Complete!          ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
print_success "Installation finished successfully!"
print_success "Kodachi Dashboard and all binaries can now run with sudo without password"
if ! detect_gui_environment; then
    print_info "Conky: skipped (no GUI detected)"
fi
echo ""
# Force success exit code - ignore bash -n false positives
exit 0
