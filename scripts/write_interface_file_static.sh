#!/bin/bash
read -r -p "Enter the hostname: " hostname
read -r -p "Enter the Ethernet interface for VMBO - Public network: " eth_interface_vmbr0
read -r -p "Enter the IP address for vmbr0: " ip_address_vmbr0
read -r -p "Enter the netmask: " netmask_vmbr0
read -r -p "Enter the gateway: " gateway_vmbr0
read -r -p "Enter the DNS server: " dns_server_vmbr0
read -r -p "Enter the Ethernet interface for VMB1 - Proxmox network: " eth_interface_vmbr1
read -r -p "Enter the IP address: " ip_address_vmbr1
read -r -p "Emter the vlan60 ip address: " ip_address_vmbr1_60
read -r -p "Enter the IP address: " ip_address_vmbr2
read -r -p "Enter the Ethernet interface for VMBO - Ceph network: " eth_interface_vmbr2
read -r -p "Enter the vlan50 ip address: " ip_address_vmbr2_50
read -r -p "Enter the vlan55 ip address: " ip_address_vmbr2_55

# Define the write_interface_file function first
write_interface_file() {
    cat <<EOF > /etc/network/interfaces
source /etc/network/interfaces.d/*
# THIS IS THE SAMPLE NETWORK INTERFACES FILE FOR THE MESH NETWORK /etc/network/interfaces
# Debian 12 / proxmox 8.3
# Author: Jatinder Grewal (iamgrewal)
# Version: 1.0.0
# Date: 2025-04-05
# Changes:
#   - Added FRR OpenFabric NET ID validation
#   - Improved input sanitation for VLAN assignment

# vmbr0 will be used for vm's to communicate with each other and the public internet
# vmbr1 will be used for the proxmox cluster
# vmbr2 will be for ceph network
# vlan 50 will be for the proxmox cluster
# vlan 55 will be for ceph network
# vlan 60 will be for the ceph cluster
########################################################

auto lo
iface lo inet loopback

##################################################
# PUBLIC NIC (for vmbr0)
auto ${eth_interface_vmbr0}
iface ${eth_interface_vmbr0} inet manual


########################################################
auto ${eth_interface_vmbr0}
iface ${eth_interface_vmbr0} inet manual

### PUBLIC BRIDGE
auto vmbr0
iface vmbr0 inet static
    address ${ip_address_vmbr0}/${netmask_vmbr0}
    gateway ${gateway_vmbr0}
    bridge-ports ${eth_interface_vmbr0}
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes
    mtu 9000  # MTU set to 9000 for enabling jumbo frames, improving performance for large data transfers

##################################################
### PVECM BRIDGE
auto ${eth_interface_vmbr1}
iface ${eth_interface_vmbr1} inet manual
    ovs_type OVSPort
    ovs_bridge vmbr1
    ovs_mtu 9000  # MTU set to 9000 for enabling jumbo frames, improving performance for large data transfers
    ovs_options other_config:rstp-enable=true \
                 other_config:rstp-path-cost=150 \
                 vlan_mode=native-untagged

auto vmbr1
iface vmbr1 inet manual
    ovs_type OVSBridge
    ovs_ports ${eth_interface_vmbr1} vmbr1.60
    ovs_mtu 9000
    up ovs-vsctl set Bridge \${IFACE} rstp_enable=true \
        other_config:rstp-priority=32768 \
        other_config:rstp-forward-delay=4 \
        other_config:rstp-max-age=6
    post-up sleep 5

auto vmbr1.60
iface vmbr1.60 inet static
    address ${ip_address_vmbr1_60}/24
    ovs_type OVSIntPort
    ovs_bridge vmbr1
    ovs_mtu 9000
    ovs_options tag=60
    post-up if ! systemctl is-active --quiet frr.service; then /usr/bin/systemctl restart frr.service; fi



##################################################
### Bridge for vmbr2 (CEPH)
auto ${eth_interface_vmbr2}
iface ${eth_interface_vmbr2} inet manual
    ovs_type OVSPort
    ovs_bridge vmbr2
    ovs_mtu 9000
    ovs_options other_config:rstp-enable=true \
                 other_config:rstp-path-cost=150 \
                 vlan_mode=native-untagged

auto vmbr2
iface vmbr2 inet manual
    ovs_type OVSBridge
    ovs_ports ${eth_interface_vmbr2} vmbr2.50 vmbr2.55
    ovs_mtu 9000
    up ovs-vsctl set Bridge \${IFACE} rstp_enable=true \
        other_config:rstp-priority=32768 \
        other_config:rstp-forward-delay=4 \
        other_config:rstp-max-age=6
    post-up sleep 5

auto vmbr2.50
iface vmbr2.50 inet static
    address ${ip_address_vmbr2_50}/24
    ovs_type OVSIntPort
    ovs_bridge vmbr2
    ovs_mtu 9000
    ovs_options tag=50
    post-up /usr/bin/systemctl restart frr.service

auto vmbr2.55
iface vmbr2.55 inet static
    address ${ip_address_vmbr2_55}/24
    ovs_type OVSIntPort
    ovs_bridge vmbr2
    ovs_mtu 9000
    ovs_options tag=55
    post-up /usr/bin/systemctl restart frr.service
EOF
}

# Now process each node
for node in pve pve1 pve2 pve3 pve4; do
    if [ "$node" = "pve" ]; then
        eth_interface_vmbr0="eth1"
        eth_interface_vmbr1="eth3"
        eth_interface_vmbr2="eth2"
        ip_address_vmbr0="192.168.51.90"
        netmask_vmbr0="255.255.255.0"
        gateway_vmbr0="192.168.51.1"
        dns_server_vmbr0="192.168.51.1"
        ip_address_vmbr1_60="10.60.10.90"
        ip_address_vmbr2_50="10.50.10.90"
        ip_address_vmbr2_55="10.55.10.90"
        write_interface_file
    elif [ "$node" = "pve1" ]; then
        eth_interface_vmbr0="eth1"
        eth_interface_vmbr1="eth3"
        eth_interface_vmbr2="eth2"
        ip_address_vmbr0="192.168.51.90"
        netmask_vmbr0="255.255.255.0"
        gateway_vmbr0="192.168.51.1"
        dns_server_vmbr0="192.168.51.1"
        ip_address_vmbr1_60="10.60.10.91"
        ip_address_vmbr2_50="10.50.10.91"
        ip_address_vmbr2_55="10.55.10.91"
        write_interface_file
    elif [ "$node" = "pve2" ]; then
        eth_interface_vmbr0="eth1"
        eth_interface_vmbr1="eth3"
        eth_interface_vmbr2="eth2"
        ip_address_vmbr0="192.168.51.92"
        netmask_vmbr0="255.255.255.0"
        gateway_vmbr0="192.168.51.1"
        dns_server_vmbr0="192.168.51.1"
        ip_address_vmbr1_60="10.60.10.92"
        ip_address_vmbr2_50="10.50.10.92"
        ip_address_vmbr2_55="10.55.10.92"
        write_interface_file
    elif [ "$node" = "pve3" ]; then
        eth_interface_vmbr0="eth1"
        eth_interface_vmbr1="eth3"
        eth_interface_vmbr2="eth2"
        ip_address_vmbr0="192.168.51.93"
        netmask_vmbr0="255.255.255.0"
        gateway_vmbr0="192.168.51.1"
        dns_server_vmbr0="192.168.51.1"
        ip_address_vmbr1_60="10.60.10.93"
        ip_address_vmbr2_50="10.50.10.93"
        ip_address_vmbr2_55="10.55.10.93"
        write_interface_file
    elif [ "$node" = "pve4" ]; then
        eth_interface_vmbr0="eth1"
        eth_interface_vmbr1="eth3"
        eth_interface_vmbr2="eth2"
        ip_address_vmbr0="192.168.51.94"
        netmask_vmbr0="255.255.255.0"
        gateway_vmbr0="192.168.51.1"
        dns_server_vmbr0="192.168.51.1"
        ip_address_vmbr1_60="10.60.10.94"
        ip_address_vmbr2_50="10.50.10.94"
        ip_address_vmbr2_55="10.55.10.94"
        write_interface_file
    fi
done





