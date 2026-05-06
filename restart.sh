#!/bin/bash
#
# restart.sh - Ethereum RPC Filter Restart Script
# Supports both Docker and Native (systemd) deployment modes
#

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "${GREEN}[RESTART]${NC} $1"; }

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Ethereum RPC Filter - Restart Services${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# Detect deployment mode
if command -v docker &> /dev/null && docker ps &> /dev/null 2>&1; then
    # Docker mode
    info "Using Docker deployment"
    docker-compose restart
    info "Docker containers restarted"

else
    # Native (systemd) mode
    info "Using native systemd deployment"

    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}[ERROR] Native deployment requires root privileges${NC}"
        echo "Please run: sudo ./restart.sh"
        exit 1
    fi

    # Restart services
    info "Restarting Mock Backend..."
    systemctl restart ethereum-rpc-mock

    info "Restarting Apache Proxy..."
    systemctl restart httpd

    info "Services restarted"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo ""
