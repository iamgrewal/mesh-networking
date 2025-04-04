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

2. Use the interactive menu to run scripts:
   ```bash
   sudo ./scripts/mesh-menu.sh
   ```

   Or run individual scripts:

3. Rename network interfaces (optional but recommended):
   ```bash
   sudo ./scripts/network_rename.sh
   ```

4. Run the setup script:
   ```bash
   sudo ./scripts/mesh-setup.sh
   ```

5. Validate the configuration:
   ```bash
   sudo ./scripts/validate-network.sh
   ```

## Scripts

### mesh-menu.sh
- Interactive menu for running all mesh networking scripts
- Provides a user-friendly interface for script execution
- Includes options for installing network testing tools
- Displays real-time output from script execution
- Handles errors gracefully with clear feedback

### network_rename.sh
- Interactive interface renaming utility
- Displays interface information including MAC addresses and speeds
- Creates persistent systemd .link files for renaming
- Backs up existing configuration
- Requires reboot to apply changes

### mesh-setup.sh
- Initial network configuration
- OVS bridge setup
- FRR configuration
- VLAN configuration
- Supports dry-run and force modes
- Includes backup functionality

### validate-network.sh
- Validates network interfaces
- Checks OVS configuration
- Verifies FRR settings
- Tests network connectivity

### rollback.sh
- Restores previous configuration
- Cleans up OVS bridges
- Reverts FRR settings

## Using the Interactive Menu

The `mesh-menu.sh` script provides a convenient way to run all the mesh networking scripts from a single interface:

1. Run the menu script:
   ```bash
   sudo ./scripts/mesh-menu.sh
   ```

2. Select an option from the menu:
   - Option 1: Run Mesh Setup Script
   - Option 2: Run Network Interface Rename Script
   - Option 3: Run Network Validation Script
   - Option 4: Run Rollback Script
   - Option 5: Install Network Testing Tools
   - Option 6: Run Network Test
   - Option 0: Exit

3. Follow the on-screen instructions for each option.

The menu provides real-time feedback and ensures proper execution of each script with appropriate error handling.

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
   - Use consistent interface naming across all nodes

2. Open vSwitch
   - Enable RSTP on all bridges
   - Set appropriate path costs
   - Configure native-untagged VLAN mode for Ceph interfaces

3. FRRouting
   - Enable fabricd daemon
   - Configure proper NET IDs
   - Set appropriate hello intervals
   - Use passive interfaces for loopback

4. Interface Renaming
   - Use the network_rename.sh script for consistent naming
   - Choose meaningful prefixes (eth, net, etc.)
   - Consider interface speeds when ordering
   - Back up configurations before making changes

## Troubleshooting

1. Network Issues
   - Check interface status with `ip link show`
   - Verify OVS bridges with `ovs-vsctl show`
   - Test connectivity with `ping` and `traceroute`

2. FRR Issues
   - Check FRR status with `systemctl status frr`
   - Verify FRR configuration with `vtysh -c "show running-config"`
   - Check FRR logs with `journalctl -u frr`

3. Interface Renaming Issues
   - Check .link files in `/etc/systemd/network/`
   - Verify MAC addresses with `ip link show`
   - Check logs at `/var/log/network-rename.log`

4. Menu Script Issues
   - Ensure all scripts are executable with `chmod +x scripts/*.sh`
   - Check for proper permissions with `ls -la scripts/`
   - Verify script paths with `which mesh-menu.sh`

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Authors

- Jatinder Grewal <jgrewal@po1.me>

## Acknowledgments

- Proxmox VE Community
- Open vSwitch Project
- FRRouting Project 