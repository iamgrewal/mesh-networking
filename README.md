# Proxmox VE Mesh Network Configuration

This repository contains scripts for setting up and managing a full mesh network configuration for Proxmox VE clusters with Ceph storage. The configuration uses Open vSwitch with RSTP and FRRouting with OpenFabric for optimal performance and high availability.

## Overview

The mesh network configuration provides:
- Direct high-speed connections between nodes (10/25/40/100Gbps)
- Automatic failover routing
- Separate VLANs for Ceph and cluster traffic
- Jumbo frames (MTU 9000) for optimal performance

## Network Architecture

The configuration implements a 5-node cluster with the following network segments:
- Public network: 192.168.51.9x/24 (vmbr0)
- Cluster network: VLAN 55 with IPs 10.55.10.9x/24
- Ceph network: VLAN 60 with IPs 10.60.10.9x/24

## Prerequisites

- Proxmox VE 8.3
- Debian 12
- Root access
- Network interfaces with support for jumbo frames
- Open vSwitch and FRRouting packages

## Scripts

### 1. mesh-setup.sh

Initial setup script for configuring the mesh network.

Usage:
```bash
sudo ./mesh-setup.sh
```

The script will:
- Install required packages
- Prompt for node information
- Configure network interfaces
- Set up OVS bridges with RSTP
- Configure FRR with OpenFabric

### 2. validate-network.sh

Validation script to verify network configuration and connectivity.

Usage:
```bash
sudo ./validate-network.sh
```

The script checks:
- Interface configurations
- OVS bridge settings
- FRR configuration
- Network connectivity between nodes

### 3. rollback.sh

Rollback script to restore previous configuration in case of failures.

Usage:
```bash
sudo ./rollback.sh
```

The script will:
- Find the latest backup
- Clean up OVS bridges
- Restore network configuration
- Verify restoration

## Configuration Files

### Network Interfaces
Location: `/etc/network/interfaces`
- Configures physical interfaces
- Sets up OVS bridges
- Defines VLAN interfaces

### FRR Configuration
Location: `/etc/frr/frr.conf`
- Configures OpenFabric routing
- Sets up interface parameters
- Defines routing policies

## Backup and Recovery

Configuration backups are stored in `/etc/network/backups/` with timestamps. The rollback script can restore the most recent backup if needed.

## Logging

All scripts write logs to:
- `/var/log/mesh-setup.log`
- `/var/log/mesh-validation.log`
- `/var/log/mesh-rollback.log`

## Best Practices

1. Always run scripts as root
2. Backup existing configuration before running setup
3. Validate network configuration after setup
4. Monitor logs for any issues
5. Use rollback script if problems occur

## Troubleshooting

Common issues and solutions:

1. Interface not found
   - Verify interface names
   - Check physical connections

2. MTU mismatch
   - Ensure hardware support for jumbo frames
   - Verify MTU settings on all nodes

3. FRR service issues
   - Check FRR daemon status
   - Verify configuration syntax

4. OVS bridge problems
   - Check OVS service status
   - Verify bridge configuration

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## References

- [Proxmox VE Documentation](https://pve.proxmox.com/wiki/Main_Page)
- [Open vSwitch Documentation](https://docs.openvswitch.org/)
- [FRRouting Documentation](https://docs.frrouting.org/)
- [Ceph Documentation](https://docs.ceph.com/) 