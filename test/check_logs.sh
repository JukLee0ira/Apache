#!/bin/bash

# check_logs.sh - View interception and request logs
# Display all blocked requests and requests that reached the backend

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "Blocked Log Check"
echo "=========================================="
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
    echo -e "  ${GREEN}✓ Data consistent: All allowed requests reached backend${NC}"
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
