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

# Build signature - UPDATE BUILD_NUM BEFORE CREATING ISO
BUILD_VERSION="9.0.1"
BUILD_NUM="2"  # Change this number before each build (1, 2, 3, etc.)
BUILD_DATE="2025-10-29"  # Auto-updated during ISO creation
SCRIPT_VERSION="${BUILD_VERSION}.${BUILD_NUM}"

# Color codes for compact display (optimized for black terminal)
RED='\033[0;31m'
GREEN='\033[1;32m'    # Lime green for positive/success values
YELLOW='\033[1;35m'   # Bright magenta for progress/working messages
BLUE='\033[1;36m'     # Bright cyan (was dark blue - invisible on black terminal)
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Kodachi version and website
KODACHI_VERSION="9.0.1"
KODACHI_WEBSITE="kodachi.cloud"

# Auto-refresh timeout in seconds (600 = 10 minutes)
# Change this value to adjust auto-refresh interval
AUTO_REFRESH_TIMEOUT=600

# Detect real user home directory (even when running with sudo)
if [ -n "$SUDO_USER" ]; then
    REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    REAL_HOME="$HOME"
fi

# Global variable to store actual DNS mode (verified, not assumed)
ACTUAL_DNS_MODE="Unknown"

# Global variables for Tor DNS verification
TOR_DNS_DIRECT_STATUS="unknown"
TOR_DNS_PORT_STATUS="unknown"
TOR_DNS_OVERALL_STATUS="false"
TOR_DNS_DETAILED=""

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

# Detect if we are running from the live ISO environment
is_live_session() {
    if grep -q "boot=live\|persistent=0\|boot=casper" /proc/cmdline 2>/dev/null; then
        return 0
    fi

    if mount | grep -q "/run/live" 2>/dev/null; then
        return 0
    fi

    if [ -d /run/live/medium ] || [ -d /run/live/rootfs ]; then
        return 0
    fi

    return 1
}

# Ensure installed system has Kodachi GRUB branding applied
ensure_grub_theme() {
    local helper="/usr/local/bin/kodachi-apply-grub-theme"
    local theme_txt="/boot/grub/live-theme/theme.txt"
    local splash_png="/boot/grub/splash.png"
    local cfg_file="/etc/default/grub.d/40-kodachi-theme.cfg"

    echo -e "${CYAN}▸ Checking Kodachi GRUB theme...${NC}"

    # Live sessions do not ship the GRUB helper; skip silently
    if is_live_session; then
        echo -e "${CYAN}▸ Live session detected - skipping GRUB theme check${NC}"
        return 0
    fi

    # Helper only exists on installed systems; warn if missing
    if [ ! -x "$helper" ]; then
        echo -e "${YELLOW}! Theme helper not found (${helper}) - skipping${NC}"
        return 0
    fi

    local needs_fix=0
    [ -f "$theme_txt" ] || needs_fix=1
    [ -f "$splash_png" ] || needs_fix=1
    if [ ! -s "$cfg_file" ] || ! grep -q "live-theme/theme.txt" "$cfg_file" 2>/dev/null; then
        needs_fix=1
    fi

    if [ $needs_fix -eq 1 ]; then
        echo -e "${CYAN}▸ Restoring Kodachi GRUB theme...${NC}"
        if sudo "$helper" >/tmp/kodachi-grub-theme.log 2>&1; then
            echo -e "${GREEN}✓ GRUB theme synchronized${NC}"
        else
            echo -e "${YELLOW}! Unable to apply GRUB theme (see /tmp/kodachi-grub-theme.log)${NC}"
        fi
    else
        echo -e "${GREEN}✓ GRUB theme already applied${NC}"
    fi
}

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
    echo -e "${YELLOW}▸ Searching for binaries in home directory...${NC}"

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
            echo -e "${GREEN}✓ Found binaries at: ${HOOKS_DIR}${NC}"
            return 0
        fi
    done

    # If we found any valid directory (even with fewer binaries), use it
    if [ -n "$best_dir" ] && [ $best_count -ge 3 ]; then
        HOOKS_DIR="$best_dir"
        echo -e "${GREEN}✓ Found binaries at: ${HOOKS_DIR}${NC}"
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
        echo -e "${GREEN}✓ Found binaries at: ${HOOKS_DIR}${NC}"
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
                echo -e "${GREEN}✓ Found binaries at: ${HOOKS_DIR}${NC}"
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
    echo -e "${YELLOW}▸ Detecting binaries location...${NC}"

    # Check current directory first
    if [ -f "./global-launcher" ] && verify_hooks_structure "."; then
        HOOKS_DIR="$(pwd)"
        echo -e "${GREEN}✓ Found binaries at: ${HOOKS_DIR}${NC}"
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

# Helper function to execute commands with fallback to hooks directory
run_command() {
    local cmd="$1"
    local timeout_val="${2:-0}"  # Second arg is timeout (default: 0 = no timeout)
    shift 2
    local args="$@"

    # Build timeout command if specified
    local timeout_cmd=""
    if [ "$timeout_val" -gt 0 ] 2>/dev/null; then
        timeout_cmd="timeout $timeout_val"
    fi

    # If deployment succeeded, use global command
    if [ "$DEPLOY_STATUS" = "${GREEN}[GDeploy:+]${NC}" ]; then
        $timeout_cmd sudo "$cmd" $args
    elif [ -n "$HOOKS_DIR" ] && [ -f "$HOOKS_DIR/$cmd" ]; then
        # Fallback to hooks directory
        $timeout_cmd sudo "$HOOKS_DIR/$cmd" $args
    else
        # Try global command anyway
        $timeout_cmd sudo "$cmd" $args
    fi
}

# Function to deploy binaries with proper verification
deploy_binaries() {
    echo -e "${YELLOW}▸ Checking binary deployment...${NC}"

    # Try to detect hooks directory
    if ! detect_hooks_dir; then
        # No hooks directory found - this is normal for ISO users!
        # Binaries are installed system-wide in /usr/local/bin
        echo -e "${GREEN}✓ Using system-wide binaries${NC}"
        DEPLOY_STATUS="${GREEN}[GDeploy:N/A]${NC}"
        return 0
    fi

    # Hooks directory found - verify we're in it
    cd "$HOOKS_DIR" || {
        echo -e "${YELLOW}! Cannot access hooks directory${NC}"
        DEPLOY_STATUS="${YELLOW}[GDeploy:Local]${NC}"
        return 0  # Not fatal - will use hooks directory directly
    }

    # Check if global-launcher exists
    if [ ! -f "./global-launcher" ]; then
        echo -e "${YELLOW}! global-launcher not found${NC}"
        DEPLOY_STATUS="${GREEN}[GDeploy:N/A]${NC}"
        return 0
    fi

    # First check if already deployed and verified
    echo -e "${GREEN}  • Checking existing deployment...${NC}"
    if ./global-launcher verify --json >/tmp/verify-check.json 2>&1; then
        # Use grep-first approach (reliable, no jq dependency)
        if grep -q '"verification_success":true' /tmp/verify-check.json 2>/dev/null; then
            # Extract count using grep/sed (works without jq)
            local count=$(grep -o '"total_verified":[0-9]*' /tmp/verify-check.json 2>/dev/null | grep -o '[0-9]*' | head -1)

            # Validate we got a count
            if [ -n "$count" ] && [ "$count" -gt 0 ]; then
                echo -e "${GREEN}  ✓ Already deployed ($count binaries verified)${NC}"
                DEPLOY_STATUS="${GREEN}[GDeploy:+]${NC}"
                rm -f /tmp/verify-check.json
                return 0
            fi
        fi
    fi

    # If we reached here, verification failed or returned unexpected data
    # Safe to proceed with deployment

    # Need to deploy
    echo -e "  • Deploying binaries to /usr/local/bin/..."
    if sudo ./global-launcher deploy 2>&1 | tee /tmp/deploy-output.txt; then
        # Deployment command succeeded - now VERIFY it actually worked
        echo -e "  • Verifying deployment..."
        sleep 1

        if ./global-launcher verify --json >/tmp/verify-result.json 2>&1; then
            if check_jq; then
                local verified=$(jq -r '.verification_success // empty' /tmp/verify-result.json 2>/dev/null)
                local count=$(jq -r '.total_verified // empty' /tmp/verify-result.json 2>/dev/null)
                local broken=$(jq -r '.total_broken // empty' /tmp/verify-result.json 2>/dev/null)

                # Check if jq actually returned values (not null/empty)
                if [ -n "$verified" ] && [ -n "$count" ] && [ -n "$broken" ]; then
                    if [ "$verified" = "true" ] && [ "$count" -gt 0 ] && [ "$broken" = "0" ]; then
                        echo -e "${GREEN}  ✓ Deployment successful ($count/$count binaries verified)${NC}"
                        DEPLOY_STATUS="${GREEN}[GDeploy:+]${NC}"
                        rm -f /tmp/verify-result.json /tmp/deploy-output.txt /tmp/verify-check.json
                        return 0
                    else
                        echo -e "${RED}  ✗ Verification failed ($count verified, $broken broken)${NC}"
                        echo -e "${YELLOW}  ! Falling back to local execution from hooks directory${NC}"
                        DEPLOY_STATUS="${YELLOW}[GDeploy:Local]${NC}"
                        rm -f /tmp/verify-result.json /tmp/deploy-output.txt /tmp/verify-check.json
                        return 0
                    fi
                else
                    # jq returned null/empty - fallback to grep
                    if grep -q '"verification_success":true' /tmp/verify-result.json 2>/dev/null; then
                        echo -e "${GREEN}  ✓ Deployment successful (verified via grep)${NC}"
                        DEPLOY_STATUS="${GREEN}[GDeploy:+]${NC}"
                        rm -f /tmp/verify-result.json /tmp/deploy-output.txt /tmp/verify-check.json
                        return 0
                    else
                        echo -e "${RED}  ✗ Verification parsing failed${NC}"
                        echo -e "${YELLOW}  ! Falling back to local execution from hooks directory${NC}"
                        DEPLOY_STATUS="${YELLOW}[GDeploy:Local]${NC}"
                        rm -f /tmp/verify-result.json /tmp/deploy-output.txt /tmp/verify-check.json
                        return 0
                    fi
                fi
            else
                # No jq - check if verify command succeeded
                if grep -q '"verification_success":true' /tmp/verify-result.json 2>/dev/null; then
                    echo -e "${GREEN}  ✓ Deployment successful${NC}"
                    DEPLOY_STATUS="${GREEN}[GDeploy:+]${NC}"
                    rm -f /tmp/verify-result.json /tmp/deploy-output.txt /tmp/verify-check.json
                    return 0
                else
                    echo -e "${RED}  ✗ Verification failed${NC}"
                    echo -e "${YELLOW}  ! Falling back to local execution from hooks directory${NC}"
                    DEPLOY_STATUS="${YELLOW}[GDeploy:Local]${NC}"
                    rm -f /tmp/verify-result.json /tmp/deploy-output.txt /tmp/verify-check.json
                    return 0
                fi
            fi
        else
            echo -e "${RED}  ✗ Verification command failed${NC}"
            echo -e "${YELLOW}  ! Falling back to local execution from hooks directory${NC}"
            DEPLOY_STATUS="${YELLOW}[GDeploy:Local]${NC}"
            rm -f /tmp/verify-result.json /tmp/deploy-output.txt /tmp/verify-check.json
            return 0
        fi
    else
        # Deployment failed
        echo -e "${RED}  ✗ Deployment failed${NC}"
        if [ -f /tmp/deploy-output.txt ]; then
            echo -e "${YELLOW}  ! Error: $(cat /tmp/deploy-output.txt | head -1)${NC}"
        fi
        echo -e "${YELLOW}  ! Falling back to local execution from hooks directory${NC}"
        DEPLOY_STATUS="${YELLOW}[GDeploy:Local]${NC}"
        rm -f /tmp/deploy-output.txt /tmp/verify-check.json
        return 0
    fi
}

# Function to authenticate silently
authenticate() {
    # CHECK FIRST if already logged in (50s timeout)
    LOGIN_CHECK=$(run_command online-auth 50 check-login --json 2>/dev/null)
    IS_LOGGED_IN=$(parse_json "$LOGIN_CHECK" ".data.is_logged_in")

    if [ "$IS_LOGGED_IN" = "true" ]; then
        # Already logged in - store status
        AUTH_STATUS="${GREEN}[Auth:+]${NC}"
        return 0
    fi

    # NOT logged in - authenticate now (50s timeout)
    run_command online-auth 50 authenticate --relogin >/dev/null 2>&1

    # Verify it worked (50s timeout)
    LOGIN_CHECK=$(run_command online-auth 50 check-login --json 2>/dev/null)
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
    # CRITICAL: Reset ALL DNS variables to ensure fresh detection after profile changes
    ACTUAL_DNS_MODE="Unknown"
    DNS_STATUS_MSG=""
    TOR_DNS_DIRECT_STATUS="unknown"
    TOR_DNS_PORT_STATUS="unknown"
    TOR_DNS_OVERALL_STATUS="false"
    TOR_DNS_DETAILED=""

    # STEP 1: Check ACTUAL current DNS (always, no caching)
    DNS_STATUS=$(run_command dns-switch 50 status --json 2>/dev/null)

    # Parse nameservers array
    if check_jq; then
        NAMESERVERS=$(echo "$DNS_STATUS" | jq -r '.data.nameservers[]' 2>/dev/null | tr '\n' ', ' | sed 's/, $//')
    else
        # Fallback parsing without jq
        NAMESERVERS=$(echo "$DNS_STATUS" | grep -o '"nameservers":\[[^]]*\]' | sed 's/.*\[\(.*\)\].*/\1/' | tr -d '"' | sed 's/,/, /g')
    fi

    # Handle empty nameservers
    if [ -z "$NAMESERVERS" ]; then
        echo -e "${RED}  ✗ Failed to detect DNS servers${NC}"
        ACTUAL_DNS_MODE="Unknown"
        DNS_STATUS_MSG="${RED}[SDNS:✗]${NC}"
        return 1
    fi

    # STEP 2: Smart DNSCrypt verification and auto-fix
    # Check if DNSCrypt is running but being bypassed by systemd-resolved

    # Get DNSCrypt service status
    DNSCRYPT_CHECK=$(run_command dns-switch 50 dnscrypt --json 2>/dev/null)
    SERVICE_ACTIVE=$(parse_json "$DNSCRYPT_CHECK" ".data.service_active")
    LISTENING=$(parse_json "$DNSCRYPT_CHECK" ".data.listening")
    CONFIGURED_AS_RESOLVER=$(parse_json "$DNSCRYPT_CHECK" ".data.configured_as_resolver")

    # Check if DNSCrypt is running AND listening but NOT configured as resolver - HIJACKED!
    if [ "$SERVICE_ACTIVE" = "true" ] && [ "$LISTENING" = "true" ] && [ "$CONFIGURED_AS_RESOLVER" != "true" ]; then
        # DNSCrypt is running but NOT configured as resolver - HIJACKED!
        echo -e "${YELLOW}! DNSCrypt is running but NOT configured as resolver (current DNS: $NAMESERVERS)${NC}"
        echo -e "${YELLOW}! Fixing DNSCrypt configuration...${NC}"

        # Re-configure DNSCrypt as resolver (dns-switch handles systemd-resolved automatically)
        echo "  • Configuring DNSCrypt as DNS resolver..."
        run_command dns-switch 50 switch --names dnscrypt >/dev/null 2>&1
        sleep 2

        # Verify fix worked
        DNSCRYPT_CHECK=$(run_command dns-switch 50 dnscrypt --json 2>/dev/null)
        CONFIGURED_AS_RESOLVER=$(parse_json "$DNSCRYPT_CHECK" ".data.configured_as_resolver")

        if [ "$CONFIGURED_AS_RESOLVER" = "true" ]; then
            echo -e "${GREEN}  ✓ DNSCrypt successfully configured as resolver${NC}"
        else
            echo -e "${RED}  ✗ Failed to configure DNSCrypt as resolver${NC}"
        fi

        # Update NAMESERVERS for display
        DNS_STATUS=$(run_command dns-switch 50 status --json 2>/dev/null)
        if check_jq; then
            NAMESERVERS=$(echo "$DNS_STATUS" | jq -r '.data.nameservers[]' 2>/dev/null | tr '\n' ', ' | sed 's/, $//')
        else
            NAMESERVERS=$(echo "$DNS_STATUS" | grep -o '"nameservers":\[[^]]*\]' | sed 's/.*\[\(.*\)\].*/\1/' | tr -d '"' | sed 's/,/, /g')
        fi
    fi

    # STEP 3: Report actual DNS based on verification (always truthful, no caching)
    # This always runs, even on refresh, to detect DNS changes
    # Check for 127.0.0.1 and determine if it's Tor DNS or DNSCrypt
    if echo "$NAMESERVERS" | grep -q "127.0.0.1"; then
        # First check if this is Tor DNS by trying to verify it
        # Tor DNS uses port 9053, so verify-tor-dns will succeed if Tor DNS is active
        verify_tor_dns

        if [ "$TOR_DNS_OVERALL_STATUS" = "true" ]; then
            # Tor DNS is active and both methods successful - GREEN
            # Show detailed status only when fully working
            ACTUAL_DNS_MODE="127.0.0.1:9053 (Tor DNS) ${TOR_DNS_DETAILED}"
            DNS_STATUS_MSG="${GREEN}[SDNS:Tor:✓✓]${NC}"
            return 0
        fi

        # Tor DNS failed - don't show detailed breakdown, just show it's not working

        # Not Tor DNS or Tor DNS failed - check if it's DNSCrypt
        DNSCRYPT_CHECK=$(run_command dns-switch 50 dnscrypt --json 2>/dev/null)
        DNSCRYPT_STATUS=$(parse_json "$DNSCRYPT_CHECK" ".data.status")
        SERVICE_ACTIVE=$(parse_json "$DNSCRYPT_CHECK" ".data.service_active")
        CONFIGURED_AS_RESOLVER=$(parse_json "$DNSCRYPT_CHECK" ".data.configured_as_resolver")
        LISTENING=$(parse_json "$DNSCRYPT_CHECK" ".data.listening")

        if [ "$DNSCRYPT_STATUS" = "success" ] && \
           [ "$SERVICE_ACTIVE" = "true" ] && \
           [ "$CONFIGURED_AS_RESOLVER" = "true" ] && \
           [ "$LISTENING" = "true" ]; then
            # DNSCrypt is fully operational
            ACTUAL_DNS_MODE="127.0.0.1 (DNSCrypt)"
            DNS_STATUS_MSG="${GREEN}[SDNS:+]${NC}"
            return 0
        else
            # 127.0.0.1 configured but neither Tor DNS nor DNSCrypt working
            ACTUAL_DNS_MODE="127.0.0.1 (service not running)"
            DNS_STATUS_MSG="${RED}[SDNS:✗]${NC}"
            return 1
        fi
    else
        # Using direct DNS servers (not DNSCrypt/Tor) - WARNING state
        ACTUAL_DNS_MODE="$NAMESERVERS"
        DNS_STATUS_MSG="${YELLOW}[SDNS:Direct]${NC}"
        return 0
    fi
}

# Function to verify Tor DNS with both direct and port methods
verify_tor_dns() {
    echo -e "${YELLOW}  • Verifying Tor DNS configuration...${NC}"

    # Reset global variables to ensure fresh verification
    TOR_DNS_DIRECT_STATUS="unknown"
    TOR_DNS_PORT_STATUS="unknown"
    TOR_DNS_OVERALL_STATUS="false"
    TOR_DNS_DETAILED=""

    # Call tor-switch verify-tor-dns with 60s timeout
    local TOR_DNS_JSON=$(run_command tor-switch 60 verify-tor-dns --json 2>/dev/null)

    # Parse direct_method and port_method (boolean values)
    if check_jq; then
        TOR_DNS_DIRECT_STATUS=$(echo "$TOR_DNS_JSON" | jq -r '.data.direct_method // "unknown"' 2>/dev/null)
        TOR_DNS_PORT_STATUS=$(echo "$TOR_DNS_JSON" | jq -r '.data.port_method // "unknown"' 2>/dev/null)
    else
        # Fallback parsing without jq
        TOR_DNS_DIRECT_STATUS=$(parse_json "$TOR_DNS_JSON" ".data.direct_method" || echo "unknown")
        TOR_DNS_PORT_STATUS=$(parse_json "$TOR_DNS_JSON" ".data.port_method" || echo "unknown")
    fi

    # Convert boolean values to consistent format
    # Expected values: true, false, or unknown
    if [ "$TOR_DNS_DIRECT_STATUS" = "true" ]; then
        TOR_DNS_DIRECT_STATUS="success"
    elif [ "$TOR_DNS_DIRECT_STATUS" = "false" ]; then
        TOR_DNS_DIRECT_STATUS="failed"
    else
        TOR_DNS_DIRECT_STATUS="failed"
    fi

    if [ "$TOR_DNS_PORT_STATUS" = "true" ]; then
        TOR_DNS_PORT_STATUS="success"
    elif [ "$TOR_DNS_PORT_STATUS" = "false" ]; then
        TOR_DNS_PORT_STATUS="failed"
    else
        TOR_DNS_PORT_STATUS="failed"
    fi

    # Determine overall status (both must succeed for GREEN, direct is critical)
    if [ "$TOR_DNS_DIRECT_STATUS" = "success" ] && [ "$TOR_DNS_PORT_STATUS" = "success" ]; then
        TOR_DNS_OVERALL_STATUS="true"
        TOR_DNS_DETAILED="[Direct:✓ Port:✓]"
        echo -e "${GREEN}  ✓ Tor DNS is active (both methods verified)${NC}"
        return 0
    else
        # Tor DNS is not enabled or not fully configured
        TOR_DNS_OVERALL_STATUS="false"
        TOR_DNS_DETAILED=""  # Don't show details when not enabled
        echo -e "${CYAN}  • Tor DNS not detected (rules not set)${NC}"
        return 1
    fi
}

# Function to count profiles
count_profiles() {
    # Only count if hooks directory exists
    if [ -n "$HOOKS_DIR" ] && [ -d "$HOOKS_DIR/config/profiles" ]; then
        local count=$(ls -1 "$HOOKS_DIR/config/profiles"/*.json 2>/dev/null | wc -l)
        PROFILE_COUNT="Profiles: ${GREEN}${count}${NC}"
        PROFILE_COUNT_RAW="$count"
    else
        # Hooks directory not found - show N/A (normal for ISO users)
        PROFILE_COUNT="Profiles: ${GREEN}N/A${NC}"
        PROFILE_COUNT_RAW="0"
    fi
}

# Function to count log files
count_logs() {
    # Only count if hooks directory exists
    if [ -n "$HOOKS_DIR" ] && [ -d "$HOOKS_DIR/logs" ]; then
        # Count only FILES, not folders
        local count=$(find "$HOOKS_DIR/logs" -maxdepth 1 -type f 2>/dev/null | wc -l)
        LOGS_COUNT="Logs: ${GREEN}${count}${NC}"
    else
        # Hooks directory not found - show N/A (normal for ISO users)
        LOGS_COUNT="Logs: ${GREEN}N/A${NC}"
    fi
}

# Function to count binaries
count_binaries() {
    # Only count if hooks directory exists
    if [ -n "$HOOKS_DIR" ] && [ -d "$HOOKS_DIR" ]; then
        # Count executable binary files in hooks directory (actual deployed binaries)
        local count=$(find "$HOOKS_DIR" -maxdepth 1 -type f -executable ! -name "*.sh" ! -name ".*" 2>/dev/null | wc -l)
        BINARIES_COUNT="Binaries: ${GREEN}${count}${NC}"
    else
        # Hooks directory not found - show N/A (normal for ISO users)
        BINARIES_COUNT="Binaries: ${GREEN}N/A${NC}"
    fi
}

# Function to check permission guard status
check_permission_guard() {
    local PERM_JSON=$(run_command permission-guard 30 status --json 2>/dev/null)
    local STATUS=$(parse_json "$PERM_JSON" ".data.status" || echo "")

    if [ "$STATUS" = "ok" ]; then
        PERM_GUARD_STATUS="${GREEN}[PermG:+]${NC}"
    else
        PERM_GUARD_STATUS="${RED}[PermG:✗]${NC}"
    fi
}

# Function to fetch latest version
fetch_latest_version() {
    local RELEASE_JSON=$(run_command online-info-switch 60 releases --json 2>/dev/null)
    local MAIN_VERSION=$(parse_json "$RELEASE_JSON" ".terminal.main_version" || echo "N/A")
    local NIGHTLY_VERSION=$(parse_json "$RELEASE_JSON" ".terminal.nightly_version" || echo "")

    # Build version string - title white, value GREEN (same as PermG:+)
    if [ "$MAIN_VERSION" != "N/A" ] && [ -n "$MAIN_VERSION" ]; then
        LATEST_VERSION="Main: ${GREEN}${MAIN_VERSION}${NC}"

        # Add nightly version if available
        if [ -n "$NIGHTLY_VERSION" ] && [ "$NIGHTLY_VERSION" != "null" ]; then
            LATEST_VERSION="${LATEST_VERSION} | Nbuild: ${GREEN}${NIGHTLY_VERSION}${NC}"
        fi
    else
        LATEST_VERSION="Main: ${GREEN}N/A${NC}"
    fi
}

# Function to fetch cryptocurrency prices
fetch_crypto_prices() {
    local CRYPTO_JSON=$(run_command online-info-switch 60 price all --json 2>/dev/null)

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
    local MAX_RETRIES=3
    local retry_count=0
    local HEADLINE1=""
    local HEADLINE2=""
    local NEWS_JSON=""

    # Retry loop to handle empty/failed RSS feeds
    while [ $retry_count -lt $MAX_RETRIES ]; do
        NEWS_JSON=$(run_command online-info-switch 50 rss --random --max-items 2 --json 2>/dev/null)

        if check_jq && [ -n "$NEWS_JSON" ]; then
            # Get first 2 headlines and add ellipsis if truncated (max 71 chars + "...")
            HEADLINE1=$(echo "$NEWS_JSON" | jq -r '.items[0].title' 2>/dev/null || echo "")
            HEADLINE2=$(echo "$NEWS_JSON" | jq -r '.items[1].title' 2>/dev/null || echo "")

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

            # Check if we got at least one valid headline
            if [ -n "$HEADLINE1" ] && [ "$HEADLINE1" != "null" ]; then
                # Success - we have valid news
                break
            fi
        fi

        # No valid headlines - retry
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $MAX_RETRIES ]; then
            sleep 1  # Wait 1 second before retry
        fi
    done

    # Set final NEWS_HEADLINES based on result
    if [ -n "$HEADLINE1" ] && [ "$HEADLINE1" != "null" ]; then
        NEWS_HEADLINES="${BOLD}•${NC} ${GREEN}${HEADLINE1}${NC}"
        if [ -n "$HEADLINE2" ] && [ "$HEADLINE2" != "null" ]; then
            NEWS_HEADLINES="${NEWS_HEADLINES}\n${BOLD}•${NC} ${GREEN}${HEADLINE2}${NC}"
        fi
    else
        NEWS_HEADLINES="${YELLOW}No news available${NC}"
    fi
}

# Function to fetch and parse system information
fetch_system_info() {
    # Fetch IP information (60s timeout for Tor-friendly operation)
    IP_JSON=$(run_command ip-fetch 60 --json 2>/dev/null | tail -1)
    IP_ADDR=$(parse_json "$IP_JSON" ".data.records[0].ip" || echo "N/A")
    COUNTRY=$(parse_json "$IP_JSON" ".data.records[0].country_name" || echo "N/A")
    CITY=$(parse_json "$IP_JSON" ".data.records[0].city" || echo "N/A")
    FLAG=$(parse_json "$IP_JSON" ".data.records[0].flag" || echo "")

    # Fetch Tor status with dynamic color (60s timeout)
    TOR_CHECK=$(run_command ip-fetch 60 check-tor --json 2>/dev/null)
    IS_TOR=$(parse_json "$TOR_CHECK" ".IsTor" || echo "false")
    if [ "$IS_TOR" = "true" ]; then
        TOR_STATUS="${GREEN}✓ Tor${NC}"       # Bright green when using Tor
    else
        TOR_STATUS="${RED}✗ Direct${NC}"      # Red when NOT using Tor
    fi

    # Fetch network connection status (50s timeout)
    # Bright green for VPN, RED for no VPN
    ROUTING_JSON=$(run_command routing-switch 50 status --json 2>/dev/null)
    CONNECTED=$(parse_json "$ROUTING_JSON" ".data.connected" || echo "false")
    PROTOCOL=$(parse_json "$ROUTING_JSON" ".data.protocol" || echo "none")
    if [ "$CONNECTED" = "true" ]; then
        NET_STATUS="${GREEN}${PROTOCOL}${NC}"  # Bright green for VPN
    else
        NET_STATUS="${RED}No VPN${NC}"
    fi

    # Fetch hardening verification (50s timeout)
    HARDENING_JSON=$(run_command health-control 50 security-verify --json 2>/dev/null)
    if check_jq; then
        HARDENED=$(echo "$HARDENING_JSON" | jq '[.data.modules[] | select(.hardening_status == "hardened")] | length' 2>/dev/null || echo "?")
        TOTAL=$(echo "$HARDENING_JSON" | jq '.data.modules | length' 2>/dev/null || echo "?")
    else
        HARDENED="?"
        TOTAL="?"
    fi
    HARDENING_STATUS="${HARDENED}/${TOTAL} Modules"

    # Fetch security score (50s timeout)
    SCORE_JSON=$(run_command health-control 50 security-score --json 2>/dev/null)
    SEC_SCORE=$(parse_json "$SCORE_JSON" ".data.total_score" || echo "N/A")
    SEC_STATUS=$(parse_json "$SCORE_JSON" ".data.security_level" || echo "UNKNOWN")

    # Fetch hostname (30s timeout - local call)
    HOST_JSON=$(run_command health-control 30 get-hostname --json 2>/dev/null)
    HOSTNAME=$(parse_json "$HOST_JSON" ".data.hostname" || echo "N/A")

    # Fetch timezone (30s timeout - local call)
    TZ_JSON=$(run_command health-control 30 show-timezone --json 2>/dev/null)
    TIMEZONE=$(parse_json "$TZ_JSON" ".data.timezone" || echo "N/A")

    # Fetch MAC address (30s timeout - local call)
    MAC_JSON=$(run_command health-control 30 mac-show-macs --json 2>/dev/null)
    MAC_ADDR=$(parse_json "$MAC_JSON" ".data.interfaces[0].mac_address" || echo "N/A")

    # Store status
    INFO_STATUS="${GREEN}[Net:+]${NC}"
}

# Function to detect boot mode (UEFI or Legacy BIOS)
detect_boot_mode() {
    # Check if running in UEFI mode
    if [ -d /sys/firmware/efi ]; then
        echo "UEFI"
    else
        echo "Legacy"
    fi
}

# Function to detect system status (Live vs Installed + Encryption + Boot Mode)
detect_system_status() {
    # Method 1: Live ISO Detection (robust - checks multiple indicators)
    if grep -q "boot=live\|live" /proc/cmdline 2>/dev/null || mount | grep -q "overlay" 2>/dev/null; then
        local boot_mode=$(detect_boot_mode)
        echo "Live - ${boot_mode}"
        return 0
    fi

    # Method 2: Encryption Detection (uses health-control if available)
    local boot_mode=$(detect_boot_mode)

    # Try to use health-control binary for comprehensive encryption check
    if command -v health-control >/dev/null 2>&1; then
        # Call health-control encryption-status command
        ENCRYPTION_JSON=$(run_command health-control 30 encryption-status --json 2>/dev/null)

        # Parse JSON to check if system is encrypted
        if check_jq; then
            SYSTEM_ENCRYPTED=$(echo "$ENCRYPTION_JSON" | jq -r '.data.system_encrypted' 2>/dev/null)
        else
            # Fallback parsing without jq
            SYSTEM_ENCRYPTED=$(echo "$ENCRYPTION_JSON" | grep -o '"system_encrypted":[^,}]*' | cut -d':' -f2 | tr -d ' "')
        fi

        if [ "$SYSTEM_ENCRYPTED" = "true" ]; then
            echo "Installed - Encrypted - ${boot_mode}"
        else
            echo "Installed - Not Encrypted - ${boot_mode}"
        fi
    else
        # Fallback: Simple lsblk check if health-control not available
        if lsblk -f 2>/dev/null | grep -qi "crypto_LUKS"; then
            echo "Installed - Encrypted - ${boot_mode}"
        else
            echo "Installed - Not Encrypted - ${boot_mode}"
        fi
    fi
}

# Function to display system info compactly
display_info() {
    # Detect system status
    SYSTEM_STATUS=$(detect_system_status)

    # Get uptime and load average (single average value)
    local UPTIME_RAW=$(uptime -p | sed 's/up //; s/ hours\?/h/; s/ minutes\?/m/; s/ days\?/d/; s/,//g')
    local LOAD_AVG=$(cat /proc/loadavg | awk '{printf "%.2f", ($1 + $2 + $3) / 3}')

    # Apply color based on status
    # Bright green for: Live OR Encrypted (same as PermG:+)
    # Red for: Not Encrypted (installed without encryption)
    if [[ "$SYSTEM_STATUS" == *"Not Encrypted"* ]]; then
        SYSTEM_STATUS_COLORED="${RED}${SYSTEM_STATUS}${NC}"
    elif [[ "$SYSTEM_STATUS" == *"Live"* ]] || [[ "$SYSTEM_STATUS" == *"Encrypted"* ]]; then
        SYSTEM_STATUS_COLORED="${GREEN}${SYSTEM_STATUS}${NC}"  # Bright green (same as PermG:+)
    else
        SYSTEM_STATUS_COLORED="${SYSTEM_STATUS}"  # Fallback (no color)
    fi

    echo ""
    echo -e "${BOLD}SSTATUS:${NC} ${SYSTEM_STATUS_COLORED} | ${BOLD}Uptime:${NC} ${GREEN}${UPTIME_RAW}${NC} | ${BOLD}Load:${NC} ${GREEN}${LOAD_AVG}${NC}"
    echo -e "${CYAN}────────────────────────────────────────────────────────────────────────────${NC}"

    # Security score with color based on value (handle both int and float)
    # Color scheme: RED (<60), YELLOW (60-79), GREEN (≥80)
    if [[ "$SEC_SCORE" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        # Convert to integer for comparison (drop decimal part)
        SCORE_INT=$(echo "$SEC_SCORE" | cut -d. -f1)
        if [ "$SCORE_INT" -ge 80 ]; then
            SCORE_COLOR="${GREEN}"    # Bright green (same as PermG:+)
        elif [ "$SCORE_INT" -ge 60 ]; then
            SCORE_COLOR="${YELLOW}"   # Magenta (warning)
        else
            SCORE_COLOR="${RED}"      # Red (critical)
        fi
    else
        SCORE_COLOR="${RED}"
    fi

    # Show ACTUAL DNS mode (verified, not hardcoded)
    # Truncate DNS mode if too long (allow space for [Direct:✓ Port:✓])
    DNS_DISPLAY=$(echo "$ACTUAL_DNS_MODE" | cut -c1-65)

    # Color DNS based on status
    if [[ "$ACTUAL_DNS_MODE" == *"[Direct:✓ Port:✓]"* ]]; then
        DNS_COLOR="${GREEN}"  # Bright green for Tor DNS with both methods successful
    elif [[ "$ACTUAL_DNS_MODE" == *"DNSCrypt"* ]]; then
        DNS_COLOR="${GREEN}"  # Bright green for DNSCrypt
    elif [[ "$ACTUAL_DNS_MODE" == *"service not running"* ]]; then
        DNS_COLOR="${RED}"  # Red for service not running
    else
        DNS_COLOR="${YELLOW}"  # Yellow for direct DNS or anything else
    fi

    # Line 1: Security Score | Hardening | Torrified Status
    echo -e "${BOLD}Security:${NC} ${SCORE_COLOR}${SEC_SCORE}/100 [${SEC_STATUS}]${NC} | ${BOLD}Hardening:${NC} ${GREEN}${HARDENING_STATUS}${NC} | ${BOLD}Torrified:${NC} ${TOR_STATUS}"

    # Line 2: Network Connection | DNS
    echo -e "${BOLD}Network:${NC} ${NET_STATUS} | ${BOLD}DNS:${NC} ${DNS_COLOR}${DNS_DISPLAY}${NC}"

    # Line 3: IP, Country, City (bright green - same as PermG:+)
    echo -e "${BOLD}IP:${NC} ${GREEN}${IP_ADDR}${NC} | ${BOLD}Country:${NC} ${GREEN}${FLAG} ${COUNTRY}${NC} | ${BOLD}City:${NC} ${GREEN}${CITY}${NC}"

    # Line 4: Hostname, MAC, Timezone (bright green - same as PermG:+)
    echo -e "${BOLD}Hostname:${NC} ${GREEN}${HOSTNAME}${NC} | ${BOLD}MAC:${NC} ${GREEN}${MAC_ADDR}${NC} | ${BOLD}TZ:${NC} ${GREEN}${TIMEZONE}${NC}"

    echo ""
    # Crypto prices line
    echo -e "${BOLD}CRYPTO PRICES:${NC}"
    echo -e "${CRYPTO_PRICES}"

    echo ""
    # News headlines
    echo -e "${BOLD}LATEST NEWS:${NC}"
    echo -e "${NEWS_HEADLINES}"

    echo -e "${CYAN}────────────────────────────────────────────────────────────────────────────${NC}"
}

# Function to display profile menu
# CRITICAL: Keep menu display under 50 lines total (currently 36 lines)
show_menu() {
    echo -e "${BOLD}SELECT PROFILE:${NC}"
    echo ""
    echo -e " ${GREEN}[1]${NC} ${BOLD}Connect to WireGuard:${NC} ${CYAN}→${NC} Auth ${CYAN}→${NC} Status ${CYAN}→${NC} Harden ${CYAN}→${NC} WireGuard ${CYAN}→${NC} Verify"
    echo -e " ${GREEN}[2]${NC} ${BOLD}Connect to Xray-VLESS-Reality:${NC} ${CYAN}→${NC} Auth ${CYAN}→${NC} Status ${CYAN}→${NC} Harden ${CYAN}→${NC} Connect ${CYAN}→${NC} Verify"
    echo -e " ${GREEN}[3]${NC} ${BOLD}Connect to OpenVPN:${NC} ${CYAN}→${NC} Auth ${CYAN}→${NC} Status ${CYAN}→${NC} Harden ${CYAN}→${NC} OpenVPN ${CYAN}→${NC} Verify"
    echo -e " ${GREEN}[4]${NC} ${BOLD}Connect to V2Ray:${NC} ${CYAN}→${NC} Auth ${CYAN}→${NC} Status ${CYAN}→${NC} Harden ${CYAN}→${NC} V2Ray ${CYAN}→${NC} Verify"
    echo -e " ${GREEN}[5]${NC} ${BOLD}Connect to Hysteria2:${NC} ${CYAN}→${NC} Auth ${CYAN}→${NC} Status ${CYAN}→${NC} Harden ${CYAN}→${NC} Hysteria2 ${CYAN}→${NC} Verify"
    echo -e " ${GREEN}[6]${NC} ${BOLD}Connect to Xray-VLESS:${NC} ${CYAN}→${NC} Auth ${CYAN}→${NC} Status ${CYAN}→${NC} Harden ${CYAN}→${NC} Xray-VLESS ${CYAN}→${NC} Verify"
    echo -e " ${GREEN}[7]${NC} ${BOLD}Connect to Xray-Trojan:${NC} ${CYAN}→${NC} Auth ${CYAN}→${NC} Status ${CYAN}→${NC} Harden ${CYAN}→${NC} Xray-Trojan ${CYAN}→${NC} Verify"
    echo -e " ${GREEN}[8]${NC} ${BOLD}Connect to Mita:${NC} ${CYAN}→${NC} Auth ${CYAN}→${NC} Status ${CYAN}→${NC} Harden ${CYAN}→${NC} Mita ${CYAN}→${NC} Verify"
    echo -e " ${GREEN}[9]${NC} ${BOLD}Torrify: Round-Robin${NC} ${CYAN}→${NC} Load-balanced Tor (even distribution)"
    echo -e " ${GREEN}[10]${NC} ${BOLD}Torrify: Consistent-Hash${NC} ${CYAN}→${NC} Load-balanced Tor (stable per-connection)"
    echo -e " ${GREEN}[11]${NC} ${BOLD}Torrify: Weighted${NC} ${CYAN}→${NC} Load-balanced Tor (priority-based)"
    echo -e " ${GREEN}[12]${NC} ${BOLD}Connect WireGuard + Torrify:${NC} ${CYAN}→${NC} Auth ${CYAN}→${NC} Harden ${CYAN}→${NC} Connect ${CYAN}→${NC} Torrify ${CYAN}→${NC} Verify"
    echo -e " ${GREEN}[13]${NC} ${BOLD}Enable DNSCrypt:${NC} ${CYAN}→${NC} Set Cloudflare ${CYAN}→${NC} Enable ${CYAN}→${NC} Net Check ${CYAN}→${NC} Verify"
    echo -e " ${GREEN}[14]${NC} ${BOLD}Enable Tor DNS:${NC} ${CYAN}→${NC} Auth ${CYAN}→${NC} Torrify ${CYAN}→${NC} nftables ${CYAN}→${NC} DNS ${CYAN}→${NC} Verify"
    echo -e " ${GREEN}[15]${NC} ${BOLD}Disconnect Routing:${NC} ${CYAN}→${NC} Disconnect ${CYAN}→${NC} Status ${CYAN}→${NC} IP Fetch"
    echo -e " ${GREEN}[16]${NC} ${BOLD}Detorrify System:${NC} ${CYAN}→${NC} Remove iptables ${CYAN}→${NC} Remove nftables ${CYAN}→${NC} Stop DNS ${CYAN}→${NC} Verify"
    echo -e " ${GREEN}[17]${NC} ${BOLD}Emergency Network Recovery:${NC} ${CYAN}→${NC} Detorrify ${CYAN}→${NC} Disconnect ${CYAN}→${NC} Recover ${CYAN}→${NC} Reset ${CYAN}→${NC} Verify"
    echo -e " ${GREEN}[18]${NC} ${BOLD}Check Security Score:${NC} ${CYAN}→${NC} Display comprehensive security score report"
    echo -e " ${GREEN}[19]${NC} ${BOLD}Reboot System${NC} - Restart the system"
    echo -e " ${GREEN}[20]${NC} ${BOLD}Shutdown System${NC} - Power off the system"
    echo -e " ${GREEN}[21]${NC} ${BOLD}Exit${NC} - Skip to shell (Return: type ${CYAN}'kodachi'${NC} and press Enter)"
    echo -e "${CYAN}────────────────────────────────────────────────────────────────────────────${NC}"
    echo -e "${YELLOW}NOTE:${NC} ${CYAN}health-control -e${NC}, ${CYAN}routing-switch -e${NC} | ${PROFILE_COUNT_RAW}+ profiles: ${CYAN}workflow-manager list${NC}"
    echo -e "${YELLOW}TIP:${NC} MicroSOCKS: ${CYAN}routing-switch microsocks-enable -u USER -p PASS${NC}"
    echo ""
    # Calculate and display timeout dynamically
    if [ $AUTO_REFRESH_TIMEOUT -ge 60 ]; then
        local timeout_minutes=$((AUTO_REFRESH_TIMEOUT / 60))
        echo -ne "${BOLD}Enter choice [1-21]${NC} ${CYAN}(auto-refresh in ${timeout_minutes} min)${NC}: "
    else
        echo -ne "${BOLD}Enter choice [1-21]${NC} ${CYAN}(auto-refresh in ${AUTO_REFRESH_TIMEOUT} sec)${NC}: "
    fi
}

# Function to execute selected profile
execute_profile() {
    local choice="$1"

    case "$choice" in
        1)
            echo -e "\n${YELLOW}Connecting to WireGuard...${NC}\n"
            run_command workflow-manager 0 run initial_terminal_setup_wireguard_only
            echo ""
            echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════${NC}"
            echo -e "${BOLD}Return to Menu Options:${NC}"
            echo -e "  ${GREEN}[Enter]${NC} - Refresh data and show menu (recommended)"
            echo -e "  ${GREEN}[s]${NC}     - Skip refresh and show menu (fast)"
            echo -e "  ${GREEN}[Ctrl+C]${NC} - Exit to shell"
            echo ""
            echo -ne "${BOLD}Your choice:${NC} "
            read -r refresh_choice
            ;;
        2)
            echo -e "\n${YELLOW}Connecting to Xray-VLESS-Reality...${NC}\n"
            run_command workflow-manager 0 run initial_terminal_setup_xray_vless_reality_only
            echo ""
            echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════${NC}"
            echo -e "${BOLD}Return to Menu Options:${NC}"
            echo -e "  ${GREEN}[Enter]${NC} - Refresh data and show menu (recommended)"
            echo -e "  ${GREEN}[s]${NC}     - Skip refresh and show menu (fast)"
            echo -e "  ${GREEN}[Ctrl+C]${NC} - Exit to shell"
            echo ""
            echo -ne "${BOLD}Your choice:${NC} "
            read -r refresh_choice
            ;;
        3)
            echo -e "\n${YELLOW}Connecting to OpenVPN...${NC}\n"
            run_command workflow-manager 0 run initial_terminal_setup_openvpn_only
            echo ""
            echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════${NC}"
            echo -e "${BOLD}Return to Menu Options:${NC}"
            echo -e "  ${GREEN}[Enter]${NC} - Refresh data and show menu (recommended)"
            echo -e "  ${GREEN}[s]${NC}     - Skip refresh and show menu (fast)"
            echo -e "  ${GREEN}[Ctrl+C]${NC} - Exit to shell"
            echo ""
            echo -ne "${BOLD}Your choice:${NC} "
            read -r refresh_choice
            ;;
        4)
            echo -e "\n${YELLOW}Connecting to V2Ray...${NC}\n"
            run_command workflow-manager 0 run initial_terminal_setup_v2ray_only
            echo ""
            echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════${NC}"
            echo -e "${BOLD}Return to Menu Options:${NC}"
            echo -e "  ${GREEN}[Enter]${NC} - Refresh data and show menu (recommended)"
            echo -e "  ${GREEN}[s]${NC}     - Skip refresh and show menu (fast)"
            echo -e "  ${GREEN}[Ctrl+C]${NC} - Exit to shell"
            echo ""
            echo -ne "${BOLD}Your choice:${NC} "
            read -r refresh_choice
            ;;
        5)
            echo -e "\n${YELLOW}Connecting to Hysteria2...${NC}\n"
            run_command workflow-manager 0 run initial_terminal_setup_hysteria2_only
            echo ""
            echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════${NC}"
            echo -e "${BOLD}Return to Menu Options:${NC}"
            echo -e "  ${GREEN}[Enter]${NC} - Refresh data and show menu (recommended)"
            echo -e "  ${GREEN}[s]${NC}     - Skip refresh and show menu (fast)"
            echo -e "  ${GREEN}[Ctrl+C]${NC} - Exit to shell"
            echo ""
            echo -ne "${BOLD}Your choice:${NC} "
            read -r refresh_choice
            ;;
        6)
            echo -e "\n${YELLOW}Connecting to Xray-VLESS...${NC}\n"
            run_command workflow-manager 0 run initial_terminal_setup_xray_vless_only
            echo ""
            echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════${NC}"
            echo -e "${BOLD}Return to Menu Options:${NC}"
            echo -e "  ${GREEN}[Enter]${NC} - Refresh data and show menu (recommended)"
            echo -e "  ${GREEN}[s]${NC}     - Skip refresh and show menu (fast)"
            echo -e "  ${GREEN}[Ctrl+C]${NC} - Exit to shell"
            echo ""
            echo -ne "${BOLD}Your choice:${NC} "
            read -r refresh_choice
            ;;
        7)
            echo -e "\n${YELLOW}Connecting to Xray-Trojan...${NC}\n"
            run_command workflow-manager 0 run initial_terminal_setup_xray_trojan_only
            echo ""
            echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════${NC}"
            echo -e "${BOLD}Return to Menu Options:${NC}"
            echo -e "  ${GREEN}[Enter]${NC} - Refresh data and show menu (recommended)"
            echo -e "  ${GREEN}[s]${NC}     - Skip refresh and show menu (fast)"
            echo -e "  ${GREEN}[Ctrl+C]${NC} - Exit to shell"
            echo ""
            echo -ne "${BOLD}Your choice:${NC} "
            read -r refresh_choice
            ;;
        8)
            echo -e "\n${YELLOW}Connecting to Mita...${NC}\n"
            run_command workflow-manager 0 run initial_terminal_setup_mita_only
            echo ""
            echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════${NC}"
            echo -e "${BOLD}Return to Menu Options:${NC}"
            echo -e "  ${GREEN}[Enter]${NC} - Refresh data and show menu (recommended)"
            echo -e "  ${GREEN}[s]${NC}     - Skip refresh and show menu (fast)"
            echo -e "  ${GREEN}[Ctrl+C]${NC} - Exit to shell"
            echo ""
            echo -ne "${BOLD}Your choice:${NC} "
            read -r refresh_choice
            ;;
        9)
            echo -e "\n${YELLOW}Torrifying System (Round-Robin)...${NC}\n"
            run_command workflow-manager 0 run torrify-balance-nftables-roundrobin
            echo ""
            echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════${NC}"
            echo -e "${BOLD}Return to Menu Options:${NC}"
            echo -e "  ${GREEN}[Enter]${NC} - Refresh data and show menu (recommended)"
            echo -e "  ${GREEN}[s]${NC}     - Skip refresh and show menu (fast)"
            echo -e "  ${GREEN}[Ctrl+C]${NC} - Exit to shell"
            echo ""
            echo -ne "${BOLD}Your choice:${NC} "
            read -r refresh_choice
            ;;
        10)
            echo -e "\n${YELLOW}Torrifying System (Consistent-Hash)...${NC}\n"
            run_command workflow-manager 0 run torrify-balance-nftables-consistent
            echo ""
            echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════${NC}"
            echo -e "${BOLD}Return to Menu Options:${NC}"
            echo -e "  ${GREEN}[Enter]${NC} - Refresh data and show menu (recommended)"
            echo -e "  ${GREEN}[s]${NC}     - Skip refresh and show menu (fast)"
            echo -e "  ${GREEN}[Ctrl+C]${NC} - Exit to shell"
            echo ""
            echo -ne "${BOLD}Your choice:${NC} "
            read -r refresh_choice
            ;;
        11)
            echo -e "\n${YELLOW}Torrifying System (Weighted)...${NC}\n"
            run_command workflow-manager 0 run torrify-balance-nftables-weighted
            echo ""
            echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════${NC}"
            echo -e "${BOLD}Return to Menu Options:${NC}"
            echo -e "  ${GREEN}[Enter]${NC} - Refresh data and show menu (recommended)"
            echo -e "  ${GREEN}[s]${NC}     - Skip refresh and show menu (fast)"
            echo -e "  ${GREEN}[Ctrl+C]${NC} - Exit to shell"
            echo ""
            echo -ne "${BOLD}Your choice:${NC} "
            read -r refresh_choice
            ;;
        12)
            echo -e "\n${YELLOW}Connecting WireGuard + Torrifying...${NC}\n"
            run_command workflow-manager 0 run initial_terminal_setup_wireguard_torrify
            echo ""
            echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════${NC}"
            echo -e "${BOLD}Return to Menu Options:${NC}"
            echo -e "  ${GREEN}[Enter]${NC} - Refresh data and show menu (recommended)"
            echo -e "  ${GREEN}[s]${NC}     - Skip refresh and show menu (fast)"
            echo -e "  ${GREEN}[Ctrl+C]${NC} - Exit to shell"
            echo ""
            echo -ne "${BOLD}Your choice:${NC} "
            read -r refresh_choice
            ;;
        13)
            echo -e "\n${YELLOW}Enabling DNSCrypt...${NC}\n"
            run_command workflow-manager 0 run dns-dnscrypt-enable
            echo ""
            echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════${NC}"
            echo -e "${BOLD}Return to Menu Options:${NC}"
            echo -e "  ${GREEN}[Enter]${NC} - Refresh data and show menu (recommended)"
            echo -e "  ${GREEN}[s]${NC}     - Skip refresh and show menu (fast)"
            echo -e "  ${GREEN}[Ctrl+C]${NC} - Exit to shell"
            echo ""
            echo -ne "${BOLD}Your choice:${NC} "
            read -r refresh_choice
            ;;
        14)
            echo -e "\n${YELLOW}Enabling Tor DNS...${NC}\n"
            run_command workflow-manager 0 run tor-dns-nftables-full
            echo ""
            echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════${NC}"
            echo -e "${BOLD}Return to Menu Options:${NC}"
            echo -e "  ${GREEN}[Enter]${NC} - Refresh data and show menu (recommended)"
            echo -e "  ${GREEN}[s]${NC}     - Skip refresh and show menu (fast)"
            echo -e "  ${GREEN}[Ctrl+C]${NC} - Exit to shell"
            echo ""
            echo -ne "${BOLD}Your choice:${NC} "
            read -r refresh_choice
            ;;
        15)
            echo -e "\n${YELLOW}Disconnecting Routing...${NC}\n"
            run_command workflow-manager 0 run routing-disconnect-clean
            echo ""
            echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════${NC}"
            echo -e "${BOLD}Return to Menu Options:${NC}"
            echo -e "  ${GREEN}[Enter]${NC} - Refresh data and show menu (recommended)"
            echo -e "  ${GREEN}[s]${NC}     - Skip refresh and show menu (fast)"
            echo -e "  ${GREEN}[Ctrl+C]${NC} - Exit to shell"
            echo ""
            echo -ne "${BOLD}Your choice:${NC} "
            read -r refresh_choice
            ;;
        16)
            echo -e "\n${YELLOW}Detorrifying System...${NC}\n"
            run_command workflow-manager 0 run detorrify-complete-verify
            echo ""
            echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════${NC}"
            echo -e "${BOLD}Return to Menu Options:${NC}"
            echo -e "  ${GREEN}[Enter]${NC} - Refresh data and show menu (recommended)"
            echo -e "  ${GREEN}[s]${NC}     - Skip refresh and show menu (fast)"
            echo -e "  ${GREEN}[Ctrl+C]${NC} - Exit to shell"
            echo ""
            echo -ne "${BOLD}Your choice:${NC} "
            read -r refresh_choice
            ;;
        17)
            echo -e "\n${YELLOW}Running Emergency Network Recovery...${NC}\n"
            run_command workflow-manager 0 run recovery-master-complete
            echo ""
            echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════${NC}"
            echo -e "${BOLD}Return to Menu Options:${NC}"
            echo -e "  ${GREEN}[Enter]${NC} - Refresh data and show menu (recommended)"
            echo -e "  ${GREEN}[s]${NC}     - Skip refresh and show menu (fast)"
            echo -e "  ${GREEN}[Ctrl+C]${NC} - Exit to shell"
            echo ""
            echo -ne "${BOLD}Your choice:${NC} "
            read -r refresh_choice
            ;;
        18)
            echo -e "\n${YELLOW}Checking Security Score...${NC}\n"
            run_command health-control 0 security-score
            echo ""
            echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════${NC}"
            echo -e "${BOLD}Return to Menu Options:${NC}"
            echo -e "  ${GREEN}[Enter]${NC} - Refresh data and show menu (recommended)"
            echo -e "  ${GREEN}[s]${NC}     - Skip refresh and show menu (fast)"
            echo -e "  ${GREEN}[Ctrl+C]${NC} - Exit to shell"
            echo ""
            echo -ne "${BOLD}Your choice:${NC} "
            read -r refresh_choice
            ;;
        19)
            echo -e "\n${YELLOW}Reboot System${NC}"
            echo -ne "${RED}Are you sure you want to reboot? [y/N]:${NC} "
            read -r confirm
            if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                echo -e "${GREEN}Rebooting system...${NC}"
                sudo reboot
            else
                echo -e "${YELLOW}Reboot cancelled.${NC}"
                sleep 1
            fi
            ;;
        20)
            echo -e "\n${YELLOW}Shutdown System${NC}"
            echo -ne "${RED}Are you sure you want to shutdown? [y/N]:${NC} "
            read -r confirm
            if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                echo -e "${GREEN}Shutting down system...${NC}"
                sudo shutdown -h now
            else
                echo -e "${YELLOW}Shutdown cancelled.${NC}"
                sleep 1
            fi
            ;;
        21)
            echo -e "\n${GREEN}Exiting to shell...${NC}\n"
            return 1
            ;;
        *)
            echo -e "\n${RED}Invalid choice. Please try again...${NC}\n"
            sleep 1
            ;;
    esac
}

# Main execution
main() {
    # Display header
    show_header

    # Print build signature once at start
    echo -e "${CYAN}▸ Welcome Script v${SCRIPT_VERSION} | Build: ${BUILD_DATE} | Runtime: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${CYAN}▸ You can stop this script anytime by pressing ${BOLD}Ctrl+C${NC}${CYAN} keys${NC}"
    echo ""

    # Ensure installed GRUB menu shows Kodachi branding
    ensure_grub_theme

    # Deploy binaries (detect_hooks_dir will print status)
    deploy_binaries

    # Sleep to ensure internet connectivity is established
    echo -e "${YELLOW}▸ Waiting for network (5s)...${NC}"
    sleep 5

    # Authenticate BEFORE DNS setup
    # First check if already logged in (50s timeout)
    LOGIN_CHECK=$(run_command online-auth 50 check-login --json 2>/dev/null)
    IS_LOGGED_IN=$(parse_json "$LOGIN_CHECK" ".data.is_logged_in")

    if [ "$IS_LOGGED_IN" = "true" ]; then
        echo -e "${GREEN}▸ Already authenticated - skipping${NC}"
        AUTH_STATUS="${GREEN}[Auth:+]${NC}"
    else
        echo -e "${YELLOW}▸ Not authenticated - authenticating now...${NC}"
        if ! authenticate; then
            echo -e "${YELLOW}! Authentication failed - continuing anyway${NC}"
        fi
    fi

    # Setup DNSCrypt
    echo -e "${YELLOW}▸ Configuring DNS...${NC}"
    setup_dnscrypt

    # Check authentication status after DNSCrypt setup
    if [ "${AUTH_STATUS}" = "${GREEN}[Auth:+]${NC}" ]; then
        # Already authenticated from initial attempt
        echo -e "${GREEN}✓ Authentication verified - already logged in${NC}"
    else
        # Not authenticated - retry now that DNS is configured
        echo -e "${YELLOW}▸ Retrying authentication after DNS setup...${NC}"
        if authenticate; then
            echo -e "${GREEN}✓ Authentication successful${NC}"
        else
            echo -e "${RED}! Authentication failed - continuing with limited functionality${NC}"
        fi
    fi

    # Fetch system information
    echo -e "${YELLOW}▸ Fetching system data...${NC}"
    fetch_system_info

    # Count profiles, logs, and binaries
    count_profiles
    count_logs
    count_binaries

    # Check permission guard status
    check_permission_guard

    # Fetch online data
    echo -e "${YELLOW}▸ Fetching online data...${NC}"
    fetch_latest_version
    fetch_crypto_prices
    fetch_news_headlines

    echo -e "${GREEN}✓ All checks complete!${NC}"
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

    # Menu loop - continue until user selects Exit
    while true; do
        # Show menu and get user choice
        show_menu
        read -t $AUTO_REFRESH_TIMEOUT -r choice
        local read_status=$?

        # Check if read timed out (status > 128 means timeout)
        if [ $read_status -gt 128 ]; then
            # Timeout occurred - trigger auto-refresh
            local timeout_minutes=$((AUTO_REFRESH_TIMEOUT / 60))
            echo ""
            echo -e "${CYAN}▸ Auto-refresh triggered (${timeout_minutes} minutes elapsed)${NC}"
            echo -e "${CYAN}▸ Refreshing system data...${NC}"

            # Re-fetch all dynamic data
            fetch_system_info
            count_profiles
            count_logs
            count_binaries
            check_permission_guard
            fetch_latest_version
            fetch_crypto_prices
            fetch_news_headlines

            echo -e "${GREEN}+ Auto-refresh complete!${NC}"
            sleep 0.5

            # Clear and redisplay everything
            clear
            show_header
            echo -e "${DEPLOY_STATUS} | ${AUTH_STATUS} | ${DNS_STATUS_MSG} | ${INFO_STATUS} | ${PERM_GUARD_STATUS}"

            # Build counts line
            local counts_line=""
            [ -n "$PROFILE_COUNT" ] && counts_line="${PROFILE_COUNT}"
            [ -n "$LOGS_COUNT" ] && counts_line="${counts_line:+$counts_line | }${LOGS_COUNT}"
            [ -n "$BINARIES_COUNT" ] && counts_line="${counts_line:+$counts_line | }${BINARIES_COUNT}"
            [ -n "$LATEST_VERSION" ] && counts_line="${counts_line:+$counts_line | }${LATEST_VERSION}"

            # Only print counts line if we have something to show
            [ -n "$counts_line" ] && echo -e "$counts_line"

            # Display information
            display_info

            # Continue to next iteration (show menu again)
            continue
        fi

        # Execute selected profile
        execute_profile "$choice"

        # Check if user wants to exit
        if [ $? -eq 1 ]; then
            break  # Exit selected
        fi

        # Check user's refresh preference
        if [ "$refresh_choice" != "s" ] && [ "$refresh_choice" != "S" ]; then
            # User pressed Enter (or anything else) - FULL REFRESH
            echo ""
            echo -e "${CYAN}▸ Refreshing system data...${NC}"

            # Re-fetch all dynamic data
            setup_dnscrypt  # Re-detect DNS configuration
            fetch_system_info
            count_profiles
            count_logs
            count_binaries
            check_permission_guard
            fetch_latest_version
            fetch_crypto_prices
            fetch_news_headlines

            echo -e "${GREEN}+ Data refresh complete!${NC}"
            sleep 0.5
        else
            # User pressed 's' - SKIP REFRESH
            echo ""
            echo -e "${YELLOW}▸ Skipping data refresh (using cached data)${NC}"
            sleep 0.3
        fi

        # Clear and redisplay header with status
        clear
        show_header
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
    done

    echo ""
}

# Run main function
main

# Return to shell
return 0 2>/dev/null || exit 0
