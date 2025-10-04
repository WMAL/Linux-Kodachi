#!/bin/bash

# Kodachi Binary Installation Script (NO SUDO REQUIRED)
# ======================================================
#
# Author: Warith Al Maawali
# Copyright (c) 2025 Kodachi Security OS
# License: See LICENSE file or https://kodachi.cloud/license
#
# Version: 9.0.1
# Last updated: 2025-10-04
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

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

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

# Function to download with retry
download_with_retry() {
    local url="$1"
    local output="$2"
    local max_retries=3
    local retry=0

    while [[ $retry -lt $max_retries ]]; do
        if curl -fsSL --connect-timeout 10 --max-time 300 "$url" -o "$output"; then
            return 0
        fi
        retry=$((retry + 1))
        print_warning "Download failed, retry $retry/$max_retries..."
        sleep 2
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
print_step "Extracting package..."
cd "$TEMP_DIR"
tar -xzf "$PACKAGE_FILE"
EXTRACT_DIR="$TEMP_DIR/$PACKAGE_NAME"

if [[ ! -d "$EXTRACT_DIR" ]]; then
    print_error "Failed to extract package"
    exit 1
fi
print_success "Package extracted successfully"

# Step 5: Create installation directory structure
print_step "Creating installation directories..."
mkdir -p "$INSTALL_PATH"/{config/signkeys,logs,tmp,results/signatures,backups,others,sounds,flags}
print_success "Directory structure created"

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

# Step 9: Add to PATH in .bashrc
if [[ "$SKIP_PATH_UPDATE" != "true" ]]; then
    print_step "Updating PATH in .bashrc..."

    # Check if already in bashrc
    if ! grep -q "KODACHI_HOME=\"$INSTALL_PATH\"" "$HOME/.bashrc" 2>/dev/null; then
        echo "" >> "$HOME/.bashrc"
        echo "# Kodachi Binary Tools" >> "$HOME/.bashrc"
        echo "export KODACHI_HOME=\"$INSTALL_PATH\"" >> "$HOME/.bashrc"
        echo "export PATH=\"\$KODACHI_HOME:\$PATH\"" >> "$HOME/.bashrc"
        print_success "Added to .bashrc"
    else
        print_info "Already in .bashrc"
    fi
fi

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
        echo -e "   ${BOLD}curl -sSL $CDN_BASE/kodachi-deps-install.sh | sudo bash${NC}"
        echo ""
        echo "2. Deploy binaries globally (requires sudo):"
        echo -e "   ${BOLD}sudo $INSTALL_PATH/global-launcher deploy${NC}"
        echo "   This creates symlinks in /usr/local/bin for system-wide access"
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
        echo -e "   ${BOLD}sudo bash ~/kodachi-deps-install.sh${NC}"
        echo ""
        echo "2. Deploy binaries globally:"
        echo -e "   ${BOLD}sudo $INSTALL_PATH/global-launcher deploy${NC}"
    fi
}

echo ""
# Check sudoers status and provide appropriate next steps
check_sudoers_status
echo ""

# Download dependency installer for convenience
print_step "Downloading dependency installer for later use..."
DEPS_SCRIPT="$HOME/kodachi-deps-install.sh"
if download_with_retry "$CDN_BASE/kodachi-deps-install.sh" "$DEPS_SCRIPT"; then
    chmod +x "$DEPS_SCRIPT"
    print_success "Dependency installer saved to: $DEPS_SCRIPT"
    echo ""
    print_info "To install dependencies later, run:"
    echo "  sudo bash $DEPS_SCRIPT"
else
    print_warning "Could not download dependency installer"
    print_info "You can download it later from:"
    echo "  $CDN_BASE/kodachi-deps-install.sh"
fi

echo ""
print_success "Binary installation complete! No sudo was required."
echo ""