# Mesh Networking for Proxmox VE

[![Latest Release](https://img.shields.io/github/v/release/iamgrewal/mesh-networking?style=flat-square)](https://github.com/iamgrewal/mesh-networking/releases)
[![GitHub Actions](https://img.shields.io/github/workflow/status/iamgrewal/mesh-networking/Build%20%26%20Release%20mesh-networking%20.deb?style=flat-square)](https://github.com/iamgrewal/mesh-networking/actions)

A comprehensive automation framework for setting up full mesh networking in Proxmox VE clusters using Open vSwitch, FRRouting, and Ceph.

## Features

- **Full Mesh Topology**: Every node connects directly to all other nodes using high-speed interfaces
- **VLAN Segregation**: Separate VLANs for cluster traffic, Ceph traffic, and public access
- **Open vSwitch Integration**: RSTP-enabled bridges for resilient network paths
- **FRR OpenFabric Routing**: Rapid convergence with optimized routing protocols
- **Jumbo Frames**: MTU 9000 for high-performance Ceph network
- **Automated Configuration**: Interactive and non-interactive setup options
- **Auto-Discovery**: Automatically discover mesh nodes from `/etc/hosts`
- **Systemd Integration**: Proper service management and dependency handling
- **Log Rotation**: Automatic log management to prevent disk space issues

## Installation

```bash
# Download the latest release
# Option 1: Using wget (if the latest release is available)
wget https://github.com/iamgrewal/mesh-networking/releases/latest/download/mesh-networking_all.deb

# Option 2: Using curl (alternative)
curl -L -o mesh-networking_all.deb https://github.com/iamgrewal/mesh-networking/releases/latest/download/mesh-networking_all.deb

# Option 3: Manual download from GitHub Releases page
# Visit https://github.com/iamgrewal/mesh-networking/releases
# Download the latest mesh-networking_*_all.deb file

# Install the package
sudo dpkg -i mesh-networking_all.deb
sudo apt-get install -f  # Install any missing dependencies
```

> **Note**: If you encounter a 404 error when downloading, please check the [Releases page](https://github.com/iamgrewal/mesh-networking/releases) directly to find the latest release file.

## Usage

### Interactive Mode

```bash
sudo mesh-network-gen
```

### Non-Interactive Mode (for automation)

```bash
sudo mesh-network-gen --auto --node pve1 --eth0 eth0 --eth1 eth1 --eth2 eth2
```

### Command-Line Options

- `--node`: Specify the node hostname
- `--eth0`, `--eth1`, `--eth2`: Specify network interfaces
- `--auto`: Enable non-interactive mode
- `--check`: Validate existing configuration
- `--no-frr`: Skip FRR configuration
- `--no-hosts`: Skip /etc/hosts update
- `--version`: Display version information

## Documentation

For detailed documentation, see the [package documentation](https://github.com/iamgrewal/mesh-networking/tree/main/mesh-networking-deb/usr/share/mesh-networking).

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details. 