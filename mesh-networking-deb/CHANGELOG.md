# Changelog

All notable changes to the mesh-networking package will be documented in this file.

## [1.0.1] - 2025-04-10
### Added
- Non-interactive mode with `--auto` option for automation pipelines
- Auto-discovery of mesh nodes from /etc/hosts
- Enhanced FRR configuration with peer information
- Support for additional node names (pve5-pve9)
- Improved validation and error handling
- Added Provides and Replaces fields to package control file

### Changed
- Updated systemd service to use /bin/true for ExecStart
- Improved logging for network reload commands
- Enhanced VLAN duplicate detection

### Fixed
- Issue with FRR service restart
- Duplicate bridge detection

## [1.0.0] - 2025-04-05
### Added
- Initial release of mesh-networking package
- Open vSwitch bridge configuration with RSTP
- FRR OpenFabric routing setup
- VLAN segregation for Ceph and cluster traffic
- Interactive configuration script with command-line options
- Automatic hostname resolution via /etc/hosts
- Backup and restore capabilities
- Systemd service integration
- Comprehensive logging and validation

### Features
- Full mesh topology using Open vSwitch with RSTP
- VLAN segregation for cluster and Ceph traffic
- Jumbo Frames (MTU 9000) for Ceph network
- OpenFabric routing with FRR
- Persistent configuration across reboots
- Interactive and automated configuration options 