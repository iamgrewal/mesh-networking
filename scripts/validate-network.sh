#!/bin/bash

# Version: 1.0.0
# Author: mesh-networking
# Date: 2024-04-04
# Purpose: Validate mesh network configuration

set -euo pipefail

# Color definitions for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Log file
LOG_FILE="/var/log/mesh-validation.log"

# Configuration variables
declare -A NETWORK_CONFIG=(
    ["VLAN_CLUSTER"]="55"
    ["VLAN_CEPH"]="60"
    ["VLAN_PVECM"]="50"
    ["MTU"]="9000"
)

# Function to log messages
log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

# Function to validate interface configuration
validate_interfaces() {
    log_message "INFO" "Validating network interfaces"
    
    # Check if required interfaces exist
    local interfaces=("vmbr0" "vmbr1" "vmbr2")
    for iface in "${interfaces[@]}"; do
        if ! ip link show "$iface" &>/dev/null; then
            log_message "ERROR" "Interface $iface not found"
            return 1
        fi
    done
    
    # Check MTU settings
    for iface in "${interfaces[@]}"; do
        local mtu
        mtu=$(ip link show "$iface" | grep -oP 'mtu \K[0-9]+')
        if [[ "$mtu" != "${NETWORK_CONFIG[MTU]}" ]]; then
            log_message "ERROR" "Incorrect MTU on $iface: $mtu (expected ${NETWORK_CONFIG[MTU]})"
            return 1
        fi
    done
    
    log_message "INFO" "Interface validation successful"
    return 0
}

# Function to validate OVS configuration
validate_ovs() {
    log_message "INFO" "Validating OVS configuration"
    
    # Check if OVS bridges exist
    if ! ovs-vsctl br-exists vmbr1 || ! ovs-vsctl br-exists vmbr2; then
        log_message "ERROR" "Required OVS bridges not found"
        return 1
    fi
    
    # Check RSTP settings
    for bridge in vmbr1 vmbr2; do
        if ! ovs-vsctl get Bridge "$bridge" rstp_enable | grep -q "true"; then
            log_message "ERROR" "RSTP not enabled on $bridge"
            return 1
        fi
    done
    
    # Check VLAN configurations
    for vlan in "${NETWORK_CONFIG[@]}"; do
        if ! ovs-vsctl list-ports vmbr1 | grep -q "vmbr1.$vlan"; then
            log_message "ERROR" "VLAN $vlan not configured on vmbr1"
            return 1
        fi
    done
    
    log_message "INFO" "OVS validation successful"
    return 0
}

# Function to validate FRR configuration
validate_frr() {
    log_message "INFO" "Validating FRR configuration"
    
    # Check if FRR is running
    if ! systemctl is-active --quiet frr; then
        log_message "ERROR" "FRR service not running"
        return 1
    fi
    
    # Check FRR configuration file
    if [[ ! -f "/etc/frr/frr.conf" ]]; then
        log_message "ERROR" "FRR configuration file not found"
        return 1
    fi
    
    # Validate OpenFabric configuration
    if ! vtysh -c "show running-config" | grep -q "router openfabric"; then
        log_message "ERROR" "OpenFabric not configured in FRR"
        return 1
    fi
    
    log_message "INFO" "FRR validation successful"
    return 0
}

# Function to validate network connectivity
validate_connectivity() {
    log_message "INFO" "Validating network connectivity"
    
    # Get list of cluster nodes (this should be populated based on your environment)
    local nodes=("node1" "node2" "node3")
    
    # Test connectivity between nodes
    for node in "${nodes[@]}"; do
        # Test cluster network (VLAN 55)
        if ! ping -c 1 -I "vmbr2.${NETWORK_CONFIG[VLAN_CLUSTER]}" "$node" &>/dev/null; then
            log_message "ERROR" "Failed to ping $node on cluster network"
            return 1
        fi
        
        # Test Ceph network (VLAN 60)
        if ! ping -c 1 -I "vmbr2.${NETWORK_CONFIG[VLAN_CEPH]}" "$node" &>/dev/null; then
            log_message "ERROR" "Failed to ping $node on Ceph network"
            return 1
        fi
        
        # Test PVECM network (VLAN 50)
        if ! ping -c 1 -I "vmbr1.${NETWORK_CONFIG[VLAN_PVECM]}" "$node" &>/dev/null; then
            log_message "ERROR" "Failed to ping $node on PVECM network"
            return 1
        fi
    done
    
    log_message "INFO" "Connectivity validation successful"
    return 0
}

# Main validation function
perform_validation() {
    log_message "INFO" "Starting network validation"
    
    local validation_failed=0
    
    # Validate interfaces
    validate_interfaces || validation_failed=1
    
    # Validate OVS
    validate_ovs || validation_failed=1
    
    # Validate FRR
    validate_frr || validation_failed=1
    
    # Validate connectivity
    validate_connectivity || validation_failed=1
    
    if [[ $validation_failed -eq 1 ]]; then
        log_message "ERROR" "Network validation failed"
        return 1
    fi
    
    log_message "INFO" "Network validation completed successfully"
    return 0
}

# Main execution
main() {
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_message "ERROR" "This script must be run as root"
        exit 1
    fi
    
    # Perform validation
    perform_validation
}

# Execute main function
main "$@" 