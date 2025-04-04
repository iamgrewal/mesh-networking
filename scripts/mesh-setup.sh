#!/bin/bash

# Version: 1.0.2
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
    ["VLAN_CLUSTER"]="55"
    ["VLAN_CEPH"]="60"
    ["VLAN_PVECM"]="50"
    ["MTU"]="9000"
)

# Script flags
DRY_RUN=false
FORCE=false

# Function to log messages
log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

# Function to validate IP address format and range
validate_ip() {
    local ip=$1
    local IFS='.'
    read -ra octets <<< "$ip"
    [[ ${#octets[@]} -eq 4 ]] || return 1
    for octet in "${octets[@]}"; do
        [[ "$octet" =~ ^[0-9]+$ ]] && (( octet >= 0 && octet <= 255 )) || return 1
    done
    return 0
}

# Function to validate hostname
validate_hostname() {
    local hostname=$1
    if [[ ! "$hostname" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?$ ]]; then
        log_message "ERROR" "Invalid hostname format: $hostname"
        return 1
    fi
    return 0
}

# Function to validate network interface
validate_interface() {
    local iface=$1
    if ! ip link show "$iface" &>/dev/null; then
        log_message "ERROR" "Interface $iface not found"
        return 1
    fi
    return 0
}

# Function to validate OVS installation
validate_ovs() {
    command -v ovs-vsctl >/dev/null || {
        log_message "ERROR" "ovs-vsctl not found. Make sure Open vSwitch is installed properly."
        exit 1
    }
}

# Function to backup existing configuration
backup_config() {
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    mkdir -p /etc/network/backups/"$timestamp"
    cp /etc/network/interfaces /etc/network/backups/"$timestamp"/ || true
    cp /etc/frr/frr.conf /etc/network/backups/"$timestamp"/ || true
    log_message "INFO" "Backed up configuration to /etc/network/backups/$timestamp/"
}

# Function to collect node information
collect_node_info() {
    log_message "INFO" "Collecting node information"
    
    # Get hostname
    read -rp "Enter node hostname: " NODE_HOSTNAME
    validate_hostname "$NODE_HOSTNAME" || exit 1
    
    # Get node ID
    read -rp "Enter node ID (1-255): " NODE_ID
    if ! [[ "$NODE_ID" =~ ^[0-9]+$ ]] || (( NODE_ID < 1 || NODE_ID > 255 )); then
        log_message "ERROR" "Invalid node ID. Must be between 1 and 255"
        exit 1
    fi
    
    # Get network interfaces
    read -rp "Enter public network interface (e.g., eth0): " PUB_IFACE
    validate_interface "$PUB_IFACE" || exit 1
    
    read -rp "Enter PVECM network interface (e.g., eth1): " PVECM_IFACE
    validate_interface "$PVECM_IFACE" || exit 1
    
    read -rp "Enter Ceph network interface (e.g., eth2): " CEPH_IFACE
    validate_interface "$CEPH_IFACE" || exit 1
    
    # Get IP addresses
    read -rp "Enter public network IP (e.g., 192.168.1.10): " PUB_IP
    validate_ip "$PUB_IP" || exit 1
    
    read -rp "Enter PVECM network IP (e.g., 10.50.10.10): " PVECM_IP
    validate_ip "$PVECM_IP" || exit 1
    
    read -rp "Enter Ceph network IP (e.g., 10.60.10.10): " CEPH_IP
    validate_ip "$CEPH_IP" || exit 1
    
    log_message "INFO" "Node information collected successfully"
}

# Function to setup mesh network
setup_mesh_network() {
    log_message "INFO" "Setting up mesh network"
    
    # Set hostname
    if [[ "$DRY_RUN" == "false" ]]; then
        echo "$NODE_HOSTNAME" > /etc/hostname
        hostnamectl set-hostname "$NODE_HOSTNAME"
        log_message "INFO" "Hostname set to $NODE_HOSTNAME"
    else
        log_message "INFO" "[DRY RUN] Would set hostname to $NODE_HOSTNAME"
    fi
    
    # Backup existing configuration
    if [[ "$DRY_RUN" == "false" ]]; then
        backup_config
    else
        log_message "INFO" "[DRY RUN] Would backup existing configuration"
    fi
    
    # Create network configuration
    generate_network_config
    
    # Apply network configuration
    if [[ "$DRY_RUN" == "false" ]]; then
        # Enable fabricd in FRR daemons
        sed -i 's/^fabricd=no/fabricd=yes/' /etc/frr/daemons
        
        # Apply network configuration
        ifreload -a
        
        # Enable and start FRR service
        systemctl enable frr.service
        systemctl start frr.service
    else
        log_message "INFO" "[DRY RUN] Would apply network configuration and restart services"
    fi
    
    # Output node summary
    output_node_summary
    
    # Validate Ceph if available
    validate_ceph
    
    log_message "INFO" "Mesh network setup completed"
}

# Function to generate network configuration
generate_network_config() {
    local node_ip_public="192.168.51.${NODE_ID}"
    local node_ip_cluster="10.55.10.${NODE_ID}"
    local node_ip_ceph="10.60.10.${NODE_ID}"
    local node_ip_pvecm="10.50.10.${NODE_ID}"
    
    # Generate interfaces configuration
    if [[ "$DRY_RUN" == "false" ]]; then
        cat << EOF > /etc/network/interfaces
auto lo
iface lo inet loopback

auto ${PUB_IFACE}
iface ${PUB_IFACE} inet manual

auto vmbr0
iface vmbr0 inet static
    address ${node_ip_public}/24
    gateway 192.168.51.1
    bridge_ports ${PUB_IFACE}
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
    else
        log_message "INFO" "[DRY RUN] Would generate network configuration files:"
        log_message "INFO" "[DRY RUN] - /etc/network/interfaces"
        log_message "INFO" "[DRY RUN] - /etc/frr/frr.conf"
    fi

    log_message "INFO" "Network configuration generated"
}

# Function to output node summary
output_node_summary() {
    local node_ip_public="192.168.51.${NODE_ID}"
    local node_ip_cluster="10.55.10.${NODE_ID}"
    local node_ip_ceph="10.60.10.${NODE_ID}"
    local node_ip_pvecm="10.50.10.${NODE_ID}"
    
    log_message "INFO" "Node Configuration Summary:"
    log_message "INFO" "Hostname: ${NODE_HOSTNAME}"
    log_message "INFO" "Node ID: ${NODE_ID}"
    log_message "INFO" "Public Network: ${PUB_IFACE} -> vmbr0 -> ${node_ip_public}/24"
    log_message "INFO" "PVECM Network: ${PVECM_IFACE} -> vmbr1.${NETWORK_CONFIG[VLAN_PVECM]} -> ${node_ip_pvecm}/24"
    log_message "INFO" "Cluster Network: ${CEPH_IFACE} -> vmbr2.${NETWORK_CONFIG[VLAN_CLUSTER]} -> ${node_ip_cluster}/24"
    log_message "INFO" "Ceph Network: ${CEPH_IFACE} -> vmbr2.${NETWORK_CONFIG[VLAN_CEPH]} -> ${node_ip_ceph}/24"
}

# Function to validate Ceph
validate_ceph() {
    if command -v pveceph &>/dev/null; then
        log_message "INFO" "Validating Ceph status with pveceph"
        pveceph status || log_message "WARNING" "Ceph validation failed or cluster not available"
    elif command -v ceph &>/dev/null; then
        log_message "INFO" "Validating Ceph status with ceph"
        ceph -s || log_message "WARNING" "Ceph validation failed or cluster not available"
    else
        log_message "INFO" "Ceph tools not found, skipping validation"
    fi
}

# Function to parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --help)
                echo "Usage: $0 [options]"
                echo "Options:"
                echo "  --dry-run    Show what would be done without making changes"
                echo "  --force      Skip prompts and use default values"
                echo "  --help       Show this help message"
                exit 0
                ;;
            *)
                log_message "ERROR" "Unknown option: $1"
                exit 1
                ;;
        esac
    done
}

# Main execution
main() {
    # Parse command line arguments
    parse_args "$@"
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_message "ERROR" "This script must be run as root"
        exit 1
    fi
    
    # Install required packages
    if [[ "$DRY_RUN" == "false" ]]; then
        apt update
        apt install -y openvswitch-switch frr
    else
        log_message "INFO" "[DRY RUN] Would install required packages"
    fi
    
    # Validate OVS installation
    validate_ovs
    
    # Collect node information
    if [[ "$FORCE" == "false" ]]; then
        collect_node_info
    else
        # Use default values for force mode
        NODE_HOSTNAME="pve-${NODE_ID}"
        PUB_IFACE="eth0"
        PVECM_IFACE="eth1"
        CEPH_IFACE="eth2"
        PUB_IP="192.168.51.${NODE_ID}"
        PVECM_IP="10.50.10.${NODE_ID}"
        CEPH_IP="10.60.10.${NODE_ID}"
        log_message "INFO" "Using default values in force mode"
    fi
    
    # Run setup
    setup_mesh_network
}

# Trap errors
trap 'log_message "ERROR" "An error occurred. Rolling back..."; exit 1' ERR

# Execute main function
main "$@" 