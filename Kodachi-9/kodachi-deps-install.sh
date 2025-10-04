#!/bin/bash

# Kodachi Dependencies Installation Script (REQUIRES SUDO/ROOT)
# ==============================================================
#
# Author: Warith Al Maawali
# Copyright (c) 2025 Kodachi Security OS
# License: See LICENSE file or https://kodachi.cloud/license
#
# Version: 9.0.1
# Last updated: 2025-10-01
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
#   --minimal       Install critical packages, networking, and proxy tools
#   --full          Install all packages including optional ones (default)
#   --interactive   Interactive category-based installation with prompts
#   --proxy-only    Install only proxy tools (v2ray, xray, hysteria2, mieru)
#   --auto          Automatic mode - answer yes to all prompts (default)
#   --no-auto       Disable automatic mode - require user confirmation
#   --help          Show help message

# Strict mode - will be disabled for interactive mode
set -eo pipefail

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

# Version configuration
MIERU_VERSION="3.20.1"
HYSTERIA2_VERSION="2.6.3"
V2RAY_PLUGIN_VERSION="1.3.2"
DNSCRYPT_VERSION="2.1.14"
QRENCODE_VERSION="4.1.1"
KLOAK_VERSION="0.2"

# Package categories - Reorganized for interactive installation
# Essential - Core system requirements
ESSENTIAL_PACKAGES="curl wget openssl ca-certificates coreutils findutils grep procps psmisc systemd sudo dmidecode lsof acl util-linux mount uuid-runtime inotify-tools ntpsec"

# Networking - Network and VPN tools
NETWORK_PACKAGES="tor torsocks obfs4proxy openvpn wireguard-tools iptables nftables arptables ebtables iproute2 iputils-ping net-tools nyx apt-transport-tor shadowsocks-libev redsocks haproxy"

# Security - Protection and hardening tools
SECURITY_PACKAGES="ufw macchanger firejail apparmor apparmor-utils apparmor-profiles aide lynis rkhunter chkrootkit usbguard ecryptfs-utils cryptsetup-nuke-password fail2ban unattended-upgrades auditd libpam-pwquality libpam-google-authenticator secure-delete wipe nwipe"

# Privacy - DNS and anonymity tools  
PRIVACY_PACKAGES="dnsutils"

# Advanced - Specialized tools and utilities
ADVANCED_PACKAGES="jq git build-essential bleachbit rng-tools-debian haveged ccze yamllint kitty alsa-utils pulseaudio pulseaudio-utils libnotify-bin smartmontools lm-sensors hdparm htop iotop vnstat efibootmgr rfkill"

# Packages that require contrib/non-free repositories
CONTRIB_PACKAGES="shadowsocks-v2ray-plugin v2ray"

# Separate resolvconf as it can conflict with systemd-resolved
RESOLVCONF_PACKAGE="resolvconf"

# Parse command line arguments
INSTALL_MODE="full"
AUTO_YES=true

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
        --help)
            echo "Kodachi Dependencies Installation Script"
            echo ""
            echo "Usage:"
            echo "  curl -sSL .../kodachi-deps-install.sh | sudo bash"
            echo "  sudo bash kodachi-deps-install.sh [options]"
            echo ""
            echo "Options:"
            echo "  --minimal       Install only critical packages"
            echo "  --full          Install all packages (default)"
            echo "  --interactive   Interactive category-based installation"
            echo "  --proxy-only    Install only proxy tools"
            echo "  --auto          Automatic mode - answer yes to all prompts (default)"
            echo "  --no-auto       Disable automatic mode - require user confirmation"
            echo "  --help          Show this help message"
            echo ""
            echo "Examples:"
            echo "  sudo bash kodachi-deps-install.sh --full --auto"
            echo "  sudo bash kodachi-deps-install.sh --interactive"
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

        # Option 1: Try openresolv as an alternative (more compatible)
        print_step "Installing openresolv as resolvconf alternative..."
        if apt-get install -y openresolv 2>&1 | tail -5; then
            if command -v resolvconf &>/dev/null; then
                print_success "openresolv installed successfully (provides resolvconf command)"
                return 0
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
            print_info "Note: DNS updates from VPNs will be ignored (managed by dnscrypt-proxy/Pi-hole)"
            return 0
        fi
    fi

    # If no VPN tools or alternatives worked, that's fine
    print_info "resolvconf not needed - DNS managed by dnscrypt-proxy/Pi-hole"
    print_info "If you use WireGuard/OpenVPN, DNS updates may need manual configuration"
    return 0
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

# Function to install DNSCrypt Proxy from GitHub
install_dnscrypt_github() {
    print_step "Installing DNSCrypt Proxy from GitHub..."

    if command -v dnscrypt-proxy &>/dev/null; then
        print_success "DNSCrypt Proxy is already installed"
        return 0
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

    if curl -LS --connect-timeout 30 --max-time 120 --progress-bar -o "$temp_dir/dnscrypt-proxy.tar.gz" "$url"; then
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
    print_step "Installing QRencode..."

    if command -v qrencode &>/dev/null; then
        print_success "QRencode is already installed"
        return 0
    fi

    # QRencode Installation Strategy:
    # - APT first: Same version (4.1.1), pre-compiled, faster installation
    # - GitHub fallback: For systems without apt package or version mismatch
    # - Compilation avoided when possible to reduce dependencies and time
    # - Archive URL used instead of releases/download (which doesn't exist)
    
    local install_success=false

    # Try APT installation first (preferred method)
    print_info "Attempting APT installation first (faster, pre-compiled)..."
    if timeout 60 apt-get install -y qrencode 2>/dev/null; then
        if command -v qrencode &>/dev/null; then
            print_success "QRencode installed successfully via APT"
            return 0
        fi
    fi

    # Fallback to GitHub compilation if APT fails
    print_warning "APT installation failed, falling back to GitHub compilation..."
    local url="https://github.com/fukuchi/libqrencode/archive/v${QRENCODE_VERSION}.tar.gz"
    local temp_dir="/tmp/qrencode-install-$$"

    echo "Installing build dependencies for compilation..."
    # Install build dependencies
    apt-get update 2>/dev/null || true
    apt-get install -y build-essential libpng-dev 2>&1 | tail -5

    echo "Downloading QRencode v${QRENCODE_VERSION} source..."
    mkdir -p "$temp_dir"
    cd "$temp_dir" || return 1

    # Download source from GitHub (using fixed archive URL)
    if curl -L --connect-timeout 30 --max-time 120 -O "$url" 2>/dev/null; then
        echo "Downloaded QRencode source from GitHub"
        
        # Extract and compile
        if tar xf "v${QRENCODE_VERSION}.tar.gz" 2>/dev/null; then
            cd "libqrencode-${QRENCODE_VERSION}" || return 1
            
            if ./configure --prefix=/usr/local >/dev/null 2>&1 && \
               make >/dev/null 2>&1 && \
               make install >/dev/null 2>&1; then
                
                # Update library cache
                ldconfig 2>/dev/null || true
                
                # Verify installation
                if command -v qrencode &>/dev/null || [ -x /usr/local/bin/qrencode ]; then
                    print_success "QRencode compiled and installed successfully from GitHub"
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
    print_step "Installing v2ray-plugin from GitHub..."

    if command -v v2ray-plugin &>/dev/null; then
        print_success "v2ray-plugin is already installed"
        return 0
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
        ((i++))
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
            timeout 60 apt-get install -y --no-install-recommends $rkhunter_separate 2>&1 | tail -5
        fi

        # Install other packages normally
        local install_result=true
        if [[ -n "$other_packages" ]]; then
            if ! timeout 60 apt-get install -y $other_packages 2>&1 | tail -5; then
                install_result=false
            fi
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

            # Retry installation once
            print_info "Retrying installation..."
            if timeout 60 apt-get install -y $to_install 2>&1 | tail -5; then
                print_success "Retry successful"
            fi

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
            if timeout 60 apt-get install -y shadowsocks-v2ray-plugin 2>&1 | tail -5; then
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
            if timeout 60 apt-get install -y v2ray 2>&1 | tail -5; then
                print_success "v2ray installed via apt"
                v2ray_installed=true
            else
                print_warning "Failed to install v2ray via apt"
                print_info "v2ray may require manual installation or is not available in your distribution"
            fi
        fi
    else
        # Repositories not enabled - handle fallback installations
        if ! $v2ray_plugin_installed || ! $v2ray_installed; then
            show_repo_warning=true
        fi

        if $show_repo_warning; then
            print_warning "Contrib and/or non-free repositories are NOT enabled!"
            echo ""
            print_highlight "IMPORTANT: Some packages require contrib and non-free repositories"
            echo ""
            print_info "To enable them, add 'contrib non-free' to your sources.list:"
            echo -e "  ${BOLD}sudo nano /etc/apt/sources.list${NC}"
            echo ""
            echo "Example for Debian Bookworm:"
            echo -e "  ${CYAN}deb http://deb.debian.org/debian/ bookworm main contrib non-free non-free-firmware${NC}"
            echo -e "  ${CYAN}deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware${NC}"
            echo -e "  ${CYAN}deb http://deb.debian.org/debian/ bookworm-updates main contrib non-free non-free-firmware${NC}"
            echo ""
            print_info "After enabling, run: sudo apt update"
            echo ""
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
        if timeout 60 apt-get install -y v2ray 2>&1 | tail -5; then
            if command -v v2ray &>/dev/null; then
                print_success "v2ray installed via apt"
                return 0
            fi
        fi
    fi

    # Fallback to GitHub installation
    echo "Installing v2ray from GitHub..."
    # Download and execute the v2ray installer script
    if curl -L --connect-timeout 30 --max-time 120 https://github.com/v2fly/fhs-install-v2ray/raw/master/install-release.sh -o /tmp/v2ray-install.sh; then
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
    if timeout 120 bash -c "$(curl -L --connect-timeout 30 --max-time 120 https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root; then
        print_success "xray installed successfully"
    else
        print_error "Failed to install xray"
    fi
}

# Function to install mieru
install_mieru() {
    print_step "Installing mieru client..."

    if command -v mieru &>/dev/null || dpkg -l mieru 2>/dev/null | grep -q "^ii"; then
        print_success "mieru client is already installed"
        return 0
    fi

    local temp_file="/tmp/mieru_${MIERU_VERSION}_amd64.deb"
    local url="https://github.com/enfein/mieru/releases/download/v${MIERU_VERSION}/mieru_${MIERU_VERSION}_amd64.deb"

    echo "Downloading mieru client..."
    if curl -LS --connect-timeout 30 --max-time 120 --progress-bar -o "$temp_file" "$url"; then
        echo "Installing mieru client package..."

        # Make sure no apt is running
        cleanup_apt

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
    print_step "Installing hysteria2..."

    if command -v hysteria &>/dev/null; then
        print_success "hysteria2 is already installed"
        return 0
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

    local version=$(curl -s --connect-timeout 10 --max-time 30 https://api.github.com/repos/apernet/hysteria/releases/latest 2>/dev/null | grep -Po '"tag_name": "app/\K[^"]*' || echo "$HYSTERIA2_VERSION")
    local url="https://github.com/apernet/hysteria/releases/download/app%2F${version}/hysteria-linux-${arch}"

    echo "Downloading hysteria2..."
    if curl -L --connect-timeout 30 --max-time 120 --progress-bar -o /tmp/hysteria "$url"; then
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
    print_step "Installing kloak (keystroke anonymization)..."

    if command -v kloak &>/dev/null; then
        print_success "kloak is already installed"
        setup_kloak_service
        return 0
    fi

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
    
    if curl -L --connect-timeout 30 --max-time 120 -o kloak.tar.gz "https://github.com/vmonaco/kloak/archive/v${KLOAK_VERSION}.tar.gz"; then
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

# Function to install Pi-hole
# To uninstall Pi-hole, run: echo -e "yes\nno\nno\nno\nno\nno\nno\nno\nno\nno" | sudo pihole uninstall
install_pihole() {
    print_step "Installing Pi-hole..."

    # Check if Pi-hole is already installed
    if systemctl status pihole-FTL &>/dev/null || command -v pihole &>/dev/null; then
        print_success "Pi-hole is already installed"

        # Try to get Pi-hole status
        if command -v pihole &>/dev/null; then
            pihole status 2>/dev/null | head -5 || true
        fi
        return 0
    fi

    echo "Pi-hole is not installed. Installing now..."
    echo ""

    if [[ "$AUTO_YES" == "true" ]]; then
        print_info "Auto mode: Installing Pi-hole with default settings (Quad9 Unfiltered DNS)..."

        # Generate setupVars.conf for unattended installation
        if generate_pihole_setupvars; then
            # Run Pi-hole installer in unattended mode
            if curl -sSL https://install.pi-hole.net | bash /dev/stdin --unattended; then
                print_success "Pi-hole installed successfully in unattended mode"

                # Display saved password if available
                if [[ -f /etc/pihole/.webpassword_initial ]]; then
                    local saved_password=$(cat /etc/pihole/.webpassword_initial)
                    print_info "Pi-hole Web Interface Password: $saved_password"
                    print_warning "Password saved to: /etc/pihole/.webpassword_initial"
                fi
            else
                print_error "Pi-hole unattended installation failed"
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
        # Run Pi-hole installer
        curl -sSL https://install.pi-hole.net | bash
    fi

    # Check installation result
    if command -v pihole &>/dev/null || systemctl is-active --quiet pihole-FTL 2>/dev/null; then
        print_success "Pi-hole installed successfully"

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

# Function to install RAM wipe packages with user confirmation
install_ram_wipe_packages() {
    print_step "Advanced Security Tools Installation"
    echo ""
    print_warning "The following advanced security tools will be installed:"
    echo ""
    echo -e "  ${BOLD}RAM Wipe Tools:${NC}"
    echo -e "    ${BOLD}dracut${NC} - Initramfs infrastructure for secure boot operations"
    echo -e "    ${BOLD}dracut-core${NC} - Core components for dracut framework"
    echo -e "    ${BOLD}ram-wipe${NC} - Securely wipes RAM contents on shutdown/reboot"
    echo ""
    echo -e "  ${BOLD}Keystroke Anonymization:${NC}"
    echo -e "    ${BOLD}kloak${NC} - Obfuscates typing behavior to prevent keystroke biometrics"
    echo ""
    print_highlight "These tools provide:"
    echo "  • Protection against cold boot attacks"
    echo "  • Secure erasure of sensitive data from RAM"
    echo "  • Enhanced privacy when shutting down the system"
    echo "  • Keystroke timing anonymization to prevent typing fingerprinting"
    echo ""
    print_warning "RAM wiping may slow down shutdown/reboot processes."
    print_warning "Kloak service will be enabled but not started (manual activation required)."
    echo ""
    
    # Ask for user confirmation
    if [[ "$AUTO_YES" == "true" ]]; then
        print_info "Auto mode: Installing advanced security tools..."
        REPLY="yes"
        else
            # FIXED: Simple working input method (stdin already redirected via exec)
            echo -n "Do you want to install advanced security tools (RAM wipe + keystroke anonymization)? (YES/no) [default: yes]: "
            read -r REPLY
            # Default to YES if empty
            if [[ -z "$REPLY" ]]; then
                REPLY="yes"
            fi
            echo ""
        fi
    
    if [[ $REPLY =~ ^[Yy]([Ee][Ss])?$ ]]; then
        print_info "Installing RAM wipe packages..."
        
        # First install dracut packages from standard repos
        print_step "Installing dracut packages..."
        if apt-get install -y dracut dracut-core 2>&1 | tail -5; then
            print_success "dracut packages installed successfully"
        else
            print_warning "Failed to install some dracut packages"
        fi
        
        # Check if Kicksecure repository is already configured
        if [[ -f "/etc/apt/sources.list.d/kicksecure.list" ]] && [[ -f "/usr/share/keyrings/kicksecure.gpg" ]]; then
            print_info "Kicksecure repository already configured"
        else
            print_step "Adding Kicksecure repository for ram-wipe..."
            
            # Create keyrings directory
            install -d -m 0755 /usr/share/keyrings
            
            # Import repo key
            print_info "Importing Kicksecure repository key..."
            if curl -fsSL https://www.kicksecure.com/keys/derivative.asc | gpg --dearmor -o /usr/share/keyrings/kicksecure.gpg; then
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
        if apt-get install -y ram-wipe 2>&1 | tail -5; then
            print_success "ram-wipe installed successfully"
            echo ""
            print_info "RAM wipe is now configured and will activate on shutdown/reboot"
            print_info "To check status: sudo systemctl status ram-wipe"
        else
            print_error "Failed to install ram-wipe"
            print_info "You may need to troubleshoot the Kicksecure repository"
        fi
        
        # Install kloak (keystroke anonymization)
        echo ""
        print_step "Installing kloak (keystroke anonymization)..."
        install_kloak
        
    else
        print_info "Skipping advanced security tools installation"
        echo ""
        print_highlight "To install advanced security tools manually:"
        echo ""
        echo -e "  ${BOLD}RAM Wipe Tools:${NC}"
        echo "    # Install dracut packages"
        echo -e "    ${BOLD}sudo apt-get install dracut dracut-core${NC}"
        echo ""
        echo "    # Import Kicksecure repo key"
        echo -e "    ${BOLD}sudo install -d -m 0755 /usr/share/keyrings${NC}"
        echo -e "    ${BOLD}curl -fsSL https://www.kicksecure.com/keys/derivative.asc | sudo gpg --dearmor -o /usr/share/keyrings/kicksecure.gpg${NC}"
        echo ""
        echo "    # Add repository (adjust codename for your Debian version)"
        echo -e "    ${BOLD}echo 'deb [signed-by=/usr/share/keyrings/kicksecure.gpg] https://deb.kicksecure.com bookworm main' | sudo tee /etc/apt/sources.list.d/kicksecure.list${NC}"
        echo ""
        echo "    # Update and install ram-wipe"
        echo -e "    ${BOLD}sudo apt-get update${NC}"
        echo -e "    ${BOLD}sudo apt-get install -y ram-wipe${NC}"
        echo ""
        echo -e "  ${BOLD}Keystroke Anonymization (Kloak):${NC}"
        echo "    # Compile from source"
        echo -e "    ${BOLD}sudo apt-get install make libevdev-dev build-essential${NC}"
        echo -e "    ${BOLD}curl -L https://github.com/vmonaco/kloak/archive/v0.2.tar.gz | tar xz${NC}"
        echo -e "    ${BOLD}cd kloak-0.2 && make all && sudo mv kloak /usr/local/bin/${NC}"
        echo ""
        echo "    # Or install from Whonix repository"
        echo -e "    ${BOLD}curl -fsSL https://www.whonix.org/patrick.asc | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/whonix.gpg${NC}"
        echo -e "    ${BOLD}echo 'deb https://deb.whonix.org bullseye main' | sudo tee /etc/apt/sources.list.d/whonix.list${NC}"
        echo -e "    ${BOLD}sudo apt-get update && sudo apt-get install kloak${NC}"
        echo ""
    fi
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
  • Network tools: curl, wget, openssl
  • System utilities: sudo, systemd, mount
  • File operations: coreutils, findutils, grep"
    
    ESSENTIAL_MANUAL="  sudo apt-get install curl wget openssl ca-certificates coreutils findutils grep \\
    procps psmisc systemd sudo dmidecode lsof acl util-linux mount \\
    uuid-runtime inotify-tools"
    
    install_category_interactive "$ESSENTIAL_PACKAGES" "Essential" "$ESSENTIAL_DESC" "$ESSENTIAL_MANUAL"
    ensure_dpkg_healthy
    
    # Networking packages
    NETWORK_DESC="Network and VPN connectivity tools:
  • Anonymity: Tor network and configuration
  • VPN support: OpenVPN, WireGuard
  • Firewall: iptables, nftables
  • Proxy tools: Shadowsocks, Redsocks, HAProxy"
    
    NETWORK_MANUAL="  sudo apt-get install tor openvpn wireguard-tools iptables nftables \\
    arptables ebtables iproute2 iputils-ping net-tools nyx apt-transport-tor \\
    shadowsocks-libev redsocks haproxy"
    
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
    
    # Advanced packages  
    ADVANCED_DESC="Additional tools and utilities:
  • Development: git, build-essential
  • System monitoring: htop, iotop, sensors
  • Terminal: kitty (emoji support)
  • Audio support: PulseAudio, ALSA
  • Hardware tools: smartmontools, rfkill"
    
    ADVANCED_MANUAL="  sudo apt-get install jq git build-essential bleachbit rng-tools-debian \\
    haveged ccze yamllint kitty qrencode alsa-utils pulseaudio \\
    pulseaudio-utils libnotify-bin smartmontools lm-sensors hdparm \\
    htop iotop vnstat efibootmgr rfkill"
    
    install_category_interactive "$ADVANCED_PACKAGES" "Advanced" "$ADVANCED_DESC" "$ADVANCED_MANUAL"
    ensure_dpkg_healthy
    
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
    
    # Advanced security tools (RAM wipe + keystroke anonymization)
    echo ""
    install_ram_wipe_packages

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
    # Install DNS packages
    install_packages "$PRIVACY_PACKAGES" "Privacy"
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
    install_packages "$PRIVACY_PACKAGES" "Privacy"
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

    # Also install proxy tools
    echo ""
    print_highlight "Installing Proxy Tools"
    echo ""
    install_v2ray
    install_xray
    install_hysteria2
    install_mieru
    
    # Install advanced security tools (RAM wipe + keystroke anonymization)
    echo ""
    install_ram_wipe_packages

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
    install_packages "$PRIVACY_PACKAGES" "Privacy"
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

    # Also install proxy tools
    echo ""
    print_highlight "Installing Proxy Tools"
    echo ""
    install_v2ray
    install_xray
    install_hysteria2
    install_mieru
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
for tool in wireguard-tools shadowsocks-libev redsocks iptables nftables; do
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

# Check RAM wipe security tools (Kick Secure)
echo ""
print_step "Checking RAM wipe security tools (Kick Secure)..."
if check_package "ram-wipe"; then
    echo -e "  ${GREEN}✓${NC} ram-wipe - installed"
else
    echo -e "  ${YELLOW}!${NC} ram-wipe - not found (advanced security tool)"
fi

if check_package "dracut"; then
    echo -e "  ${GREEN}✓${NC} dracut - installed"
else
    echo -e "  ${YELLOW}!${NC} dracut - not found"
fi

if check_package "dracut-core"; then
    echo -e "  ${GREEN}✓${NC} dracut-core - installed"
else
    echo -e "  ${YELLOW}!${NC} dracut-core - not found"
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

# Final status
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Dependency Installation Complete!          ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""

print_success "Script execution complete!"

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
            rm -rf ${file_pattern} 2>/dev/null && ((cleaned_files++))
        fi
    done
    
    # Clean up any other GitHub-related temp files
    find /tmp -maxdepth 1 -name "*github*" -o -name "*install*" -o -name "*.tar.gz" -o -name "*.deb" 2>/dev/null | while read temp_file; do
        if [[ -f "$temp_file" ]] || [[ -d "$temp_file" ]]; then
            rm -rf "$temp_file" 2>/dev/null && ((cleaned_files++))
        fi
    done
    
    if [[ $cleaned_files -gt 0 ]]; then
        print_success "Cleaned up $cleaned_files temporary files"
    else
        print_info "No temporary files to clean up"
    fi
}

cleanup_github_temp_files

# Final Pi-hole installation reminder if not installed
if [[ "$PIHOLE_INSTALLED" == "false" ]]; then
    echo ""
    print_warning "Pi-hole was NOT installed!"
    echo ""
    print_info "Pi-hole provides network-wide ad blocking and DNS filtering."
    print_info "To install Pi-hole manually, run:"
    echo ""
    echo -e "  ${BOLD}${CYAN}curl -sSL https://install.pi-hole.net | bash${NC}"
    echo ""
    print_info "Note: Pi-hole installation is interactive and requires configuration."
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

# Check if binaries are installed
if command -v ip-fetch &>/dev/null 2>&1; then
    print_success "Kodachi binaries detected in PATH"
    echo ""
    print_info "You can now use Kodachi tools!"
else
    print_warning "Kodachi binaries not detected in PATH"
    echo ""
    print_info "If you haven't installed the binaries yet, run:"
    echo "  curl -sSL https://www.kodachi.cloud/apps/os/install/kodachi-binary-install.sh | bash"
    echo ""
    print_info "Or if already installed, reload your PATH:"
    echo "  source ~/.bashrc"
fi

echo ""
print_success "Dependencies installation complete!"
echo ""

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
            if printf "%s\n%s\n" "$new_pihole_password" "$new_pihole_password" | pihole setpassword 2>/dev/null; then
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