#!/usr/bin/env python3

# =============================================================================
# Script Name: mac-tool.py
# Author: gnu-coffee
# Created: 2026-06-30
# Description: Generate and Resolve MAC addresses
# License: GNU General Public License v3 (GPLv3)
# =============================================================================

import argparse
import re
import secrets
import sys

# ----------------------------------------------------
# Vendors Database
# ----------------------------------------------------

VENDORS = {
    "Dell": [
        "00:14:22",
        "18:03:73",
        "B8:CA:3A",
    ],
    "Cisco": [
        "00:1B:54",
        "00:25:45",
        "00:40:96",
    ],
    "Intel": [
        "00:1B:21",
        "3C:FD:FE",
        "A0:36:9F",
    ],
    "HPE": [
        "3C:52:82",
        "B4:99:BA",
    ],
    "MikroTik": [
        "4C:5E:0C",
        "D4:CA:6D",
    ],
    "Juniper": [
        "00:05:85",
        "2C:6B:F5",
    ],
}

# ----------------------------------------------------
# Reverse OUI Index
# ----------------------------------------------------

OUI_INDEX = {}

for vendor, ouis in VENDORS.items():
    for oui in ouis:
        OUI_INDEX[oui.upper()] = vendor

# ----------------------------------------------------
# Generator
# ----------------------------------------------------


def generate_mac(vendor):

    oui = secrets.choice(VENDORS[vendor])

    suffix = [
        secrets.randbelow(256),
        secrets.randbelow(256),
        secrets.randbelow(256),
    ]

    return "{}:{:02X}:{:02X}:{:02X}".format(
        oui,
        suffix[0],
        suffix[1],
        suffix[2],
    )


# ----------------------------------------------------
# Resolver
# ----------------------------------------------------


def resolve_mac(mac):

    mac = mac.upper().replace("-", ":")

    if not re.fullmatch(r"([0-9A-F]{2}:){5}[0-9A-F]{2}", mac):
        print(" [-] Invalid MAC address.")
        sys.exit(1)

    oui = ":".join(mac.split(":")[:3])

    return OUI_INDEX.get(oui, " [-] Not detected")


# ----------------------------------------------------
# Vendor Selection
# ----------------------------------------------------


def select_vendor():

    vendors = list(VENDORS.keys())

    print()

    for i, vendor in enumerate(vendors, start=1):
        print(f"     [{i}] {vendor}")

    print()

    while True:

        try:

            choice = int(input(" [*] Select Vendor: "))

            if 1 <= choice <= len(vendors):
                return vendors[choice - 1]

            print(" [-] Invalid selection!")

        except ValueError:
            print(" [-] Invalid input!")


# ----------------------------------------------------
# Count
# ----------------------------------------------------


def ask_count():

    while True:

        try:

            count = int(input(" [?] Number of MACs to generate: "))

            if count > 0:
                return count

            print(" [-] Number must be greater than zero!")

        except ValueError:
            print(" [-] Invalid input!")


# ----------------------------------------------------
# Generator Mode
# ----------------------------------------------------


def generator_mode():

    print(" [*] Please choose the vendor:")
    vendor = select_vendor()

    count = ask_count()
    print()
    print(f" [+] Vendor : {vendor}")
    print()

    print(f"     {'No.':<6}MAC Address")
    print("-" * 30)

    for i in range(1, count + 1):
        print(f"     {i:<6}{generate_mac(vendor)}")


# ----------------------------------------------------
# Resolver Mode
# ----------------------------------------------------


def resolver_mode(mac):

    vendor = resolve_mac(mac)

    print()
    print(f" [+] MAC    : {mac.upper()}")
    print(f" [+] Vendor : {vendor}")


# ----------------------------------------------------
# Main
# ----------------------------------------------------


def main():

    parser = argparse.ArgumentParser(
        description="MAC Address Generator & Resolver"
    )

    group = parser.add_mutually_exclusive_group(required=True)

    group.add_argument(
        "-g",
        "--generator",
        action="store_true",
        help="Generate MAC addresses",
    )

    group.add_argument(
        "-r",
        "--resolver",
        metavar="MAC",
        help="Resolve MAC vendor",
    )

    args = parser.parse_args()

    if args.generator:
        generator_mode()

    elif args.resolver:
        resolver_mode(args.resolver)


# ----------------------------------------------------

if __name__ == "__main__":

    try:
        main()

    except KeyboardInterrupt:
        print("\n [-] Exiting...")
        sys.exit(0)

    except EOFError:
        print("\n [-] Exiting...")
        sys.exit(0)
