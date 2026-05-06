#!/bin/bash

# view_blocked.sh - View blocked records (from Mock Server)
# Supports both Docker and Native (systemd) deployment modes

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Detect deployment mode
check_docker_mode() {
    command -v docker &> /dev/null && docker ps &> /dev/null 2>&1
}

echo "=========================================="
echo "Blocked Request Record Query"
echo "=========================================="
echo ""

if ! curl -s http://localhost:8545/health | grep -q OK; then
    echo -e "${RED}X Mock Server not running${NC}"
    if check_docker_mode; then
        echo "Start with: docker-compose up -d"
    else
        echo "Start with: sudo systemctl start ethereum-rpc-mock"
    fi
    exit 1
fi

# Get statistics
echo "Statistics:"
echo "-------------------------------------------"
stats=$(curl -s http://localhost:8545/stats 2>/dev/null)
if [ $? -eq 0 ]; then
    if command -v jq >/dev/null 2>&1; then
        echo "$stats" | jq . 2>/dev/null || echo "$stats"
    else
        echo "$stats"
    fi
else
    echo "   Unable to fetch statistics"
fi

echo ""
echo "Recent blocked records:"
echo "-------------------------------------------"
blocked=$(curl -s http://localhost:8545/blocked 2>/dev/null)
if [ -n "$blocked" ] && [ "$blocked" != "[]" ]; then
    if command -v jq >/dev/null 2>&1; then
        echo "$blocked" | jq . 2>/dev/null || echo "$blocked"
    else
        echo "$blocked"
    fi
else
    echo "  (no blocked records yet)"
fi

echo ""

if check_docker_mode; then
    echo "Detailed Apache blocked logs:"
    echo "-------------------------------------------"
    docker logs apache-rpc-proxy 2>&1 | grep "\[BLOCKED\]" | tail -5 | sed 's/^/  /' \
        || echo "  (no blocked logs yet)"

    echo ""
    echo "Real-time monitoring commands:"
    echo "  # Monitor Apache blocking"
    echo "  docker logs apache-rpc-proxy -f | grep BLOCKED"
    echo ""
    echo "  # Monitor backend reception"
    echo "  docker logs ethereum-rpc-mock -f | grep RECEIVED"
    echo ""
else
    echo "Detailed Apache blocked logs:"
    echo "-------------------------------------------"
    journalctl -u httpd --since "10 minutes ago" --no-pager 2>/dev/null | grep -iE "blocked|403" | tail -5 | sed 's/^/  /' \
        || echo "  (no blocked logs yet)"

    echo ""
    echo "Real-time monitoring commands:"
    echo "  # Monitor Apache logs"
    echo "  journalctl -u httpd -f"
    echo ""
    echo "  # Monitor backend logs"
    echo "  journalctl -u ethereum-rpc-mock -f"
    echo ""
fi
