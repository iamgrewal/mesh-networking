#!/bin/bash

# Version: 1.0.0
# Author: mesh-networking
# Date: 2024-04-04
# Purpose: Validate mesh network configuration and connectivity

set -euo pipefail

# Color definitions for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Log file
LOG_FILE="/var/log/mesh-validation.log"

# Function to log messages
log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

# Function to check interface configuration
check_interface() {
    local iface=$1
    local expected_mtu=${2:-1500}
    
    if ! ip link show "$iface" &>/dev/null; then
        log_message "ERROR" "Interface $iface does not exist"
        return 1
    fi
    
    local mtu
    mtu=$(ip link show "$iface" | grep -o 'mtu [0-9]*' | awk '{print $2}')
    if [[ "$mtu" != "$expected_mtu" ]]; then
        log_message "ERROR" "Interface $iface MTU mismatch: expected $expected_mtu, got $mtu"
        return 1
    fi
    
    log_message "INFO" "Interface $iface configuration OK"
    return 0
}

# Function to check OVS bridge configuration
check_ovs_bridge() {
    local bridge=$1
    
    if ! ovs-vsctl br-exists "$bridge"; then
        log_message "ERROR" "OVS bridge $bridge does not exist"
        return 1
    fi
    
    # Check RSTP configuration
    if ! ovs-vsctl get Bridge "$bridge" rstp_enable | grep -q true; then
        log_message "ERROR" "RSTP not enabled on bridge $bridge"
        return 1
    fi
    
    local priority
    priority=$(ovs-vsctl get Bridge "$bridge" other_config:rstp-priority)
    if [[ "$priority" != "32768" ]]; then
        log_message "ERROR" "Incorrect RSTP priority on bridge $bridge"
        return 1
    fi
    
    log_message "INFO" "OVS bridge $bridge configuration OK"
    return 0
}

# Function to check FRR configuration
check_frr_config() {
    if ! systemctl is-active --quiet frr; then
        log_message "ERROR" "FRR service not running"
        return 1
    fi
    
    # Check OpenFabric configuration
    if ! vtysh -c "show running-config" | grep -q "router openfabric 1"; then
        log_message "ERROR" "OpenFabric not configured"
        return 1
    fi
    
    log_message "INFO" "FRR configuration OK"
    return 0
}

# Function to check network connectivity
check_connectivity() {
    local target_ip=$1
    local interface=$2
    
    if ! ping -c 3 -I "$interface" "$target_ip" &>/dev/null; then
        log_message "ERROR" "Cannot reach $target_ip via $interface"
        return 1
    fi
    
    log_message "INFO" "Connectivity to $target_ip via $interface OK"
    return 0
}

# Main validation function
validate_network() {
    log_message "INFO" "Starting network validation"
    
    # Check interfaces
    check_interface "vmbr0" "1500"
    check_interface "vmbr2" "9000"
    check_interface "vmbr2.55" "9000"
    check_interface "vmbr2.60" "9000"
    
    # Check OVS bridges
    check_ovs_bridge "vmbr2"
    
    # Check FRR configuration
    check_frr_config
    
    # Check connectivity to other nodes
    # Note: This assumes a 5-node cluster with IPs 90-94
    local node_id
    node_id=$(hostname | grep -o '[0-9]*$')
    
    for i in {90..94}; do
        if [[ "$i" != "$node_id" ]]; then
            check_connectivity "10.55.10.$i" "vmbr2.55"
            check_connectivity "10.60.10.$i" "vmbr2.60"
        fi
    done
    
    log_message "INFO" "Network validation completed"
}

# Main execution
main() {
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_message "ERROR" "This script must be run as root"
        exit 1
    fi
    
    # Run validation
    validate_network
}

# Execute main function
main "$@" 