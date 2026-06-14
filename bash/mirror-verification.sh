#!/bin/bash
set -euo pipefail

# ==========================================================
# Colors
# ==========================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[+]${NC} $1"; }
info() { echo -e "${CYAN}[*]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[-]${NC} $1"; }

trap 'err "FAILED at line $LINENO"' ERR

# ==========================================================
# System constraints
# ==========================================================

ARCH="$(dpkg --print-architecture)"
[[ "$ARCH" != "amd64" ]] && err "Only amd64 supported!" && exit 1

# Detect release from system
RELEASE=$(grep -R "^Suites:" /etc/apt/sources.list /etc/apt/sources.list.d/*.sources 2>/dev/null \
  | awk '{for(i=2;i<=NF;i++) print $i}' \
  | grep -E "stable|testing|unstable|bookworm|trixie" \
  | head -n1 || true)

ALLOWED=0

for r in $RELEASE; do
    case "$r" in
        stable|testing|unstable|bookworm|trixie)
            ALLOWED=1
            ;;
        *)
            err "Invalid APT release detected: $r"
            exit 1
            ;;
    esac
done

if [[ -z "$RELEASE" ]]; then
    err "No APT release detected"
    exit 1
fi

ok "APT release is valid: $RELEASE"

# ==========================================================
# Mirror dictionary (EASILY EXTENDABLE)
# ==========================================================

declare -A MIRRORS=(
    ["shatel"]="https://mirror.shatel.ir/debian"
    ["parspack"]="https://repo.abrha.net/debian"
    ["arvancloud"]="https://mirror.arvancloud.ir/debian"
)

declare -A SECURITY_MIRRORS=(
    ["shatel"]="https://mirror.shatel.ir/debian-security"
    ["parspack"]="https://repo.abrha.net/debian-security"
    ["arvancloud"]="https://mirror.arvancloud.ir/debian-security "
)

OFFICIAL="https://deb.debian.org/debian"
SEC_OFFICIAL="https://security.debian.org/debian-security"

# ==========================================================
# Workdir
# ==========================================================

WORKDIR="/tmp/repo-audit"
mkdir -p "$WORKDIR"
trap 'rm -rf "$WORKDIR"' EXIT

# ==========================================================
# Detect active mirror (IMPORTANT LOGIC)
# ==========================================================

info "Detecting active system mirror..."
POLICY_OUTPUT=$(apt-cache policy)

ACTIVE=""

while read -r line; do
    case "$line" in
        *shatel*)
            ACTIVE="shatel"
            ;;
        *abrha*)
            ACTIVE="parspack"
            ;;
        *arvancloud*)
            ACTIVE="arvancloud"
            ;;
    esac
done <<< "$POLICY_OUTPUT"

if [[ -z "$ACTIVE" ]]; then
    err "No known mirror detected in apt-cache policy"
    exit 1
fi

ok "Detected mirror: $ACTIVE"

MIRROR="${MIRRORS[$ACTIVE]}"
SECURITY_MIRROR="${SECURITY_MIRRORS[$ACTIVE]}"

# ==========================================================
# Components check (non-blocking)
# ==========================================================

info "Checking APT components..."

for c in main contrib non-free non-free-firmware; do
    grep -Rq "$c" /etc/apt 2>/dev/null || warn "Missing component: $c"
done

# ==========================================================
# Header
# ==========================================================

echo "======================================"
echo " Debian Mirror Audit (Active mode)"
echo " Mirror: $ACTIVE"
echo " Release: $RELEASE | Arch: $ARCH"
echo "======================================"

# ==========================================================
# Safe fetch
# ==========================================================

fetch() {
    curl -fsSL --retry 2 --max-time 120 "$1" -o "$2" || {
        warn "Fetch failed: $1"
        return 1
    }
}

# ==========================================================
# Helpers
# ==========================================================

extract_sha() {
    grep -A1 "SHA256" "$1" 2>/dev/null | tail -n +2 | sha256sum | awk '{print $1}' || echo "0"
}

get_date() {
    grep "^Date:" "$1" 2>/dev/null | cut -d' ' -f2- || echo ""
}

# ==========================================================
# Step 1 - Fetch ONLY active + official
# ==========================================================

info "[1] Fetching metadata..."

OFF="$WORKDIR/official"
ACT="$WORKDIR/active"

fetch "$OFFICIAL/dists/$RELEASE/InRelease" "$OFF"
fetch "$MIRROR/dists/$RELEASE/InRelease" "$ACT"

ok "    Metadata fetched"

# ==========================================================
# Step 2 - Signature check
# ==========================================================

info "[2] Signature check"

KEYRING="/usr/share/keyrings/debian-archive-keyring.gpg"

gpgv --keyring "$KEYRING" "$OFF" >/dev/null 2>&1 && echo "        Official: OK" || echo "        Official: FAIL"
gpgv --keyring "$KEYRING" "$ACT" >/dev/null 2>&1 && echo "        Active:   OK" || echo "        Active:   FAIL"

# ==========================================================
# Step 3 - Integrity
# ==========================================================

info "[3] Integrity check"

OFF_SHA=$(extract_sha "$OFF")
ACT_SHA=$(extract_sha "$ACT")

if [[ "$OFF_SHA" == "$ACT_SHA" ]]; then
    echo "        MATCH"
else
    echo "        MISMATCH"
fi

# ==========================================================
# Step 4 - Freshness
# ==========================================================

info "[4] Freshness"

OFF_DATE=$(get_date "$OFF")
ACT_DATE=$(get_date "$ACT")

OFF_TS=$(date -d "$OFF_DATE" +%s 2>/dev/null || echo 0)
ACT_TS=$(date -d "$ACT_DATE" +%s 2>/dev/null || echo 0)

DELAY=$(((OFF_TS - ACT_TS) / 3600))

echo "        Delay: ${DELAY}h"

# ==========================================================
# Step 5 - Security
# ==========================================================

info "[5] Security check"

SEC_OFF="$WORKDIR/sec_off"
SEC_ACT="$WORKDIR/sec_act"

fetch "$SEC_OFFICIAL/dists/${RELEASE}-security/InRelease" "$SEC_OFF"
fetch "${SECURITY_MIRRORS[$ACTIVE]}/dists/${RELEASE}-security/InRelease" "$SEC_ACT"

SEC_OFF_TS=$(date -d "$(get_date "$SEC_OFF")" +%s 2>/dev/null || echo 0)
SEC_ACT_TS=$(date -d "$(get_date "$SEC_ACT")" +%s 2>/dev/null || echo 0)

SEC_DELAY=$(((SEC_OFF_TS - SEC_ACT_TS) / 3600))

echo "        Security delay: ${SEC_DELAY}h"

# ==========================================================
# Step 6 - Package drift
# ==========================================================

info "[6] Package drift"

OFF_P="$WORKDIR/off.pack"
ACT_P="$WORKDIR/act.pack"

fetch "$OFFICIAL/dists/$RELEASE/main/binary-$ARCH/Packages.gz" "$WORKDIR/off.gz"
fetch "$MIRROR/dists/$RELEASE/main/binary-$ARCH/Packages.gz" "$WORKDIR/act.gz"

zcat "$WORKDIR/off.gz" 2>/dev/null | grep "^Package:" | sort > "$OFF_P" || true
zcat "$WORKDIR/act.gz" 2>/dev/null | grep "^Package:" | sort > "$ACT_P" || true

DIFF=$(diff "$OFF_P" "$ACT_P" 2>/dev/null | wc -l || true)

echo "        Drift: $DIFF"

# ==========================================================
# Step 7 - Score
# ==========================================================

info "[7] Score"

SCORE=100

[[ "$OFF_SHA" != "$ACT_SHA" ]] && SCORE=$((SCORE - 40))
[[ "$DELAY" -gt 2 ]] && SCORE=$((SCORE - 20))
[[ "$SEC_DELAY" -gt 1 ]] && SCORE=$((SCORE - 30))
[[ "$DIFF" -gt 0 ]] && SCORE=$((SCORE - 10))

(( SCORE < 0 )) && SCORE=0

echo "======================================"
echo " RESULT"
echo "======================================"
echo "Active mirror: $ACTIVE"
echo "Release:       $RELEASE"
echo "Arch:          $ARCH"
echo "Delay:         ${DELAY}h"
echo "Security:      ${SEC_DELAY}h"
echo "Drift:         $DIFF"
echo "Score:         $SCORE/100"
echo "======================================"

if [[ $SCORE -ge 90 ]]; then
    echo "STATUS: HEALTHY"
elif [[ $SCORE -ge 70 ]]; then
    echo "STATUS: ACCEPTABLE"
else
    echo "STATUS: RISKY"
fi

echo "======================================"
