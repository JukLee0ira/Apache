#!/bin/bash
#
# deploy.sh - Ethereum RPC Filter Auto-Deploy Script
# Automatically detects environment and chooses deployment method
#

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Detect deployment mode
detect_mode() {
    if command -v docker &> /dev/null && docker ps &> /dev/null 2>&1; then
        return 0  # Docker mode
    fi
    return 1  # Native mode
}

# Main
main() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  Ethereum RPC Filter - Auto Deploy${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""

    # Check if running as root (needed for native installation)
    if [ "$EUID" -ne 0 ]; then
        if detect_mode; then
            echo "Docker detected, proceeding without root..."
        else
            echo -e "${YELLOW}Note: Native installation will require sudo${NC}"
        fi
    fi

    echo ""
    echo "Detecting deployment environment..."
    echo ""

    if detect_mode; then
        # Docker mode
        echo -e "${GREEN}[MODE] Docker Deployment${NC}"
        echo ""
        echo "This will:"
        echo "  1. Build Docker images"
        echo "  2. Start containers"
        echo "  3. Verify services"
        echo ""
        read -p "Continue? (y/n) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Cancelled."
            exit 1
        fi

        echo ""
        echo "Starting Docker deployment..."
        ./start.sh

    else
        # Check if running as root
        if [ "$EUID" -ne 0 ]; then
            echo -e "${YELLOW}[MODE] Native Installation (requires sudo)${NC}"
        else
            echo -e "${GREEN}[MODE] Native Installation (RHEL/CentOS/Rocky)${NC}"
        fi
        echo ""
        echo "This will:"
        echo "  1. Install system dependencies (Apache, Lua)"
        echo "  2. Compile Lua extensions"
        echo "  3. Configure Apache"
        echo "  4. Install systemd services"
        echo "  5. Start services"
        echo "  6. Verify installation"
        echo ""

        # Check for required tools
        if ! grep -qiE "Red Hat|CentOS|Rocky|AlmaLinux" /etc/os-release 2>/dev/null; then
            echo -e "${RED}[ERROR] This installation script is for RHEL/CentOS/Rocky Linux only${NC}"
            echo ""
            echo "For other distributions, please use Docker deployment."
            echo "Install Docker: https://docs.docker.com/engine/install/"
            exit 1
        fi

        read -p "Continue? (y/n) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Cancelled."
            exit 1
        fi

        echo ""
        echo "Starting native installation..."
        ./install-rhel.sh
    fi
}

main "$@"
