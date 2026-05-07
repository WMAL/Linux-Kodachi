#!/bin/bash

# Kodachi OS Debug Collector
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
# Last updated: 2026-04-16
#
# Description:
# Collects comprehensive system diagnostics for remote troubleshooting
# of Kodachi OS installations. Gathers boot logs, hardware info, network
# configuration, Kodachi service status, LUKS/nuke state, and more.
# All data is packaged into a zip file on the user's Desktop.
#
# Privacy:
# This script does NOT collect any personal data, browsing history,
# IP addresses, WiFi passwords, home folder contents, or any data
# that could compromise user privacy. Only system/service diagnostics
# are collected. WiFi credentials are automatically redacted from
# NetworkManager configs.
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
#   # Run with sudo (required for system log access)
#   curl -sSL https://www.kodachi.cloud/apps/os/install/kodachi-debug-collector.sh | sudo bash
#
#   # Or run locally
#   sudo bash kodachi-debug-collector.sh
#
#   # Skip interactive menu (collect everything)
#   sudo bash kodachi-debug-collector.sh --all
#
# Output:
#   ~/Desktop/kodachi-debug-HOSTNAME-YYYYMMDD-HHMMSS.zip
#
# ======================================================

set -Eo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ---- CLI argument parsing ----
SKIP_MENU=0
for arg in "$@"; do
    case "$arg" in
        --all|--no-interactive) SKIP_MENU=1 ;;
    esac
done

# ---- Category selection state ----
CAT_ENABLED=(1 1 1 1 1 1 1 1 1 1 1 1 1)
CAT_LABEL=(
    "Kodachi Meta"
    "Boot & System Logs"
    "Hardware Info"
    "Network Config"
    "Tor"
    "VPN"
    "Kodachi Services"
    "Installation"
    "Display & Desktop"
    "Performance"
    "Security"
    "Live System"
    "System Config"
)
CAT_DESC=(
    "Version, live/installed, LUKS, nuke status"
    "dmesg, journalctl, failed services, syslog"
    "CPU cores, RAM, SSD/HDD, GPU, disk space"
    "Routes, firewall rules, DNS, ports"
    "Tor status, logs, config (redacted)"
    "OpenVPN/WireGuard status and logs"
    "Binary versions, service logs and results"
    "Installer logs, EFI boot, initramfs, packages"
    "Xorg, display manager, screen resolution"
    "Processes, CPU/memory/IO load"
    "AppArmor status, login history"
    "Mount points, persistence, fstab"
    "Locale, timezone, GRUB config"
)

# Progress counter (set dynamically after menu)
STEP=0
TOTAL_STEPS=16

# Detect real user (even when run via sudo)
detect_real_user() {
    if [[ -n "${SUDO_USER:-}" ]]; then
        echo "$SUDO_USER"
    elif [[ -n "${USER:-}" ]] && [[ "$USER" != "root" ]]; then
        echo "$USER"
    else
        # Fallback: detect from console login
        who | awk 'NR==1{print $1}' || echo "kodachi"
    fi
}

REAL_USER=$(detect_real_user)
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
DESKTOP_DIR="${REAL_HOME}/Desktop"

# Ensure Desktop directory exists
mkdir -p "$DESKTOP_DIR"

# Create temp collection directory
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
HOSTNAME=$(hostname)
TEMP_DIR=$(mktemp -d -t kodachi-debug-XXXXXX)
COLLECTION_NAME="kodachi-debug-${HOSTNAME}-${TIMESTAMP}"
COLLECTION_DIR="${TEMP_DIR}/${COLLECTION_NAME}"
ZIP_FILE="${DESKTOP_DIR}/${COLLECTION_NAME}.zip"

mkdir -p "$COLLECTION_DIR"

# Progress indicator
progress() {
    STEP=$((STEP + 1))
    echo -e "${BLUE}[${STEP}/${TOTAL_STEPS}]${NC} $1"
}

# Safe command execution with error handling
safe_exec() {
    local output_file="$1"
    shift
    local cmd="$*"
    local output rc

    output=$(eval "$cmd" 2>&1)
    rc=$?

    if [[ $rc -ne 0 ]]; then
        echo "[EXIT CODE: $rc] Command failed: $cmd" >> "$output_file"
        [[ -n "$output" ]] && echo "$output" >> "$output_file"
    elif [[ -z "$output" ]]; then
        echo "[EXIT CODE: 0] Command produced no output: $cmd" >> "$output_file"
    else
        echo "$output" >> "$output_file"
    fi
}

# Safe file copy with size check
safe_copy() {
    local src="$1"
    local dest="$2"
    local max_size=$((50 * 1024 * 1024)) # 50MB

    if [[ ! -f "$src" ]]; then
        echo "File not found: $src" > "${dest}/$(basename "$src").missing"
        return
    fi

    local file_size
    file_size=$(stat -c%s "$src" 2>/dev/null || echo 0)

    if [[ $file_size -gt $max_size ]]; then
        # Truncate large files
        tail -c 50M "$src" > "${dest}/$(basename "$src").truncated" 2>/dev/null || true
        echo "Original file size: $file_size bytes (truncated to last 50MB)" >> "${dest}/$(basename "$src").truncated"
    else
        cp "$src" "$dest/" 2>/dev/null || echo "Failed to copy: $src" > "${dest}/$(basename "$src").error"
    fi
}

# Run a command as the real (non-root) user with full graphical-session env so
# that systemctl --user, journalctl --user, xfconf-query, xrandr, dconf, etc.
# all reach the right session bus and runtime directory. We do not assume the
# user is root — if collector is run as the user already, fall back to plain
# eval. audit 2026-05-07 (login-stall investigation): without this helper,
# user-systemd state and ~/.xsession-errors were never captured, so xfce4
# session hangs were undiagnosable.
REAL_UID=$(id -u "${REAL_USER}" 2>/dev/null || echo "")
safe_exec_user() {
    local output_file="$1"
    shift
    local cmd="$*"
    local output rc

    if [[ -z "$REAL_UID" ]]; then
        echo "[SKIP] real user UID unknown for: $cmd" >> "$output_file"
        return
    fi

    if [[ "$(id -u)" == "0" ]] && [[ -n "${REAL_USER:-}" ]] && [[ "$REAL_USER" != "root" ]]; then
        # Running as root — drop to real user with their session env restored.
        output=$(sudo -u "$REAL_USER" \
            XDG_RUNTIME_DIR="/run/user/${REAL_UID}" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${REAL_UID}/bus" \
            DISPLAY="${DISPLAY:-:0}" \
            HOME="$REAL_HOME" \
            bash -lc "$cmd" 2>&1)
        rc=$?
    else
        output=$(eval "$cmd" 2>&1)
        rc=$?
    fi

    if [[ $rc -ne 0 ]]; then
        echo "[EXIT CODE: $rc] Command failed: $cmd" >> "$output_file"
        [[ -n "$output" ]] && echo "$output" >> "$output_file"
    elif [[ -z "$output" ]]; then
        echo "[EXIT CODE: 0] Command produced no output: $cmd" >> "$output_file"
    else
        echo "$output" >> "$output_file"
    fi
}

# Copy a file owned by REAL_USER (e.g., ~/.xsession-errors). Falls back to
# plain copy if collector is already running as that user.
safe_copy_user() {
    local src="$1"
    local dest="$2"

    if [[ "$src" != /* ]]; then
        # Resolve relative-to-home paths.
        src="${REAL_HOME}/${src#~/}"
    fi

    if [[ ! -e "$src" ]]; then
        echo "File not found: $src" > "${dest}/$(basename "$src").missing"
        return
    fi

    if [[ "$(id -u)" == "0" ]]; then
        # Use sudo cat to preserve permissions / handle non-root home dirs.
        sudo -u "$REAL_USER" cat "$src" > "${dest}/$(basename "$src")" 2>/dev/null \
            || echo "Failed to copy (perm denied): $src" > "${dest}/$(basename "$src").error"
    else
        cp "$src" "$dest/" 2>/dev/null \
            || echo "Failed to copy: $src" > "${dest}/$(basename "$src").error"
    fi
}

# ---- Interactive category selection menu ----

show_menu() {
    clear 2>/dev/null || true
    echo -e "${GREEN}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║         KODACHI OS DEBUG COLLECTOR v1.4                  ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    echo "Select what to collect (all selected by default):"
    echo ""
    for i in "${!CAT_LABEL[@]}"; do
        local num=$((i + 1))
        local mark="X"
        local color="${GREEN}"
        if [[ "${CAT_ENABLED[$i]}" == "0" ]]; then
            mark=" "
            color="${RED}"
        fi
        printf "  ${color}[%s]${NC} %2d. ${BOLD}%-22s${NC} %s\n" "$mark" "$num" "${CAT_LABEL[$i]}" "${CAT_DESC[$i]}"
    done
    echo ""
    echo -e "  ${YELLOW}No IPs, passwords, browsing data, or personal files are collected.${NC}"
    echo ""
    echo -e "  Toggle: type number (${CYAN}1-13${NC}) | ${CYAN}a${NC}=all | ${CYAN}n${NC}=none | ${CYAN}ENTER${NC}=start"
}

interactive_select() {
    local input
    while true; do
        show_menu
        printf "> "
        read -r input < /dev/tty || break

        # Empty input = proceed with current selection
        if [[ -z "$input" ]]; then
            break
        fi

        case "$input" in
            a|A)
                for i in "${!CAT_ENABLED[@]}"; do CAT_ENABLED[$i]=1; done
                ;;
            n|N)
                for i in "${!CAT_ENABLED[@]}"; do CAT_ENABLED[$i]=0; done
                ;;
            [1-9]|1[0-3])
                local idx=$((input - 1))
                if [[ $idx -ge 0 ]] && [[ $idx -lt ${#CAT_ENABLED[@]} ]]; then
                    if [[ "${CAT_ENABLED[$idx]}" == "1" ]]; then
                        CAT_ENABLED[$idx]=0
                    else
                        CAT_ENABLED[$idx]=1
                    fi
                fi
                ;;
            *)
                # Ignore invalid input
                ;;
        esac
    done
}

# Banner (shown when menu is skipped)
show_banner() {
    echo -e "${GREEN}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║         KODACHI OS DEBUG COLLECTOR v1.4                  ║"
    echo "║    Comprehensive System Diagnostics Tool                 ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo "v1.4 (audit 2026-05-07): user-systemd, ~/.xsession-errors, xfconf,"
    echo "autostart, Calamares, kodachi-* logs, prev-boot journals, ordering"
    echo "cycles, cgroup hierarchy."
    echo ""
    echo "Collecting: version, live/installed, LUKS, nuke, Tor, VPN,"
    echo "  boot logs, hardware, network, Kodachi services, and more."
    echo ""
    echo -e "${YELLOW}Privacy:${NC} No IP addresses, browsing data, passwords, or personal"
    echo "  files are collected. WiFi credentials and MACs are redacted."
    echo ""
    echo "Output will be saved to: ${ZIP_FILE}"
    echo ""
}

# ---- Run interactive menu or show banner ----
if [[ "$SKIP_MENU" == "0" ]] && [[ -e "/dev/tty" ]]; then
    interactive_select
    # Print a compact summary of what will be collected
    echo ""
    ENABLED_LIST=""
    for i in "${!CAT_ENABLED[@]}"; do
        if [[ "${CAT_ENABLED[$i]}" == "1" ]]; then
            [[ -n "$ENABLED_LIST" ]] && ENABLED_LIST+=", "
            ENABLED_LIST+="${CAT_LABEL[$i]}"
        fi
    done
    if [[ -z "$ENABLED_LIST" ]]; then
        echo -e "${RED}No categories selected. Nothing to collect.${NC}"
        rm -rf "$TEMP_DIR"
        exit 0
    fi
    echo -e "${GREEN}Collecting:${NC} ${ENABLED_LIST}"
    echo -e "Output: ${ZIP_FILE}"
    echo ""
else
    show_banner
fi

# ---- Compute dynamic step count ----
ENABLED_COUNT=0
for e in "${CAT_ENABLED[@]}"; do
    [[ "$e" == "1" ]] && ENABLED_COUNT=$((ENABLED_COUNT + 1))
done
TOTAL_STEPS=$((ENABLED_COUNT + 3)) # +3 for metadata, zip, cleanup

# ============================================================================
# CATEGORY 0: KODACHI META SUMMARY (version, live/installed, LUKS, nuke, etc.)
# ============================================================================
if [[ "${CAT_ENABLED[0]}" == "1" ]]; then
progress "Collecting Kodachi meta information..."

mkdir -p "$COLLECTION_DIR/00-kodachi-meta"

(
set +e
echo "=============================================="
echo "   KODACHI OS - SYSTEM META SUMMARY"
echo "=============================================="
echo ""
echo "Collection Date: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "Hostname:        $(hostname 2>/dev/null || echo 'unknown')"
echo "Real User:       ${REAL_USER}"
echo "Kernel:          $(uname -r 2>/dev/null || echo 'unknown')"
echo ""

# ------- Kodachi Version -------
echo "----------------------------------------------"
echo "  KODACHI VERSION"
echo "----------------------------------------------"

# Try multiple version sources
KODACHI_VERSION="unknown"

if [[ -f "/etc/kodachi-version" ]]; then
    KODACHI_VERSION=$(cat /etc/kodachi-version 2>/dev/null || echo "unreadable")
    echo "Version (kodachi-version file): $KODACHI_VERSION"
fi

if [[ -f "/etc/kodachi_version" ]]; then
    echo "Version (kodachi_version file): $(cat /etc/kodachi_version 2>/dev/null)"
fi

# Check build-meta.json (primary Kodachi version source)
for build_meta in /opt/*/dashboard/hooks/config/build-meta.json "${REAL_HOME}"/*/dashboard/hooks/config/build-meta.json /opt/kodachi*/dashboard/hooks/config/build-meta.json; do
    if [[ -f "$build_meta" ]]; then
        echo "build-meta.json ($build_meta):"
        cat "$build_meta" 2>/dev/null | sed 's/^/  /'
        # Extract version and build info from build-meta
        if [[ "$KODACHI_VERSION" == "unknown" ]]; then
            BM_VER=$(grep -oP '"version"\s*:\s*"\K[^"]+' "$build_meta" 2>/dev/null | head -1)
            if [[ -n "$BM_VER" ]]; then
                KODACHI_VERSION="$BM_VER"
            fi
        fi
        NIGHTLY_VERSION=$(grep -oP '"nightly_version"\s*:\s*"\K[^"]+' "$build_meta" 2>/dev/null | head -1)
        BUILD_NUMBER=$(grep -oP '"build_number"\s*:\s*\K[0-9]+' "$build_meta" 2>/dev/null | head -1)
        PACK_DATE=$(grep -oP '"pack_date"\s*:\s*"\K[^"]+' "$build_meta" 2>/dev/null | head -1)
    fi
done

# Check os-release for kodachi info
if grep -qi kodachi /etc/os-release 2>/dev/null; then
    echo "OS Release:"
    grep -i -E "(PRETTY_NAME|VERSION|NAME)" /etc/os-release 2>/dev/null | sed 's/^/  /'
    # Extract version from os-release if not already found
    if [[ "$KODACHI_VERSION" == "unknown" ]]; then
        OS_VER=$(grep "^VERSION_ID=" /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
        if [[ -n "$OS_VER" ]]; then
            KODACHI_VERSION="$OS_VER"
        fi
    fi
fi

# Check lsb_release
if command -v lsb_release &>/dev/null; then
    echo "LSB Release: $(lsb_release -d 2>/dev/null | cut -f2)"
fi

# Check main-info.json if present
for info_json in /opt/*/installers/main-info.json /opt/kodachi*/main-info.json "${REAL_HOME}"/*/installers/main-info.json; do
    if [[ -f "$info_json" ]]; then
        echo "main-info.json ($info_json):"
        cat "$info_json" 2>/dev/null | sed 's/^/  /'
    fi
done

# Check installed kodachi packages
echo ""
echo "Installed Kodachi packages:"
dpkg -l 2>/dev/null | grep -i kodachi | sed 's/^/  /' || echo "  (none found via dpkg)"

echo ""

# ------- Live vs Installed -------
echo "----------------------------------------------"
echo "  SYSTEM TYPE: LIVE vs INSTALLED"
echo "----------------------------------------------"

SYSTEM_TYPE="UNKNOWN"

# Method 1: /run/live directory
if [[ -d "/run/live" ]]; then
    SYSTEM_TYPE="LIVE"
    echo "Detection: /run/live exists -> LIVE SYSTEM"
    echo "Live medium contents:"
    ls -la /run/live/ 2>/dev/null | sed 's/^/  /'
    if [[ -d "/run/live/medium" ]]; then
        echo "Live medium mount:"
        ls -la /run/live/medium/ 2>/dev/null | sed 's/^/  /'
    fi
    if [[ -d "/run/live/persistence" ]]; then
        echo "Persistence: ENABLED"
        ls -la /run/live/persistence/ 2>/dev/null | sed 's/^/  /'
    else
        echo "Persistence: NOT DETECTED"
    fi
fi

# Method 2: Kernel cmdline
if grep -q "boot=live" /proc/cmdline 2>/dev/null; then
    SYSTEM_TYPE="LIVE"
    echo "Detection: boot=live in kernel cmdline -> LIVE SYSTEM"
    echo "Boot params: $(cat /proc/cmdline 2>/dev/null)"
fi

# Method 3: Root filesystem type
ROOT_FS=$(findmnt -n -o FSTYPE / 2>/dev/null || echo "unknown")
ROOT_SOURCE=$(findmnt -n -o SOURCE / 2>/dev/null || echo "unknown")
echo "Root filesystem type: $ROOT_FS"
echo "Root source: $ROOT_SOURCE"

if [[ "$ROOT_FS" == "overlay" ]] || [[ "$ROOT_FS" == "tmpfs" ]] || [[ "$ROOT_FS" == "aufs" ]]; then
    SYSTEM_TYPE="LIVE"
    echo "Detection: Root is $ROOT_FS -> LIVE SYSTEM"
elif [[ "$ROOT_FS" == "ext4" ]] || [[ "$ROOT_FS" == "btrfs" ]] || [[ "$ROOT_FS" == "xfs" ]]; then
    if [[ "$SYSTEM_TYPE" == "UNKNOWN" ]]; then
        SYSTEM_TYPE="INSTALLED"
        echo "Detection: Root is $ROOT_FS on real partition -> INSTALLED SYSTEM"
    fi
fi

# Method 4: Check if /cdrom or /media/cdrom exists
if [[ -d "/cdrom" ]] || [[ -d "/lib/live" ]]; then
    echo "Live system libraries/media detected"
    [[ "$SYSTEM_TYPE" == "UNKNOWN" ]] && SYSTEM_TYPE="LIVE"
fi

echo ""
echo ">>> SYSTEM TYPE: $SYSTEM_TYPE <<<"
echo ""

# ------- LUKS Encryption -------
echo "----------------------------------------------"
echo "  LUKS ENCRYPTION STATUS"
echo "----------------------------------------------"

LUKS_ACTIVE="NO"

# Check for dm-crypt devices
echo "DM-Crypt mappings:"
if command -v dmsetup &>/dev/null; then
    DMSETUP_OUT=$(dmsetup ls 2>/dev/null)
    if [[ -n "$DMSETUP_OUT" ]] && [[ "$DMSETUP_OUT" != "No devices found" ]]; then
        echo "$DMSETUP_OUT" | sed 's/^/  /'
    else
        echo "  (no dm-crypt devices)"
    fi
fi

# Check lsblk for crypto_LUKS
echo ""
echo "LUKS partitions (lsblk):"
LUKS_PARTS=$(lsblk -f 2>/dev/null | grep -i "crypto_LUKS" || true)
if [[ -n "$LUKS_PARTS" ]]; then
    LUKS_ACTIVE="YES"
    echo "$LUKS_PARTS" | sed 's/^/  /'
else
    echo "  (no LUKS partitions detected)"
fi

# Check /etc/crypttab
echo ""
echo "Crypttab:"
if [[ -f "/etc/crypttab" ]]; then
    cat /etc/crypttab 2>/dev/null | grep -v '^#' | grep -v '^$' | sed 's/^/  /'
    [[ -n "$(cat /etc/crypttab 2>/dev/null | grep -v '^#' | grep -v '^$')" ]] && LUKS_ACTIVE="YES"
else
    echo "  /etc/crypttab not found"
fi

# Check blkid for LUKS
echo ""
echo "LUKS UUIDs (blkid):"
BLKID_LUKS=$(blkid 2>/dev/null | grep -i "LUKS" || true)
if [[ -n "$BLKID_LUKS" ]]; then
    LUKS_ACTIVE="YES"
    echo "$BLKID_LUKS" | sed 's/^/  /'
else
    echo "  (no LUKS entries in blkid)"
fi

# Try cryptsetup status on known mappings
echo ""
echo "Active LUKS volumes:"
if command -v cryptsetup &>/dev/null; then
    for dm_dev in /dev/mapper/*; do
        dm_name=$(basename "$dm_dev" 2>/dev/null)
        [[ "$dm_name" == "control" ]] && continue
        status=$(cryptsetup status "$dm_name" 2>/dev/null || true)
        if echo "$status" | grep -qi "active"; then
            LUKS_ACTIVE="YES"
            echo "  $dm_name: ACTIVE"
            echo "$status" | sed 's/^/    /'
        fi
    done
fi

# Check if root is on LUKS
echo ""
if echo "$ROOT_SOURCE" | grep -q "/dev/mapper"; then
    echo "Root partition is on dm-crypt: $ROOT_SOURCE"
    LUKS_ACTIVE="YES"
fi

echo ""
echo ">>> LUKS ENCRYPTION: $LUKS_ACTIVE <<<"
echo ""

# ------- Nuke Password -------
echo "----------------------------------------------"
echo "  NUKE PASSWORD STATUS"
echo "----------------------------------------------"

NUKE_STATUS="NOT DETECTED"

# Check if cryptsetup-nuke-password package is installed
if dpkg -l 2>/dev/null | grep -qi "cryptsetup-nuke"; then
    NUKE_STATUS="PACKAGE INSTALLED"
    echo "cryptsetup-nuke-password package: INSTALLED"
    dpkg -l 2>/dev/null | grep -i "nuke" | sed 's/^/  /'
else
    echo "cryptsetup-nuke-password package: NOT INSTALLED"
fi

# Check for nuke initramfs hook
if [[ -f "/usr/share/initramfs-tools/hooks/cryptsetup-nuke" ]] || [[ -f "/etc/initramfs-tools/hooks/cryptsetup-nuke" ]]; then
    NUKE_STATUS="HOOK PRESENT"
    echo "Nuke initramfs hook: FOUND"
fi

# Check LUKS key slots for nuke slot (slot 1 is typically nuke)
echo ""
echo "LUKS key slot analysis:"
if command -v cryptsetup &>/dev/null && [[ "$LUKS_ACTIVE" == "YES" ]]; then
    # Find LUKS devices
    for luks_dev in $(blkid 2>/dev/null | grep -i "LUKS" | cut -d: -f1); do
        echo "  Device: $luks_dev"
        DUMP=$(cryptsetup luksDump "$luks_dev" 2>/dev/null || true)
        if [[ -n "$DUMP" ]]; then
            # Count active key slots
            ACTIVE_SLOTS=$(echo "$DUMP" | grep -c "ENABLED" 2>/dev/null || echo "0")
            echo "    Active key slots: $ACTIVE_SLOTS"
            echo "$DUMP" | grep -E "(Key Slot|ENABLED|DISABLED)" | head -16 | sed 's/^/    /'
            if [[ "$ACTIVE_SLOTS" -ge 2 ]]; then
                NUKE_STATUS="LIKELY ENABLED (multiple key slots active)"
                echo "    NOTE: Multiple key slots active - nuke password is likely configured"
            fi
        fi
    done
else
    echo "  (no LUKS devices to check)"
fi

echo ""
echo ">>> NUKE PASSWORD: $NUKE_STATUS <<<"
echo ""

# ------- Additional Kodachi Meta -------
echo "----------------------------------------------"
echo "  ADDITIONAL KODACHI METADATA"
echo "----------------------------------------------"

# Swap encryption
echo "Swap status:"
swapon --show 2>/dev/null | sed 's/^/  /' || echo "  (no swap active)"
if swapon --show 2>/dev/null | grep -q "/dev/mapper"; then
    echo "  Swap is ENCRYPTED (on dm-crypt)"
elif swapon --show 2>/dev/null | grep -q "zram"; then
    echo "  Swap is ZRAM (compressed RAM, no disk)"
else
    SWAP_DEV=$(swapon --show 2>/dev/null | tail -n+2 | awk '{print $1}')
    if [[ -z "$SWAP_DEV" ]]; then
        echo "  No swap active"
    else
        echo "  Swap is on: $SWAP_DEV (check if encrypted above)"
    fi
fi
echo ""

# MAC address randomization (MACs masked for privacy - only shows randomization status)
echo "MAC Randomization Status:"
for iface in $(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -v lo); do
    MAC=$(ip link show "$iface" 2>/dev/null | grep ether | awk '{print $2}')
    PERM_MAC=$(ethtool -P "$iface" 2>/dev/null | awk '{print $NF}' || echo "unavailable")
    if [[ -n "$MAC" ]]; then
        # Mask MACs: show only vendor prefix (first 3 octets) for debugging driver issues
        MASKED_MAC=$(echo "$MAC" | cut -d: -f1-3)":XX:XX:XX"
        if [[ "$MAC" != "$PERM_MAC" ]] && [[ "$PERM_MAC" != "unavailable" ]] && [[ "$PERM_MAC" != "00:00:00:00:00:00" ]]; then
            echo "  $iface: vendor=$MASKED_MAC -> MAC RANDOMIZATION ACTIVE"
        else
            echo "  $iface: vendor=$MASKED_MAC -> USING HARDWARE MAC"
        fi
    fi
done
echo ""

# Tor mode
echo "Tor Status:"
if systemctl is-active tor 2>/dev/null | grep -q "active"; then
    echo "  Tor service: RUNNING"
    # Check if system is fully torrified
    TOR_SOCKS=$(ss -tulnp 2>/dev/null | grep ":9050 " || true)
    if [[ -n "$TOR_SOCKS" ]]; then
        echo "  SOCKS proxy (9050): LISTENING"
    fi
    TOR_TRANS=$(ss -tulnp 2>/dev/null | grep ":9040 " || true)
    if [[ -n "$TOR_TRANS" ]]; then
        echo "  TransPort (9040): LISTENING (transparent proxy active)"
    fi
    TOR_DNS=$(ss -tulnp 2>/dev/null | grep ":5353 " || true)
    if [[ -n "$TOR_DNS" ]]; then
        echo "  DNS Port (5353): LISTENING"
    fi
else
    echo "  Tor service: NOT RUNNING"
fi
echo ""

# VPN
echo "VPN Status:"
VPN_IFACES=$(ip -o link show 2>/dev/null | grep -E "(tun|tap|wg)" | awk -F': ' '{print $2}')
if [[ -n "$VPN_IFACES" ]]; then
    echo "  VPN interfaces found: $VPN_IFACES"
    for viface in $VPN_IFACES; do
        ip addr show "$viface" 2>/dev/null | grep inet | sed 's/^/    /'
    done
else
    echo "  No VPN interfaces detected"
fi
OPENVPN_PROCS=$(pgrep -a openvpn 2>/dev/null || true)
if [[ -n "$OPENVPN_PROCS" ]]; then
    echo "  OpenVPN processes: $OPENVPN_PROCS"
fi
WG_STATUS=$(wg show 2>/dev/null || true)
if [[ -n "$WG_STATUS" ]]; then
    echo "  WireGuard:"
    echo "$WG_STATUS" | sed 's/^/    /'
fi
echo ""

# DNSCrypt
echo "DNSCrypt Status:"
if systemctl is-active dnscrypt-proxy 2>/dev/null | grep -q "active"; then
    echo "  dnscrypt-proxy: RUNNING"
elif pgrep -x dnscrypt-proxy &>/dev/null; then
    echo "  dnscrypt-proxy: RUNNING (not systemd)"
else
    echo "  dnscrypt-proxy: NOT RUNNING"
fi
echo ""

# Conky
echo "Conky Status:"
if pgrep -x conky &>/dev/null; then
    echo "  Conky: RUNNING"
else
    echo "  Conky: NOT RUNNING"
fi
echo ""

# Dashboard status
echo "Kodachi Dashboard:"
if pgrep -f "kodachi-dashboard" &>/dev/null; then
    echo "  Dashboard process: RUNNING"
else
    echo "  Dashboard process: NOT RUNNING"
fi
echo ""

# Secure Boot
echo "Secure Boot:"
if command -v mokutil &>/dev/null; then
    mokutil --sb-state 2>/dev/null | sed 's/^/  /' || echo "  (mokutil failed)"
elif [[ -d "/sys/firmware/efi" ]]; then
    echo "  UEFI boot: YES"
    SB=$(od -An -t u1 /sys/firmware/efi/efivars/SecureBoot-* 2>/dev/null | awk '{print $NF}' || echo "unknown")
    if [[ "$SB" == "1" ]]; then
        echo "  Secure Boot: ENABLED"
    elif [[ "$SB" == "0" ]]; then
        echo "  Secure Boot: DISABLED"
    else
        echo "  Secure Boot: UNKNOWN"
    fi
else
    echo "  Legacy BIOS boot (no UEFI/SecureBoot)"
fi
echo ""

# Boot mode
echo "Boot Mode:"
if [[ -d "/sys/firmware/efi" ]]; then
    echo "  UEFI"
else
    echo "  Legacy BIOS"
fi
echo ""

# RAM and storage summary
echo "Quick Resource Summary:"
echo "  RAM: $(free -h 2>/dev/null | awk '/Mem:/{print $2 " total, " $3 " used, " $7 " available"}')"
echo "  Root disk: $(df -h / 2>/dev/null | awk 'NR==2{print $2 " total, " $3 " used, " $4 " free (" $5 " used)"}')"
echo ""

# ------- QUICK SUMMARY BOX -------
echo "=============================================="
echo "   QUICK DIAGNOSIS SUMMARY"
echo "=============================================="
echo ""
echo "  Kodachi Version:    ${KODACHI_VERSION}"
echo "  Nightly Build:      ${NIGHTLY_VERSION:-unknown}"
echo "  Build Number:       ${BUILD_NUMBER:-unknown}"
echo "  Pack Date:          ${PACK_DATE:-unknown}"
echo "  System Type:        ${SYSTEM_TYPE}"
echo "  LUKS Encryption:    ${LUKS_ACTIVE}"
echo "  Nuke Password:      ${NUKE_STATUS}"
echo "  Root Filesystem:    ${ROOT_FS} (${ROOT_SOURCE})"
echo "  Boot Mode:          $(if [[ -d /sys/firmware/efi ]]; then echo 'UEFI'; else echo 'Legacy BIOS'; fi)"
echo "  Tor Running:        $(systemctl is-active tor 2>/dev/null || echo 'unknown')"
VPN_LABEL="NO"; [[ -n "${VPN_IFACES:-}" ]] && VPN_LABEL="YES"
echo "  VPN Active:         ${VPN_LABEL}"
echo "  DNSCrypt:           $(if pgrep -x dnscrypt-proxy &>/dev/null; then echo 'RUNNING'; else echo 'NOT RUNNING'; fi)"
echo ""
echo "=============================================="

) > "$COLLECTION_DIR/00-kodachi-meta/kodachi-meta-summary.txt" 2>&1

# Also save raw data for parsing (re-detect since subshell variables don't propagate)
(
set +e
KODACHI_VERSION="unknown"
if [[ -f "/etc/kodachi-version" ]]; then KODACHI_VERSION=$(cat /etc/kodachi-version 2>/dev/null || echo "unknown"); fi
if [[ -f "/etc/kodachi_version" ]]; then KODACHI_VERSION=$(cat /etc/kodachi_version 2>/dev/null || echo "unknown"); fi
# Check build-meta.json
if [[ "$KODACHI_VERSION" == "unknown" ]]; then
    for bm in /opt/*/dashboard/hooks/config/build-meta.json; do
        if [[ -f "$bm" ]]; then
            BM_V=$(grep -oP '"version"\s*:\s*"\K[^"]+' "$bm" 2>/dev/null | head -1)
            if [[ -n "$BM_V" ]]; then KODACHI_VERSION="$BM_V"; break; fi
        fi
    done
fi
# Check os-release
if [[ "$KODACHI_VERSION" == "unknown" ]]; then
    OS_V=$(grep "^VERSION_ID=" /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
    if [[ -n "$OS_V" ]]; then KODACHI_VERSION="$OS_V"; fi
fi

SYSTEM_TYPE="UNKNOWN"
if [[ -d "/run/live" ]] || grep -q "boot=live" /proc/cmdline 2>/dev/null; then
    SYSTEM_TYPE="LIVE"
else
    ROOT_FS_TYPE=$(findmnt -n -o FSTYPE / 2>/dev/null || echo "unknown")
    if [[ "$ROOT_FS_TYPE" == "ext4" ]] || [[ "$ROOT_FS_TYPE" == "btrfs" ]] || [[ "$ROOT_FS_TYPE" == "xfs" ]]; then
        SYSTEM_TYPE="INSTALLED"
    fi
fi

LUKS_ACTIVE="NO"
lsblk -f 2>/dev/null | grep -qi "crypto_LUKS" && LUKS_ACTIVE="YES"

NUKE_STATUS="NOT DETECTED"
dpkg -l 2>/dev/null | grep -qi "cryptsetup-nuke" && NUKE_STATUS="PACKAGE INSTALLED"

ROOT_FS=$(findmnt -n -o FSTYPE / 2>/dev/null || echo "unknown")
ROOT_SOURCE=$(findmnt -n -o SOURCE / 2>/dev/null || echo "unknown")

echo "KODACHI_VERSION=${KODACHI_VERSION}"
# Extract build info from build-meta.json (re-detect in subshell)
_NV="unknown"; _BN="unknown"; _PD="unknown"
for _bm in /opt/*/dashboard/hooks/config/build-meta.json "${REAL_HOME}"/*/dashboard/hooks/config/build-meta.json; do
    if [[ -f "$_bm" ]]; then
        _NV=$(grep -oP '"nightly_version"\s*:\s*"\K[^"]+' "$_bm" 2>/dev/null | head -1)
        _BN=$(grep -oP '"build_number"\s*:\s*\K[0-9]+' "$_bm" 2>/dev/null | head -1)
        _PD=$(grep -oP '"pack_date"\s*:\s*"\K[^"]+' "$_bm" 2>/dev/null | head -1)
        break
    fi
done
echo "NIGHTLY_VERSION=${_NV:-unknown}"
echo "BUILD_NUMBER=${_BN:-unknown}"
echo "PACK_DATE=${_PD:-unknown}"
echo "SYSTEM_TYPE=${SYSTEM_TYPE}"
echo "LUKS_ACTIVE=${LUKS_ACTIVE}"
echo "NUKE_STATUS=${NUKE_STATUS}"
echo "ROOT_FS=${ROOT_FS}"
echo "ROOT_SOURCE=${ROOT_SOURCE}"
echo "BOOT_MODE=$(if [[ -d /sys/firmware/efi ]]; then echo 'UEFI'; else echo 'BIOS'; fi)"
) > "$COLLECTION_DIR/00-kodachi-meta/meta-vars.txt" 2>&1

fi # end CATEGORY 0

# ============================================================================
# CATEGORY 1: System & Boot Information
# ============================================================================
if [[ "${CAT_ENABLED[1]}" == "1" ]]; then
progress "Collecting system and boot information..."

mkdir -p "$COLLECTION_DIR/01-system-boot"

safe_exec "$COLLECTION_DIR/01-system-boot/os-release.txt" "cat /etc/os-release"
safe_exec "$COLLECTION_DIR/01-system-boot/uname.txt" "uname -a"
safe_exec "$COLLECTION_DIR/01-system-boot/kernel-cmdline.txt" "cat /proc/cmdline"
safe_exec "$COLLECTION_DIR/01-system-boot/kernel-version.txt" "cat /proc/version"
safe_exec "$COLLECTION_DIR/01-system-boot/uptime.txt" "uptime"
safe_exec "$COLLECTION_DIR/01-system-boot/loadavg.txt" "cat /proc/loadavg"
safe_exec "$COLLECTION_DIR/01-system-boot/dmesg.txt" "dmesg --ctime"
safe_exec "$COLLECTION_DIR/01-system-boot/journalctl-full.txt" "journalctl -b --no-pager"
safe_exec "$COLLECTION_DIR/01-system-boot/journalctl-errors.txt" "journalctl -b -p err --no-pager"
safe_exec "$COLLECTION_DIR/01-system-boot/journalctl-warnings.txt" "journalctl -b -p warning --no-pager"
safe_exec "$COLLECTION_DIR/01-system-boot/systemctl-failed.txt" "systemctl --failed --no-pager"
safe_exec "$COLLECTION_DIR/01-system-boot/systemctl-all-units.txt" "systemctl list-units --all --no-pager"
safe_exec "$COLLECTION_DIR/01-system-boot/systemctl-timers.txt" "systemctl list-timers --all --no-pager"
safe_exec "$COLLECTION_DIR/01-system-boot/systemd-analyze-time.txt" "systemd-analyze time"
safe_exec "$COLLECTION_DIR/01-system-boot/systemd-analyze-blame.txt" "systemd-analyze blame"
safe_exec "$COLLECTION_DIR/01-system-boot/systemd-analyze-critical.txt" "systemd-analyze critical-chain"
safe_exec "$COLLECTION_DIR/01-system-boot/kernel-taint.txt" "cat /proc/sys/kernel/tainted"

# audit 2026-05-07: extra system-side data that helps when symptoms only
# manifest "this morning" / "after a few reboots". Without these we can't
# correlate the slow boot to anything that changed across boots.
safe_exec "$COLLECTION_DIR/01-system-boot/journalctl-prev-boot.txt" \
    "journalctl -b -1 --no-pager"
safe_exec "$COLLECTION_DIR/01-system-boot/journalctl-prev-boot-errors.txt" \
    "journalctl -b -1 -p err --no-pager"
safe_exec "$COLLECTION_DIR/01-system-boot/journalctl-list-boots.txt" \
    "journalctl --list-boots --no-pager"
safe_exec "$COLLECTION_DIR/01-system-boot/systemd-analyze-plot.svg" \
    "systemd-analyze plot"
safe_exec "$COLLECTION_DIR/01-system-boot/systemd-cgls.txt" \
    "systemd-cgls --no-pager"
safe_exec "$COLLECTION_DIR/01-system-boot/systemd-analyze-dump-targets.txt" \
    "systemd-analyze dump | grep -E '^(Unit|.*: dependency|Following|swap|local-fs|cryptsetup|graphical-session)' | head -200"
safe_exec "$COLLECTION_DIR/01-system-boot/systemd-analyze-units-graphical.txt" \
    "systemd-analyze critical-chain graphical.target"
safe_exec "$COLLECTION_DIR/01-system-boot/systemd-analyze-units-multi-user.txt" \
    "systemd-analyze critical-chain multi-user.target"

# Cycle-detection helper — surfaces any "Found ordering cycle" lines from
# THIS boot together with the units involved so reviewers don't have to
# grep journalctl-full.txt by hand.
safe_exec "$COLLECTION_DIR/01-system-boot/ordering-cycles.txt" \
    "journalctl -b --no-pager | grep -E 'ordering cycle|deleted to break|Found dependency on' || echo 'No ordering cycles detected this boot.'"

# Copy system logs
safe_copy "/var/log/syslog" "$COLLECTION_DIR/01-system-boot"
safe_copy "/var/log/kern.log" "$COLLECTION_DIR/01-system-boot"
safe_copy "/var/log/boot.log" "$COLLECTION_DIR/01-system-boot"
# Copy auth.log but redact password/credential lines
if [[ -f "/var/log/auth.log" ]]; then
    sed -E 's/(password|credential|secret|token)=[^ ]*/\1=[REDACTED]/gi' \
        /var/log/auth.log > "$COLLECTION_DIR/01-system-boot/auth.log" 2>/dev/null || \
        echo "Failed to copy auth.log" > "$COLLECTION_DIR/01-system-boot/auth.log.error"
fi
safe_copy "/var/log/daemon.log" "$COLLECTION_DIR/01-system-boot"

fi # end CATEGORY 1

# ============================================================================
# CATEGORY 2: Hardware & Drivers (Privacy-Hardened)
# ============================================================================
if [[ "${CAT_ENABLED[2]}" == "1" ]]; then
progress "Collecting hardware and driver information..."

mkdir -p "$COLLECTION_DIR/02-hardware-drivers"

# Concise PCI device list with IDs (enough to identify driver issues, no verbose subsystem dump)
safe_exec "$COLLECTION_DIR/02-hardware-drivers/lspci.txt" "lspci -nn"
# Basic USB list (no -v flag, avoids dumping device serial numbers)
safe_exec "$COLLECTION_DIR/02-hardware-drivers/lsusb.txt" "lsusb"
# Filesystem info
safe_exec "$COLLECTION_DIR/02-hardware-drivers/lsblk.txt" "lsblk -f"
# CPU info (cores, architecture, cache, model)
safe_exec "$COLLECTION_DIR/02-hardware-drivers/lscpu.txt" "lscpu"
# Loaded kernel modules (driver issues)
safe_exec "$COLLECTION_DIR/02-hardware-drivers/lsmod.txt" "lsmod"
# Detailed memory stats
safe_exec "$COLLECTION_DIR/02-hardware-drivers/meminfo.txt" "cat /proc/meminfo"
# RAM total/used/available
safe_exec "$COLLECTION_DIR/02-hardware-drivers/free.txt" "free -h"
# Disk space usage
safe_exec "$COLLECTION_DIR/02-hardware-drivers/df.txt" "df -h"
# Wireless kill switches
safe_exec "$COLLECTION_DIR/02-hardware-drivers/rfkill.txt" "rfkill list all"
# Firmware messages
safe_exec "$COLLECTION_DIR/02-hardware-drivers/dmesg-firmware.txt" "dmesg | grep -i firmware"
# Error messages
safe_exec "$COLLECTION_DIR/02-hardware-drivers/dmesg-errors.txt" "dmesg | grep -i error"
# GPU model only (VGA/3D/display controllers)
safe_exec "$COLLECTION_DIR/02-hardware-drivers/gpu-info.txt" "lspci | grep -iE 'vga|3d|display'"
# SSD vs HDD detection (ROTA=0 means SSD, ROTA=1 means HDD)
safe_exec "$COLLECTION_DIR/02-hardware-drivers/disk-type.txt" "lsblk -d -o NAME,SIZE,ROTA,TRAN,TYPE"
# System brand/model only — no serial numbers, no UUIDs, no asset tags
safe_exec "$COLLECTION_DIR/02-hardware-drivers/dmidecode-system.txt" "dmidecode --type system 2>/dev/null | grep -iE 'manufacturer|product|family' || echo 'dmidecode not available'"

# Sensors if available
if command -v sensors &> /dev/null; then
    safe_exec "$COLLECTION_DIR/02-hardware-drivers/sensors.txt" "sensors"
fi

# Modprobe configs (blacklists, driver options)
if [[ -d "/etc/modprobe.d" ]]; then
    mkdir -p "$COLLECTION_DIR/02-hardware-drivers/modprobe.d"
    for mconf in /etc/modprobe.d/*.conf; do
        [[ -f "$mconf" ]] && cp "$mconf" "$COLLECTION_DIR/02-hardware-drivers/modprobe.d/" 2>/dev/null || true
    done
fi

# DKMS module status
if command -v dkms &> /dev/null; then
    safe_exec "$COLLECTION_DIR/02-hardware-drivers/dkms-status.txt" "dkms status"
fi

# NVMe health (if nvme-cli installed)
if command -v nvme &> /dev/null; then
    safe_exec "$COLLECTION_DIR/02-hardware-drivers/nvme-smart.txt" "nvme smart-log /dev/nvme0n1 2>/dev/null || echo 'No NVMe device'"
fi

# S.M.A.R.T disk health
if command -v smartctl &> /dev/null; then
    safe_exec "$COLLECTION_DIR/02-hardware-drivers/smart-health.txt" "smartctl -H /dev/sda 2>/dev/null || smartctl -H /dev/nvme0n1 2>/dev/null || echo 'No SMART-capable device'"
fi

# Virtualization detection
safe_exec "$COLLECTION_DIR/02-hardware-drivers/virt-detect.txt" "systemd-detect-virt 2>/dev/null || echo 'not detected'"

# CPU microcode version
safe_exec "$COLLECTION_DIR/02-hardware-drivers/cpu-microcode.txt" "grep -m1 microcode /proc/cpuinfo 2>/dev/null || echo 'no microcode info'"

fi # end CATEGORY 2

# ============================================================================
# CATEGORY 3: Network Configuration (CRITICAL for Kodachi)
# ============================================================================
if [[ "${CAT_ENABLED[3]}" == "1" ]]; then
progress "Collecting network configuration..."

mkdir -p "$COLLECTION_DIR/03-network"

safe_exec "$COLLECTION_DIR/03-network/ip-addr.txt" "ip addr show"
safe_exec "$COLLECTION_DIR/03-network/ip-route.txt" "ip route show"
safe_exec "$COLLECTION_DIR/03-network/ip-route-all.txt" "ip route show table all"
safe_exec "$COLLECTION_DIR/03-network/resolv.conf.txt" "cat /etc/resolv.conf"
safe_exec "$COLLECTION_DIR/03-network/iptables-filter.txt" "iptables -L -v -n"
safe_exec "$COLLECTION_DIR/03-network/iptables-nat.txt" "iptables -t nat -L -v -n"
safe_exec "$COLLECTION_DIR/03-network/nftables.txt" "nft list ruleset"
safe_exec "$COLLECTION_DIR/03-network/listening-ports.txt" "ss -tulnp"
safe_exec "$COLLECTION_DIR/03-network/socket-stats.txt" "ss -s"

# DNS stack configs (critical for DNS degradation debugging)
safe_copy "/etc/systemd/resolved.conf" "$COLLECTION_DIR/03-network"
if [[ -d "/etc/systemd/resolved.conf.d" ]]; then
    mkdir -p "$COLLECTION_DIR/03-network/resolved.conf.d"
    cp /etc/systemd/resolved.conf.d/*.conf "$COLLECTION_DIR/03-network/resolved.conf.d/" 2>/dev/null || true
fi
# DNSCrypt config (redact server_names/stamps that could identify provider choice)
if [[ -f "/etc/dnscrypt-proxy/dnscrypt-proxy.toml" ]]; then
    grep -v -E "^(stamp|server_names)" /etc/dnscrypt-proxy/dnscrypt-proxy.toml \
        > "$COLLECTION_DIR/03-network/dnscrypt-proxy.toml" 2>/dev/null || true
fi

# WireGuard status (redact private/preshared keys)
if command -v wg &> /dev/null; then
    wg show all 2>/dev/null | sed -E 's/(private key|preshared key): .*/\1: [REDACTED]/g' \
        > "$COLLECTION_DIR/03-network/wireguard-show.txt" 2>/dev/null || true
fi

# NetworkManager dispatcher scripts (list only, don't copy contents)
safe_exec "$COLLECTION_DIR/03-network/nm-dispatcher-scripts.txt" "ls -la /etc/NetworkManager/dispatcher.d/ 2>/dev/null || echo 'no dispatcher scripts'"

# NetworkManager
if command -v nmcli &> /dev/null; then
    safe_exec "$COLLECTION_DIR/03-network/nmcli-general.txt" "nmcli general status"
    safe_exec "$COLLECTION_DIR/03-network/nmcli-connections.txt" "nmcli connection show"
fi

# Copy NetworkManager configs (redact WiFi passwords and sensitive credentials)
if [[ -d "/etc/NetworkManager" ]]; then
    mkdir -p "$COLLECTION_DIR/03-network/NetworkManager-config"
    # Copy structure but redact secrets from connection files
    find /etc/NetworkManager -type f 2>/dev/null | while read -r nm_file; do
        dest_file="$COLLECTION_DIR/03-network/NetworkManager-config/${nm_file#/etc/NetworkManager/}"
        mkdir -p "$(dirname "$dest_file")"
        if echo "$nm_file" | grep -qE "(system-connections|secrets)"; then
            # Redact passwords, PSK, secrets from connection profiles
            sed -E 's/(psk=).*/\1[REDACTED]/g; s/(password=).*/\1[REDACTED]/g; s/(secret=).*/\1[REDACTED]/g; s/(wep-key[0-9]*=).*/\1[REDACTED]/g; s/(leap-password=).*/\1[REDACTED]/g; s/(pin=).*/\1[REDACTED]/g; s/(private-key-password=).*/\1[REDACTED]/g' \
                "$nm_file" > "$dest_file" 2>/dev/null || true
        else
            cp "$nm_file" "$dest_file" 2>/dev/null || true
        fi
    done
fi

# resolvectl if available
if command -v resolvectl &> /dev/null; then
    safe_exec "$COLLECTION_DIR/03-network/resolvectl.txt" "resolvectl status"
fi

# DNS resolution testing (tests functionality only, no IP collection)
safe_exec "$COLLECTION_DIR/03-network/dns-test-dig.txt" "dig google.com"
safe_exec "$COLLECTION_DIR/03-network/dns-test-nslookup.txt" "nslookup google.com"

# NOTE: No IP address fetching (ipinfo.io, torproject check, etc.)
# to protect user privacy. Only local network config is collected.

fi # end CATEGORY 3

# ============================================================================
# CATEGORY 4: Tor Configuration & Status
# ============================================================================
if [[ "${CAT_ENABLED[4]}" == "1" ]]; then
progress "Collecting Tor information..."

mkdir -p "$COLLECTION_DIR/04-tor"

safe_exec "$COLLECTION_DIR/04-tor/tor-service-status.txt" "systemctl status tor* --no-pager"

# Copy Tor logs
if [[ -d "/var/log/tor" ]]; then
    mkdir -p "$COLLECTION_DIR/04-tor/logs"
    for logfile in /var/log/tor/*.log; do
        [[ -f "$logfile" ]] && safe_copy "$logfile" "$COLLECTION_DIR/04-tor/logs"
    done
fi

# Copy Tor config (redact all sensitive data: bridges, passwords, auth cookies, hidden service keys)
if [[ -f "/etc/tor/torrc" ]]; then
    grep -v -E "(Bridge |ServerTransport|Cookie|Password|HiddenService|ClientOnionAuth)" /etc/tor/torrc \
        | sed -E 's/(HashedControlPassword ).*/\1[REDACTED]/g' \
        > "$COLLECTION_DIR/04-tor/torrc.txt" 2>/dev/null || \
        echo "Could not read torrc" > "$COLLECTION_DIR/04-tor/torrc.txt"
fi

fi # end CATEGORY 4

# ============================================================================
# CATEGORY 5: VPN Configuration & Status
# ============================================================================
if [[ "${CAT_ENABLED[5]}" == "1" ]]; then
progress "Collecting VPN information..."

mkdir -p "$COLLECTION_DIR/05-vpn"

safe_exec "$COLLECTION_DIR/05-vpn/openvpn-service-status.txt" "systemctl status openvpn* --no-pager"

# WireGuard service and interface status
safe_exec "$COLLECTION_DIR/05-vpn/wireguard-service-status.txt" "systemctl status wg-quick* --no-pager 2>/dev/null || echo 'no wg-quick service'"
if command -v wg &> /dev/null; then
    wg show all 2>/dev/null | sed -E 's/(private key|preshared key): .*/\1: [REDACTED]/g' \
        > "$COLLECTION_DIR/05-vpn/wireguard-detail.txt" 2>/dev/null || true
fi

# Proxy tunnel processes (tun2socks, xray, hysteria, shadowsocks)
safe_exec "$COLLECTION_DIR/05-vpn/proxy-processes.txt" "ps auxww | grep -E 'tun2socks|xray|hysteria|ss-local|ss-redir|microsocks|redsocks' | grep -v grep || echo 'no proxy tunnels running'"

# Copy VPN logs
if [[ -d "/var/log/openvpn" ]]; then
    mkdir -p "$COLLECTION_DIR/05-vpn/logs"
    for logfile in /var/log/openvpn/*.log; do
        [[ -f "$logfile" ]] && safe_copy "$logfile" "$COLLECTION_DIR/05-vpn/logs"
    done
fi

# VPN routing tables (custom tables used by routing-switch)
safe_exec "$COLLECTION_DIR/05-vpn/ip-rule-list.txt" "ip rule list"

fi # end CATEGORY 5

# ============================================================================
# CATEGORY 6: Kodachi-Specific Logs & Services (CRITICAL)
# ============================================================================
if [[ "${CAT_ENABLED[6]}" == "1" ]]; then
progress "Collecting Kodachi-specific logs and services..."

mkdir -p "$COLLECTION_DIR/06-kodachi"

# Search for Kodachi hooks dynamically
KODACHI_HOOKS_DIRS=(
    "/opt/kodachi/dashboard/hooks"
    "${REAL_HOME}/dashboard/hooks"
    "/opt/*/dashboard/hooks"
)

for hooks_pattern in "${KODACHI_HOOKS_DIRS[@]}"; do
    for hooks_dir in $hooks_pattern; do
        if [[ -d "$hooks_dir" ]]; then
            echo "Found Kodachi hooks at: $hooks_dir" >> "$COLLECTION_DIR/06-kodachi/hooks-locations.txt"

            # Copy logs
            if [[ -d "$hooks_dir/logs" ]]; then
                mkdir -p "$COLLECTION_DIR/06-kodachi/hooks-logs"
                cp -r "$hooks_dir/logs"/* "$COLLECTION_DIR/06-kodachi/hooks-logs/" 2>/dev/null || true
            fi

            # Copy results (excluding privacy-sensitive files)
            if [[ -d "$hooks_dir/results" ]]; then
                mkdir -p "$COLLECTION_DIR/06-kodachi/hooks-results"
                # Use rsync or find to exclude IP-containing files
                find "$hooks_dir/results" -type f 2>/dev/null | while read -r rfile; do
                    rbase=$(basename "$rfile")
                    # Skip files that contain user IP addresses or personal data
                    case "$rbase" in
                        myip.json|ip_history.json|ip_info.json|my_ip.json|*ip_cache*)
                            echo "EXCLUDED for privacy: $rbase" >> "$COLLECTION_DIR/06-kodachi/hooks-results/PRIVACY_EXCLUDED.txt"
                            continue
                            ;;
                    esac
                    # Determine relative path and recreate structure
                    rrel="${rfile#$hooks_dir/results/}"
                    rdest="$COLLECTION_DIR/06-kodachi/hooks-results/$rrel"
                    mkdir -p "$(dirname "$rdest")"
                    # Redact credentials from VPN/proxy config files
                    case "$rbase" in
                        *.ovpn|*.conf|*.json)
                            if echo "$rrel" | grep -qE "^configs/"; then
                                sed -E \
                                    's/("password"[[:space:]]*:[[:space:]]*")[^"]*"/\1[REDACTED]"/gi;
                                     s/("secret"[[:space:]]*:[[:space:]]*")[^"]*"/\1[REDACTED]"/gi;
                                     s/("psk"[[:space:]]*:[[:space:]]*")[^"]*"/\1[REDACTED]"/gi;
                                     s/("key"[[:space:]]*:[[:space:]]*")[^"]*"/\1[REDACTED]"/gi;
                                     s/(password[= ]).*/\1[REDACTED]/gi;
                                     s/(auth-user-pass).*/\1 [REDACTED]/gi;
                                     s/(secret[= ]).*/\1[REDACTED]/gi;
                                     s/(password=)[^ ]*/\1[REDACTED]/gi;
                                     s/(hysteria2:\/\/[^?]*\?password=)[^ &"]*/\1[REDACTED]/gi' \
                                    "$rfile" > "$rdest" 2>/dev/null || cp "$rfile" "$rdest" 2>/dev/null || true
                            else
                                cp "$rfile" "$rdest" 2>/dev/null || true
                            fi
                            ;;
                        *)
                            cp "$rfile" "$rdest" 2>/dev/null || true
                            ;;
                    esac
                done
            fi
        fi
    done
done

# Check Kodachi binaries in /usr/local/bin/.
# Required binaries are part of every shipped ISO and must be present.
# Optional binaries are AI/experimental components that may not be shipped
# in every release (the orchestrator `kodachi-ai` is not yet bundled in the
# v9.0.1 ISO cache — only the subagents ai-admin/ai-cmd/.../ai-trainer are
# shipped); flagging them as ✗ NOT FOUND in field debug bundles caused
# noise reports against systems that were operating correctly.
KODACHI_BINARIES_REQUIRED=(
    "health-control"
    "tor-switch"
    "dns-switch"
    "dns-leak"
    "routing-switch"
    "ip-fetch"
    "online-auth"
    "integrity-check"
    "permission-guard"
    "logs-hook"
    "deps-checker"
    "workflow-manager"
    "global-launcher"
)
KODACHI_BINARIES_OPTIONAL=(
    "kodachi-ai"
    "ai-admin"
    "ai-cmd"
    "ai-discovery"
    "ai-gateway"
    "ai-learner"
    "ai-monitor"
    "ai-scheduler"
    "ai-trainer"
)

echo "Kodachi Binary Status:" > "$COLLECTION_DIR/06-kodachi/binary-status.txt"
echo "" >> "$COLLECTION_DIR/06-kodachi/binary-status.txt"
echo "[Required]" >> "$COLLECTION_DIR/06-kodachi/binary-status.txt"
for binary in "${KODACHI_BINARIES_REQUIRED[@]}"; do
    if command -v "$binary" &> /dev/null; then
        echo "✓ $binary: FOUND" >> "$COLLECTION_DIR/06-kodachi/binary-status.txt"
        "$binary" --version >> "$COLLECTION_DIR/06-kodachi/binary-status.txt" 2>&1 || echo "  (no version info)" >> "$COLLECTION_DIR/06-kodachi/binary-status.txt"
    else
        echo "✗ $binary: NOT FOUND" >> "$COLLECTION_DIR/06-kodachi/binary-status.txt"
    fi
done
echo "" >> "$COLLECTION_DIR/06-kodachi/binary-status.txt"
echo "[Optional / AI subsystem]" >> "$COLLECTION_DIR/06-kodachi/binary-status.txt"
for binary in "${KODACHI_BINARIES_OPTIONAL[@]}"; do
    if command -v "$binary" &> /dev/null; then
        echo "✓ $binary: FOUND" >> "$COLLECTION_DIR/06-kodachi/binary-status.txt"
        "$binary" --version >> "$COLLECTION_DIR/06-kodachi/binary-status.txt" 2>&1 || echo "  (no version info)" >> "$COLLECTION_DIR/06-kodachi/binary-status.txt"
    else
        echo "○ $binary: not installed (optional)" >> "$COLLECTION_DIR/06-kodachi/binary-status.txt"
    fi
done

# List /opt/kodachi* contents
ls -lah /opt/kodachi* > "$COLLECTION_DIR/06-kodachi/opt-kodachi-listing.txt" 2>&1 || echo "No /opt/kodachi* directories" > "$COLLECTION_DIR/06-kodachi/opt-kodachi-listing.txt"

# Copy build-meta.json (version/build info)
for build_meta in /opt/*/dashboard/hooks/config/build-meta.json; do
    if [[ -f "$build_meta" ]]; then
        cp "$build_meta" "$COLLECTION_DIR/06-kodachi/build-meta.json" 2>/dev/null || true
        break
    fi
done

# Copy Kodachi config files (non-sensitive)
for hooks_pattern in "/opt/kodachi/dashboard/hooks" "${REAL_HOME}/dashboard/hooks" "/opt/*/dashboard/hooks"; do
    for hooks_dir in $hooks_pattern; do
        if [[ -d "$hooks_dir/config" ]]; then
            mkdir -p "$COLLECTION_DIR/06-kodachi/hooks-config"
            # Copy config files but skip signkeys and any credential files
            find "$hooks_dir/config" -type f \( -name "*.json" -o -name "*.conf" -o -name "*.toml" \) \
                ! -path "*/signkeys/*" ! -path "*/secrets/*" ! -path "*credential*" ! -path "*password*" ! -path "*token*" \
                2>/dev/null | while read -r cfile; do
                crel="${cfile#$hooks_dir/config/}"
                cdest="$COLLECTION_DIR/06-kodachi/hooks-config/$crel"
                mkdir -p "$(dirname "$cdest")"
                cp "$cfile" "$cdest" 2>/dev/null || true
            done
            break 2
        fi
    done
done

# Kodachi systemd services
safe_exec "$COLLECTION_DIR/06-kodachi/kodachi-services.txt" "systemctl list-units 'kodachi*' --all --no-pager"

# Health-control diagnostics (read-only commands, safe to run)
if command -v health-control &> /dev/null; then
    safe_exec "$COLLECTION_DIR/06-kodachi/health-control-security-score.txt" "health-control security-score --json 2>/dev/null || echo 'security-score unavailable'"
    safe_exec "$COLLECTION_DIR/06-kodachi/health-control-net-check.txt" "health-control net-check --json 2>/dev/null || echo 'net-check unavailable'"
    safe_exec "$COLLECTION_DIR/06-kodachi/health-control-ipv6-status.txt" "health-control ipv6-status --json 2>/dev/null || echo 'ipv6-status unavailable'"
    safe_exec "$COLLECTION_DIR/06-kodachi/health-control-swap-status.txt" "health-control swap-status --json 2>/dev/null || echo 'swap-status unavailable'"
fi

# DNS-switch status
if command -v dns-switch &> /dev/null; then
    safe_exec "$COLLECTION_DIR/06-kodachi/dns-switch-status.txt" "dns-switch status --json 2>/dev/null || echo 'dns-switch unavailable'"
fi

# Routing-switch state
if command -v routing-switch &> /dev/null; then
    safe_exec "$COLLECTION_DIR/06-kodachi/routing-switch-status.txt" "routing-switch status --json 2>/dev/null || echo 'routing-switch unavailable'"
fi

fi # end CATEGORY 6

# ============================================================================
# CATEGORY 7: Installation & Package Logs
# ============================================================================
if [[ "${CAT_ENABLED[7]}" == "1" ]]; then
progress "Collecting installation and package logs..."

mkdir -p "$COLLECTION_DIR/07-installation-packages"

# Calamares installer logs (check all known locations)
CALAMARES_DIRS=(
    "/var/log/installer"
    "/var/log/calamares"
    "${REAL_HOME}/.cache/calamares"
    "/tmp/calamares-logs"
    "/var/log/Calamares"
)
for calamares_dir in "${CALAMARES_DIRS[@]}"; do
    if [[ -d "$calamares_dir" ]]; then
        mkdir -p "$COLLECTION_DIR/07-installation-packages/calamares"
        cp -r "$calamares_dir"/* "$COLLECTION_DIR/07-installation-packages/calamares/" 2>/dev/null || true
        echo "Found: $calamares_dir" >> "$COLLECTION_DIR/07-installation-packages/calamares/sources.txt"
    fi
done
# Single-file Calamares log
safe_copy "/var/log/Calamares.log" "$COLLECTION_DIR/07-installation-packages"

# Debian installer logs (d-i)
if [[ -d "/var/log/installer" ]]; then
    mkdir -p "$COLLECTION_DIR/07-installation-packages/debian-installer"
    cp -r /var/log/installer/* "$COLLECTION_DIR/07-installation-packages/debian-installer/" 2>/dev/null || true
fi
# Post-install Kodachi finish logs
safe_copy "/target/tmp/kodachi-grub-theme.log" "$COLLECTION_DIR/07-installation-packages"
safe_copy "/var/log/kodachi-finish-install.log" "$COLLECTION_DIR/07-installation-packages"

# audit 2026-05-07: extra Kodachi install / first-boot logs that were
# previously missed. Each is independently captured because Calamares,
# kodachi-finish-install, plymouth-firstboot, and crypttab-repair write to
# different locations and any of them can fingerprint a slow-boot incident.
safe_copy "/var/log/kodachi-cryptswap-activate.log" "$COLLECTION_DIR/07-installation-packages"
safe_copy "/var/log/kodachi-plymouth-firstboot.log" "$COLLECTION_DIR/07-installation-packages"
safe_copy "/var/log/kodachi-deps-install.log" "$COLLECTION_DIR/07-installation-packages"
safe_copy "/var/log/kodachi-binary-install.log" "$COLLECTION_DIR/07-installation-packages"
safe_copy "/var/log/kodachi-autoshield.log" "$COLLECTION_DIR/07-installation-packages"
safe_copy "/var/log/kodachi-fix-resolvconf.log" "$COLLECTION_DIR/07-installation-packages"

# Anything else under /var/log named kodachi-*.log
mkdir -p "$COLLECTION_DIR/07-installation-packages/kodachi-logs"
find /var/log -maxdepth 2 -name 'kodachi-*.log' -o -name 'kodachi*.log' 2>/dev/null | head -50 | while read -r kl; do
    safe_copy "$kl" "$COLLECTION_DIR/07-installation-packages/kodachi-logs"
done

# /var/lib/kodachi marker files (one-shot install/upgrade markers — their
# presence/absence tells us which post-install hooks have run).
if [[ -d /var/lib/kodachi ]]; then
    mkdir -p "$COLLECTION_DIR/07-installation-packages/kodachi-state"
    cp -r /var/lib/kodachi/* "$COLLECTION_DIR/07-installation-packages/kodachi-state/" 2>/dev/null || true
    safe_exec "$COLLECTION_DIR/07-installation-packages/kodachi-state/listing.txt" \
        "ls -laR /var/lib/kodachi"
fi

# /var/log/live-build/ if it survived install (rare but useful for live-ISO
# build-time issues that surface only after install).
if [[ -d /var/log/live-build ]]; then
    mkdir -p "$COLLECTION_DIR/07-installation-packages/live-build"
    cp -r /var/log/live-build/* "$COLLECTION_DIR/07-installation-packages/live-build/" 2>/dev/null || true
fi

# Crypttab (raw copy — critical for cryptswap timeout debugging)
safe_copy "/etc/crypttab" "$COLLECTION_DIR/07-installation-packages"

# Crypttab repair logs (Kodachi's boot-time cryptswap fixer)
safe_copy "/var/log/kodachi-crypttab-fix.log" "$COLLECTION_DIR/07-installation-packages"

# Partition layout
if command -v parted &> /dev/null; then
    safe_exec "$COLLECTION_DIR/07-installation-packages/parted-list.txt" "parted -l 2>/dev/null || echo 'parted failed'"
fi

# Preseed configuration (used during installation)
for preseed in /cdrom/preseed*.cfg /preseed*.cfg /tmp/preseed*.cfg; do
    if [[ -f "$preseed" ]]; then
        safe_copy "$preseed" "$COLLECTION_DIR/07-installation-packages"
    fi
done

# EFI boot entries (critical for UEFI boot debugging)
mkdir -p "$COLLECTION_DIR/07-installation-packages/efi-boot"
if command -v efibootmgr &>/dev/null; then
    safe_exec "$COLLECTION_DIR/07-installation-packages/efi-boot/efibootmgr.txt" "efibootmgr -v"
fi
if [[ -d "/boot/efi" ]]; then
    safe_exec "$COLLECTION_DIR/07-installation-packages/efi-boot/efi-contents.txt" "find /boot/efi -type f"
fi
if [[ -d "/sys/firmware/efi" ]]; then
    safe_exec "$COLLECTION_DIR/07-installation-packages/efi-boot/efi-vars-list.txt" "ls -la /sys/firmware/efi/efivars/ | head -50"
fi

# initramfs configuration (affects boot)
mkdir -p "$COLLECTION_DIR/07-installation-packages/initramfs"
if [[ -d "/etc/initramfs-tools" ]]; then
    cp -r /etc/initramfs-tools/* "$COLLECTION_DIR/07-installation-packages/initramfs/" 2>/dev/null || true
fi
# Check which initramfs hooks are installed
safe_exec "$COLLECTION_DIR/07-installation-packages/initramfs/hooks-list.txt" "ls -la /usr/share/initramfs-tools/hooks/ 2>/dev/null"
safe_exec "$COLLECTION_DIR/07-installation-packages/initramfs/scripts-list.txt" "ls -laR /usr/share/initramfs-tools/scripts/ 2>/dev/null"
# dracut if used instead
if [[ -d "/etc/dracut.conf.d" ]]; then
    mkdir -p "$COLLECTION_DIR/07-installation-packages/dracut"
    cp -r /etc/dracut.conf.d/* "$COLLECTION_DIR/07-installation-packages/dracut/" 2>/dev/null || true
fi

# Package management logs
safe_copy "/var/log/apt/history.log" "$COLLECTION_DIR/07-installation-packages"
safe_copy "/var/log/apt/term.log" "$COLLECTION_DIR/07-installation-packages"
safe_copy "/var/log/dpkg.log" "$COLLECTION_DIR/07-installation-packages"
safe_copy "/var/log/alternatives.log" "$COLLECTION_DIR/07-installation-packages"

# Installed packages list
safe_exec "$COLLECTION_DIR/07-installation-packages/dpkg-list.txt" "dpkg -l"
safe_exec "$COLLECTION_DIR/07-installation-packages/apt-list.txt" "apt list --installed 2>/dev/null"

fi # end CATEGORY 7

# ============================================================================
# CATEGORY 8: Display & Desktop Environment + User-session diagnostics
# audit 2026-05-07: massively expanded to capture user-systemd, xsession-errors,
# xfconf state, autostart entries, and session timing — without these the
# 135 s post-login stall on the CentOS-Stream-9 / GLaDOS bundles was
# undiagnosable from the collected data alone.
# ============================================================================
if [[ "${CAT_ENABLED[8]}" == "1" ]]; then
progress "Collecting display, desktop, and user-session information..."

mkdir -p "$COLLECTION_DIR/08-display-desktop"
mkdir -p "$COLLECTION_DIR/08-display-desktop/user-session"
mkdir -p "$COLLECTION_DIR/08-display-desktop/xfce-config"
mkdir -p "$COLLECTION_DIR/08-display-desktop/autostart"

safe_copy "/var/log/Xorg.0.log" "$COLLECTION_DIR/08-display-desktop"
safe_copy "/var/log/Xorg.0.log.old" "$COLLECTION_DIR/08-display-desktop"

# Display manager logs (lightdm + greeter + per-seat X server logs)
for dm_dir in "/var/log/lightdm" "/var/log/sddm" "/var/log/gdm3"; do
    if [[ -d "$dm_dir" ]]; then
        mkdir -p "$COLLECTION_DIR/08-display-desktop/display-manager"
        cp -r "$dm_dir"/* "$COLLECTION_DIR/08-display-desktop/display-manager/" 2>/dev/null || true
    fi
done

# Basic display info
safe_exec "$COLLECTION_DIR/08-display-desktop/xrandr.txt" "xrandr --verbose"
safe_exec "$COLLECTION_DIR/08-display-desktop/session-type.txt" "echo \${XDG_SESSION_TYPE:-not_set}"
safe_exec "$COLLECTION_DIR/08-display-desktop/desktop-session.txt" "echo \${DESKTOP_SESSION:-not_set}"

# ---- USER-SIDE SYSTEMD STATE ---------------------------------------------
# Without this, post-login hangs (xfce4-session waiting on a user service or
# a stuck autostart entry) are invisible. Boot-side journalctl-full.txt
# captures system events but NOT systemd[uid].
safe_exec_user "$COLLECTION_DIR/08-display-desktop/user-session/systemd-analyze-user-time.txt" \
    "systemd-analyze --user time"
safe_exec_user "$COLLECTION_DIR/08-display-desktop/user-session/systemd-analyze-user-blame.txt" \
    "systemd-analyze --user blame"
safe_exec_user "$COLLECTION_DIR/08-display-desktop/user-session/systemd-analyze-user-critical-chain.txt" \
    "systemd-analyze --user critical-chain"
safe_exec_user "$COLLECTION_DIR/08-display-desktop/user-session/systemctl-user-all-units.txt" \
    "systemctl --user list-units --all --no-pager"
safe_exec_user "$COLLECTION_DIR/08-display-desktop/user-session/systemctl-user-failed.txt" \
    "systemctl --user --failed --no-pager"
safe_exec_user "$COLLECTION_DIR/08-display-desktop/user-session/systemctl-user-timers.txt" \
    "systemctl --user list-timers --all --no-pager"
safe_exec_user "$COLLECTION_DIR/08-display-desktop/user-session/journalctl-user-current-boot.txt" \
    "journalctl --user -b --no-pager"
safe_exec_user "$COLLECTION_DIR/08-display-desktop/user-session/journalctl-user-warnings.txt" \
    "journalctl --user -b -p warning --no-pager"
safe_exec "$COLLECTION_DIR/08-display-desktop/user-session/journalctl-uid.txt" \
    "journalctl _UID=${REAL_UID:-1001} -b --no-pager"
safe_exec "$COLLECTION_DIR/08-display-desktop/user-session/loginctl-sessions.txt" \
    "loginctl list-sessions --no-pager && echo '---' && loginctl list-users --no-pager"
safe_exec "$COLLECTION_DIR/08-display-desktop/user-session/loginctl-session-status.txt" \
    "for s in \$(loginctl list-sessions --no-legend | awk '{print \$1}'); do echo '=== Session '\$s' ==='; loginctl session-status \$s --no-pager; echo; done"
safe_exec "$COLLECTION_DIR/08-display-desktop/user-session/last-logins.txt" "last -n 30"
safe_exec "$COLLECTION_DIR/08-display-desktop/user-session/lastlog.txt" "lastlog"

# ---- ~/.xsession-errors AND XFCE LOGS ------------------------------------
# This is THE file that captures every Xsession.d/* and autostart .desktop
# stdout/stderr — slow login symptoms always surface here first.
safe_copy_user "${REAL_HOME}/.xsession-errors" "$COLLECTION_DIR/08-display-desktop/user-session"
safe_copy_user "${REAL_HOME}/.xsession-errors.old" "$COLLECTION_DIR/08-display-desktop/user-session"
safe_copy_user "${REAL_HOME}/.cache/sessions/xfce4-session-:0" "$COLLECTION_DIR/08-display-desktop/user-session"
# XFCE-specific log files (xfsettingsd, conky, kodachi user-side scripts)
if [[ -n "$REAL_HOME" ]] && [[ -d "$REAL_HOME/.cache" ]]; then
    sudo -u "$REAL_USER" find "$REAL_HOME/.cache" -maxdepth 2 -type f \
        \( -name '*.log' -o -name 'xfsettingsd*' -o -name 'kodachi-*' \) \
        -size -5M 2>/dev/null | while read -r logf; do
        safe_copy_user "$logf" "$COLLECTION_DIR/08-display-desktop/user-session"
    done
fi

# Saved XFCE session files (a stale saved session is a known cause of
# 90-180 s post-login stalls — xfce4-session retries restore with timeouts).
if sudo -u "$REAL_USER" test -d "$REAL_HOME/.cache/sessions" 2>/dev/null; then
    safe_exec_user "$COLLECTION_DIR/08-display-desktop/user-session/cache-sessions-listing.txt" \
        "ls -laR \$HOME/.cache/sessions"
fi

# ---- XFCE CONFIG (xfconf channels) ---------------------------------------
# xfconf is XFCE's per-user settings DB. Slow logins can be caused by stale
# session restore flags, broken keyboard shortcuts pointing at missing bins,
# or panel layouts referencing dead D-Bus services.
safe_exec_user "$COLLECTION_DIR/08-display-desktop/xfce-config/xfconf-channels.txt" \
    "xfconf-query -l"
for chan in xfce4-session xfwm4 xsettings xfce4-desktop xfce4-panel xfce4-keyboard-shortcuts displays; do
    safe_exec_user "$COLLECTION_DIR/08-display-desktop/xfce-config/xfconf-${chan}.txt" \
        "xfconf-query -c '$chan' -lv"
done

# Per-user XFCE XML configs (always-up-to-date snapshot, even if xfconfd is
# the one hung). Captured via filesystem to bypass any xfconfd issue.
if sudo -u "$REAL_USER" test -d "$REAL_HOME/.config/xfce4" 2>/dev/null; then
    sudo -u "$REAL_USER" find "$REAL_HOME/.config/xfce4" -maxdepth 5 -type f \
        \( -name '*.xml' -o -name '*.rc' \) -size -2M 2>/dev/null | while read -r f; do
        # Preserve relative path under xfce-config/
        rel="${f#${REAL_HOME}/.config/xfce4/}"
        target="$COLLECTION_DIR/08-display-desktop/xfce-config/files/$rel"
        mkdir -p "$(dirname "$target")"
        sudo -u "$REAL_USER" cat "$f" > "$target" 2>/dev/null || true
    done
fi

# ---- AUTOSTART ENTRIES (system + user) -----------------------------------
# These are the .desktop files that xfce4-session iterates at login. A
# blocking exec here surfaces directly as a login stall.
for d in /etc/xdg/autostart "${REAL_HOME}/.config/autostart"; do
    if [[ -d "$d" ]]; then
        rel="$(echo "$d" | tr '/' '_')"
        mkdir -p "$COLLECTION_DIR/08-display-desktop/autostart/${rel}"
        if [[ "$d" == /etc/* ]]; then
            cp -r "$d"/*.desktop "$COLLECTION_DIR/08-display-desktop/autostart/${rel}/" 2>/dev/null || true
        else
            sudo -u "$REAL_USER" sh -c "cp -r '$d'/*.desktop '$COLLECTION_DIR/08-display-desktop/autostart/${rel}/'" 2>/dev/null || true
        fi
    fi
done

# Listing of /etc/X11/Xsession.d/ — the Debian-style scripts that run in
# series on every graphical login. A slow one here = 100% login-stall culprit.
safe_exec "$COLLECTION_DIR/08-display-desktop/Xsession.d-listing.txt" \
    "ls -la /etc/X11/Xsession.d/ /etc/X11/Xsession 2>/dev/null"
if [[ -d /etc/X11/Xsession.d ]]; then
    mkdir -p "$COLLECTION_DIR/08-display-desktop/Xsession.d"
    cp -r /etc/X11/Xsession.d/* "$COLLECTION_DIR/08-display-desktop/Xsession.d/" 2>/dev/null || true
fi

# /etc/profile.d/ — also runs on login shell (incl. lightdm xsession). The
# Kodachi-specific kodachi-autoshield.sh and kodachi-path.sh live here.
if [[ -d /etc/profile.d ]]; then
    mkdir -p "$COLLECTION_DIR/08-display-desktop/profile.d"
    cp /etc/profile.d/*.sh "$COLLECTION_DIR/08-display-desktop/profile.d/" 2>/dev/null || true
fi

# User shell init files — if they have side-effects (network calls, slow
# command-not-found handlers, etc.) login feels slow even when systemd is fine.
for shf in .profile .bash_profile .bash_login .bashrc .zshrc .xprofile .xsessionrc .xinitrc; do
    if sudo -u "$REAL_USER" test -f "$REAL_HOME/$shf" 2>/dev/null; then
        safe_copy_user "$REAL_HOME/$shf" "$COLLECTION_DIR/08-display-desktop/user-session"
    fi
done

# ---- LIVE-PROCESS SNAPSHOT FOR THE USER SESSION --------------------------
# Captures the whole xfce4-session process subtree state at collection time.
# If a child is in 'D' (uninterruptible sleep) we see exactly which one.
safe_exec "$COLLECTION_DIR/08-display-desktop/user-session/process-tree-user.txt" \
    "ps -ef --forest -u ${REAL_USER}"
safe_exec "$COLLECTION_DIR/08-display-desktop/user-session/wchan-user.txt" \
    "ps -o pid,user,stat,wchan:30,cmd -u ${REAL_USER}"

fi # end CATEGORY 8

# ============================================================================
# CATEGORY 9: Performance & Processes
# ============================================================================
if [[ "${CAT_ENABLED[9]}" == "1" ]]; then
progress "Collecting performance and process information..."

mkdir -p "$COLLECTION_DIR/09-performance-processes"

safe_exec "$COLLECTION_DIR/09-performance-processes/ps-tree.txt" "ps auxf"
safe_exec "$COLLECTION_DIR/09-performance-processes/top-snapshot.txt" "top -bn1"
safe_exec "$COLLECTION_DIR/09-performance-processes/vmstat.txt" "vmstat 1 5"

if command -v iostat &> /dev/null; then
    safe_exec "$COLLECTION_DIR/09-performance-processes/iostat.txt" "iostat"
fi

# Pressure stall info
safe_exec "$COLLECTION_DIR/09-performance-processes/pressure-cpu.txt" "cat /proc/pressure/cpu"
safe_exec "$COLLECTION_DIR/09-performance-processes/pressure-memory.txt" "cat /proc/pressure/memory"
safe_exec "$COLLECTION_DIR/09-performance-processes/pressure-io.txt" "cat /proc/pressure/io"

# Top CPU and memory consumers (sorted)
safe_exec "$COLLECTION_DIR/09-performance-processes/top-cpu-consumers.txt" "ps aux --sort=-%cpu | head -25"
safe_exec "$COLLECTION_DIR/09-performance-processes/top-mem-consumers.txt" "ps aux --sort=-%mem | head -25"

# CPU frequency/throttling state
safe_exec "$COLLECTION_DIR/09-performance-processes/cpu-freq.txt" "cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver 2>/dev/null && cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || echo 'cpufreq not available'"

fi # end CATEGORY 9

# ============================================================================
# CATEGORY 10: Security & Permissions
# ============================================================================
if [[ "${CAT_ENABLED[10]}" == "1" ]]; then
progress "Collecting security and permissions information..."

mkdir -p "$COLLECTION_DIR/10-security-permissions"

safe_exec "$COLLECTION_DIR/10-security-permissions/id.txt" "id"
safe_exec "$COLLECTION_DIR/10-security-permissions/who.txt" "who"
safe_exec "$COLLECTION_DIR/10-security-permissions/w.txt" "w"
safe_exec "$COLLECTION_DIR/10-security-permissions/last.txt" "last -20"

# SELinux/AppArmor
safe_exec "$COLLECTION_DIR/10-security-permissions/getenforce.txt" "getenforce"
safe_exec "$COLLECTION_DIR/10-security-permissions/aa-status.txt" "aa-status"

# Kernel hardening sysctl values (critical for security scoring debug)
safe_exec "$COLLECTION_DIR/10-security-permissions/sysctl-kernel.txt" "sysctl kernel.kptr_restrict kernel.dmesg_restrict kernel.unprivileged_bpf_disabled kernel.yama.ptrace_scope kernel.randomize_va_space kernel.kexec_load_disabled kernel.sysrq kernel.perf_event_paranoid fs.protected_symlinks fs.protected_hardlinks net.ipv4.tcp_syncookies net.ipv4.ip_forward net.ipv6.conf.all.disable_ipv6 2>/dev/null"

# sysctl.d drop-in configs
if [[ -d "/etc/sysctl.d" ]]; then
    mkdir -p "$COLLECTION_DIR/10-security-permissions/sysctl.d"
    for sconf in /etc/sysctl.d/*.conf; do
        [[ -f "$sconf" ]] && cp "$sconf" "$COLLECTION_DIR/10-security-permissions/sysctl.d/" 2>/dev/null || true
    done
fi

# chkrootkit config and status
safe_copy "/etc/chkrootkit/chkrootkit.conf" "$COLLECTION_DIR/10-security-permissions"
safe_exec "$COLLECTION_DIR/10-security-permissions/chkrootkit-service.txt" "systemctl status chkrootkit.service --no-pager 2>/dev/null || echo 'chkrootkit service not found'"

# fail2ban status
if command -v fail2ban-client &> /dev/null; then
    safe_exec "$COLLECTION_DIR/10-security-permissions/fail2ban-status.txt" "fail2ban-client status 2>/dev/null || echo 'fail2ban not running'"
fi

# auditd rules and status
if command -v auditctl &> /dev/null; then
    safe_exec "$COLLECTION_DIR/10-security-permissions/auditd-rules.txt" "auditctl -l 2>/dev/null || echo 'auditd not running'"
    safe_exec "$COLLECTION_DIR/10-security-permissions/auditd-status.txt" "systemctl status auditd --no-pager 2>/dev/null"
fi

# usbguard status
if command -v usbguard &> /dev/null; then
    safe_exec "$COLLECTION_DIR/10-security-permissions/usbguard-rules.txt" "usbguard list-rules 2>/dev/null || echo 'usbguard not active'"
    safe_exec "$COLLECTION_DIR/10-security-permissions/usbguard-devices.txt" "usbguard list-devices 2>/dev/null || echo 'usbguard not active'"
fi

# NTP service status (for IPv6 bind error debugging)
safe_exec "$COLLECTION_DIR/10-security-permissions/ntpsec-status.txt" "systemctl status ntpsec --no-pager 2>/dev/null || systemctl status ntp --no-pager 2>/dev/null || echo 'no NTP service'"
safe_copy "/etc/ntpsec/ntp.conf" "$COLLECTION_DIR/10-security-permissions"

# Sudoers (list files only, don't copy contents — too sensitive)
safe_exec "$COLLECTION_DIR/10-security-permissions/sudoers-files.txt" "ls -la /etc/sudoers.d/ 2>/dev/null || echo 'no sudoers.d'"

fi # end CATEGORY 10

# ============================================================================
# CATEGORY 11: Live System Information
# ============================================================================
if [[ "${CAT_ENABLED[11]}" == "1" ]]; then
progress "Collecting live system information..."

mkdir -p "$COLLECTION_DIR/11-live-system"

safe_exec "$COLLECTION_DIR/11-live-system/mount.txt" "mount"
safe_exec "$COLLECTION_DIR/11-live-system/proc-mounts.txt" "cat /proc/mounts"
safe_exec "$COLLECTION_DIR/11-live-system/findmnt.txt" "findmnt --real"
safe_copy "/etc/fstab" "$COLLECTION_DIR/11-live-system"

# Live system detection
if [[ -d "/run/live" ]]; then
    echo "Running from LIVE system" > "$COLLECTION_DIR/11-live-system/live-status.txt"
    ls -lah /run/live >> "$COLLECTION_DIR/11-live-system/live-status.txt"
    # Live-specific: squashfs info and overlay details
    safe_exec "$COLLECTION_DIR/11-live-system/squashfs-mounts.txt" "mount | grep -E 'squash|overlay|aufs'"
    if [[ -d "/run/live/medium" ]]; then
        safe_exec "$COLLECTION_DIR/11-live-system/live-medium-contents.txt" "ls -lah /run/live/medium/"
    fi
    if [[ -d "/run/live/persistence" ]]; then
        safe_exec "$COLLECTION_DIR/11-live-system/persistence-status.txt" "ls -lah /run/live/persistence/"
    fi
else
    echo "Running from INSTALLED system" > "$COLLECTION_DIR/11-live-system/live-status.txt"
fi

fi # end CATEGORY 11

# ============================================================================
# CATEGORY 12: Miscellaneous System Configuration
# ============================================================================
if [[ "${CAT_ENABLED[12]}" == "1" ]]; then
progress "Collecting miscellaneous system configuration..."

mkdir -p "$COLLECTION_DIR/12-misc-config"

safe_exec "$COLLECTION_DIR/12-misc-config/locale.txt" "locale"
safe_exec "$COLLECTION_DIR/12-misc-config/timedatectl.txt" "timedatectl"
safe_exec "$COLLECTION_DIR/12-misc-config/hostname.txt" "hostname"
safe_copy "/etc/default/grub" "$COLLECTION_DIR/12-misc-config"

# GRUB config (truncate if too large)
if [[ -f "/boot/grub/grub.cfg" ]]; then
    safe_copy "/boot/grub/grub.cfg" "$COLLECTION_DIR/12-misc-config"
fi

# GRUB drop-in configs
if [[ -d "/etc/default/grub.d" ]]; then
    mkdir -p "$COLLECTION_DIR/12-misc-config/grub.d"
    cp /etc/default/grub.d/*.cfg "$COLLECTION_DIR/12-misc-config/grub.d/" 2>/dev/null || true
fi

# systemd core configs
safe_copy "/etc/systemd/journald.conf" "$COLLECTION_DIR/12-misc-config"
safe_copy "/etc/systemd/system.conf" "$COLLECTION_DIR/12-misc-config"
if [[ -d "/etc/systemd/journald.conf.d" ]]; then
    mkdir -p "$COLLECTION_DIR/12-misc-config/journald.conf.d"
    cp /etc/systemd/journald.conf.d/*.conf "$COLLECTION_DIR/12-misc-config/journald.conf.d/" 2>/dev/null || true
fi

# Environment and defaults
safe_copy "/etc/environment" "$COLLECTION_DIR/12-misc-config"

# Kodachi-specific system configs
safe_copy "/etc/kodachi-version" "$COLLECTION_DIR/12-misc-config"
safe_copy "/etc/kodachi-release" "$COLLECTION_DIR/12-misc-config"

fi # end CATEGORY 12

# ============================================================================
# CATEGORY 13: Collection Metadata (always runs)
# ============================================================================
progress "Generating collection metadata..."

mkdir -p "$COLLECTION_DIR/00-metadata"

# Record which categories were collected
{
    echo "Kodachi Debug Collection Metadata"
    echo "=================================="
    echo "Collection Date: $(date)"
    echo "Hostname: $HOSTNAME"
    echo "Real User: $REAL_USER"
    echo "Real Home: $REAL_HOME"
    echo "Collection Directory: $COLLECTION_DIR"
    echo ""
    echo "Categories Collected:"
    echo "---------------------"
    for i in "${!CAT_LABEL[@]}"; do
        if [[ "${CAT_ENABLED[$i]}" == "1" ]]; then
            echo "  [X] $((i+1)). ${CAT_LABEL[$i]}"
        else
            echo "  [ ] $((i+1)). ${CAT_LABEL[$i]} (skipped)"
        fi
    done
    echo ""
    echo "System Information:"
    echo "-------------------"
    uname -a
    echo ""
    echo "Disk Space Available:"
    echo "---------------------"
    df -h "$DESKTOP_DIR"
    echo ""
} > "$COLLECTION_DIR/00-metadata/collection-info.txt" 2>&1

# Collection tree
tree "$COLLECTION_DIR" > "$COLLECTION_DIR/00-metadata/directory-tree.txt" 2>/dev/null || \
    find "$COLLECTION_DIR" -type f > "$COLLECTION_DIR/00-metadata/file-list.txt"

# ============================================================================
# CATEGORY 14: Create ZIP Archive (always runs)
# ============================================================================
progress "Creating compressed archive..."

cd "$TEMP_DIR" || exit 1
if zip -r "$ZIP_FILE" "$COLLECTION_NAME" > /dev/null 2>&1; then
    ZIP_SIZE=$(du -h "$ZIP_FILE" | cut -f1)
    echo -e "${GREEN}✓ Archive created successfully${NC}"
else
    echo -e "${RED}✗ Failed to create archive${NC}"
    exit 1
fi

# ============================================================================
# CATEGORY 15: Cleanup & Summary (always runs)
# ============================================================================
progress "Cleaning up temporary files..."

rm -rf "$TEMP_DIR"

# Change ownership to real user
chown "$REAL_USER:$REAL_USER" "$ZIP_FILE"

# Summary
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              COLLECTION COMPLETED SUCCESSFULLY            ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Print the quick meta summary on screen too
if [[ -f "$ZIP_FILE" ]]; then
    echo -e "${YELLOW}--- Quick System Info ---${NC}"
    # We already cleaned up COLLECTION_DIR, so re-read from the zip isn't practical.
    # Instead, re-detect the key values quickly:
    _ver="unknown"
    if [[ -f "/etc/kodachi-version" ]]; then _ver=$(cat /etc/kodachi-version 2>/dev/null || echo "unknown"); fi
    if [[ -f "/etc/kodachi_version" ]]; then _ver=$(cat /etc/kodachi_version 2>/dev/null || echo "unknown"); fi
    if [[ "$_ver" == "unknown" ]]; then
        for _bm in /opt/*/dashboard/hooks/config/build-meta.json; do
            if [[ -f "$_bm" ]]; then
                _bv=$(grep -oP '"version"\s*:\s*"\K[^"]+' "$_bm" 2>/dev/null | head -1)
                if [[ -n "$_bv" ]]; then _ver="$_bv"; break; fi
            fi
        done
    fi
    if [[ "$_ver" == "unknown" ]]; then
        _ov=$(grep "^VERSION_ID=" /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
        if [[ -n "$_ov" ]]; then _ver="$_ov"; fi
    fi
    if [[ -d "/run/live" ]] || grep -q "boot=live" /proc/cmdline 2>/dev/null; then
        _type="LIVE"
    else
        _type="INSTALLED"
    fi
    _luks="NO"
    if lsblk -f 2>/dev/null | grep -qi "crypto_LUKS"; then _luks="YES"; fi
    _nuke="NOT DETECTED"
    if dpkg -l 2>/dev/null | grep -qi "cryptsetup-nuke"; then _nuke="PACKAGE INSTALLED"; fi
    echo -e "  Version:     ${BLUE}${_ver}${NC}"
    echo -e "  System:      ${BLUE}${_type}${NC}"
    echo -e "  LUKS:        ${BLUE}${_luks}${NC}"
    echo -e "  Nuke:        ${BLUE}${_nuke}${NC}"
    echo -e "  Tor:         ${BLUE}$(systemctl is-active tor 2>/dev/null || echo 'unknown')${NC}"
    echo ""
fi

echo -e "${YELLOW}Archive Location:${NC} $ZIP_FILE"
echo -e "${YELLOW}Archive Size:${NC} $ZIP_SIZE"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo "  1. The debug archive has been saved to your Desktop"
echo "  2. Upload the file to your preferred file sharing service"
echo "  3. Share the download link with Kodachi support team"
echo "  4. Include a brief description of the issue you're experiencing"
echo ""
echo -e "${YELLOW}Note:${NC} This archive contains system logs and configuration."
echo "       Review the contents if you have privacy concerns before sharing."
echo ""
echo -e "${GREEN}Thank you for helping improve Kodachi OS!${NC}"
echo ""
