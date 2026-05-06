#!/bin/bash
#
# status.sh - Ethereum RPC Filter Status Check Script
# Supports both Docker and Native (systemd) deployment modes
#

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}==========================================${NC}"
echo -e "${CYAN}  Ethereum RPC Filter - Service Status${NC}"
echo -e "${CYAN}==========================================${NC}"
echo ""

# Detect deployment mode
if command -v docker &> /dev/null && docker ps &> /dev/null 2>&1; then
    # Docker mode
    echo "Deployment Mode: Docker"
    echo ""

    echo "Container status:"
    docker-compose ps

    echo ""
    echo "Health check:"
    curl -s http://localhost:8888/health && echo " [OK]" || echo -e "${RED} [FAILED]${NC}"

    echo ""
    echo "Statistics:"
    stats=$(curl -s http://localhost:8545/stats 2>/dev/null)
    if [ -n "$stats" ]; then
        if command -v jq >/dev/null 2>&1; then
            echo "$stats" | jq . 2>/dev/null || echo "$stats"
        else
            echo "$stats"
        fi
    else
        echo "Unable to fetch statistics"
    fi

    echo ""
    echo "Recent logs (Apache):"
    docker logs apache-rpc-proxy --tail 5 2>&1 | sed 's/^/  /'

    echo ""
    echo "Recent logs (Mock):"
    docker logs ethereum-rpc-mock --tail 5 2>&1 | sed 's/^/  /'

else
    # Native (systemd) mode
    echo "Deployment Mode: Native (systemd)"
    echo ""

    echo "Service status:"
    echo ""

    # Mock Backend
    echo -n "  ethereum-rpc-mock: "
    if systemctl is-active --quiet ethereum-rpc-mock 2>/dev/null; then
        echo -e "${GREEN}running${NC}"
    else
        echo -e "${RED}stopped${NC}"
    fi

    # Apache Proxy
    echo -n "  httpd (apache-proxy): "
    if systemctl is-active --quiet httpd 2>/dev/null; then
        echo -e "${GREEN}running${NC}"
    else
        echo -e "${RED}stopped${NC}"
    fi

    echo ""
    echo "Detailed status:"
    echo ""

    echo "--- ethereum-rpc-mock ---"
    systemctl status ethereum-rpc-mock --no-pager 2>/dev/null | head -5 || echo "  Not installed or not a systemd service"

    echo ""
    echo "--- httpd ---"
    systemctl status httpd --no-pager 2>/dev/null | head -5 || echo "  Not installed or not running"

    echo ""
    echo "Health check:"
    health_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8888/health 2>/dev/null)
    if [ "$health_code" = "200" ]; then
        echo -e "  http://localhost:8888/health: ${GREEN}OK${NC}"
    else
        echo -e "  http://localhost:8888/health: ${RED}FAILED${NC} (HTTP $health_code)"
    fi

    echo ""
    echo "Statistics:"
    stats=$(curl -s http://localhost:8545/stats 2>/dev/null)
    if [ -n "$stats" ]; then
        if command -v jq >/dev/null 2>&1; then
            echo "$stats" | jq . 2>/dev/null || echo "$stats"
        else
            echo "$stats"
        fi
    else
        echo "  Unable to fetch statistics (service may be down)"
    fi

    echo ""
    echo "Recent logs (Mock):"
    journalctl -u ethereum-rpc-mock --no-pager -n 5 2>/dev/null | sed 's/^/  /' || echo "  No logs available"

    echo ""
    echo "Recent logs (Apache):"
    tail -n 5 /var/log/httpd/rpc-proxy-access.log 2>/dev/null | sed 's/^/  /' || echo "  No logs available"

fi

echo ""
echo -e "${CYAN}==========================================${NC}"
echo ""
