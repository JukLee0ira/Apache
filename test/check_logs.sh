#!/bin/bash

# check_logs.sh - View interception and request logs
# Display all blocked requests and requests that reached the backend
# Supports both Docker and Native (systemd) deployment modes

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Detect deployment mode
check_docker_mode() {
    command -v docker &> /dev/null && docker ps &> /dev/null 2>&1
}

echo "=========================================="
echo "Blocked Log Check"
echo "=========================================="
echo ""

if check_docker_mode; then
    echo "Deployment Mode: Docker"
    echo ""

    # Check containers
    if ! docker ps | grep -q "apache-rpc-proxy"; then
        echo -e "${RED}X Apache proxy container not running${NC}"
        exit 1
    fi

    if ! docker ps | grep -q "ethereum-rpc-mock"; then
        echo -e "${RED}X Mock Server container not running${NC}"
        exit 1
    fi

    # Display blocked logs
    echo "Recent 10 blocked logs (rejected requests):"
    echo "-------------------------------------------"
    docker logs apache-rpc-proxy 2>&1 \
        | grep "\[BLOCKED\]" \
        | tail -10 \
        | sed 's/\[BLOCKED\]/\n[BLOCKED]/g' \
        || echo "  (no blocked records)"

    echo ""
    echo "Recent 10 allowed logs (requests that reached backend):"
    echo "-------------------------------------------"
    docker logs apache-rpc-proxy 2>&1 \
        | grep "\[ALLOWED\]" \
        | tail -10 \
        | sed 's/\[ALLOWED\]/\n[ALLOWED]/g' \
        || echo "  (no allowed records)"

    echo ""
    echo "Requests received by Mock Server:"
    echo "-------------------------------------------"
    docker logs ethereum-rpc-mock --tail 20 2>&1 \
        | grep "RECEIVED RPC REQUEST" \
        | sed 's/RECEIVED/\\nRECEIVED/' \
        || echo "  (no request records)"

    echo ""
    echo "Statistics:"
    echo "-------------------------------------------"
    blocked=$(docker logs apache-rpc-proxy 2>&1 | grep -c "\[BLOCKED\]" || echo 0)
    allowed=$(docker logs apache-rpc-proxy 2>&1 | grep -c "\[ALLOWED\]" || echo 0)
    mock_received=$(docker logs ethereum-rpc-mock 2>&1 | grep -c "RECEIVED" || echo 0)

    echo -e "  Blocked requests: ${YELLOW}$blocked${NC}"
    echo -e "  Allowed requests: ${GREEN}$allowed${NC}"
    echo -e "  Backend received: ${GREEN}$mock_received${NC}"

    # Verify consistency
    if [ "$allowed" -eq "$mock_received" ]; then
        echo ""
        echo -e "  ${GREEN}OK: Data consistent - All allowed requests reached backend${NC}"
    elif [ "$mock_received" -gt "$allowed" ]; then
        echo ""
        echo -e "  ${RED}WARNING: Backend received more requests than allowed logs!${NC}"
        echo -e "    There may be direct requests bypassing the proxy"
    elif [ "$mock_received" -lt "$allowed" ]; then
        echo ""
        echo -e "  ${YELLOW}NOTE: Some allowed requests may not have reached backend yet${NC}"
    fi

    echo ""
    echo "Real-time log monitoring:"
    echo "  1. Monitor blocked logs: docker logs apache-rpc-proxy -f | grep BLOCKED"
    echo "  2. Monitor backend logs: docker logs ethereum-rpc-mock -f"
    echo ""

else
    echo "Deployment Mode: Native (systemd)"
    echo ""

    # Check services
    echo "Checking services..."
    if ! systemctl is-active --quiet ethereum-rpc-mock 2>/dev/null; then
        echo -e "${RED}X Mock Server not running${NC}"
        echo "Please run: sudo systemctl start ethereum-rpc-mock"
        exit 1
    fi
    echo -e "  Mock Server: ${GREEN}running${NC}"

    # Get statistics via API
    echo ""
    echo "Statistics (via API):"
    echo "-------------------------------------------"
    stats=$(curl -s http://localhost:8545/stats 2>/dev/null)
    if [ -n "$stats" ]; then
        if command -v jq >/dev/null 2>&1; then
            echo "$stats" | jq .
        else
            echo "$stats"
        fi
    else
        echo "  Unable to fetch statistics"
    fi

    # Get recent blocked records
    echo ""
    echo "Recent blocked records:"
    echo "-------------------------------------------"
    blocked=$(curl -s http://localhost:8545/blocked 2>/dev/null)
    if [ -n "$blocked" ] && [ "$blocked" != "[]" ]; then
        if command -v jq >/dev/null 2>&1; then
            echo "$blocked" | jq '.[-10:]' 2>/dev/null || echo "$blocked"
        else
            echo "$blocked"
        fi
    else
        echo "  (no blocked records)"
    fi

    # Get recent allowed records
    echo ""
    echo "Recent allowed records:"
    echo "-------------------------------------------"
    allowed=$(curl -s http://localhost:8545/allowed 2>/dev/null)
    if [ -n "$allowed" ] && [ "$allowed" != "[]" ]; then
        if command -v jq >/dev/null 2>&1; then
            echo "$allowed" | jq '.[-10:]' 2>/dev/null || echo "$allowed"
        else
            echo "$allowed"
        fi
    else
        echo "  (no allowed records)"
    fi

    # Systemd journal logs
    echo ""
    echo "Mock Server journal logs (recent 10 lines):"
    echo "-------------------------------------------"
    journalctl -u ethereum-rpc-mock --no-pager -n 10 2>/dev/null | sed 's/^/  /' || echo "  No logs available"

    echo ""
    echo "Apache access logs (recent 10 lines):"
    echo "-------------------------------------------"
    tail -n 10 /var/log/httpd/rpc-proxy-access.log 2>/dev/null | sed 's/^/  /' || echo "  No logs available"

    echo ""
    echo "Real-time log monitoring:"
    echo "  1. Monitor Mock Server: journalctl -u ethereum-rpc-mock -f"
    echo "  2. Monitor Apache: tail -f /var/log/httpd/rpc-proxy-access.log"
    echo "  3. View blocked records: curl -s http://localhost:8545/blocked | jq ."
    echo ""
fi
