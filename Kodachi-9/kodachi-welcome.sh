#!/bin/bash

# Kodachi Welcome Script - Login Session Information Display
# ===========================================================
#
# SPDX-License-Identifier: LicenseRef-Kodachi-SAN-1.0
# Copyright (c) 2013-2025 Warith Al Maawali
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
# Last updated: 2025-10-21
#
# Description:
# This script displays system status, security information, and network details
# when users log in to Kodachi OS. Optimized for 80x24 terminal resolution.
# Provides interactive menu for executing common system profiles and workflows.
#
# Links:
# - Website: https://www.digi77.com
# - Website: https://www.kodachi.cloud
# - GitHub: https://github.com/WMAL
# - Discord: https://discord.gg/KEFErEx
# - LinkedIn: https://www.linkedin.com/in/warith1977
# - X (Twitter): https://x.com/warith2020
#
# Installation:
#   sudo cp kodachi-welcome.sh /etc/profile.d/kodachi-welcome.sh
#   sudo chmod +x /etc/profile.d/kodachi-welcome.sh
#
# Usage:
#   Automatically runs on login for interactive shell sessions.
#   To skip: export KODACHI_SKIP_WELCOME=1 before login
#
# Features:
#   - Binary deployment verification
#   - Online authentication status
#   - DNSCrypt configuration
#   - Network and system information display
#   - Security score and hardening status
#   - Cryptocurrency prices and news headlines
#   - Interactive profile menu for system workflows

# Skip if environment variable is set
if [ "$KODACHI_SKIP_WELCOME" = "1" ]; then
    return 0 2>/dev/null || exit 0
fi

# Skip if not interactive
if [[ $- != *i* ]]; then
    return 0 2>/dev/null || exit 0
fi

# Color codes for compact display (optimized for black terminal)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;36m'     # Bright cyan (was dark blue - invisible on black terminal)
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Kodachi version and website
KODACHI_VERSION="9.0.1"
KODACHI_WEBSITE="kodachi.cloud"

# Detect real user home directory (even when running with sudo)
if [ -n "$SUDO_USER" ]; then
    REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    REAL_HOME="$HOME"
fi

# Global variable to store actual DNS mode (verified, not assumed)
ACTUAL_DNS_MODE="Unknown"

# Global variables for consolidated status display
DEPLOY_STATUS=""
AUTH_STATUS=""
DNS_STATUS_MSG=""
INFO_STATUS=""
PERM_GUARD_STATUS=""
PROFILE_COUNT=""
LOGS_COUNT=""
BINARIES_COUNT=""
LATEST_VERSION=""
CRYPTO_PRICES=""
NEWS_HEADLINES=""

# Hooks directory
HOOKS_DIR=""

# Function to check if jq is available
check_jq() {
    command -v jq >/dev/null 2>&1
}

# Function to parse JSON with fallback
parse_json() {
    local json="$1"
    local key="$2"

    if check_jq; then
        echo "$json" | jq -r "$key" 2>/dev/null | head -1
    else
        # Fallback to grep/sed
        echo "$json" | grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed 's/.*"\([^"]*\)"$/\1/' | head -1
    fi
}

# Function to display compact header
show_header() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}${BOLD}  Linux Kodachi ${KODACHI_VERSION} - Privacy & Security OS - ${KODACHI_WEBSITE} | digi77.com    ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Function to verify hooks directory structure
verify_hooks_structure() {
    local dir="$1"

    # Count how many core binaries exist in this directory
    local binary_count=0
    local core_binaries=("health-control" "ip-fetch" "tor-switch" "online-auth" "dns-switch" "global-launcher")

    for binary in "${core_binaries[@]}"; do
        [ -f "$dir/$binary" ] && [ -x "$dir/$binary" ] && ((binary_count++))
    done

    # Need at least 3 core binaries to be considered valid hooks directory
    [ $binary_count -lt 3 ] && return 1

    # Should have at least one of these essential subdirectories
    [ -d "$dir/config" ] || [ -d "$dir/logs" ] || [ -d "$dir/tmp" ] || [ -d "$dir/results" ]
}

# Function to search for binaries in home directory (fallback)
search_binaries_in_home() {
    echo -e "${CYAN}▸ Searching for binaries in home directory...${NC}"

    # Strategy 1: Quick search for directories with multiple core binaries (any depth up to 5)
    # Check multiple depth levels with glob patterns
    local depth_patterns=(
        "$REAL_HOME/*"
        "$REAL_HOME/*/*"
        "$REAL_HOME/*/*/*"
        "$REAL_HOME/*/*/*/*"
        "$REAL_HOME/*/*/*/*/*"
    )

    local best_dir=""
    local best_count=0

    for pattern in "${depth_patterns[@]}"; do
        for dir in $pattern; do
            # Only check directories
            [ ! -d "$dir" ] && continue

            # Skip known trash/backup/system directories
            if echo "$dir" | grep -qE "(trash-bin|backup|archive|\.Trash|/old/|-old|-before-|/cache/|/chroot/|/bootstrap/|\.git/)"; then
                continue
            fi

            # Quick check: does it have at least one core binary?
            if [ -f "$dir/health-control" ] || [ -f "$dir/global-launcher" ] || [ -f "$dir/ip-fetch" ]; then
                # Verify full structure
                if verify_hooks_structure "$dir"; then
                    # Count binaries to find the best match
                    local count=$(find "$dir" -maxdepth 1 -type f -executable ! -name "*.sh" 2>/dev/null | wc -l)

                    # Pick directory with most binaries
                    if [ $count -gt $best_count ]; then
                        best_count=$count
                        best_dir="$dir"
                    fi
                fi
            fi
        done

        # If we found a good match (5+ binaries), use it immediately
        if [ -n "$best_dir" ] && [ $best_count -ge 5 ]; then
            HOOKS_DIR="$best_dir"
            echo -e "${GREEN}+ Found binaries at: ${HOOKS_DIR}${NC}"
            return 0
        fi
    done

    # If we found any valid directory (even with fewer binaries), use it
    if [ -n "$best_dir" ] && [ $best_count -ge 3 ]; then
        HOOKS_DIR="$best_dir"
        echo -e "${GREEN}+ Found binaries at: ${HOOKS_DIR}${NC}"
        return 0
    fi

    # Strategy 2: Search for dashboard/hooks pattern with timeout (medium depth)
    local hooks_dirs=$(timeout 10 find "$REAL_HOME" -maxdepth 4 -type d -name "hooks" -path "*/dashboard/hooks" \
        ! -path "*/trash-bin/*" \
        ! -path "*/backup/*" \
        ! -path "*/archive/*" \
        ! -path "*/.Trash/*" \
        ! -path "*/old/*" \
        ! -path "*-old/*" \
        ! -path "*-before-*" \
        ! -path "*/chroot/*" \
        ! -path "*/cache/*" \
        ! -path "*/bootstrap/*" \
        2>/dev/null)

    # Find the best match by counting binaries
    local best_dir=""
    local best_count=0

    for dir in $hooks_dirs; do
        if verify_hooks_structure "$dir"; then
            local count=$(find "$dir" -maxdepth 1 -type f -executable ! -name "*.sh" 2>/dev/null | wc -l)

            if [ $count -gt $best_count ]; then
                best_count=$count
                best_dir="$dir"
            fi
        fi
    done

    if [ -n "$best_dir" ] && [ $best_count -ge 3 ]; then
        HOOKS_DIR="$best_dir"
        echo -e "${GREEN}+ Found binaries at: ${HOOKS_DIR}${NC}"
        return 0
    fi

    # Strategy 3: Search for core binaries (broader search with timeout)
    local core_binaries=("health-control" "global-launcher" "ip-fetch")

    for binary_name in "${core_binaries[@]}"; do
        local found_binary=$(timeout 10 find "$REAL_HOME" -maxdepth 5 -name "$binary_name" -type f -executable \
            ! -path "*/trash-bin/*" \
            ! -path "*/backup/*" \
            ! -path "*/archive/*" \
            ! -path "*/chroot/*" \
            ! -path "*/cache/*" \
            2>/dev/null | head -1)

        if [ -n "$found_binary" ]; then
            local binary_dir=$(dirname "$found_binary")

            if verify_hooks_structure "$binary_dir"; then
                HOOKS_DIR="$binary_dir"
                echo -e "${GREEN}+ Found binaries at: ${HOOKS_DIR}${NC}"
                return 0
            fi
        fi
    done

    # Not found
    HOOKS_DIR=""
    return 1
}

# Function to detect hooks directory
detect_hooks_dir() {
    echo -e "${CYAN}▸ Detecting binaries location...${NC}"

    # Check current directory first
    if [ -f "./global-launcher" ] && verify_hooks_structure "."; then
        HOOKS_DIR="$(pwd)"
        echo -e "${GREEN}+ Found binaries at: ${HOOKS_DIR}${NC}"
        return 0
    fi

    # Search for health-control in home directory (PRIMARY METHOD)
    if search_binaries_in_home; then
        return 0
    fi

    # Last resort: Hooks directory not found
    echo -e "${YELLOW}! Hooks directory not found, using system binaries only${NC}"
    HOOKS_DIR=""
    return 1
}

# Function to deploy binaries (OPTIONAL - only for development/testing)
deploy_binaries() {
    # Try to detect hooks directory
    if ! detect_hooks_dir; then
        # No hooks directory found - this is normal for ISO users!
        # Binaries are installed system-wide in /usr/local/bin
        DEPLOY_STATUS="${GREEN}[GDeploy:N/A]${NC}"
        return 0
    fi

    # Hooks directory found - try to deploy/verify
    cd "$HOOKS_DIR" || {
        DEPLOY_STATUS="${YELLOW}[GDeploy:N/A]${NC}"
        return 0  # Not a fatal error
    }

    # Verify binaries in hooks directory
    if [ -f "./global-launcher" ]; then
        if ./global-launcher verify >/dev/null 2>&1; then
            DEPLOY_STATUS="${GREEN}[GDeploy:+]${NC}"
            return 0
        fi

        # Need to deploy
        if sudo ./global-launcher deploy >/dev/null 2>&1; then
            DEPLOY_STATUS="${GREEN}[GDeploy:+]${NC}"
            return 0
        else
            DEPLOY_STATUS="${YELLOW}[GDeploy:!]${NC}"
            return 0  # Not fatal - binaries still in /usr/local/bin
        fi
    else
        # No global-launcher - using system binaries
        DEPLOY_STATUS="${GREEN}[GDeploy:N/A]${NC}"
        return 0
    fi
}

# Function to authenticate silently
authenticate() {
    # CHECK FIRST if already logged in
    LOGIN_CHECK=$(sudo online-auth check-login --json 2>/dev/null)
    IS_LOGGED_IN=$(parse_json "$LOGIN_CHECK" ".data.is_logged_in")

    if [ "$IS_LOGGED_IN" = "true" ]; then
        # Already logged in - store status
        AUTH_STATUS="${GREEN}[Auth:+]${NC}"
        return 0
    fi

    # NOT logged in - authenticate now
    sudo online-auth authenticate --relogin >/dev/null 2>&1

    # Verify it worked
    LOGIN_CHECK=$(sudo online-auth check-login --json 2>/dev/null)
    IS_LOGGED_IN=$(parse_json "$LOGIN_CHECK" ".data.is_logged_in")

    if [ "$IS_LOGGED_IN" = "true" ]; then
        AUTH_STATUS="${GREEN}[Auth:+]${NC}"
        return 0
    else
        # Failed - print error immediately
        echo -e "${RED}✗ Authentication FAILED - Not logged in${NC}"
        AUTH_STATUS="${RED}[Auth:✗]${NC}"
        return 1
    fi
}

# Function to configure DNSCrypt
setup_dnscrypt() {
    # Get DNSCrypt status
    DNSCRYPT_CHECK=$(sudo dns-switch dnscrypt --json 2>/dev/null)

    # Parse all critical fields
    DNSCRYPT_STATUS=$(parse_json "$DNSCRYPT_CHECK" ".data.status")
    SERVICE_ACTIVE=$(parse_json "$DNSCRYPT_CHECK" ".data.service_active")
    CONFIGURED_AS_RESOLVER=$(parse_json "$DNSCRYPT_CHECK" ".data.configured_as_resolver")
    LISTENING=$(parse_json "$DNSCRYPT_CHECK" ".data.listening")

    # Check if DNSCrypt is FULLY operational (all 3 conditions must be true)
    if [ "$DNSCRYPT_STATUS" = "success" ] && \
       [ "$SERVICE_ACTIVE" = "true" ] && \
       [ "$CONFIGURED_AS_RESOLVER" = "true" ] && \
       [ "$LISTENING" = "true" ]; then
        # All checks passed - DNSCrypt is fully operational
        ACTUAL_DNS_MODE="127.0.0.1 (DNSCrypt)"
        DNS_STATUS_MSG="${GREEN}[SDNS:+]${NC}"
        return 0
    fi

    # DNSCrypt is not fully operational - attempt to fix
    echo -e "${YELLOW}! DNSCrypt needs configuration...${NC}"

    # If service is not active, start it first
    if [ "$SERVICE_ACTIVE" != "true" ]; then
        echo "  • Starting DNSCrypt service..."
        sudo systemctl start dnscrypt-proxy >/dev/null 2>&1
        sleep 2
    fi

    # If not configured as resolver or not listening, configure it
    if [ "$CONFIGURED_AS_RESOLVER" != "true" ] || [ "$LISTENING" != "true" ]; then
        echo "  • Configuring DNSCrypt as DNS resolver..."
        sudo dns-switch switch --names dnscrypt >/dev/null 2>&1
        sleep 1
    fi

    # Verify the fix
    DNSCRYPT_CHECK=$(sudo dns-switch dnscrypt --json 2>/dev/null)
    DNSCRYPT_STATUS=$(parse_json "$DNSCRYPT_CHECK" ".data.status")
    SERVICE_ACTIVE=$(parse_json "$DNSCRYPT_CHECK" ".data.service_active")
    CONFIGURED_AS_RESOLVER=$(parse_json "$DNSCRYPT_CHECK" ".data.configured_as_resolver")
    LISTENING=$(parse_json "$DNSCRYPT_CHECK" ".data.listening")

    # Get actual nameservers for fallback display
    DNS_STATUS=$(sudo dns-switch status --json 2>/dev/null)
    if check_jq; then
        NAMESERVERS=$(echo "$DNS_STATUS" | jq -r '.data.nameservers[]' 2>/dev/null | tr '\n' ', ' | sed 's/, $//')
    else
        NAMESERVERS=$(echo "$DNS_STATUS" | grep -o '"nameservers":\[[^]]*\]' | sed 's/.*\[\(.*\)\].*/\1/' | tr -d '"' | tr ',' ' ')
    fi

    # Check if all conditions are now met
    if [ "$DNSCRYPT_STATUS" = "success" ] && \
       [ "$SERVICE_ACTIVE" = "true" ] && \
       [ "$CONFIGURED_AS_RESOLVER" = "true" ] && \
       [ "$LISTENING" = "true" ]; then
        echo -e "${GREEN}  + DNSCrypt configured successfully${NC}"
        ACTUAL_DNS_MODE="127.0.0.1 (DNSCrypt)"
        DNS_STATUS_MSG="${GREEN}[SDNS:+]${NC}"
        return 0
    else
        # Configuration failed - provide detailed status
        echo -e "${RED}  ✗ DNSCrypt configuration failed${NC}"
        echo "    Status: service_active=$SERVICE_ACTIVE, configured=$CONFIGURED_AS_RESOLVER, listening=$LISTENING"
        ACTUAL_DNS_MODE="${NAMESERVERS:-Unknown}"
        DNS_STATUS_MSG="${RED}[SDNS:✗]${NC}"
        return 1
    fi
}

# Function to count profiles
count_profiles() {
    # Only count if hooks directory exists
    if [ -n "$HOOKS_DIR" ] && [ -d "$HOOKS_DIR/config/profiles" ]; then
        local count=$(ls -1 "$HOOKS_DIR/config/profiles"/*.json 2>/dev/null | wc -l)
        PROFILE_COUNT="${CYAN}Profiles: ${count}${NC}"
        PROFILE_COUNT_RAW="$count"
    else
        # Hooks directory not found - skip profile counting (normal for ISO users)
        PROFILE_COUNT=""
        PROFILE_COUNT_RAW="0"
    fi
}

# Function to count log files
count_logs() {
    # Only count if hooks directory exists
    if [ -n "$HOOKS_DIR" ] && [ -d "$HOOKS_DIR/logs" ]; then
        # Count only FILES, not folders
        local count=$(find "$HOOKS_DIR/logs" -maxdepth 1 -type f 2>/dev/null | wc -l)
        LOGS_COUNT="${CYAN}Logs: ${count}${NC}"
    else
        # Hooks directory not found - skip log counting (normal for ISO users)
        LOGS_COUNT=""
    fi
}

# Function to count binaries
count_binaries() {
    # Only count if hooks directory exists
    if [ -n "$HOOKS_DIR" ] && [ -d "$HOOKS_DIR" ]; then
        # Count executable binary files in hooks directory (actual deployed binaries)
        local count=$(find "$HOOKS_DIR" -maxdepth 1 -type f -executable ! -name "*.sh" ! -name ".*" 2>/dev/null | wc -l)
        BINARIES_COUNT="${CYAN}Binaries: ${count}${NC}"
    else
        # Hooks directory not found - skip binary counting (normal for ISO users)
        BINARIES_COUNT=""
    fi
}

# Function to check permission guard status
check_permission_guard() {
    local PERM_JSON=$(sudo permission-guard status --json 2>/dev/null)
    local STATUS=$(parse_json "$PERM_JSON" ".data.status" || echo "")

    if [ "$STATUS" = "ok" ]; then
        PERM_GUARD_STATUS="${GREEN}[PermG:+]${NC}"
    else
        PERM_GUARD_STATUS="${RED}[PermG:✗]${NC}"
    fi
}

# Function to fetch latest version
fetch_latest_version() {
    local RELEASE_JSON=$(sudo online-info-switch releases --json 2>/dev/null)
    local MAIN_VERSION=$(parse_json "$RELEASE_JSON" ".terminal.main_version" || echo "N/A")
    local NIGHTLY_VERSION=$(parse_json "$RELEASE_JSON" ".terminal.nightly_version" || echo "")

    # Build version string
    if [ "$MAIN_VERSION" != "N/A" ] && [ -n "$MAIN_VERSION" ]; then
        LATEST_VERSION="${CYAN}Main: ${MAIN_VERSION}${NC}"

        # Add nightly version if available
        if [ -n "$NIGHTLY_VERSION" ] && [ "$NIGHTLY_VERSION" != "null" ]; then
            LATEST_VERSION="${LATEST_VERSION} | ${CYAN}Nbuild: ${NIGHTLY_VERSION}${NC}"
        fi
    else
        LATEST_VERSION="${YELLOW}Main: N/A${NC}"
    fi
}

# Function to fetch cryptocurrency prices
fetch_crypto_prices() {
    local CRYPTO_JSON=$(sudo online-info-switch price all --json 2>/dev/null)

    if check_jq && [ -n "$CRYPTO_JSON" ]; then
        local BTC=$(echo "$CRYPTO_JSON" | jq -r '.prices[] | select(.coin=="BTC") | .price_usd' 2>/dev/null | cut -d. -f1 || echo "N/A")
        local ETH=$(echo "$CRYPTO_JSON" | jq -r '.prices[] | select(.coin=="ETH") | .price_usd' 2>/dev/null | cut -d. -f1 || echo "N/A")
        local XMR=$(echo "$CRYPTO_JSON" | jq -r '.prices[] | select(.coin=="XMR") | .price_usd' 2>/dev/null | cut -d. -f1 || echo "N/A")
        local AZERO=$(echo "$CRYPTO_JSON" | jq -r '.prices[] | select(.coin=="AZERO") | .price_usd' 2>/dev/null || echo "N/A")

        # Format AZERO to 2 decimal places if numeric
        if [[ "$AZERO" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            AZERO=$(printf "%.2f" "$AZERO")
        fi

        CRYPTO_PRICES="${BOLD}BTC:${NC} ${GREEN}\$${BTC}${NC} | ${BOLD}ETH:${NC} ${GREEN}\$${ETH}${NC} | ${BOLD}XMR:${NC} ${GREEN}\$${XMR}${NC} | ${BOLD}AZERO:${NC} ${GREEN}\$${AZERO}${NC}"
    else
        CRYPTO_PRICES="${YELLOW}Crypto prices unavailable${NC}"
    fi
}

# Function to fetch news headlines
fetch_news_headlines() {
    local NEWS_JSON=$(sudo online-info-switch rss --random --max-items 2 --json 2>/dev/null)

    if check_jq && [ -n "$NEWS_JSON" ]; then
        # Get first 2 headlines and add ellipsis if truncated (max 71 chars + "...")
        local HEADLINE1=$(echo "$NEWS_JSON" | jq -r '.items[0].title' 2>/dev/null || echo "")
        local HEADLINE2=$(echo "$NEWS_JSON" | jq -r '.items[1].title' 2>/dev/null || echo "")

        # Truncate with ellipsis if too long
        if [ -n "$HEADLINE1" ] && [ "$HEADLINE1" != "null" ]; then
            if [ ${#HEADLINE1} -gt 71 ]; then
                HEADLINE1="${HEADLINE1:0:71}..."
            fi
        fi

        if [ -n "$HEADLINE2" ] && [ "$HEADLINE2" != "null" ]; then
            if [ ${#HEADLINE2} -gt 71 ]; then
                HEADLINE2="${HEADLINE2:0:71}..."
            fi
        fi

        if [ -n "$HEADLINE1" ] && [ "$HEADLINE1" != "null" ]; then
            NEWS_HEADLINES="${BOLD}•${NC} ${CYAN}${HEADLINE1}${NC}"
            if [ -n "$HEADLINE2" ] && [ "$HEADLINE2" != "null" ]; then
                NEWS_HEADLINES="${NEWS_HEADLINES}\n${BOLD}•${NC} ${CYAN}${HEADLINE2}${NC}"
            fi
        else
            NEWS_HEADLINES="${YELLOW}No news available${NC}"
        fi
    else
        NEWS_HEADLINES="${YELLOW}No news available${NC}"
    fi
}

# Function to fetch and parse system information
fetch_system_info() {
    # Fetch IP information
    IP_JSON=$(sudo ip-fetch --json 2>/dev/null | tail -1)
    IP_ADDR=$(parse_json "$IP_JSON" ".data.records[0].ip" || echo "N/A")
    COUNTRY=$(parse_json "$IP_JSON" ".data.records[0].country_name" || echo "N/A")
    CITY=$(parse_json "$IP_JSON" ".data.records[0].city" || echo "N/A")

    # Fetch Tor status with dynamic color
    TOR_CHECK=$(sudo ip-fetch check-tor --json 2>/dev/null)
    IS_TOR=$(parse_json "$TOR_CHECK" ".IsTor" || echo "false")
    if [ "$IS_TOR" = "true" ]; then
        TOR_STATUS="${GREEN}+ Tor${NC}"        # Green when using Tor
    else
        TOR_STATUS="${RED}✗ Direct${NC}"      # Red when NOT using Tor
    fi

    # Fetch network connection status
    # Unified color scheme: RED for no VPN, GREEN for connected
    ROUTING_JSON=$(sudo routing-switch status --json 2>/dev/null)
    CONNECTED=$(parse_json "$ROUTING_JSON" ".data.connected" || echo "false")
    PROTOCOL=$(parse_json "$ROUTING_JSON" ".data.protocol" || echo "none")
    if [ "$CONNECTED" = "true" ]; then
        NET_STATUS="${GREEN}${PROTOCOL}${NC}"
    else
        NET_STATUS="${RED}No VPN${NC}"
    fi

    # Fetch hardening verification
    HARDENING_JSON=$(sudo health-control security-verify --json 2>/dev/null)
    if check_jq; then
        HARDENED=$(echo "$HARDENING_JSON" | jq '[.data.modules[] | select(.hardening_status == "hardened")] | length' 2>/dev/null || echo "?")
        TOTAL=$(echo "$HARDENING_JSON" | jq '.data.modules | length' 2>/dev/null || echo "?")
    else
        HARDENED="?"
        TOTAL="?"
    fi
    HARDENING_STATUS="${HARDENED}/${TOTAL} Modules"

    # Fetch security score
    SCORE_JSON=$(sudo health-control security-score --json 2>/dev/null)
    SEC_SCORE=$(parse_json "$SCORE_JSON" ".data.total_score" || echo "N/A")
    SEC_STATUS=$(parse_json "$SCORE_JSON" ".data.security_level" || echo "UNKNOWN")

    # Fetch hostname
    HOST_JSON=$(sudo health-control get-hostname --json 2>/dev/null)
    HOSTNAME=$(parse_json "$HOST_JSON" ".data.hostname" || echo "N/A")

    # Fetch timezone
    TZ_JSON=$(sudo health-control show-timezone --json 2>/dev/null)
    TIMEZONE=$(parse_json "$TZ_JSON" ".data.timezone" || echo "N/A")

    # Fetch MAC address (first interface only)
    MAC_JSON=$(sudo health-control mac-show-macs --json 2>/dev/null)
    MAC_ADDR=$(parse_json "$MAC_JSON" ".data.interfaces[0].mac_address" || echo "N/A")

    # Store status
    INFO_STATUS="${GREEN}[Net:+]${NC}"
}

# Function to display system info compactly
display_info() {
    echo ""
    echo -e "${BOLD}SYSTEM STATUS:${NC}"
    echo -e "${CYAN}────────────────────────────────────────────────────────────────────────────${NC}"

    # Security score with color based on value (handle both int and float)
    # Unified color scheme: RED for bad (<60), GREEN for good (≥60)
    if [[ "$SEC_SCORE" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        # Convert to integer for comparison (drop decimal part)
        SCORE_INT=$(echo "$SEC_SCORE" | cut -d. -f1)
        if [ "$SCORE_INT" -ge 60 ]; then
            SCORE_COLOR="${GREEN}"
        else
            SCORE_COLOR="${RED}"
        fi
    else
        SCORE_COLOR="${RED}"
    fi

    # Show ACTUAL DNS mode (verified, not hardcoded)
    # Truncate DNS mode if too long
    DNS_DISPLAY=$(echo "$ACTUAL_DNS_MODE" | cut -c1-25)

    # Line 1: Security Score | Hardening | Torrified Status
    echo -e "${BOLD}Security:${NC} ${SCORE_COLOR}${SEC_SCORE}/100 [${SEC_STATUS}]${NC} | ${BOLD}Hardening:${NC} ${GREEN}${HARDENING_STATUS}${NC} | ${BOLD}Torrified:${NC} ${TOR_STATUS}"

    # Line 2: Network Connection | DNS (colors already applied in variables)
    echo -e "${BOLD}Network:${NC} ${NET_STATUS} | ${BOLD}DNS:${NC} ${GREEN}${DNS_DISPLAY}${NC}"

    # Line 3: IP, Country, City (neutral colors)
    echo -e "${BOLD}IP:${NC} ${CYAN}${IP_ADDR}${NC} | ${BOLD}Country:${NC} ${CYAN}${COUNTRY}${NC} | ${BOLD}City:${NC} ${CYAN}${CITY}${NC}"

    # Line 4: Hostname, MAC, Timezone (neutral colors)
    echo -e "${BOLD}Hostname:${NC} ${CYAN}${HOSTNAME}${NC} | ${BOLD}MAC:${NC} ${CYAN}${MAC_ADDR}${NC} | ${BOLD}TZ:${NC} ${CYAN}${TIMEZONE}${NC}"

    echo ""
    # Crypto prices line
    echo -e "${BOLD}CRYPTO PRICES:${NC}"
    echo -e "${CRYPTO_PRICES}"

    echo ""
    # News headlines
    echo -e "${BOLD}LATEST NEWS:${NC}"
    echo -e "${NEWS_HEADLINES}"

    echo -e "${CYAN}────────────────────────────────────────────────────────────────────────────${NC}"
    echo ""
}

# Function to display profile menu
show_menu() {
    echo -e "${BOLD}SELECT PROFILE:${NC}"
    echo ""
    echo -e " ${GREEN}[1]${NC} ${BOLD}WireGuard Setup:${NC} ${CYAN}→${NC} Auth ${CYAN}→${NC} Status ${CYAN}→${NC} Harden ${CYAN}→${NC} WireGuard ${CYAN}→${NC} Verify"
    echo -e " ${GREEN}[2]${NC} ${BOLD}Xray-VLESS-Reality:${NC} ${CYAN}→${NC} Auth ${CYAN}→${NC} Status ${CYAN}→${NC} Harden ${CYAN}→${NC} Connect ${CYAN}→${NC} Verify"
    echo -e " ${GREEN}[3]${NC} ${BOLD}OpenVPN Setup:${NC} ${CYAN}→${NC} Auth ${CYAN}→${NC} Status ${CYAN}→${NC} Harden ${CYAN}→${NC} OpenVPN ${CYAN}→${NC} Verify"
    echo -e " ${GREEN}[4]${NC} ${BOLD}V2Ray Setup:${NC} ${CYAN}→${NC} Auth ${CYAN}→${NC} Status ${CYAN}→${NC} Harden ${CYAN}→${NC} V2Ray ${CYAN}→${NC} Verify"
    echo -e " ${GREEN}[5]${NC} ${BOLD}Hysteria2 Setup:${NC} ${CYAN}→${NC} Auth ${CYAN}→${NC} Status ${CYAN}→${NC} Harden ${CYAN}→${NC} Hysteria2 ${CYAN}→${NC} Verify"
    echo -e " ${GREEN}[6]${NC} ${BOLD}Xray-VLESS Setup:${NC} ${CYAN}→${NC} Auth ${CYAN}→${NC} Status ${CYAN}→${NC} Harden ${CYAN}→${NC} Xray-VLESS ${CYAN}→${NC} Verify"
    echo -e " ${GREEN}[7]${NC} ${BOLD}Xray-Trojan Setup:${NC} ${CYAN}→${NC} Auth ${CYAN}→${NC} Status ${CYAN}→${NC} Harden ${CYAN}→${NC} Xray-Trojan ${CYAN}→${NC} Verify"
    echo -e " ${GREEN}[8]${NC} ${BOLD}Mita Setup:${NC} ${CYAN}→${NC} Auth ${CYAN}→${NC} Status ${CYAN}→${NC} Harden ${CYAN}→${NC} Mita ${CYAN}→${NC} Verify"
    echo -e " ${GREEN}[9]${NC} ${BOLD}Torrify Only:${NC} ${CYAN}→${NC} Auth ${CYAN}→${NC} Net Check ${CYAN}→${NC} Torrify ${CYAN}→${NC} Verify"
    echo -e " ${GREEN}[10]${NC} ${BOLD}WireGuard+Torrify:${NC} ${CYAN}→${NC} Auth ${CYAN}→${NC} Harden ${CYAN}→${NC} Connect ${CYAN}→${NC} Torrify ${CYAN}→${NC} Verify"
    echo -e " ${GREEN}[11]${NC} ${BOLD}Exit${NC} - Skip to shell (Return: type ${CYAN}'kodachi'${NC} and press Enter)"
    echo ""
    echo -e "${YELLOW}NOTE:${NC} ${CYAN}health-control -e${NC}, ${CYAN}routing-switch -e${NC} | ${PROFILE_COUNT_RAW}+ profiles: ${CYAN}workflow-manager list${NC}"
    echo -e "${YELLOW}TIP:${NC} MicroSOCKS: ${CYAN}routing-switch microsocks-enable -u USER -p PASS${NC}"
    echo ""
    echo -ne "${BOLD}Enter choice [1-11]:${NC} "
}

# Function to execute selected profile
execute_profile() {
    local choice="$1"

    case "$choice" in
        1)
            echo -e "\n${YELLOW}Running WireGuard Setup...${NC}\n"
            sudo workflow-manager run initial_terminal_setup_wireguard_only
            ;;
        2)
            echo -e "\n${YELLOW}Running Xray-VLESS-Reality Setup...${NC}\n"
            sudo workflow-manager run initial_terminal_setup_xray_vless_reality_only
            ;;
        3)
            echo -e "\n${YELLOW}Running OpenVPN Setup...${NC}\n"
            sudo workflow-manager run initial_terminal_setup_openvpn_only
            ;;
        4)
            echo -e "\n${YELLOW}Running V2Ray Setup...${NC}\n"
            sudo workflow-manager run initial_terminal_setup_v2ray_only
            ;;
        5)
            echo -e "\n${YELLOW}Running Hysteria2 Setup...${NC}\n"
            sudo workflow-manager run initial_terminal_setup_hysteria2_only
            ;;
        6)
            echo -e "\n${YELLOW}Running Xray-VLESS Setup...${NC}\n"
            sudo workflow-manager run initial_terminal_setup_xray_vless_only
            ;;
        7)
            echo -e "\n${YELLOW}Running Xray-Trojan Setup...${NC}\n"
            sudo workflow-manager run initial_terminal_setup_xray_trojan_only
            ;;
        8)
            echo -e "\n${YELLOW}Running Mita Setup...${NC}\n"
            sudo workflow-manager run initial_terminal_setup_mita_only
            ;;
        9)
            echo -e "\n${YELLOW}Running Torrify Only Setup...${NC}\n"
            sudo workflow-manager run initial_terminal_setup_auth_torrify_only
            ;;
        10)
            echo -e "\n${YELLOW}Running WireGuard + Torrify Setup...${NC}\n"
            sudo workflow-manager run initial_terminal_setup_wireguard_torrify
            ;;
        11)
            echo -e "\n${GREEN}Continuing to shell...${NC}\n"
            return 0
            ;;
        *)
            echo -e "\n${RED}Invalid choice. Continuing to shell...${NC}\n"
            return 1
            ;;
    esac
}

# Main execution
main() {
    # Display header
    show_header

    # Deploy binaries (detect_hooks_dir will print status)
    deploy_binaries

    # Authenticate
    echo -e "${CYAN}▸ Authenticating...${NC}"
    if ! authenticate; then
        echo -e "${YELLOW}! Authentication failed - continuing with limited functionality${NC}"
        # Don't exit - allow script to continue
    fi

    # Setup DNSCrypt
    echo -e "${CYAN}▸ Configuring DNS...${NC}"
    setup_dnscrypt

    # Fetch system information
    echo -e "${CYAN}▸ Fetching system data...${NC}"
    fetch_system_info

    # Count profiles, logs, and binaries
    count_profiles
    count_logs
    count_binaries

    # Check permission guard status
    check_permission_guard

    # Fetch online data
    echo -e "${CYAN}▸ Fetching online data...${NC}"
    fetch_latest_version
    fetch_crypto_prices
    fetch_news_headlines

    echo -e "${GREEN}+ All checks complete!${NC}"
    sleep 0.5

    # Clear and redisplay header
    clear
    show_header

    # Print consolidated status line
    echo -e "${DEPLOY_STATUS} | ${AUTH_STATUS} | ${DNS_STATUS_MSG} | ${INFO_STATUS} | ${PERM_GUARD_STATUS}"

    # Build counts line only if we have hooks directory info
    local counts_line=""
    [ -n "$PROFILE_COUNT" ] && counts_line="${PROFILE_COUNT}"
    [ -n "$LOGS_COUNT" ] && counts_line="${counts_line:+$counts_line | }${LOGS_COUNT}"
    [ -n "$BINARIES_COUNT" ] && counts_line="${counts_line:+$counts_line | }${BINARIES_COUNT}"
    [ -n "$LATEST_VERSION" ] && counts_line="${counts_line:+$counts_line | }${LATEST_VERSION}"

    # Only print counts line if we have something to show
    [ -n "$counts_line" ] && echo -e "$counts_line"

    # Display information
    display_info

    # Show menu and get user choice
    show_menu
    read -r choice

    # Execute selected profile
    execute_profile "$choice"

    echo ""
}

# Run main function
main

# Return to shell
return 0 2>/dev/null || exit 0
