# Mesh Networking for Proxmox VE Ceph Cluster

This repository contains scripts and configurations for setting up a full mesh network for a Proxmox VE Ceph cluster using Open vSwitch and FRRouting.

## Overview

The mesh network configuration provides:
- High-availability networking for Ceph storage
- Redundant cluster communication
- Efficient network isolation using VLANs
- Rapid convergence using RSTP
- Optimized routing with OpenFabric

## Network Architecture

The network consists of three main segments:
1. Public Network (vmbr0)
   - Standard network interface for general access
   - MTU: 1500

2. PVECM Network (vmbr1)
   - VLAN 50 for Proxmox cluster management
   - Used for corosync communication
   - MTU: 9000

3. Ceph/Cluster Network (vmbr2)
   - VLAN 55 for cluster traffic
   - VLAN 60 for Ceph traffic
   - MTU: 9000

## Prerequisites

- Proxmox VE 8.3 or later
- Open vSwitch
- FRRouting
- At least 3 network interfaces per node
- Root access

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/iamgrewal/mesh-networking.git
   cd mesh-networking
   ```

2. Run the setup script:
   ```bash
   sudo ./scripts/mesh-setup.sh
   ```

3. Validate the configuration:
   ```bash
   sudo ./scripts/validate-network.sh
   ```

## Scripts

### mesh-setup.sh
- Initial network configuration
- OVS bridge setup
- FRR configuration
- VLAN configuration

### validate-network.sh
- Validates network interfaces
- Checks OVS configuration
- Verifies FRR settings
- Tests network connectivity

### rollback.sh
- Restores previous configuration
- Cleans up OVS bridges
- Reverts FRR settings

## Configuration

### Network Interfaces
- eth0: Public network
- eth1: PVECM network
- eth2: Ceph/Cluster network

### VLANs
- VLAN 50: PVECM traffic
- VLAN 55: Cluster traffic
- VLAN 60: Ceph traffic

### OVS Bridges
- vmbr0: Public network
- vmbr1: PVECM network
- vmbr2: Ceph/Cluster network

## Best Practices

1. Network Configuration
   - Use consistent VLAN IDs across all nodes
   - Set appropriate MTU values
   - Configure proper interface bonding

2. Open vSwitch
   - Enable RSTP on all bridges
   - Set appropriate priorities
   - Configure proper aging time

3. FRRouting
   - Use correct NET ID format
   - Set appropriate timers
   - Enable integrated configuration

4. Security
   - Run scripts as root only
   - Validate all inputs
   - Create backups before changes

## Troubleshooting

1. Network Issues
   - Check interface status
   - Verify VLAN configuration
   - Test connectivity between nodes

2. OVS Problems
   - Check bridge status
   - Verify RSTP configuration
   - Monitor port states

3. FRR Issues
   - Check service status
   - Verify configuration
   - Monitor routing tables

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Authors

- Jatinder Grewal <jgrewal@po1.me>

## Acknowledgments

- Proxmox VE team
- Open vSwitch community
- FRRouting community 