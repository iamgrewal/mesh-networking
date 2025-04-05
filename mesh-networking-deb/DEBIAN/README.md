# Mesh Networking .deb Package Guide

This document explains how to create, update, and maintain the mesh-networking .deb package for Proxmox VE mesh networking automation.

## Package Structure

The mesh-networking package follows the standard Debian package structure:

```
mesh-networking-deb/
├── DEBIAN/
│   ├── control           # Package metadata and dependencies
│   ├── postinst         # Post-installation script
│   ├── prerm            # Pre-removal script
│   └── README.md        # This file
├── etc/
│   ├── frr/
│   │   └── frr.conf.template  # FRR configuration template
│   └── systemd/
│       └── system/
│           └── mesh-networking.service  # Systemd service file
└── usr/
    ├── local/
    │   └── bin/
    │       └── mesh-network-gen         # Main script
    └── share/
        └── mesh-networking/
            ├── hosts.template            # Hosts file template
            └── README.md                 # User documentation
```

## Creating the .deb Package

### Prerequisites

- Debian-based system (Debian, Ubuntu, Proxmox VE)
- `dpkg-deb` utility
- Root or sudo access

### Step 1: Prepare the Package Structure

1. Create the package directory structure:

```bash
mkdir -p mesh-networking-deb/DEBIAN
mkdir -p mesh-networking-deb/etc/frr
mkdir -p mesh-networking-deb/etc/systemd/system
mkdir -p mesh-networking-deb/usr/local/bin
mkdir -p mesh-networking-deb/usr/share/mesh-networking
```

2. Set proper permissions:

```bash
chmod 755 mesh-networking-deb/DEBIAN
chmod 644 mesh-networking-deb/DEBIAN/control
chmod 755 mesh-networking-deb/DEBIAN/postinst
chmod 755 mesh-networking-deb/DEBIAN/prerm
chmod 755 mesh-networking-deb/usr/local/bin/mesh-network-gen
```

### Step 2: Create the Control File

The `control` file contains package metadata and dependencies:

```
Package: mesh-networking
Version: 1.0.0
Section: admin
Priority: optional
Architecture: all
Depends: openvswitch-switch, frr, iproute2, systemd
Maintainer: Jatinder Grewal <iamgrewal@gmail.com>
Description: Proxmox Mesh Network Automation Script with FRR OpenFabric
 Provides full automation of mesh-ready network interfaces and routing for Proxmox VE clusters.
 This package includes scripts for configuring Open vSwitch bridges with RSTP,
 FRR OpenFabric routing, and VLAN segregation for Ceph and cluster traffic.
```

### Step 3: Create Installation Scripts

#### Post-Installation Script (postinst)

```bash
#!/bin/bash
set -e

echo "[INFO] Running post-install script for mesh-networking"

# Enable FRR at boot
if systemctl list-unit-files | grep -q '^frr.service'; then
    systemctl enable frr.service
    echo "[INFO] Enabled frr.service at boot"
fi

# Make log dir if missing
mkdir -p /var/log

# Create a backup of existing hosts file if it doesn't already have mesh entries
if ! grep -q "# Proxmox Mesh Cluster Nodes" /etc/hosts; then
    cp /etc/hosts /etc/hosts.mesh-backup.$(date +%Y%m%d%H%M%S)
    echo "[INFO] Created backup of /etc/hosts"
fi

# Create a default FRR daemons file if it doesn't exist
if [ ! -f /etc/frr/daemons ]; then
    cat > /etc/frr/daemons << EOF
# This file tells the frr package which daemons to start.
#
# Sample configurations for BGP, OSPF, RIP, etc are shown.
#
# ATTENTION: BGP and OSPFv3 may not work as expected in this
# configuration.  See the /etc/frr/README file for an explanation.
#
# The traditional vtysh shell is also enabled by default.
#
# If you want to enable the integrated vtysh shell, uncomment the
# following line.
#vtysh_enable=yes
vtysh_enable=yes
zebra=yes
bgpd=no
ospfd=no
ospf6d=no
ripd=no
ripngd=no
isisd=no
pimd=no
ldpd=no
nhrpd=no
eigrpd=no
babeld=no
sharpd=no
pbrd=no
bfdd=no
fabricd=yes
pathd=no
EOF
    echo "[INFO] Created default FRR daemons file with fabricd enabled"
fi

# Ensure fabricd is enabled in FRR daemons
if grep -q "^fabricd=no" /etc/frr/daemons; then
    sed -i 's/^fabricd=no/fabricd=yes/' /etc/frr/daemons
    echo "[INFO] Enabled fabricd in FRR daemons"
fi

echo "[INFO] mesh-networking package installed successfully."
```

#### Pre-Removal Script (prerm)

```bash
#!/bin/bash
set -e

echo "[INFO] Running pre-removal script for mesh-networking"

# Ask if user wants to restore original network configuration
if [ "$1" = "remove" ] || [ "$1" = "deconfigure" ]; then
    read -rp "Do you want to restore the original network configuration? (y/n): " restore_config
    if [[ "$restore_config" =~ ^[Yy]$ ]]; then
        # Find the most recent backup
        latest_backup=$(ls -t /etc/network/interfaces.*.bak 2>/dev/null | head -n 1)
        if [ -n "$latest_backup" ]; then
            cp "$latest_backup" /etc/network/interfaces
            echo "[INFO] Restored network configuration from $latest_backup"
        else
            echo "[WARN] No backup found for network configuration"
        fi
    fi
fi

echo "[INFO] Pre-removal tasks completed."
```

### Step 4: Create the Systemd Service File

```ini
[Unit]
Description=Proxmox Mesh Networking Service
After=network.target openvswitch-switch.service frr.service
Requires=openvswitch-switch.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/mesh-network-gen --check
ExecStop=/bin/true
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
```

### Step 5: Add Configuration Templates

#### FRR Configuration Template

```
frr defaults traditional
hostname NODE_NAME
log syslog warning
ip forwarding
no ipv6 forwarding
service integrated-vtysh-config

interface lo
 ip address CLUSTER_IP/32
 ip router openfabric 1
 openfabric passive

interface vmbr1.60
 ip router openfabric 1
 openfabric csnp-interval 2
 openfabric hello-interval 1
 openfabric hello-multiplier 2

interface vmbr2.50
 ip router openfabric 1
 openfabric csnp-interval 2
 openfabric hello-interval 1
 openfabric hello-multiplier 2

interface vmbr2.55
 ip router openfabric 1
 openfabric csnp-interval 2
 openfabric hello-interval 1
 openfabric hello-multiplier 2

line vty

router openfabric 1
 net 49.0001.1000.0000.00NET_ID.00
 lsp-gen-interval 1
 max-lsp-lifetime 600
 lsp-refresh-interval 180
```

#### Hosts Template

```
# Proxmox Mesh Cluster Nodes
192.168.51.90 pve
192.168.51.91 pve1
192.168.51.92 pve2
192.168.51.93 pve3
192.168.51.94 pve4
```

### Step 6: Build the .deb Package

1. Navigate to the parent directory of `mesh-networking-deb`:

```bash
cd /path/to/parent/directory
```

2. Build the package:

```bash
dpkg-deb --build mesh-networking-deb
```

3. Rename the package with version information:

```bash
mv mesh-networking-deb.deb mesh-networking_1.0.0_all.deb
```

## Installing the Package

### On Proxmox VE

```bash
# Install the package
dpkg -i mesh-networking_1.0.0_all.deb

# If there are dependency issues, run:
apt-get install -f

# Run the configuration script
mesh-network-gen
```

## Updating the Package

### Step 1: Update the Version Number

1. Update the version number in the `control` file:

```
Package: mesh-networking
Version: 1.0.1
...
```

2. Update the version number in the script header comments.

### Step 2: Make Your Changes

1. Modify the scripts, templates, or add new files as needed.
2. Ensure all file permissions are correct.
3. Update the README.md with any new features or changes.

### Step 3: Rebuild the Package

1. Navigate to the parent directory of `mesh-networking-deb`.
2. Build the package with the new version:

```bash
dpkg-deb --build mesh-networking-deb
mv mesh-networking-deb.deb mesh-networking_1.0.1_all.deb
```

## Maintaining the Package

### Version Control

1. Use Git to track changes to your package:

```bash
git init
git add .
git commit -m "Initial commit of mesh-networking package"
```

2. Create a .gitignore file to exclude build artifacts:

```
*.deb
*.bak
```

### Testing

1. Test the package installation on a clean Proxmox VE system.
2. Verify that all scripts run correctly.
3. Check that the network configuration is applied properly.
4. Test the FRR OpenFabric routing functionality.

### Documentation

1. Keep the README.md up to date with:
   - New features
   - Bug fixes
   - Usage examples
   - Troubleshooting tips

2. Document any changes in a CHANGELOG.md file:

```markdown
# Changelog

## [1.0.1] - 2025-04-10
### Added
- Support for custom VLAN tags
- Enhanced validation for network interfaces

### Fixed
- Issue with FRR service restart
- Duplicate bridge detection

## [1.0.0] - 2025-04-05
### Added
- Initial release
- Open vSwitch bridge configuration
- FRR OpenFabric routing
- VLAN segregation
```

## Troubleshooting

### Common Issues

1. **Package installation fails with dependency errors**
   - Solution: Run `apt-get install -f` to resolve dependencies

2. **Scripts don't have execute permissions**
   - Solution: Ensure all scripts have `chmod 755` permissions

3. **FRR service doesn't start**
   - Solution: Check the FRR daemons file and ensure fabricd is enabled

4. **Network interfaces don't reload**
   - Solution: Check if ifreload is installed, otherwise use systemctl restart networking

### Logs

- Check `/var/log/mesh-network-gen.log` for script execution logs
- Check system logs with `journalctl -xe` for service-related issues

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

This package is provided under the MIT License. 