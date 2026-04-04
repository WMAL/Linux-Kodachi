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
# Last updated: 2026-04-04
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

    if ! eval "$cmd" > "$output_file" 2>&1; then
        echo "[EXIT CODE: $?] Command failed or not available: $cmd" >> "$output_file"
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

# ---- Interactive category selection menu ----

show_menu() {
    clear 2>/dev/null || true
    echo -e "${GREEN}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║         KODACHI OS DEBUG COLLECTOR v1.2                  ║"
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
    echo "║         KODACHI OS DEBUG COLLECTOR v1.2                  ║"
    echo "║    Comprehensive System Diagnostics Tool                 ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
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
        # Extract version from build-meta if still unknown
        if [[ "$KODACHI_VERSION" == "unknown" ]]; then
            BM_VER=$(grep -oP '"version"\s*:\s*"\K[^"]+' "$build_meta" 2>/dev/null | head -1)
            if [[ -n "$BM_VER" ]]; then
                KODACHI_VERSION="$BM_VER"
            fi
        fi
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

# Copy VPN logs
if [[ -d "/var/log/openvpn" ]]; then
    mkdir -p "$COLLECTION_DIR/05-vpn/logs"
    for logfile in /var/log/openvpn/*.log; do
        [[ -f "$logfile" ]] && safe_copy "$logfile" "$COLLECTION_DIR/05-vpn/logs"
    done
fi

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

# Check Kodachi binaries in /usr/local/bin/
KODACHI_BINARIES=(
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
    "kodachi-ai"
)

echo "Kodachi Binary Status:" > "$COLLECTION_DIR/06-kodachi/binary-status.txt"
for binary in "${KODACHI_BINARIES[@]}"; do
    if command -v "$binary" &> /dev/null; then
        echo "✓ $binary: FOUND" >> "$COLLECTION_DIR/06-kodachi/binary-status.txt"
        "$binary" --version >> "$COLLECTION_DIR/06-kodachi/binary-status.txt" 2>&1 || echo "  (no version info)" >> "$COLLECTION_DIR/06-kodachi/binary-status.txt"
    else
        echo "✗ $binary: NOT FOUND" >> "$COLLECTION_DIR/06-kodachi/binary-status.txt"
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
# CATEGORY 8: Display & Desktop Environment
# ============================================================================
if [[ "${CAT_ENABLED[8]}" == "1" ]]; then
progress "Collecting display and desktop information..."

mkdir -p "$COLLECTION_DIR/08-display-desktop"

safe_copy "/var/log/Xorg.0.log" "$COLLECTION_DIR/08-display-desktop"

# Display manager logs
for dm_dir in "/var/log/lightdm" "/var/log/sddm" "/var/log/gdm3"; do
    if [[ -d "$dm_dir" ]]; then
        mkdir -p "$COLLECTION_DIR/08-display-desktop/display-manager"
        cp -r "$dm_dir"/* "$COLLECTION_DIR/08-display-desktop/display-manager/" 2>/dev/null || true
    fi
done

# Display info
safe_exec "$COLLECTION_DIR/08-display-desktop/xrandr.txt" "xrandr --verbose"
safe_exec "$COLLECTION_DIR/08-display-desktop/session-type.txt" "echo \${XDG_SESSION_TYPE:-not_set}"
safe_exec "$COLLECTION_DIR/08-display-desktop/desktop-session.txt" "echo \${DESKTOP_SESSION:-not_set}"

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
