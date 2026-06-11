#!/bin/bash
set -euo pipefail

OFFICIAL="https://deb.debian.org/debian"
SECURITY_OFFICIAL="https://security.debian.org/debian-security"

MIRROR="https://mirror.shatel.ir/debian"
SECURITY_MIRROR="https://mirror.shatel.ir/debian-security"
WORKDIR="/tmp/repo-audit"
mkdir -p "$WORKDIR"

OFF="$WORKDIR/official.InRelease"
MIR="$WORKDIR/mirror.InRelease"

echo "======================================"
echo " Debian Mirror Audit (7-Layer Check)"
echo "======================================"

########################################
# LAYER 1 - FETCH SNAPSHOTS
########################################
echo "[1] Fetching InRelease files..."

curl -fsSL "$OFFICIAL/dists/stable/InRelease" -o "$OFF"
curl -fsSL "$MIRROR/dists/stable/InRelease" -o "$MIR"

########################################
# LAYER 2 - SIGNATURE CHECK
########################################
echo "[2] Verifying GPG signatures..."

if gpgv --keyring /usr/share/keyrings/debian-archive-keyring.gpg "$OFF" >/dev/null 2>&1; then
    echo "  official: OK"
else
    echo "  official: FAIL"
fi

if gpgv --keyring /usr/share/keyrings/debian-archive-keyring.gpg "$MIR" >/dev/null 2>&1; then
    echo "  mirror: OK"
else
    echo "  mirror: FAIL"
fi

########################################
# LAYER 3 - METADATA DIFF (CORRUPTION CHECK)
########################################
echo "[3] Checking metadata consistency..."

OFF_SHA=$(grep -A1 "SHA256" "$OFF" | tail -n +2 | sha256sum | awk '{print $1}')
MIR_SHA=$(grep -A1 "SHA256" "$MIR" | tail -n +2 | sha256sum | awk '{print $1}')

if [[ "$OFF_SHA" == "$MIR_SHA" ]]; then
    echo "  SHA256 metadata: MATCH"
else
    echo "  SHA256 metadata: MISMATCH (possible corruption or drift)"
fi

########################################
# LAYER 4 - FRESHNESS (GENERAL DELAY)
########################################
echo "[4] Checking repository freshness..."

OFF_DATE=$(grep "^Date:" "$OFF" | cut -d' ' -f2-)
MIR_DATE=$(grep "^Date:" "$MIR" | cut -d' ' -f2-)

OFF_TS=$(date -d "$OFF_DATE" +%s)
MIR_TS=$(date -d "$MIR_DATE" +%s)

DELAY=$((OFF_TS - MIR_TS))
DELAY_H=$((DELAY / 3600))

echo "  Official Date: $OFF_DATE"
echo "  Mirror Date:   $MIR_DATE"
echo "  Delay:         $DELAY_H hours"

########################################
# LAYER 5 - SECURITY REPO CHECK
########################################
echo "[5] Checking security repo freshness..."

SEC_OFF="$WORKDIR/sec_off.InRelease"
SEC_MIR="$WORKDIR/sec_mir.InRelease"

curl -fsSL "$SECURITY_OFFICIAL/dists/stable-security/InRelease" -o "$SEC_OFF"
curl -fsSL "$SECURITY_MIRROR/dists/stable-security/InRelease" -o "$SEC_MIR"

SEC_OFF_DATE=$(grep "^Date:" "$SEC_OFF" | cut -d' ' -f2-)
SEC_MIR_DATE=$(grep "^Date:" "$SEC_MIR" | cut -d' ' -f2-)

SEC_OFF_TS=$(date -d "$SEC_OFF_DATE" +%s)
SEC_MIR_TS=$(date -d "$SEC_MIR_DATE" +%s)

SEC_DELAY_H=$(((SEC_OFF_TS - SEC_MIR_TS) / 3600))

echo "  Security delay: $SEC_DELAY_H hours"

########################################
# LAYER 6 - COMPLETENESS CHECK (FILE LIST DRIFT)
########################################
echo "[6] Checking package index consistency..."

OFF_PACKAGES="$WORKDIR/off.packages"
MIR_PACKAGES="$WORKDIR/mir.packages"

curl -fsSL "$OFFICIAL/dists/stable/main/binary-amd64/Packages.gz" | zcat | grep "^Package:" | sort > "$OFF_PACKAGES"
curl -fsSL "$MIRROR/dists/stable/main/binary-amd64/Packages.gz" | zcat | grep "^Package:" | sort > "$MIR_PACKAGES"

DIFF_COUNT=$(diff "$OFF_PACKAGES" "$MIR_PACKAGES" | wc -l)

if [[ "$DIFF_COUNT" -eq 0 ]]; then
    echo "  Package list: IDENTICAL"
else
    echo "  Package drift detected: $DIFF_COUNT differences"
fi

########################################
# LAYER 7 - FINAL RISK SCORE
########################################
echo "[7] Risk scoring..."

SCORE=100

# corruption penalty
if [[ "$OFF_SHA" != "$MIR_SHA" ]]; then
    SCORE=$((SCORE - 40))
fi

# delay penalty
if [[ "$DELAY_H" -gt 2 ]]; then
    SCORE=$((SCORE - 20))
fi

# security delay penalty
if [[ "$SEC_DELAY_H" -gt 1 ]]; then
    SCORE=$((SCORE - 30))
fi

# drift penalty
if [[ "$DIFF_COUNT" -gt 0 ]]; then
    SCORE=$((SCORE - 10))
fi

echo "======================================"
echo " FINAL RESULT"
echo "======================================"
echo "Integrity delay:   ${DELAY_H}h"
echo "Security delay:    ${SEC_DELAY_H}h"
echo "Package drift:     ${DIFF_COUNT}"
echo "Risk score:        ${SCORE}/100"

if [[ "$SCORE" -ge 90 ]]; then
    echo "STATUS: HEALTHY"
elif [[ "$SCORE" -ge 70 ]]; then
    echo "STATUS: ACCEPTABLE (monitor)"
else
    echo "STATUS: UNTRUSTWORTHY MIRROR"
fi

echo "======================================"
