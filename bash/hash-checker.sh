#!/bin/bash

# =============================================================================
# Script Name: hashfile-checker.sh
# Author: gnu-coffee
# Created: 2025-09-10
# Description: Create (.sha256) or verify SHA256 hash files
# License: GNU General Public License v3 (GPLv3)
# =============================================================================

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# --- Variables ---
ACTION=""
TARGET_DIR=""
HASH_FILE=""
MISSING_FILES=()
BAD_HASHES=()
EXTRA_FILES=()

script_name=$(basename "$0")

# --- Usage ---
usage() {
    cat <<EOF
Usage: ${script_name} [option]
  -c, --create-hashfile          Create hash file from target directory
  -v, --verify-hashfile <file>   Verify target directory against given hash file
  -t, --target-directory <dir>   Target directory to process
  -h, --help                     Show this help message

Sample hash file line:
  filename.txt:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
EOF
    exit 1
}

# --- No args ---
if [[ $# -eq 0 ]]; then
    usage
fi

# --- Argument parsing ---
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -c|--create-hashfile)
            ACTION="create"
            shift
            ;;
        -v|--verify-hashfile)
            ACTION="verify"
            HASH_FILE="$2"
            shift 2
            ;;
        -t|--target-directory)
            TARGET_DIR="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        -*)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            ;;
        *)
            shift
            ;;
    esac
done

# --- Validate required params ---
if [[ -z "$ACTION" ]]; then
    echo -e "${RED}Error: No action specified (-c or -v).${NC}"
    usage
fi

if [[ -z "$TARGET_DIR" ]]; then
    echo -e "${RED}Error: Target directory not specified (use -t).${NC}"
    usage
fi

# --- Resolve absolute path of target dir ---
TARGET_DIR=$(realpath "$TARGET_DIR" 2>/dev/null)
if [[ ! -d "$TARGET_DIR" ]]; then
    echo -e "${RED}Error: Directory '$TARGET_DIR' does not exist.${NC}"
    exit 1
fi

# --- Create hash file (.sha256) ---
if [[ "$ACTION" == "create" ]]; then
    dir_name=$(basename "$TARGET_DIR")
    HASH_FILE="${dir_name}.sha256"
    : > "$HASH_FILE"  # truncate/create

    # Use find -print0 to handle special chars; write relative path:hash
    while IFS= read -r -d '' file; do
        sha256=$(sha256sum "$file" | awk '{print $1}')
        rel_path=$(realpath --relative-to="$TARGET_DIR" "$file")
        printf '%s:%s\n' "$rel_path" "$sha256" >> "$HASH_FILE"
    done < <(find "$TARGET_DIR" -type f -print0)

    echo -e "${GREEN}Hash file created: $HASH_FILE${NC}"
    exit 0
fi

# --- Verify hash file ---
if [[ "$ACTION" == "verify" ]]; then
    if [[ -z "$HASH_FILE" || ! -f "$HASH_FILE" ]]; then
        echo -e "${RED}Error: Hash file not specified or does not exist.${NC}"
        usage
    fi

    # --- Read and validate hash file lines; build expected list ---
    HASH_FILES=()
    HASH_MAP_DECLARED=false
    declare -A HASHSET=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        # strip possible CR
        line="${line//$'\r'/}"
        # skip empty lines
        [[ -z "$line" ]] && continue

        # must contain colon
        if ! [[ "$line" == *:* ]]; then
            echo -e "${RED}Invalid format in hash file (no colon): ${line}${NC}"
            exit 1
        fi

        file="${line%%:*}"
        hash="${line#*:}"

        # trim whitespace (leading/trailing)
        file="${file## }"; file="${file%% }"
        hash="${hash## }"; hash="${hash%% }"

        if [[ -z "$file" || -z "$hash" ]]; then
            echo -e "${RED}Invalid format in hash file: ${line}${NC}"
            exit 1
        fi

        # validate hash length & hex
        if ! [[ "$hash" =~ ^[0-9a-fA-F]{64}$ ]]; then
            echo -e "${RED}Invalid hash value in hash file: ${line}${NC}"
            exit 1
        fi

        HASH_FILES+=("$file")
        HASHSET["$file"]=1
        HASH_MAP_DECLARED=true
    done < "$HASH_FILE"

    # --- Collect actual files in directory (relative paths, no ./) ---
    REAL_FILES=()
    while IFS= read -r -d '' f; do
        rel="${f#./}"
        REAL_FILES+=("$rel")
    done < <(cd "$TARGET_DIR" && find . -type f -print0)

    # --- Verify listed (expected) files ---
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line//$'\r'/}"
        [[ -z "$line" ]] && continue
        file="${line%%:*}"
        expected_hash="${line#*:}"

        full_path="$TARGET_DIR/$file"
        if [[ ! -f "$full_path" ]]; then
            echo -e "${RED}[!] Missing file: $file${NC}"
            MISSING_FILES+=("$file")
            continue
        fi

        actual_hash=$(sha256sum "$full_path" | awk '{print $1}')
        if [[ "$actual_hash" != "$expected_hash" ]]; then
            echo -e "${RED}[!] Hash mismatch: $file${NC}"
            BAD_HASHES+=("$file")
        else
            echo -e "${GREEN}[✓] Valid: $file${NC}"
        fi
    done < "$HASH_FILE"

    # --- Find extra files: those in REAL_FILES but not in HASHSET ---
    for f in "${REAL_FILES[@]}"; do
        if [[ -z "${HASHSET[$f]}" ]]; then
            EXTRA_FILES+=("$f")
        fi
    done

    # --- Summary ---
    echo -e "\n${YELLOW}--- Summary ---${NC}"
    if [[ ${#MISSING_FILES[@]} -eq 0 && ${#BAD_HASHES[@]} -eq 0 && ${#EXTRA_FILES[@]} -eq 0 ]]; then
        echo -e "${GREEN}All files are valid${NC}"
    else
        if [[ ${#MISSING_FILES[@]} -gt 0 ]]; then
            echo -e "${RED}Missing files (${#MISSING_FILES[@]}):${NC}"
            for f in "${MISSING_FILES[@]}"; do
                echo "  $f"
            done
        fi
        if [[ ${#BAD_HASHES[@]} -gt 0 ]]; then
            echo -e "${RED}Files with hash mismatch (${#BAD_HASHES[@]}):${NC}"
            for f in "${BAD_HASHES[@]}"; do
                echo "  $f"
            done
        fi
        if [[ ${#EXTRA_FILES[@]} -gt 0 ]]; then
            echo -e "${YELLOW}Extra files (not in hash file) (${#EXTRA_FILES[@]}):${NC}"
            for f in "${EXTRA_FILES[@]}"; do
                echo "  $f"
            done
        fi
    fi

    exit 0
fi

# --- Default ---
usage
