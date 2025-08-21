#!/bin/bash

# =============================================================================
# Script Name: grub-password-setup.sh
# Author: gnu-coffee
# Created: 2025-08-20
# Description: Setup GRUB password on your Debian/Ubuntu distros
# License: GNU General Public License
# =============================================================================

# --- Variables ----
error()    { echo -e "\e[31m [-]\e[0m $1"; }
success()  { echo -e "\e[32m [+]\e[0m $1"; }
info()     { echo -e "\e[33m [*]\e[0m $1"; }
question() { echo -e "\e[34m [?]\e[0m $1"; }

# --- Files ---
LOG_FILE="${SCRIPT_DIR}/grub_setup.log"
DISTRO_FILE="/etc/os-release"
FILE_40_CUSTOM="/etc/grub.d/40_custom"
FILE_10_LINUX="/etc/grub.d/10_linux"

# --- Root check ---
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root!"
    exit 1
fi

# --- Detect OS/Distro ---
OS_TYPE=$(uname -s)
DISTRO_FILE="/etc/os-release"

if [ "$OS_TYPE" = "Linux" ] && [ -f "$DISTRO_FILE" ]; then
    . "$DISTRO_FILE"
    DISTRO=$ID
    if [ "$DISTRO" = "debian" ] || [ "$DISTRO" = "ubuntu" ]; then
        success "Detected: ${OS_TYPE}/${DISTRO}"
        success "Environment OK - proceeding..."
    else
        error "Unsupported environment: ${OS_TYPE}/${DISTRO}"
        exit 1
    fi
else
    error "Unsupported OS: $OS_TYPE"
    exit 1
fi

# --- Check if GRUB password already exists ---
if grep -q "^set superusers=" "$FILE_40_CUSTOM"; then
    info "GRUB password is currently set."
    CURRENT_STATUS="set"
else
    info "GRUB password is not set."
    CURRENT_STATUS="unset"
fi

# --- Choose what to do ---
question "Choose your action:"
echo -e "\t\t1) Set GRUB password"
echo -e "\t\t2) Remove GRUB password"
read -rp "     [1/2]: " CHOICE

case "$CHOICE" in
    1)
        # --- Backup ---
        cp "$FILE_40_CUSTOM" "$FILE_40_CUSTOM.orig"
        cp "$FILE_10_LINUX" "$FILE_10_LINUX.orig"
        success "Backup created:"
    	info "\t $FILE_40_CUSTOM.orig"
	    info "\t $FILE_10_LINUX.orig"

        # --- Prompt for username and password ---
        question "Enter GRUB username:"
        read -rp "     Username: " GRUB_USER

        question "Enter GRUB password (will not be shown):"
        read -rsp "     Password: " GRUB_PASS1
        echo
        read -rsp "     Re-Password: " GRUB_PASS2
        echo
        if [[ "$GRUB_PASS1" != "$GRUB_PASS2" ]]; then
            error "grub-mkpasswd-pbkdf2: error: passwords don't match."
            exit 1
        fi
        # --- Generate password hash ---
        info "Generating GRUB password hash..."
        HASH_OUTPUT=$(printf "%s\n%s\n" "$GRUB_PASS1" "$GRUB_PASS1" | grub-mkpasswd-pbkdf2 2>>"$LOG_FILE")
        HASH=$(echo "$HASH_OUTPUT" | grep "grub.pbkdf2" | awk '{print $7}')

        if [[ -z "$HASH" ]]; then
            error "Failed to generate password hash. Exiting."
            exit 1
        fi
        success "Password hash generated."

        # --- Update 40_custom ---
        info "Updating $FILE_40_CUSTOM ..."
        cat > "$FILE_40_CUSTOM" <<EOF
#!/bin/sh
exec tail -n +3 \$0
# This file provides an easy way to add custom menu entries.  Simply type the
# menu entries you want to add after this comment.  Be careful not to change
# the 'exec tail' line above.

set superusers="$GRUB_USER"
password_pbkdf2 $GRUB_USER $HASH
EOF
        success "$FILE_40_CUSTOM updated."

        # --- Update  10_linux ---
        info "Patching $FILE_10_LINUX ..."
	    sed -i '/menuentry/ s/${CLASS}/--unrestricted ${CLASS}/' "$FILE_10_LINUX"
	    sed -i '/submenu /{/menuentry/ s/\\\$menuentry_id_option/--users='"$GRUB_USER"' --unrestricted \\\$menuentry_id_option/}' "$FILE_10_LINUX"
        success "$FILE_10_LINUX patched."

        # --- Update grub ---
        info "Updating GRUB..."
        if update-grub2 >>"$LOG_FILE" 2>&1; then
            success "GRUB updated successfully. Password protection enabled."
        else
            error "Failed to update GRUB."
            exit 1
        fi
        ;;

    2)
        # --- Restore from backups ---
        if [[ -f "$FILE_40_CUSTOM.orig" && -f "$FILE_10_LINUX.orig" ]]; then
            info "Restoring original GRUB files..."
            cp "$FILE_40_CUSTOM.orig" "$FILE_40_CUSTOM"
            cp "$FILE_10_LINUX.orig" "$FILE_10_LINUX"
            success "Files restored."

            info "Updating GRUB..."
            if update-grub2 >>"$LOG_FILE" 2>&1; then
                success "GRUB updated. Password protection removed."
            else
                error "Failed to update GRUB after restore."
                exit 1
            fi
        else
            error "No backup files found. Cannot restore."
            exit 1
        fi
        ;;

    *)
        error "Invalid choice. Exiting."
        exit 1
        ;;
esac
