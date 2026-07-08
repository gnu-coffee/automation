#!/usr/bin/env python3
# =============================================================================
# Script Name: tor-bridge-grabber.py
# Author: gnu-coffee
# Created: 2026-07-08
# Description: This is easy way to grab tor bridges. But remember you need to run tor service on your machine first!
# License: GNU General Public License v3 (GPLv3)
# =============================================================================

import re
import sys
import argparse
import requests
from bs4 import BeautifulSoup

URL = "https://bridges.torproject.org/bridges/en?transport=obfs4"
TORRC = "/etc/tor/torrc"

FINGERPRINT_RE = re.compile(r"^[A-Fa-f0-9]{40}$")


def parse_args():
    parser = argparse.ArgumentParser(
        usage="python3 %(prog)s -p PORT",
        description="Retrieve Tor bridge lines from the Tor Project website.",
        epilog=(
            "Requirements:\n"
            "  - Tor service must already be running.\n"
            "  - Configure Tor with a SocksPort (for example 2525).\n"
            "  - Install: requests, beautifulsoup4, pysocks\n\n"
            "Example:\n"
            "  python3 bridge-fetch.py --port 2525"
        ),
        formatter_class=argparse.RawTextHelpFormatter,
    )

    parser.add_argument(
        "-p",
        "--port",
        required=True,
        type=int,
        metavar="PORT",
        help="Tor SOCKS5 port (e.g. 9050 or 2525).",
    )

    return parser.parse_args()


def get_fingerprint(line):
    """Extract a 40-character hexadecimal fingerprint from a bridge line."""
    for field in line.split():
        if FINGERPRINT_RE.fullmatch(field):
            return field
    return None


def load_existing_fingerprints():
    fingerprints = set()

    try:
        with open(TORRC, "r") as f:
            for line in f:
                fp = get_fingerprint(line)
                if fp:
                    fingerprints.add(fp)
    except FileNotFoundError:
        pass

    return fingerprints


def main():
    args = parse_args()

    proxy = f"socks5h://127.0.0.1:{args.port}"

    session = requests.Session()
    session.proxies = {
        # Uncomment the following line to enable HTTP support.
        # "http": proxy,
        "https": proxy,
    }
    
    try:
        response = session.get(URL, timeout=30)
        response.raise_for_status()
    except requests.exceptions.ConnectionError:
        print(
            " [-] Error: Unable to connect to the Tor SOCKS proxy.\n"
            "     Please make sure:\n"
            "         - Tor is running.\n"
            "         - The SOCKS port is correct.\n"
            "         - Tor is listening on 127.0.0.1."
        )
        sys.exit(1)

    except requests.exceptions.Timeout:
        print("Error: Connection timed out.")
        sys.exit(1)
    
    except requests.exceptions.HTTPError as e:
        print(f"HTTP error: {e.response.status_code}")
        sys.exit(1)

    except requests.exceptions.RequestException as e:
        print(f"Request failed: {e}")
        sys.exit(1) 

    soup = BeautifulSoup(response.text, "html.parser")

    bridges = soup.find("div", id="bridgelines")

    if bridges is None:
        print(" [-] Error: The bridgelines div not found!")
        return

    existing = load_existing_fingerprints()

    new_bridges = []

    for line in bridges.stripped_strings:
        fp = get_fingerprint(line)

        if fp is None:
            continue

        if fp not in existing:
            new_bridges.append(line)

    if not new_bridges:
        print(" [*] No new bridges found!")
        return

    print(" [+] New bridges:")
    for bridge in new_bridges:
        print(f"\t"+bridge)

if __name__ == "__main__":
    main()
