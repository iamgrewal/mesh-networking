# Proxmox VE Mesh Networking

An automation framework for setting up full mesh networking in Proxmox VE clusters with Open vSwitch and FRR OpenFabric integration.

## Features

- Automated configuration of Open vSwitch bridges with RSTP
- FRR OpenFabric routing setup
- VLAN segregation for Ceph and cluster traffic
- Automatic hostname resolution via /etc/hosts
- Persistent configuration across reboots
- Backup and restore capabilities
- Interactive and automated configuration options
- Auto-discovery of mesh nodes from /etc/hosts

## Installation

```bash
# Install the package
dpkg -i mesh-networking_1.0.0_all.deb

# If there are dependency issues, run:
apt-get install -f

# Run the configuration script
mesh-network-gen
```

## Usage

The main script `mesh-network-gen` supports both interactive and non-interactive modes:

### Interactive Mode

Simply run the script without options:

```bash
mesh-network-gen
```

This will guide you through the configuration process with prompts.

### Non-Interactive Mode

For automation pipelines, Ansible, cloud-init, or scripted scale-outs:

```bash
mesh-network-gen --node pve5 --eth0 enp1s0 --eth1 enp2s0 --eth2 enp3s0 --auto
```

This will automatically configure the node without any user interaction.

### Command-Line Options

- `--node NODE_NAME`: Specify the Proxmox node hostname (e.g., pve, pve1)
- `--eth0 INTERFACE`: Specify the Ethernet interface for vmbr0 (Public)
- `--eth1 INTERFACE`: Specify the Ethernet interface for vmbr1 (Proxmox Cluster)
- `--eth2 INTERFACE`: Specify the Ethernet interface for vmbr2 (Ceph)
- `--auto`: Run in non-interactive mode (requires --node and interface options)
- `--check`: Check current configuration without making changes
- `--no-frr`: Skip FRR configuration generation
- `--no-hosts`: Skip /etc/hosts update
- `--help`: Show help message

## Network Architecture

The mesh network consists of three bridges:

1. **vmbr0**: Public network for VM communication and internet access
2. **vmbr1**: Proxmox cluster network with VLAN 60
3. **vmbr2**: Ceph network with VLANs 50 and 55

## Auto-Discovery

The script can automatically discover mesh nodes from /etc/hosts and use this information to:

- Populate FRR configuration with peer information
- Validate network connectivity between nodes
- Ensure consistent configuration across the cluster

## Files

- `/usr/local/bin/mesh-network-gen`: Main configuration script
- `/etc/network/interfaces.${NODE}`: Network configuration for each node
- `/etc/frr/frr.conf.${NODE}`: FRR configuration for each node
- `/etc/hosts`: Contains mesh node hostname mappings

## Troubleshooting

- Check `/var/log/mesh-network-gen.log` for script execution logs
- Verify Open vSwitch status with `systemctl status openvswitch-switch`
- Check FRR status with `systemctl status frr.service`
- View network interfaces with `ip -br link show`
- Check OpenFabric neighbors with `vtysh -c "show isis neighbors"`

## License

This package is provided under the MIT License. 