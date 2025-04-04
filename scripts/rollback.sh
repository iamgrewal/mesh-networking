#!/bin/bash

# Version: 1.0.0
# Author: mesh-networking
# Date: 2024-04-04
# Purpose: Rollback script for mesh network configuration

set -euo pipefail

# Color definitions for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Log file
LOG_FILE="/var/log/mesh-rollback.log"

# Function to log messages
log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

# Function to find latest backup
find_latest_backup() {
    local backup_dir="/etc/network/backups"
    if [[ ! -d "$backup_dir" ]]; then
        log_message "ERROR" "No backup directory found"
        return 1
    fi
    
    local latest_backup
    latest_backup=$(ls -t "$backup_dir" | head -n1)
    if [[ -z "$latest_backup" ]]; then
        log_message "ERROR" "No backups found"
        return 1
    fi
    
    echo "$backup_dir/$latest_backup"
}

# Function to restore network configuration
restore_network_config() {
    local backup_dir=$1
    
    log_message "INFO" "Restoring network configuration from $backup_dir"
    
    # Stop FRR service
    systemctl stop frr.service
    
    # Restore interfaces configuration
    if [[ -f "$backup_dir/interfaces" ]]; then
        cp "$backup_dir/interfaces" /etc/network/interfaces
        log_message "INFO" "Restored interfaces configuration"
    else
        log_message "ERROR" "No interfaces backup found"
        return 1
    fi
    
    # Restore FRR configuration if exists
    if [[ -f "$backup_dir/frr.conf" ]]; then
        cp "$backup_dir/frr.conf" /etc/frr/frr.conf
        log_message "INFO" "Restored FRR configuration"
    fi
    
    # Reload network configuration
    ifreload -a
    
    # Start FRR service
    systemctl start frr.service
    
    log_message "INFO" "Network configuration restored"
}

# Function to clean up OVS bridges
cleanup_ovs() {
    log_message "INFO" "Cleaning up OVS bridges"
    
    # Remove OVS bridges
    ovs-vsctl del-br vmbr2 2>/dev/null || true
    
    log_message "INFO" "OVS bridges cleaned up"
}

# Function to verify restoration
verify_restoration() {
    log_message "INFO" "Verifying restoration"
    
    # Check if interfaces are up
    if ! ip link show vmbr0 &>/dev/null; then
        log_message "ERROR" "vmbr0 interface not restored"
        return 1
    fi
    
    # Check if FRR is running
    if ! systemctl is-active --quiet frr; then
        log_message "ERROR" "FRR service not running"
        return 1
    fi
    
    log_message "INFO" "Restoration verified successfully"
    return 0
}

# Main rollback function
perform_rollback() {
    log_message "INFO" "Starting rollback procedure"
    
    # Find latest backup
    local backup_dir
    backup_dir=$(find_latest_backup) || exit 1
    
    # Clean up OVS
    cleanup_ovs
    
    # Restore configuration
    restore_network_config "$backup_dir" || exit 1
    
    # Verify restoration
    verify_restoration || exit 1
    
    log_message "INFO" "Rollback completed successfully"
}

# Main execution
main() {
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_message "ERROR" "This script must be run as root"
        exit 1
    fi
    
    # Perform rollback
    perform_rollback
}

# Execute main function
main "$@" 