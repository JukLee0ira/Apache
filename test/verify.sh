#!/bin/bash

# verify.sh - One-key verification script
# Supports both Docker and Native (systemd) deployment modes
# Quickly check if filtering functionality works correctly

PROXY="http://localhost:8888"
MOCK="http://localhost:8545"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Detect deployment mode
check_docker_mode() {
    command -v docker &> /dev/null && docker ps &> /dev/null 2>&1
}

echo "=========================================="
echo "Quick Verification - Ethereum RPC Filtering"
echo "=========================================="
echo ""

# Check services based on deployment mode
if check_docker_mode; then
    echo "Deployment Mode: Docker"

    if ! curl -s "$MOCK/health" | grep -q OK; then
        echo -e "${RED}X Mock Server not running${NC}"
        echo "Please run: docker-compose up -d"
        exit 1
    fi

    echo "Sending test requests..."
    echo ""

    # Send whitelist request
    echo "1. Whitelist method eth_blockNumber"
    response=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "$PROXY")
    echo "   Proxy response code: $response"
    if [ "$response" = "200" ] || [ "$response" = "0" ]; then
        echo -e "   ${GREEN}✓ Passed${NC} - Request was allowed"
    else
        echo -e "   ${RED}X Failed${NC} - Expected 200, got $response"
    fi

    sleep 1

    # Send blacklist request
    echo ""
    echo "2. Blacklisted address 0x000...000 (eth_call)"
    response=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_call","params":[{"to":"0x0000000000000000000000000000000000000000","data":"0x70a08231"}],"id":1}' \
        "$PROXY")
    echo "   Proxy response code: $response"
    if [ "$response" = "403" ]; then
        echo -e "   ${GREEN}✓ Passed${NC} - Request was blocked"
    else
        echo -e "   ${RED}X Failed${NC} - Expected 403, got $response"
    fi

    sleep 1

    # Check mock server logs
    echo ""
    echo "3. Mock Server received requests:"
    echo "   (Should only see eth_blockNumber)"
    docker logs ethereum-rpc-mock --since 5s 2>/dev/null \
        | grep -E "eth_blockNumber|eth_call|Received request" \
        | head -3 || echo "    None"

    echo ""
    echo "=========================================="
    echo -e "${GREEN}Verification complete!${NC}"
    echo ""
    echo "Detailed logs:"
    echo "  - Apache Proxy: docker logs apache-rpc-proxy -f"
    echo "  - Mock Backend: docker logs ethereum-rpc-mock -f"
    echo ""

else
    echo "Deployment Mode: Native (systemd)"

    # Check Mock Service
    if ! systemctl is-active --quiet ethereum-rpc-mock 2>/dev/null; then
        echo -e "${RED}X Mock Server not running${NC}"
        echo "Please run: sudo systemctl start ethereum-rpc-mock"
        exit 1
    fi

    if ! curl -s "$MOCK/health" | grep -q OK; then
        echo -e "${RED}X Mock Server not responding${NC}"
        echo "Check status: sudo systemctl status ethereum-rpc-mock"
        exit 1
    fi

    echo "Sending test requests..."
    echo ""

    # Send whitelist request
    echo "1. Whitelist method eth_blockNumber"
    response=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "$PROXY")
    echo "   Proxy response code: $response"
    if [ "$response" = "200" ] || [ "$response" = "0" ]; then
        echo -e "   ${GREEN}✓ Passed${NC} - Request was allowed"
    else
        echo -e "   ${RED}X Failed${NC} - Expected 200, got $response"
    fi

    sleep 1

    # Send blacklist request
    echo ""
    echo "2. Blacklisted address 0x000...000 (eth_call)"
    response=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_call","params":[{"to":"0x0000000000000000000000000000000000000000","data":"0x70a08231"}],"id":1}' \
        "$PROXY")
    echo "   Proxy response code: $response"
    if [ "$response" = "403" ]; then
        echo -e "   ${GREEN}✓ Passed${NC} - Request was blocked"
    else
        echo -e "   ${RED}X Failed${NC} - Expected 403, got $response"
    fi

    sleep 1

    # Check mock server via API
    echo ""
    echo "3. Mock Server statistics:"
    stats=$(curl -s "$MOCK/stats" 2>/dev/null)
    if [ -n "$stats" ]; then
        echo "   $stats"
    else
        echo "   Unable to fetch statistics"
    fi

    echo ""
    echo "=========================================="
    echo -e "${GREEN}Verification complete!${NC}"
    echo ""
    echo "Detailed logs:"
    echo "  - Mock Backend: journalctl -u ethereum-rpc-mock -f"
    echo "  - Apache Proxy: tail -f /var/log/httpd/rpc-proxy-access.log"
    echo ""
fi
