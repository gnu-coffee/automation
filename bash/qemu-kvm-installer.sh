#!/bin/bash

# =============================================================================
# Script Name: qemu-kvm-installer.sh
# Author: gnu-coffee
# Created: 2025-09-10
# Description: Install and configure QEMU/KVM on Debian/Ubuntu
# License: GNU General Public License v3 (GPLv3)
# =============================================================================

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Functions ---
error()    { echo -e "${RED}[-] $1${NC}"; exit 1; }
success()  { echo -e "${GREEN}[+] $1${NC}"; }
info()     { echo -e "${YELLOW}[*] $1${NC}"; }
question() { echo -e "${BLUE}[?] $1${NC}"; }

# --- Variables ---
USERNAME=""

# --- Usage ---
usage() {
    echo -e "Usage: $(basename "$0") [options]"
    echo -e "\t-u, --username <user>   Usename which is using qemu/kvm"
    echo -e "\t-h, --help              Show this help message"
    exit 1
}

# --- Parse arguments ---
if [[ $# -eq 0 ]]; then
    usage
fi

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -u|--username)
            USERNAME="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        -*)
            error "Unknown option: $1"
            ;;
        *)
            shift
            ;;
    esac
done

# --- Check username ---
if [[ -z "$USERNAME" ]]; then
    error "Username not specified. Use -u <username>."
fi

if ! id "$USERNAME" &>/dev/null; then
    error "User '$USERNAME' does not exist on this system."
fi
success "Using username: $USERNAME"

# --- Detect OS/Distro ---
OS_TYPE=$(uname -s)
DISTRO_FILE="/etc/os-release"

if [ "$OS_TYPE" != "Linux" ]; then
    error "Unsupported OS: $OS_TYPE. Only Linux is supported."
fi

if [ -f "$DISTRO_FILE" ]; then
    . "$DISTRO_FILE"
    DISTRO=$ID
    if [ "$DISTRO" != "debian" ] && [ "$DISTRO" != "ubuntu" ]; then
        error "Unsupported distribution: $DISTRO. Only Debian/Ubuntu are supported."
    fi
    success "Detected Linux/$DISTRO - Environment OK."
else
    error "Cannot detect distribution (missing /etc/os-release)."
fi

# --- Function to install package ---
install_pkg() {
    local pkg="$1"
    info "Installing package: $pkg ..."
    if apt-get install -y "$pkg" >/dev/null 2>&1; then
        success "Installed: $pkg"
    else
        error "Failed to install: $pkg"
    fi
}

# --- Update repositories ---
info "Updating package repositories..."
if apt-get update -y >/dev/null 2>&1; then
    success "Repositories updated."
else
    error "Failed to update repositories."
fi

# --- Install QEMU/KVM and related packages ---
PACKAGES=(
    qemu-kvm
    libvirt-daemon-system
    libvirt-clients
    bridge-utils
    qemu-guest-agent
    virt-manager
    cpu-checker
    hwloc
    libguestfs-tools
    virt-top
    virtiofsd
)

for pkg in "${PACKAGES[@]}"; do
    install_pkg "$pkg"
done

# --- Add user to groups ---
info "Adding user '$USERNAME' to libvirt and kvm groups..."
if adduser "$USERNAME" libvirt >/dev/null 2>&1 && adduser "$USERNAME" kvm >/dev/null 2>&1; then
    success "User '$USERNAME' added to libvirt and kvm groups."
else
    error "Failed to add user '$USERNAME' to groups."
fi

# --- Enable and start libvirtd ---
info "Enabling and starting libvirtd service..."
if systemctl enable --now libvirtd >/dev/null 2>&1; then
    success "libvirtd service enabled and started."
else
    error "Failed to enable/start libvirtd service."
fi

# --- Setup default network ---
info "Checking libvirt networks..."
if virsh net-list --all | grep -q "default"; then
    success "Default network found."
    info "Starting and enabling autostart for default network..."
    virsh net-start default >/dev/null 2>&1 || error "Failed to start default network."
    virsh net-autostart default >/dev/null 2>&1 || error "Failed to autostart default network."
    success "Default network is active and set to autostart."
else
    error "No default libvirt network found."
fi

success "QEMU/KVM installation and setup completed successfully!"
