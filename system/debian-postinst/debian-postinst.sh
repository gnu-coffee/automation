#!/usr/bin/env bash

# ==========================================================
# Debian Setup Script
# ==========================================================

set -o errexit
set -o nounset
set -o pipefail

# ----------------------------------------------------------
# Colors
# ----------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ----------------------------------------------------------
# Messages
# ----------------------------------------------------------

error()    { echo -e " ${RED}[-]${NC} $1"; }
success()  { echo -e " ${GREEN}[+]${NC} $1"; }
info()     { echo -e " ${YELLOW}[*]${NC} $1"; }
question() { echo -e " ${BLUE}[?]${NC} $1"; }

# ----------------------------------------------------------
# Files
# ----------------------------------------------------------

LOG_FILE="/var/log/debian-setup.log"
DISTRO_FILE="/etc/os-release"

# ----------------------------------------------------------
# Backup system
# ----------------------------------------------------------

BACKUP_MODE=false
RESTORE_MODE=false
BACKUP_TARGETS=()
BACKUP_ROOT="/var/backups/debian-setup"
BACKUP_TS="$(date +%Y-%m-%d_%H:%M:%S)"

# ----------------------------------------------------------
# Logging
# ----------------------------------------------------------

log() {
    local level="$1"
    local message="$2"

    printf '[%s] [%s] %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" \
        "$level" \
        "$message" >> "$LOG_FILE"
}

# ----------------------------------------------------------
# Help
# ----------------------------------------------------------

show_help() {

    printf "\n"
    printf "Usage:\n"
    printf "  %s [OPTIONS]\n\n" "$0"

    printf "Core Options:\n"
    printf "  -h, --help\n"
    printf "      Show this help message and exit\n\n"

    printf "  -b, --backup [env|apt|env,apt]\n"
    printf "      Create system backup\n\n"

    printf "      Available backup targets:\n"
    printf "        env  -> user configs (.bashrc, .vimrc, .pythonrc)\n"
    printf "        apt  -> APT repository configuration (/etc/apt)\n\n"

    printf "      Default (if no target provided):\n"
    printf "        env,apt\n\n"

    printf "      Backup location:\n"
    printf "        /var/backups/debian-setup/YYYY-MM-DD_HH:MM:SS/\n\n"

    printf "      Examples:\n"
    printf "        %s -b\n" "$0"
    printf "        %s -b env\n" "$0"
    printf "        %s -b apt,env\n\n" "$0"

    printf "  -r, --restore TARGETS -d DIRECTORY\n"
    printf "      Restore system from backup\n\n"

    printf "      Required arguments:\n"
    printf "        TARGETS   -> env, apt, or env,apt\n"
    printf "        DIRECTORY -> backup path\n\n"

    printf "      Examples:\n"
    printf "        %s -r env -d /var/backups/debian-setup/2026-06-10_23:11:34\n" "$0"
    printf "        %s -r apt,env -d /backup/latest\n\n" "$0"

    printf "Description:\n"
    printf "  Debian system configuration tool for:\n"
    printf "    - Repository management (APT)\n"
    printf "    - System updates\n"
    printf "    - Environment setup (shell + Python)\n"
    printf "    - Backup & restore operations\n\n"

    exit 0
}

# ----------------------------------------------------------
# Argument Parser
# ----------------------------------------------------------

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in

            -b|--backup)
                BACKUP_MODE=true

                if [[ $# -gt 1 && "$2" != -* ]]; then
                    IFS=',' read -r -a BACKUP_TARGETS <<< "$2"
                    shift 2
                else
                    BACKUP_TARGETS=(env apt)
                    shift
                fi
                ;;

            -r|--restore)
                RESTORE_MODE=true

                if [[ $# -gt 1 && "$2" != -* ]]; then
                    IFS=',' read -r -a RESTORE_TARGETS <<< "$2"
                    shift 2
                else
                    error "Restore mode requires targets: env, apt, or env,apt"
                    exit 1
                fi
                ;;

            -d|--directory)
                if [[ $# -gt 1 && "$2" != -* ]]; then
                    BACKUP_DIR="$2"
                    shift 2
                else
                    error "Missing directory for --directory"
                    exit 1
                fi
                ;;

            -h|--help)
                show_help
                shift
                ;;

            *)
                error "Unknown argument: $1"
                exit 1
                ;;
        esac
    done
}

# ----------------------------------------------------------
# BACKUP FUNCTION
# ----------------------------------------------------------

run_backup() {

    local dir="${BACKUP_ROOT}/${BACKUP_TS}"
    mkdir -p "$dir"

    for target in "${BACKUP_TARGETS[@]}"; do
        case "$target" in

            env)
                info "Backing up environment configs..."
                cp -a /root/.bashrc "$dir/" 2>/dev/null || true
                cp -a /root/.vimrc "$dir/" 2>/dev/null || true
                cp -a /root/.pythonrc "$dir/" 2>/dev/null || true
                ;;

            apt)
                info "Backing up APT configuration..."
                cp -a /etc/apt "$dir/"
                ;;

            *)
                error "Unknown backup target: $target"
                ;;
        esac
    done

    success "Backup completed: $dir"
}

# ----------------------------------------------------------
# RESTORE FUNCTION
# ----------------------------------------------------------

run_restore() {

    local source_dir="$BACKUP_DIR"

    if [[ -z "$source_dir" ]]; then
        error "No backup directory provided (--directory is required)"
        exit 1
    fi

    if [[ ! -d "$source_dir" ]]; then
        error "Backup directory not found: $source_dir"
        exit 1
    fi

    info "Starting restore from: $source_dir"

    for target in "${RESTORE_TARGETS[@]}"; do

        case "$target" in

            env)
                info "Restoring environment files..."

                for user_home in /root /home/*; do

                    [[ -d "$user_home" ]] || continue

                    [[ -f "$source_dir/.bashrc" ]] && cp -f "$source_dir/.bashrc" "$user_home/.bashrc"
                    [[ -f "$source_dir/.vimrc" ]] && cp -f "$source_dir/.vimrc" "$user_home/.vimrc"
                    [[ -f "$source_dir/.pythonrc" ]] && cp -f "$source_dir/.pythonrc" "$user_home/.pythonrc"

                    # fix ownership if not root
                    if [[ "$user_home" != "/root" ]]; then
                        chown "$(basename "$user_home")":"$(basename "$user_home")" \
                            "$user_home/.bashrc" \
                            "$user_home/.vimrc" \
                            "$user_home/.pythonrc" 2>/dev/null || true
                    fi

                done

                success "Environment restored."
                ;;

            apt)
                info "Restoring APT configuration..."

                if [[ -d "$source_dir/apt" ]]; then

                    rm -rf /etc/apt/sources.list.d/*.sources 2>/dev/null || true
                    rm -rf /etc/apt/sources.list 2>/dev/null || true

                    cp -a "$source_dir/apt/." /etc/apt/
                    info "Updating package lists after restore..."
                    apt --fix-missing update || true
                    success "APT configuration restored."
                else
                    error "No apt backup found in: $source_dir"
                fi
                ;;

            *)
                error "Unknown restore target: $target"
                ;;
        esac
    done

    success "Restore completed successfully."
    log "INFO" "Restore from $source_dir completed"
}

# ----------------------------------------------------------
# Root Check
# ----------------------------------------------------------

check_root() {

    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root."
        log "ERROR" "Script executed without root privileges."
        exit 1
    fi

    success "Root privileges confirmed."
    log "INFO" "Root check passed."
}

# ----------------------------------------------------------
# Debian Check
# ----------------------------------------------------------

check_debian() {

    if [[ ! -f "$DISTRO_FILE" ]]; then
        error "Cannot determine operating system."
        log "ERROR" "Missing $DISTRO_FILE"
        exit 1
    fi

    source "$DISTRO_FILE"

    if [[ "${ID:-}" != "debian" ]]; then
        error "This script only supports Debian."
        log "ERROR" "Unsupported OS: ${ID:-unknown}"
        exit 1
    fi

    success "Debian detected."
    log "INFO" "Debian check passed."
}

# ----------------------------------------------------------
# Validate Project Structure
# ----------------------------------------------------------

validate_project_structure() {

    local script_dir
    local env_dir
    local repo_dir

    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    env_dir="${script_dir}/environment"
    repo_dir="${script_dir}/repositories"

    if [[ ! -d "$env_dir" ]]; then
        error "Missing directory: environment/"
        return 1
    fi

    for f in .bashrc .vimrc .pythonrc; do
        if [[ ! -f "$env_dir/$f" ]]; then
            error "Missing environment file: $env_dir/$f"
            return 1
        fi
    done

    if [[ ! -d "$repo_dir" ]]; then
        error "Missing directory: repositories/"
        return 1
    fi

    for branch in stable testing; do
        for mirror in debian mobinhost; do

            local file_path="$repo_dir/$branch/$mirror.sources"

            if [[ ! -f "$file_path" ]]; then
                error "Missing repository file: $file_path"
                return 1
            fi

        done
    done

    success "Project structure validation passed."
    return 0
}

# ----------------------------------------------------------
# Repository Configuration
# ----------------------------------------------------------

configure_repositories() {

    local branch_choice
    local mirror_choice

    local script_dir
    local repo_dir

    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    repo_dir="${script_dir}/repositories"

    local source_file="${repo_dir}/${BRANCH}/${MIRROR}.sources"
    local target_file="/etc/apt/sources.list.d/${MIRROR}.sources"

    if [[ ! -f "$source_file" ]]; then
        error "Missing repository file: $source_file"
        return 1
    fi

    info "Backing up existing repository configuration..."

    rm -f /etc/apt/sources.list~
    rm -f /etc/apt/sources.list

    if [[ -f /etc/apt/sources.list ]]; then
        cp -f \
            /etc/apt/sources.list \
            /etc/apt/sources.list.bk.$(date +%Y%m%d%H%M%S)
    fi

    info "Cleaning repository directory..."

    rm -f /etc/apt/sources.list.d/*.sources

    info "Applying selected repository..."

    cp -f "$source_file" "$target_file"

    success "Repository configured: $BRANCH/$MIRROR"

    log "INFO" "Repositories set to $BRANCH/$MIRROR"

    echo
    info "Active repository:"
    ls /etc/apt/sources.list.d/ | sed 's/^/\t/'
    echo
}

# ----------------------------------------------------------
# System Update
# ----------------------------------------------------------

update_system() {

    info "Cleaning APT cache..."
    apt clean

    info "Updating package lists..."
    apt --fix-missing update 1>/dev/null 2>&1

    info "Performing full upgrade..."
    apt -y full-upgrade 1>/dev/null 2>&1

    info "Fixing broken packages..."
    apt -f install -y 1>/dev/null 2>&1

    info "Removing unused packages..."
    apt -y autoremove 1>/dev/null 2>&1

    info "Refreshing package lists..."
    apt --fix-missing update 1>/dev/null 2>&1

    success "System update completed."
    log "INFO" "System updated successfully."
}

# ----------------------------------------------------------
# Packages
# ----------------------------------------------------------

install_essential_packages() {

    info "Installing essential packages..."

    local packages=(
        apt-offline conntrack python3 python3-pip age parted psmisc lsof file man man-db apt-utils vim tree less curl wget gnupg gpg ca-certificates lsb-release apt-transport-https git zip unzip bash-completion util-linux grub-common bsdextrautils mokutil htop iotop mtr iftop sysstat procps iproute2 bind9-dnsutils traceroute tcpdump iputils-ping bridge-utils iptables resolvconf firewalld smartmontools net-tools ncat gnupg2 sbsigntool
    )

    log "INFO" "Installing packages: ${packages[*]}"

    if apt install -y "${packages[@]}" 1>/dev/null 2>&1; then
        systemctl disable --now firewalld.service 1>/dev/null 2>&1
        success "Essential packages installed successfully."
        log "INFO" "Essential packages installed successfully."
    else
        error "Failed to install essential packages."
        log "ERROR" "Failed to install essential packages."
        return 1
    fi
}

# ----------------------------------------------------------
# Python selection
# ----------------------------------------------------------

select_python_version() {

    local versions=()

    while IFS= read -r python_bin; do
        versions+=("$python_bin")
    done < <(
        compgen -c |
        grep '^python3\(\.[0-9]\+\)\?$' |
        sort -Vu
    )

    if [[ ${#versions[@]} -eq 0 ]]; then
        error "No Python versions found."
        return 1
    fi

    echo

    question "Select default Python version:"

    for i in "${!versions[@]}"; do
        echo "      [$((i + 1))] ${versions[i]}"
    done

    while true; do
        read -rp "      [?] Your choice: " choice

        if [[ "$choice" =~ ^[0-9]+$ ]] &&
           (( choice >= 1 && choice <= ${#versions[@]} )); then

            DEFAULT_PYTHON="${versions[$((choice-1))]}"
            break
        fi

        error "Invalid selection."
    done

    success "Python version Selected: ${DEFAULT_PYTHON}"
}

# ----------------------------------------------------------
# User selection
# ----------------------------------------------------------

select_user() {

    local users=()
    local choice

    mapfile -t users < <(
        awk -F: '
            $3 >= 1 &&
            $7 ~ /\/bin\/(sh|bash|zsh)$/ {
            print $1
            }
        ' /etc/passwd
        )

    question "Available Users:"

    for i in "${!users[@]}"; do
        echo "      [$((i + 1))] ${users[i]}"
    done

    while true; do
        read -rp "      [?] Your choice: " choice

        if [[ "$choice" =~ ^[0-9]+$ ]] &&
           (( choice >= 1 && choice <= ${#users[@]} )); then
    
            REGULAR_USER="${users[$((choice-1))]}"
            break
        fi

        error "Invalid selection."
    done

    success "Username Selected: ${REGULAR_USER}"
}

# ----------------------------------------------------------
# Environment
# ----------------------------------------------------------

configure_user_environment() {

    local home_dir
    local user_group

    local script_dir
    local env_dir

    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    env_dir="${script_dir}/environment"

    info "Setting timezone to Asia/Tehran..."

    timedatectl set-timezone "Asia/Tehran" || true

    for user in root "$REGULAR_USER"; do

        home_dir="$(getent passwd "$user" | cut -d: -f6)"
        user_group="$(id -gn "$user")"

        info "Configuring environment for user: $user"

        if [[ -f "$home_dir/.bashrc" ]]; then
            cp -f "$home_dir/.bashrc" "$home_dir/.bashrc.bak.$(date +%Y%m%d%H%M%S)"
        fi

        if [[ -f "$home_dir/.vimrc" ]]; then
            cp -f "$home_dir/.vimrc" "$home_dir/.vimrc.bak.$(date +%Y%m%d%H%M%S)"
        fi

        if [[ -f "$home_dir/.pythonrc" ]]; then
            cp -f "$home_dir/.pythonrc" "$home_dir/.pythonrc.bak.$(date +%Y%m%d%H%M%S)"
        fi

        cp -f "$env_dir/.bashrc" "$home_dir/.bashrc"
        cp -f "$env_dir/.vimrc" "$home_dir/.vimrc"
        cp -f "$env_dir/.pythonrc" "$home_dir/.pythonrc"

        cat >> "$home_dir/.bashrc" << EOF

alias python='${DEFAULT_PYTHON}'
EOF

        chown "$user:$user_group" \
            "$home_dir/.bashrc" \
            "$home_dir/.vimrc" \
            "$home_dir/.pythonrc"

        chmod 644 \
            "$home_dir/.bashrc" \
            "$home_dir/.vimrc" \
            "$home_dir/.pythonrc"

        success "Environment configured for $user"
        log "INFO" "Environment configured for $user"
    done
}

# ----------------------------------------------------------
# Confirmation
# ----------------------------------------------------------

confirm() {
    local prompt="$1"
    local answer

    echo
    question "$prompt"

    while true; do
        read -rp "      [y/n]: " answer

        case "${answer,,}" in
            y)
                return 0
                ;;
            n)
                return 1
                ;;
            *)
                error "Please enter y or n."
                ;;
        esac
    done
}

# ----------------------------------------------------------
# Run Wizard
# ----------------------------------------------------------

run_wizard() {
    declare -a TASKS

    # ----------------------------------
    # Asking for repos
    # ----------------------------------
    confirm "Configure repositories?" && TASKS+=("repo")
    if [[ " ${TASKS[*]} " =~ " repo " ]]; then
        while true; do
            echo
            question "Repository branch:"
            echo "      [1] Stable"
            echo "      [2] Testing"

            read -rp "          Select option: " REPOSITORY_BRANCH

            case "$REPOSITORY_BRANCH" in
                1)
                    BRANCH="stable"
                    break
                    ;;
                2)
                    BRANCH="testing"
                    break
                    ;;
                *)
                    error "Invalid branch!"
                    ;;
            esac
        done

        echo

        while true; do
            echo
            question "Repository source:"
            echo "      [1] Debian Official"
            echo "      [2] Mobinhost Mirror"
        
            read -rp "          Select option: " MIRROR_CHOICE

            case "$MIRROR_CHOICE" in
                1)
                    MIRROR="debian"
                    break
                    ;;
                2)
                    MIRROR="mobinhost"
                    break
                    ;;
                *)
                    error "Invalid mirror!"
                    ;;
            esac
        done

    fi

    confirm "Install essential packages?"  && TASKS+=("packages")
    confirm "Configure environment?"       && TASKS+=("env")
    if [[ " ${TASKS[*]} " =~ " env " ]]; then
        select_python_version
        echo
        select_user
    fi
    echo
    info "Executing selected tasks..."
    echo

    for task in "${TASKS[@]}"; do
        case "$task" in

            repo)
                configure_repositories
                update_system
                ;;

            packages)
                install_essential_packages
                ;;
    
            env)
                configure_user_environment
                ;;
    
        esac
    done
}

# ----------------------------------------------------------
# Main
# ----------------------------------------------------------

main() {

    parse_args "$@"

    check_root
    check_debian

    validate_project_structure || {
        error "Invalid project structure. Aborting."
        exit 1
    }
    
    # ----------------------------
    # RESTORE MODE
    # ----------------------------
    if [[ "$RESTORE_MODE" == true ]]; then
        if [[ ${#RESTORE_TARGETS[@]} -eq 0 ]]; then
            error "Restore requires targets: env or apt (or env,apt)"
            exit 1
        fi

        if [[ -z "${BACKUP_DIR:-}" ]]; then
            error "Restore requires --directory (-d)"
            exit 1
        fi

        run_restore
        exit 0
    fi

    # ----------------------------------------------------------
    # Backup Warning
    # ----------------------------------------------------------
    if [[ "$BACKUP_MODE" == false ]]; then
        echo
        error "WARNING: This script will modify system and user configuration files!"
        echo

        question "Before continuing, you MUST create a backup if you haven't already."
        read -rp "     Press ENTER to abort or type YES to continue anyway: " confirm_risky

        if [[ "${confirm_risky,,}" != "yes" ]]; then
            error "Aborted. Run  $0 -b or --backup  first."
            exit 1
        fi
    fi

    # Backup hook (NEW but optional, does not change flow)
    if [[ "$BACKUP_MODE" == true ]]; then
        run_backup
        exit 0
    fi
    
    run_wizard
    success "All tasks completed."
    log "INFO" "Script finished successfully."
}

main "$@"
