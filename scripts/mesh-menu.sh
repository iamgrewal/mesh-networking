#!/bin/bash

# Version: 1.0.0
# Author: Jatinder Grewal <jgrewal@po1.me>
# Date: 2025-04-04
# Purpose: Interactive menu for mesh networking scripts

# Set strict error handling
set -euo pipefail

# Color definitions for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to display a header
display_header() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}       Proxmox Mesh Networking Menu              ${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo ""
}

# Function to display the main menu
display_menu() {
    echo -e "${YELLOW}Available Options:${NC}"
    echo -e "  ${GREEN}1)${NC} Run Mesh Setup Script"
    echo -e "  ${GREEN}2)${NC} Run Network Interface Rename Script"
    echo -e "  ${GREEN}3)${NC} Run Network Validation Script"
    echo -e "  ${GREEN}4)${NC} Run Rollback Script"
    echo -e "  ${GREEN}5)${NC} Install Network Testing Tools"
    echo -e "  ${GREEN}6)${NC} Run Network Test"
    echo -e "  ${GREEN}0)${NC} Exit"
    echo ""
    echo -n -e "${YELLOW}Enter your choice [0-6]: ${NC}"
}

# Function to run a script with proper output
run_script() {
    local script_name=$1
    local script_path="${SCRIPT_DIR}/${script_name}"
    
    if [[ ! -f "$script_path" ]]; then
        echo -e "${RED}Error: Script $script_name not found!${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Running $script_name...${NC}"
    echo -e "${BLUE}=================================================${NC}"
    
    # Make the script executable
    chmod +x "$script_path"
    
    # Run the script and capture its output
    if "$script_path" 2>&1 | tee /tmp/script_output.log; then
        echo -e "${GREEN}Script completed successfully!${NC}"
    else
        echo -e "${RED}Script encountered an error. Check the output above.${NC}"
    fi
    
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${YELLOW}Press Enter to continue...${NC}"
    read -r
}

# Function to install network testing tools
install_network_tools() {
    echo -e "${BLUE}Installing network testing tools...${NC}"
    
    if ! command -v apt-get &> /dev/null; then
        echo -e "${RED}Error: apt-get not found. This script is designed for Debian-based systems.${NC}"
        return 1
    fi
    
    # Update package lists
    echo -e "${YELLOW}Updating package lists...${NC}"
    sudo apt-get update
    
    # Install ifupdown-extra and other useful network tools
    echo -e "${YELLOW}Installing network testing tools...${NC}"
    sudo apt-get install -y ifupdown-extra iputils-ping net-tools traceroute
    
    echo -e "${GREEN}Network testing tools installed successfully!${NC}"
    echo -e "${YELLOW}Press Enter to continue...${NC}"
    read -r
}

# Function to run network test
run_network_test() {
    echo -e "${BLUE}Running network test...${NC}"
    
    if ! command -v network-test &> /dev/null; then
        echo -e "${RED}Error: network-test command not found. Please install ifupdown-extra first.${NC}"
        echo -e "${YELLOW}Press Enter to continue...${NC}"
        read -r
        return 1
    fi
    
    echo -e "${YELLOW}Running network-test command...${NC}"
    sudo network-test
    
    echo -e "${GREEN}Network test completed!${NC}"
    echo -e "${YELLOW}Press Enter to continue...${NC}"
    read -r
}

# Main loop
while true; do
    display_header
    display_menu
    
    read -r choice
    
    case $choice in
        1)
            run_script "mesh-setup.sh"
            ;;
        2)
            run_script "network_rename.sh"
            ;;
        3)
            run_script "validate-network.sh"
            ;;
        4)
            run_script "rollback.sh"
            ;;
        5)
            install_network_tools
            ;;
        6)
            run_network_test
            ;;
        0)
            echo -e "${GREEN}Exiting...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid choice. Please try again.${NC}"
            sleep 2
            ;;
    esac
done 