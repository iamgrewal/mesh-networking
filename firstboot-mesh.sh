#!/bin/bash

set -euo pipefail

interfaces_file="/etc/network/interfaces"
frr_file="/etc/frr/frr.conf"
hostname_file="/etc/hostname"

sudo apt update
sudo apt install openvswitch-switch frr -y
sudo apt upgrade -f -y

echo "sample diagram with 4 nodes"
echo "
┌───────┐     ┌───────┐
│  pve  ├─────┤ pve1  ├─────┐
└───┬───┘     └───┬───┘     │
    │             │         │
    │             │         │
┌───┴───┐     ┌───┴───┐     │
│ pve2  ├─────┤ pve3  ├─────┘
└───┬───┘     └───┬───┘
    │             │
    └─────────────┘
          pve4
"
## This design allows for:
## 	•	Direct high-speed connections between nodes (10/25/40/100Gbps) without expensive switches
## 	•	Automatic failover routing if any direct connection fails
## 	•	Separate VLANs for Ceph and other cluster traffic
## 	•	Jumbo frames (MTU 9000) for optimal performance
##  .   For our 5-node cluster (pve, pve1, pve2, pve3, pve4), we’ll implement:
## 	•	Public network: 192.168.51.9x/24 (vmbr0) with eth0 and gateway 192.168.51.1
## 	•	Proxmox cluster network: VLAN 55 with IPs 10.55.10.9x/24
## 	•	Ceph network: VLAN 60 with IPs 10.60.10.9x/24

read -rp "Enter node hostname (e.g., pve3): " nodename
read -rp "Enter last octet for this node (e.g., 94 for 10.55.10.94): " last_octet

# Validate last octet
if ! [[ "$last_octet" =~ ^[0-9]{1,3}$ ]] || ((last_octet < 1 || last_octet > 254)); then
    echo "Invalid octet: must be 1-254"
    exit 1
fi

read -rp "Enter main public interface (e.g., eth0): " pub_iface
read -rp "Enter Ceph fabric interface (e.g., eth1): " ceph_iface

# Validate interfaces
if ! ip link show "$pub_iface" &>/dev/null; then echo "Invalid interface $pub_iface"; exit 1; fi
if ! ip link show "$ceph_iface" &>/dev/null; then echo "Invalid interface $ceph_iface"; exit 1; fi

ip_55="10.55.10.$last_octet"
ip_60="10.60.10.$last_octet"
ip_pub="192.168.51.$last_octet"
net_id_hex=$(printf "%02x" "$last_octet")

echo "[*] Writing network interfaces to $interfaces_file"
cat <<EOF > "$interfaces_file"
auto lo
iface lo inet loopback

auto $pub_iface
iface $pub_iface inet manual

auto vmbr0
iface vmbr0 inet static
    address $ip_pub/24
    gateway 192.168.51.1
    bridge_ports $pub_iface
    bridge_stp off
    bridge_fd 0
    

auto $ceph_iface
iface $ceph_iface inet manual
    ovs_type OVSPort
    ovs_bridge vmbr2
    ovs_mtu 9000
    ovs_options other_config:rstp-enable=true other_config:rstp-path-cost=150 other_config:rstp-port-admin-edge=false other_config:rstp-port-auto-edge=false other_config:rstp-port-mcheck=true vlan_mode=native-untagged


auto vmbr2
iface vmbr2 inet manual
    ovs_type OVSBridge
    ovs_ports $ceph_iface vmbr2.55 vmbr2.60
    up ovs-vsctl set Bridge \${IFACE} rstp_enable=true other_config:rstp-priority=32768
    post-up sleep 10
    ovs_mtu 9000

auto vmbr2.55
iface vmbr2.55 inet static
    address $ip_55/24
    ovs_type OVSIntPort
    ovs_bridge vmbr2
    ovs_mtu 9000
    ovs_options tag=55
    post-up /usr/bin/systemctl restart frr.service

auto vmbr2.60
iface vmbr2.60 inet static
    address $ip_60/24
    ovs_type OVSIntPort
    ovs_bridge vmbr2
    ovs_mtu 9000
    ovs_options tag=60
EOF

echo "[*] Updating hostname to $nodename"
echo "$nodename" > "$hostname_file"
hostnamectl set-hostname "$nodename"

echo "[*] Enabling fabricd in /etc/frr/daemons"
sed -i 's/^fabricd=no/fabricd=yes/' /etc/frr/daemons

echo "[*] Writing FRR OpenFabric config"
cat <<EOF > "$frr_file"
frr defaults traditional
hostname $nodename
log syslog warning
ip forwarding
no ipv6 forwarding
service integrated-vtysh-config

interface lo
 ip address $ip_55/32
 ip router openfabric 1
 openfabric passive

interface vmbr2.55
 ip router openfabric 1
 openfabric csnp-interval 2
 openfabric hello-interval 1
 openfabric hello-multiplier 2

interface vmbr2.60
 ip router openfabric 1
 openfabric csnp-interval 2
 openfabric hello-interval 1
 openfabric hello-multiplier 2

line vty

router openfabric 1
 net 49.0001.1000.0000.00${last_octet}.00
 lsp-gen-interval 1
 max-lsp-lifetime 600
 lsp-refresh-interval 180
EOF

echo "[*] Reloading network and restarting FRR..."
ifreload -a
systemctl restart frr.service

echo "[+] Configuration complete for node $nodename"
ip route



cat <<EOF > /etc/frr/frr.conf
# FRR Configuration for OpenFabric routing
frr defaults traditional
hostname pve
log syslog warning
ip forwarding
no ipv6 forwarding
service integrated-vtysh-config

interface lo
 ip address 10.55.10.90/32
 ip router openfabric 1
 openfabric passive

interface vmbr2.55
 ip router openfabric 1
 openfabric csnp-interval 2
 openfabric hello-interval 1
 openfabric hello-multiplier 2

interface vmbr2.60
 ip router openfabric 1
 openfabric csnp-interval 2
 openfabric hello-interval 1
 openfabric hello-multiplier 2

line vty

router openfabric 1
 net 49.0001.1000.0000.0090.00
 lsp-gen-interval 1
 max-lsp-lifetime 600
 lsp-refresh-interval 180
EOF


cat <<EOF > /etc/frr/daemons
# Enable the OpenFabric daemon
fabricd=yes
EOF

ifreload -a
systemctl restart frr.service

#After configuration, verify routing with:
ip route
# The expected routing table for pve should show direct routes to all other nodes:
default via 192.168.51.1 dev vmbr0 onlink
10.55.10.0/24 dev vmbr2.55 proto kernel scope link src 10.55.10.90
10.55.10.91/32 dev vmbr2.55 scope link
10.55.10.92/32 dev vmbr2.55 scope link
10.55.10.93/32 dev vmbr2.55 scope link
10.55.10.94/32 dev vmbr2.55 scope link
10.60.10.0/24 dev vmbr2.60 proto kernel scope link src 10.60.10.90
192.168.51.0/24 dev vmbr0 proto kernel scope link src 192.168.51.90
#Ceph Configuration
#After establishing the network, initialize Ceph on the first node:
#Failure Handling#
#This setup handles failures as follows:#
#	1.	Node Failure: If a node fails, Ceph and Proxmox VE clusters remain functioning with reduced redundancy.
#	2.	Connection Failure: If a direct connection between nodes fails, OpenFabric will automatically reroute traffic through other available paths in the mesh.
#	3.	Network Partition: RSTP ensures the network topology remains loop-free while maintaining maximum connectivity

# The RSTP-based full mesh network with OpenFabric routing provides an optimal solution for a Ceph storage cluster, offering:
# 	•	High bandwidth direct connections between nodes
# 	•	Automatic failover in case of link failures
# 	•	Loop-free topology with RSTP
# 	•	Traffic prioritization and separation through VLANs
# 	•	Cost-effective alternative to expensive high-speed switches