#!/bin/bash

# Version: 1.0.1
# Author: Jatinder Grewal <jgrewal@po1.me>
# Date: 2025-04-04
# Purpose: Initial setup script for Proxmox VE mesh network with Ceph
# Dependencies: openvswitch-switch, frr, ceph

set -euo pipefail

# Color definitions for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Log file
LOG_FILE="/var/log/mesh-setup.log"

# Configuration variables
declare -A NETWORK_CONFIG=(
    ["PUBLIC_NETWORK"]="192.168.51.0/24"
    ["CLUSTER_NETWORK"]="10.55.10.0/24"
    ["CEPH_NETWORK"]="10.60.10.0/24"
    ["PVECM_NETWORK"]="10.50.10.0/24"
    ["MTU"]="9000"
    ["VLAN_CLUSTER"]="55"
    ["VLAN_CEPH"]="60"
    ["VLAN_PVECM"]="50"
)

# Function to log messages
log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

# Function to validate network interface
validate_interface() {
    local iface=$1
    if ! ip link show "$iface" &>/dev/null; then
        log_message "ERROR" "Interface $iface does not exist"
        return 1
    fi
    return 0
}

# Function to validate IP address
validate_ip() {
    local ip=$1
    if ! [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        log_message "ERROR" "Invalid IP address format: $ip"
        return 1
    fi
    return 0
}

# Function to validate node ID
validate_node_id() {
    local node_id=$1
    if ! [[ $node_id =~ ^[0-9]{1,3}$ ]] || ((node_id < 90 || node_id > 94)); then
        log_message "ERROR" "Invalid node ID (must be 90-94): $node_id"
        return 1
    fi
    return 0
}

# Function to backup configuration files
backup_config() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="/etc/network/backups/${timestamp}"
    
    mkdir -p "$backup_dir"
    cp /etc/network/interfaces "$backup_dir/"
    cp /etc/frr/frr.conf "$backup_dir/" 2>/dev/null || true
    
    log_message "INFO" "Configuration backed up to $backup_dir"
}

# Function to list available network interfaces
list_interfaces() {
    log_message "INFO" "Available network interfaces:"
    ip -br link show | awk '{print "  - "$1}' | tee -a "$LOG_FILE"
}

# Function to get user input with validation
get_user_input() {
    local prompt=$1
    local var_name=$2
    local default=$3
    local is_required=${4:-true}
    local validation_func=${5:-}
    
    while true; do
        read -rp "$prompt" input
        input=${input:-$default}
        
        if [[ -z "$input" ]] && [[ "$is_required" == "true" ]]; then
            log_message "ERROR" "Input is required"
            continue
        fi
        
        if [[ -n "$validation_func" ]] && ! $validation_func "$input"; then
            continue
        fi
        
        eval "$var_name='$input'"
        break
    done
}

# Main setup function
setup_mesh_network() {
    log_message "INFO" "Starting mesh network setup"
    
    # List available interfaces
    list_interfaces
    
    # Get node information
    get_user_input "Enter node hostname: " NODE_HOSTNAME "" true
    get_user_input "Enter node ID (90-94): " NODE_ID "" true validate_node_id
    
    # Get interface information
    get_user_input "Enter public interface name (eth1): " PUBLIC_IFACE "eth1" true validate_interface
    get_user_input "Enter Ceph interface name (eth3): " CEPH_IFACE "eth3" true validate_interface
    get_user_input "Enter PVECM interface name (eth2): " PVECM_IFACE "eth2" true validate_interface
    
    # Backup existing configuration
    backup_config
    
    # Generate network configuration
    generate_network_config
    
    # Apply configuration
    apply_network_config
    
    log_message "INFO" "Mesh network setup completed successfully"
}

# Function to generate network configuration
generate_network_config() {
    local node_ip_public="192.168.51.${NODE_ID}"
    local node_ip_cluster="10.55.10.${NODE_ID}"
    local node_ip_ceph="10.60.10.${NODE_ID}"
    local node_ip_pvecm="10.50.10.${NODE_ID}"
    
    # Generate interfaces configuration
    cat << EOF > /etc/network/interfaces
auto lo
iface lo inet loopback

auto ${PUBLIC_IFACE}
iface ${PUBLIC_IFACE} inet manual

auto vmbr0
iface vmbr0 inet static
    address ${node_ip_public}/24
    gateway 192.168.51.1
    bridge_ports ${PUBLIC_IFACE}
    bridge_stp off
    bridge_fd 0

auto ${PVECM_IFACE}
iface ${PVECM_IFACE} inet manual
    ovs_type OVSPort
    ovs_bridge vmbr1
    ovs_mtu ${NETWORK_CONFIG[MTU]}
    ovs_options other_config:rstp-enable=true other_config:rstp-path-cost=150 other_config:rstp-port-admin-edge=false other_config:rstp-port-auto-edge=false other_config:rstp-port-mcheck=true vlan_mode=native-untagged

auto vmbr1
iface vmbr1 inet manual
    ovs_type OVSBridge
    ovs_ports ${PVECM_IFACE} vmbr1.${NETWORK_CONFIG[VLAN_PVECM]}
    up ovs-vsctl set Bridge \${IFACE} rstp_enable=true other_config:rstp-priority=32768
    post-up sleep 10
    ovs_mtu ${NETWORK_CONFIG[MTU]}

auto vmbr1.${NETWORK_CONFIG[VLAN_PVECM]}
iface vmbr1.${NETWORK_CONFIG[VLAN_PVECM]} inet static
    address ${node_ip_pvecm}/24
    ovs_type OVSIntPort
    ovs_bridge vmbr1
    ovs_mtu ${NETWORK_CONFIG[MTU]}
    ovs_options tag=${NETWORK_CONFIG[VLAN_PVECM]}
    post-up /usr/bin/systemctl restart frr.service

auto ${CEPH_IFACE}
iface ${CEPH_IFACE} inet manual
    ovs_type OVSPort
    ovs_bridge vmbr2
    ovs_mtu ${NETWORK_CONFIG[MTU]}
    ovs_options other_config:rstp-enable=true other_config:rstp-path-cost=150 other_config:rstp-port-admin-edge=false other_config:rstp-port-auto-edge=false other_config:rstp-port-mcheck=true vlan_mode=native-untagged

auto vmbr2
iface vmbr2 inet manual
    ovs_type OVSBridge
    ovs_ports ${CEPH_IFACE} vmbr2.${NETWORK_CONFIG[VLAN_CLUSTER]} vmbr2.${NETWORK_CONFIG[VLAN_CEPH]}
    up ovs-vsctl set Bridge \${IFACE} rstp_enable=true other_config:rstp-priority=32768
    post-up sleep 10
    ovs_mtu ${NETWORK_CONFIG[MTU]}

auto vmbr2.${NETWORK_CONFIG[VLAN_CLUSTER]}
iface vmbr2.${NETWORK_CONFIG[VLAN_CLUSTER]} inet static
    address ${node_ip_cluster}/24
    ovs_type OVSIntPort
    ovs_bridge vmbr2
    ovs_mtu ${NETWORK_CONFIG[MTU]}
    ovs_options tag=${NETWORK_CONFIG[VLAN_CLUSTER]}
    post-up /usr/bin/systemctl restart frr.service

auto vmbr2.${NETWORK_CONFIG[VLAN_CEPH]}
iface vmbr2.${NETWORK_CONFIG[VLAN_CEPH]} inet static
    address ${node_ip_ceph}/24
    ovs_type OVSIntPort
    ovs_bridge vmbr2
    ovs_mtu ${NETWORK_CONFIG[MTU]}
    ovs_options tag=${NETWORK_CONFIG[VLAN_CEPH]}
EOF

    # Generate FRR configuration
    cat << EOF > /etc/frr/frr.conf
frr defaults traditional
hostname ${NODE_HOSTNAME}
log syslog warning
ip forwarding
no ipv6 forwarding
service integrated-vtysh-config

interface lo
 ip address ${node_ip_cluster}/32
 ip router openfabric 1
 openfabric passive

interface vmbr1.${NETWORK_CONFIG[VLAN_PVECM]}
 ip router openfabric 1
 openfabric csnp-interval 2
 openfabric hello-interval 1
 openfabric hello-multiplier 2

interface vmbr2.${NETWORK_CONFIG[VLAN_CLUSTER]}
 ip router openfabric 1
 openfabric csnp-interval 2
 openfabric hello-interval 1
 openfabric hello-multiplier 2

interface vmbr2.${NETWORK_CONFIG[VLAN_CEPH]}
 ip router openfabric 1
 openfabric csnp-interval 2
 openfabric hello-interval 1
 openfabric hello-multiplier 2

line vty

router openfabric 1
 net 49.0001.1000.0000.00$(printf "%02x" "${NODE_ID}").00
 lsp-gen-interval 1
 max-lsp-lifetime 600
 lsp-refresh-interval 180
EOF

    log_message "INFO" "Network configuration generated"
}

# Function to apply network configuration
apply_network_config() {
    # Enable FRR daemon
    sed -i 's/^fabricd=no/fabricd=yes/' /etc/frr/daemons
    
    # Reload network configuration
    ifreload -a
    
    # Restart FRR service
    systemctl restart frr.service
    
    log_message "INFO" "Network configuration applied"
}

# Main execution
main() {
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_message "ERROR" "This script must be run as root"
        exit 1
    fi
    
    # Install required packages
    apt update
    apt install -y openvswitch-switch frr
    
    # Run setup
    setup_mesh_network
}

# Trap errors
trap 'log_message "ERROR" "An error occurred. Rolling back..."; exit 1' ERR

# Execute main function
main "$@" 