#!/bin/bash
# Interactive NIC Renamer for Proxmox
# Author: Jatinder Grewal <jgrewal@po1.me>
# Version: 1.0.2
# Date: 2025-04-04
# Purpose: Allows user to select and rename interfaces to consistent names (e.g., eth0, eth1...)

set -euo pipefail

LINK_DIR="/etc/systemd/network"
BACKUP_DIR="${LINK_DIR}/backup_$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/var/log/network-rename.log"

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"

log_info()  { 
    local msg="$1"
    echo -e "\e[32m[INFO]\e[0m $msg"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $msg" >> "$LOG_FILE"
}

log_warn()  { 
    local msg="$1"
    echo -e "\e[33m[WARN]\e[0m $msg"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN] $msg" >> "$LOG_FILE"
}

log_error() { 
    local msg="$1"
    echo -e "\e[31m[ERROR]\e[0m $msg"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $msg" >> "$LOG_FILE"
}

# List interfaces and return as array
get_all_interfaces() {
    ip -o link show | awk -F': ' '{print $2}' | grep -vE 'lo|vmbr|tap|fwln|fwpr|fwbr'
}

# Get MAC for interface
get_mac() {
    local iface="$1"
    if [[ -f "/sys/class/net/$iface/address" ]]; then
        cat "/sys/class/net/$iface/address"
    else
        log_error "Could not find MAC address for interface $iface"
        return 1
    fi
}

# Create persistent .link file
create_link_file() {
    local iface="$1"
    local newname="$2"
    local mac
    mac=$(get_mac "$iface") || return 1

    local file="${LINK_DIR}/10-rename-${newname}.link"
    cat <<EOF > "$file"
[Match]
MACAddress=$mac

[Link]
Name=$newname
EOF

    log_info "Created: $file"
    return 0
}

# Validate interface name
validate_interface_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid interface name: $name. Use only letters, numbers, dashes or underscores."
        return 1
    fi
    return 0
}

update_initramfs() {
    log_info "Updating initramfs..."
    if ! update-initramfs -u -k all; then
        log_error "Failed to update initramfs"
        return 1
    fi
    log_info "Initramfs updated successfully."
    return 0
}

# Backup existing configuration
backup_config() {
    log_info "Backing up existing .link files to $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    if [[ -d "$LINK_DIR" ]] && [[ -n "$(ls -A "$LINK_DIR"/*.link 2>/dev/null)" ]]; then
        cp "$LINK_DIR"/*.link "$BACKUP_DIR/" 2>/dev/null || {
            log_warn "Some files could not be backed up"
        }
    else
        log_info "No existing .link files to backup"
    fi
}

main() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root."
        exit 1
    fi

    echo -e "\n\033[1;36m=== Proxmox Interactive NIC Renamer ===\033[0m"
    echo "This utility lets you rename your network adapters to consistent names (e.g., eth0, eth1)."
    echo "Changes will persist across reboots using systemd .link files."
    echo "Log file: $LOG_FILE"

    # Step 1: Gather interfaces
    mapfile -t interfaces < <(get_all_interfaces)

    if [[ ${#interfaces[@]} -eq 0 ]]; then
        log_warn "No interfaces found."
        exit 0
    fi

    echo -e "\nDetected interfaces:"
    for i in "${!interfaces[@]}"; do
        iface="${interfaces[$i]}"
        mac=$(get_mac "$iface" || echo "Unknown")
        printf " [%d] %-10s (MAC: %s)\n" "$i" "$iface" "$mac"
    done

    echo
    read -rp "Enter prefix for renaming (e.g. eth, net, wan): " prefix
    if ! validate_interface_name "$prefix"; then
        exit 1
    fi

    echo -e "\nNow select interfaces in the order you want them to be named:"
    echo "(e.g. first one will become ${prefix}0, second → ${prefix}1, etc.)"
    echo "Enter one index at a time (or 'done' to finish)."

    declare -a chosen_order=()
    declare -A already_picked=()

    while true; do
        read -rp "Select interface index [0-${#interfaces[@]}] or 'done': " selection

        if [[ "$selection" == "done" ]]; then
            break
        elif [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 0 && selection < ${#interfaces[@]} )); then
            if [[ -n "${already_picked[$selection]+x}" ]]; then
                log_warn "You already picked index $selection (${interfaces[$selection]})."
            else
                chosen_order+=("$selection")
                already_picked[$selection]=1
                log_info "Added ${interfaces[$selection]} to rename queue"
            fi
        else
            log_error "Invalid selection. Enter a valid number or 'done'."
        fi
    done

    if [[ ${#chosen_order[@]} -eq 0 ]]; then
        log_warn "No interfaces selected for renaming."
        exit 0
    fi

    # Step 2: Confirm renaming
    echo -e "\nPlanned renaming:"
    for i in "${!chosen_order[@]}"; do
        idx="${chosen_order[$i]}"
        echo "  ${interfaces[$idx]} → ${prefix}${i}"
    done

    read -rp $'\nProceed with renaming? (y/N): ' confirm
    confirm="${confirm,,}"
    if [[ "$confirm" != "y" && "$confirm" != "yes" ]]; then
        log_warn "Aborted by user."
        exit 0
    fi

    # Step 3: Apply
    backup_config

    local success=true
    for i in "${!chosen_order[@]}"; do
        idx="${chosen_order[$i]}"
        oldname="${interfaces[$idx]}"
        newname="${prefix}${i}"
        if ! create_link_file "$oldname" "$newname"; then
            log_error "Failed to create link file for $oldname → $newname"
            success=false
        fi
    done

    if [[ "$success" == "true" ]]; then
        if ! update_initramfs; then
            log_error "Failed to update initramfs. Please run 'update-initramfs -u -k all' manually."
        fi

        echo -e "\n\033[1;33m[REBOOT REQUIRED] Please reboot to apply interface renaming.\033[0m"
        echo -e "After reboot, your interfaces will be renamed as follows:"
        for i in "${!chosen_order[@]}"; do
            idx="${chosen_order[$i]}"
            echo "  ${interfaces[$idx]} → ${prefix}${i}"
        done
    else
        log_error "Some operations failed. Please check the log file: $LOG_FILE"
        exit 1
    fi
}

# Trap errors
trap 'log_error "An error occurred. Rolling back..."; exit 1' ERR

main "$@"