#!/bin/bash
set -euo pipefail

# Color definitions for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log to console and file
LOG="/var/log/mesh-network-gen.log"
log() {
    local level=$1
    local message=$2
    local color=$NC
    
    case "$level" in
        "INFO")  color=$GREEN ;;
        "WARN")  color=$YELLOW ;;
        "ERROR") color=$RED ;;
    esac
    
    echo -e "${color}[$level] $message${NC}" | tee -a "$LOG"
}

# Display available nodes
show_nodes() {
    echo -e "${BLUE}Available nodes:${NC}"
    echo -e "  ${GREEN}pve${NC}  - IP: 192.168.51.90"
    echo -e "  ${GREEN}pve1${NC} - IP: 192.168.51.91"
    echo -e "  ${GREEN}pve2${NC} - IP: 192.168.51.92"
    echo -e "  ${GREEN}pve3${NC} - IP: 192.168.51.93"
    echo -e "  ${GREEN}pve4${NC} - IP: 192.168.51.94"
    echo ""
}

# Validate IP address format
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

# Show available network interfaces
list_interfaces() {
    echo -e "${BLUE}Available network interfaces:${NC}"
    ip -br link show | awk '{print "  - "$1}' | tee -a "$LOG"
    echo ""
}

# Check for Open vSwitch
check_ovs() {
    if ! command -v ovs-vsctl &>/dev/null; then
        log "ERROR" "Open vSwitch is not installed. Please install with: apt install openvswitch-switch"
        exit 1
    fi
    
    # Check if OVS service is running
    if ! systemctl is-active --quiet openvswitch-switch; then
        log "WARN" "Open vSwitch service is not running. Attempting to start..."
        if ! systemctl start openvswitch-switch; then
            log "ERROR" "Failed to start Open vSwitch service. Please check system logs."
            exit 1
        fi
        log "INFO" "Open vSwitch service started successfully."
    fi
    
    log "INFO" "Open vSwitch is installed and running."
}

# Validate hostname
validate_hostname() {
    local expected_hostname=$1
    local current_hostname
    
    # Get current hostname
    if command -v hostnamectl &>/dev/null; then
        current_hostname=$(hostnamectl --static)
    else
        current_hostname=$(hostname)
    fi
    
    if [[ "$current_hostname" != "$expected_hostname" ]]; then
        log "WARN" "Current hostname ($current_hostname) does not match expected hostname ($expected_hostname)"
        read -rp "Do you want to continue anyway? (y/n): " continue_anyway
        if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
            log "INFO" "Operation cancelled by user."
            exit 0
        fi
        log "INFO" "Continuing despite hostname mismatch."
    else
        log "INFO" "Hostname validation passed: $current_hostname"
    fi
}

# Check for existing bridge/VLAN configurations
check_existing_config() {
    local node=$1
    local output_file="/etc/network/interfaces.${node}"
    
    if [ -f "$output_file" ]; then
        log "INFO" "Found existing configuration file: $output_file"
        
        # Check for existing bridges
        local existing_bridges=$(grep -E "^auto vmbr[0-9]" "$output_file" | awk '{print $2}')
        if [ -n "$existing_bridges" ]; then
            log "WARN" "Found existing bridge configurations: $existing_bridges"
            read -rp "Do you want to remove these bridges before generating new configuration? (y/n): " remove_bridges
            if [[ "$remove_bridges" =~ ^[Yy]$ ]]; then
                for bridge in $existing_bridges; do
                    log "INFO" "Removing bridge $bridge..."
                    ovs-vsctl del-br "$bridge" 2>/dev/null || true
                done
                log "INFO" "Existing bridges removed."
            else
                log "INFO" "Keeping existing bridges. This may cause conflicts."
            fi
        fi
    fi
}

# Validate generated configuration
validate_generated_config() {
    local output_file=$1
    
    log "INFO" "Validating generated configuration..."
    
    # Check if the file exists
    if [ ! -f "$output_file" ]; then
        log "ERROR" "Generated configuration file not found: $output_file"
        return 1
    fi
    
    # Check for syntax errors using ifquery
    if command -v ifquery &>/dev/null; then
        if ! ifquery --list -f "$output_file" &>/dev/null; then
            log "ERROR" "Configuration validation failed. Please check the syntax."
            return 1
        fi
        log "INFO" "Configuration syntax validation passed."
    else
        log "WARN" "ifquery not available. Skipping syntax validation."
    fi
    
    # Check for duplicate bridge definitions
    local duplicate_bridges=$(grep -E "^auto vmbr[0-9]" "$output_file" | sort | uniq -d)
    if [ -n "$duplicate_bridges" ]; then
        log "ERROR" "Duplicate bridge definitions found: $duplicate_bridges"
        return 1
    fi
    
    # Check for duplicate VLAN tags
    local duplicate_vlans=$(grep -E "ovs_options tag=[0-9]+" "$output_file" | sort | uniq -d)
    if [ -n "$duplicate_vlans" ]; then
        log "ERROR" "Duplicate VLAN tags found: $duplicate_vlans"
        return 1
    fi
    
    log "INFO" "Configuration validation completed successfully."
    return 0
}

# Main script
log "INFO" "Starting mesh network interface generator"
log "INFO" "========================================="

# Check for Open vSwitch
check_ovs

# Show available nodes
show_nodes

# Ask which node to generate for
read -rp "Enter Proxmox node hostname (e.g., pve, pve1, pve2, pve3, pve4): " NODE

# Assign IPs per node
case "$NODE" in
  pve)   NODE_ID=90 ;;
  pve1)  NODE_ID=91 ;;
  pve2)  NODE_ID=92 ;;
  pve3)  NODE_ID=93 ;;
  pve4)  NODE_ID=94 ;;
  *)     log "ERROR" "Unknown node name: $NODE"; exit 1 ;;
esac

log "INFO" "Generating configuration for node: $NODE (ID: $NODE_ID)"

# Validate hostname
validate_hostname "$NODE"

# Check for existing configurations
check_existing_config "$NODE"

# Show available interfaces
list_interfaces

# Read network interfaces with validation
while true; do
    read -rp "Enter the Ethernet interface for vmbr0 (Public): " eth_interface_vmbr0
    if ip link show "$eth_interface_vmbr0" &>/dev/null; then
        break
    else
        log "WARN" "Interface $eth_interface_vmbr0 not found. Please try again."
    fi
done

while true; do
    read -rp "Enter the Ethernet interface for vmbr1 (Proxmox Cluster): " eth_interface_vmbr1
    if ip link show "$eth_interface_vmbr1" &>/dev/null; then
        break
    else
        log "WARN" "Interface $eth_interface_vmbr1 not found. Please try again."
    fi
done

while true; do
    read -rp "Enter the Ethernet interface for vmbr2 (Ceph): " eth_interface_vmbr2
    if ip link show "$eth_interface_vmbr2" &>/dev/null; then
        break
    else
        log "WARN" "Interface $eth_interface_vmbr2 not found. Please try again."
    fi
done

# Calculate IPs
ip_vmbr0="192.168.51.$NODE_ID"
ip_vmbr1_60="10.60.10.$NODE_ID"
ip_vmbr2_50="10.50.10.$NODE_ID"
ip_vmbr2_55="10.55.10.$NODE_ID"

# Output file per node
output_file="/etc/network/interfaces.${NODE}"

log "INFO" "Generating interfaces file for node $NODE at $output_file"

# Create backup of existing file if it exists
if [ -f "$output_file" ]; then
    backup_file="${output_file}.$(date +%Y%m%d%H%M%S).bak"
    cp "$output_file" "$backup_file"
    log "INFO" "Created backup of existing file at $backup_file"
fi

# Generate the interfaces file
cat <<EOF > "$output_file"
source /etc/network/interfaces.d/*
# THIS IS THE SAMPLE NETWORK INTERFACES FILE FOR THE MESH NETWORK /etc/network/interfaces
# Debian 12 / proxmox 8.3
# Author: Jatinder Grewal (iamgrewal)
# Version: 1.0.0
# Date: 2025-04-05
# Node: $NODE
# Generated: $(date)

# vmbr0 will be used for vm's to communicate with each other and the public internet
# vmbr1 will be used for the proxmox cluster
# vmbr2 will be for ceph network
# vlan 50 will be for the proxmox cluster
# vlan 55 will be for ceph network
# vlan 60 will be for the ceph cluster
########################################################

auto lo
iface lo inet loopback

# Public bridge
auto ${eth_interface_vmbr0}
iface ${eth_interface_vmbr0} inet manual

auto vmbr0
iface vmbr0 inet static
    address ${ip_vmbr0}/24
    gateway 192.168.51.1
    dns-nameservers 192.168.51.1
    bridge-ports ${eth_interface_vmbr0}
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes
    mtu 9000

# Proxmox cluster (VLAN 60)
auto ${eth_interface_vmbr1}
iface ${eth_interface_vmbr1} inet manual
    ovs_type OVSPort
    ovs_bridge vmbr1
    ovs_mtu 9000
    ovs_options other_config:rstp-enable=true other_config:rstp-path-cost=150 vlan_mode=native-untagged

auto vmbr1
iface vmbr1 inet manual
    ovs_type OVSBridge
    ovs_ports ${eth_interface_vmbr1} vmbr1.60
    ovs_mtu 9000
    up ovs-vsctl set Bridge \$IFACE rstp_enable=true other_config:rstp-priority=32768 other_config:rstp-forward-delay=4 other_config:rstp-max-age=6
    post-up sleep 5

auto vmbr1.60
iface vmbr1.60 inet static
    address ${ip_vmbr1_60}/24
    ovs_type OVSIntPort
    ovs_bridge vmbr1
    ovs_mtu 9000
    ovs_options tag=60
    post-up if ! systemctl is-active --quiet frr.service; then systemctl restart frr.service; fi

# Ceph mesh bridge (VLAN 50, 55)
auto ${eth_interface_vmbr2}
iface ${eth_interface_vmbr2} inet manual
    ovs_type OVSPort
    ovs_bridge vmbr2
    ovs_mtu 9000
    ovs_options other_config:rstp-enable=true other_config:rstp-path-cost=150 vlan_mode=native-untagged

auto vmbr2
iface vmbr2 inet manual
    ovs_type OVSBridge
    ovs_ports ${eth_interface_vmbr2} vmbr2.50 vmbr2.55
    ovs_mtu 9000
    up ovs-vsctl set Bridge \$IFACE rstp_enable=true other_config:rstp-priority=32768 other_config:rstp-forward-delay=4 other_config:rstp-max-age=6
    post-up sleep 5

auto vmbr2.50
iface vmbr2.50 inet static
    address ${ip_vmbr2_50}/24
    ovs_type OVSIntPort
    ovs_bridge vmbr2
    ovs_mtu 9000
    ovs_options tag=50
    post-up /usr/bin/systemctl restart frr.service

auto vmbr2.55
iface vmbr2.55 inet static
    address ${ip_vmbr2_55}/24
    ovs_type OVSIntPort
    ovs_bridge vmbr2
    ovs_mtu 9000
    ovs_options tag=55
    post-up /usr/bin/systemctl restart frr.service
EOF

log "INFO" "Configuration file generated successfully at $output_file"

# Validate the generated configuration
if ! validate_generated_config "$output_file"; then
    log "ERROR" "Configuration validation failed. Please review the configuration file."
    read -rp "Do you want to continue anyway? (y/n): " continue_anyway
    if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
        log "INFO" "Operation cancelled by user."
        exit 1
    fi
    log "INFO" "Continuing despite validation failures."
fi

# Ask if user wants to apply the configuration
read -rp "Do you want to apply this configuration now? (y/n): " apply_now
if [[ "$apply_now" =~ ^[Yy]$ ]]; then
    if [ -f "/etc/network/interfaces" ]; then
        backup_file="/etc/network/interfaces.$(date +%Y%m%d%H%M%S).bak"
        cp "/etc/network/interfaces" "$backup_file"
        log "INFO" "Created backup of existing interfaces file at $backup_file"
    fi
    
    cp "$output_file" "/etc/network/interfaces"
    log "INFO" "Applied configuration to /etc/network/interfaces"
    
    read -rp "Do you want to reload network interfaces now? (y/n): " reload_now
    if [[ "$reload_now" =~ ^[Yy]$ ]]; then
        log "INFO" "Reloading network interfaces..."
        if command -v ifreload &>/dev/null; then
            ifreload -a
        else
            systemctl restart networking
        fi
        log "INFO" "Network interfaces reloaded"
    else
        log "INFO" "Skipping network reload. You can reload later with: ifreload -a"
    fi
else
    log "INFO" "Configuration saved but not applied. To apply later:"
    log "INFO" "  cp $output_file /etc/network/interfaces"
    log "INFO" "  ifreload -a"
fi

log "INFO" "Script completed successfully"




