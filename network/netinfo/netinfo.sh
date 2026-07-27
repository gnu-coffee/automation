#!/bin/bash

# =============================================================================
# Script Name: netinfo.sh
# Author: gnu-coffee
# Created: 2026-06-30
# Description: Show Network Interfaces Information On every linux distros
# License: GNU General Public License v3 (GPLv3)
# =============================================================================

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Header
printf "${GREEN}%-12s %-20s %-20s %-40s${NC}\n" \
    "Interface" "MAC" "IPv4" "IPv6"

for iface in /sys/class/net/*; do
    iface=${iface##*/}

    mac=$(<"/sys/class/net/$iface/address")
    ipv4=$(ip -4 -o addr show dev "$iface" | awk '{print $4}')
    ipv6=$(ip -6 -o addr show dev "$iface" scope global | awk '{print $4}')

    [[ -z $ipv4 ]] && ipv4="${RED}-${NC}"
    [[ -z $ipv6 ]] && ipv6="${RED}-${NC}"

    printf "${BLUE}%-12s${NC} %-20s %-20b %-40b\n" \
        "$iface" \
        "$mac" \
        "$ipv4" \
        "$ipv6"
done
