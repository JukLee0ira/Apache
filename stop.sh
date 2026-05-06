#!/bin/bash
#
# stop.sh - Ethereum RPC Filter Stop Script
# Supports both Docker and Native (systemd) deployment modes
#

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "${GREEN}[STOP]${NC} $1"; }

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Ethereum RPC Filter - Stop Services${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# Detect deployment mode
if command -v docker &> /dev/null && docker ps &> /dev/null 2>&1; then
    # Docker mode
    info "Using Docker deployment"
    docker-compose down
    info "Docker containers stopped"

else
    # Native (systemd) mode
    info "Using native systemd deployment"

    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}[ERROR] Native deployment requires root privileges${NC}"
        echo "Please run: sudo ./stop.sh"
        exit 1
    fi

    # Stop services
    info "Stopping Apache Proxy..."
    systemctl stop httpd 2>/dev/null || true

    info "Stopping Mock Backend..."
    systemctl stop ethereum-rpc-mock 2>/dev/null || true

    info "Services stopped"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo ""
