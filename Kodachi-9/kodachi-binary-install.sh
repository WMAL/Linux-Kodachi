#!/bin/bash

# Kodachi Binary Installation Script (NO SUDO REQUIRED)
# ======================================================
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
# Last updated: 2025-10-19
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
    INSTALL_PATH="$HOME/dashboard/hooks"
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

# Check if we can write to the installation path
if [[ -e "$INSTALL_PATH" ]] && [[ ! -w "$INSTALL_PATH" ]]; then
    print_error "Cannot write to $INSTALL_PATH"
    print_info "Please choose a different path or fix permissions"
    exit 1
fi

# Create temporary directory
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Function to download with retry and exponential backoff
download_with_retry() {
    local url="$1"
    local output="$2"
    local max_retries=4
    local retry=0
    local backoff=2

    while [[ $retry -lt $max_retries ]]; do
        if curl --fail --location --show-error --silent \
               --connect-timeout 15 --max-time 90 \
               "$url" -o "$output"; then
            return 0
        fi
        retry=$((retry + 1))
        if [[ $retry -lt $max_retries ]]; then
            print_warning "Download failed, retry $retry/$max_retries in ${backoff}s..."
            sleep "$backoff"
            backoff=$((backoff * 2))
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
        print_highlight "ACTION REQUIRED: Choose one of the following options:"
        echo ""
        echo "  Option 1: Stop daemon directly (if in PATH):"
        echo -e "    ${BOLD}sudo permission-guard --stop-daemon${NC}"
        echo ""
        echo "  Option 2: Stop daemon directly (direct path):"
        echo -e "    ${BOLD}sudo $INSTALL_PATH/permission-guard --stop-daemon${NC}"
        echo ""
        echo "  Option 3: Logout (daemon stops automatically):"
        echo -e "    ${BOLD}sudo online-auth logout${NC}"
        echo ""
        print_info "To verify the daemon is stopped, run:"
        echo -e "  ${BOLD}sudo permission-guard --daemon-status${NC}"
        echo ""
        print_info "Note: The daemon will automatically start again when you log in - no manual restart needed"
        echo ""
        print_warning "After stopping the daemon, re-run this installation script"
        exit 1
    fi
}

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
print_success "Package downloaded successfully"

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
mkdir -p "$INSTALL_PATH"/{config/signkeys,config/profiles,logs,tmp,results/signatures,backups,others,sounds,flags,licenses,binaries-update-scripts}
print_success "Directory structure created"

# Step 5.5: Stop permission-guard daemon if running (prevents binary replacement issues)
stop_permission_guard_if_running

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
TOTAL_COUNT=0
FAILED_BINARIES=""

for binary_file in "$EXTRACT_DIR/binaries/"*; do
    if [[ -f "$binary_file" ]]; then
        binary_name=$(basename "$binary_file")
        TOTAL_COUNT=$((TOTAL_COUNT + 1))

        # Verify signature BEFORE copying
        if verify_signature "$binary_file" "$EXTRACT_DIR/signatures"; then
            VERIFIED_COUNT=$((VERIFIED_COUNT + 1))
            echo -e "  ${GREEN}✓${NC} $binary_name - signature verified"

            # Only copy if signature is valid
            cp "$binary_file" "$INSTALL_PATH/$binary_name"
            chmod 755 "$INSTALL_PATH/$binary_name"
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
    cp -r "$EXTRACT_DIR/sounds/"* "$INSTALL_PATH/sounds/" 2>/dev/null || true
fi

if [[ -d "$EXTRACT_DIR/flags" ]]; then
    cp -r "$EXTRACT_DIR/flags/"* "$INSTALL_PATH/flags/" 2>/dev/null || true
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

# Step 9: Add to PATH in .bashrc with idempotent block management
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

# Step 10: Deploy binaries globally using global-launcher
echo ""
print_highlight "======= Deploying Binaries Globally ======="
echo ""

deploy_binaries_globally() {
    # Check if we're in live-build chroot environment
    if [[ -f "/tmp/live-build-chroot" ]]; then
        print_info "Detected live-build chroot environment"
        print_info "Skipping global deployment - binaries will be deployed on first ISO boot"
        print_info "Binaries installed to: $INSTALL_PATH"
        return 0
    fi

    # Check if global-launcher exists in installation path
    local gl_binary="$INSTALL_PATH/global-launcher"

    if [[ ! -f "$gl_binary" ]]; then
        print_warning "global-launcher not found at $gl_binary"
        print_info "Skipping global deployment - binaries are only available in $INSTALL_PATH"
        print_info "You can deploy globally later with: sudo $INSTALL_PATH/global-launcher deploy"
        return 0
    fi

    print_step "Deploying binaries to /usr/local/bin..."

    # Try deployment with sudo (non-interactive)
    # NOTE: Not using --save-hashes flag to avoid permission errors in chroot/restricted environments
    # Users can manually save hash reports later with: global-launcher verify --save-hashes
    local deploy_output
    if deploy_output=$(sudo -n "$gl_binary" deploy --force --json 2>&1); then
        print_success "Successfully deployed binaries globally"

        # Parse and display deployment stats
        local symlink_count=$(echo "$deploy_output" | grep -o '"symlinks_created":[0-9]*' | grep -o '[0-9]*' || echo "0")
        if [[ "$symlink_count" -gt 0 ]]; then
            print_info "Created $symlink_count symlinks in /usr/local/bin"
        fi

        # Verify deployment
        print_step "Verifying global deployment..."
        if "$gl_binary" verify --json &>/dev/null; then
            print_success "Global deployment verified successfully"
            print_info "All binaries are now accessible system-wide"
        else
            print_warning "Verification completed with warnings"
            print_info "Run 'global-launcher verify --detailed' for more information"
        fi

        return 0
    else
        # Deployment failed - check if it's a permission issue
        if echo "$deploy_output" | grep -qi "permission denied\|operation not permitted"; then
            print_warning "Global deployment requires sudo privileges"
            print_info "Binaries are installed in $INSTALL_PATH but not globally accessible yet"
            echo ""
            print_highlight "To deploy globally, run:"
            echo -e "  ${BOLD}sudo $INSTALL_PATH/global-launcher deploy${NC}"
            echo ""
            print_info "Or authenticate with online-auth which automatically deploys globally:"
            echo -e "  ${BOLD}sudo $INSTALL_PATH/online-auth authenticate --relogin${NC}"
        else
            print_error "Global deployment failed with error:"
            echo "$deploy_output" | head -5
            print_info "Binaries are still available in $INSTALL_PATH"
            print_info "You can retry deployment later with: sudo $INSTALL_PATH/global-launcher deploy"
        fi

        return 1
    fi
}

deploy_binaries_globally

# Final summary
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║    Binary Installation Complete!             ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
print_success "Kodachi binaries installed to: $INSTALL_PATH"
print_info "Binaries installed: $TOTAL_COUNT"
print_info "Signatures verified: $VERIFIED_COUNT"

if [[ $FAILED_COUNT -gt 0 ]]; then
    print_warning "Signatures not verified: $FAILED_COUNT"
fi

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
        print_info "You can proceed to run the dependency installer with sudo"
        echo ""
        print_highlight "Next Steps:"
        echo ""
        echo "1. Install system dependencies (requires sudo):"
        echo -e "   ${BOLD}sudo bash $INSTALL_PATH/binaries-update-scripts/kodachi-deps-install.sh${NC}"
        echo ""

        # Check if global deployment was successful
        if command -v health-control &>/dev/null; then
            print_success "Binaries are already deployed globally - system-wide access enabled"
        else
            echo "2. Deploy binaries globally (if not already done):"
            echo -e "   ${BOLD}sudo $INSTALL_PATH/global-launcher deploy${NC}"
            echo "   This creates symlinks in /usr/local/bin for system-wide access"
            echo "   Note: This step is automatically performed when you authenticate with 'sudo online-auth authenticate --relogin'"
        fi
    else
        print_warning "User '$current_user' is NOT in the sudoers group"
        echo ""
        print_highlight "IMPORTANT: You need to be in the sudoers group to continue"
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
        print_highlight "After adding to sudoers, you can:"
        echo ""
        echo "1. Install system dependencies:"
        echo -e "   ${BOLD}sudo bash $INSTALL_PATH/binaries-update-scripts/kodachi-deps-install.sh${NC}"
        echo ""

        # Check if global deployment was successful
        if command -v health-control &>/dev/null; then
            print_success "Binaries are already deployed globally - system-wide access enabled"
        else
            echo "2. Deploy binaries globally:"
            echo -e "   ${BOLD}sudo $INSTALL_PATH/global-launcher deploy${NC}"
            echo "   Note: This step is automatically performed when you authenticate with 'sudo online-auth authenticate --relogin'"
        fi
    fi
}

echo ""
# Check sudoers status and provide appropriate next steps
check_sudoers_status
echo ""
print_success "Binary installation complete! No sudo was required."
echo ""