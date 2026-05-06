#!/bin/bash

# test_mock_direct.sh - Directly test Mock RPC Server
# Verify requests can reach backend directly (bypassing Apache proxy)
# Supports both Docker and Native (systemd) deployment modes

set -e

MOCK_URL="http://localhost:8545"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Detect deployment mode
check_docker_mode() {
    command -v docker &> /dev/null && docker ps &> /dev/null 2>&1
}

echo "=========================================="
echo "Direct Test of Mock RPC Server"
echo "=========================================="
echo ""

echo -n "Checking if Mock Server is running... "
if curl -s -o /dev/null "$MOCK_URL/health"; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}Not running${NC}"
    if check_docker_mode; then
        echo "Start with: docker-compose up -d rpc-backend"
    else
        echo "Start with: sudo systemctl start ethereum-rpc-mock"
    fi
    exit 1
fi

echo ""
echo "Sending test requests to Mock Server:"
echo ""

# Test 1: eth_blockNumber
echo "1. eth_blockNumber"
if command -v jq >/dev/null 2>&1; then
    curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "$MOCK_URL" | jq .
else
    curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "$MOCK_URL"
    echo ""
fi

# Test 2: eth_call
echo ""
echo "2. eth_call"
if command -v jq >/dev/null 2>&1; then
    curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_call","params":[{"to":"0x1234567890123456789012345678901234567890","data":"0x70a08231"}],"id":1}' \
        "$MOCK_URL" | jq .
else
    curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_call","params":[{"to":"0x1234567890123456789012345678901234567890","data":"0x70a08231"}],"id":1}' \
        "$MOCK_URL"
    echo ""
fi

# Test 3: Non-standard method (verify backend responds)
echo ""
echo "3. Any method (e.g., personal_sign) - Mock Server will also respond"
if command -v jq >/dev/null 2>&1; then
    curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"personal_sign","params":["test","0x1234"],"id":1}' \
        "$MOCK_URL" | jq .
else
    curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"personal_sign","params":["test","0x1234"],"id":1}' \
        "$MOCK_URL"
    echo ""
fi

echo ""
echo -e "${GREEN}OK: All requests sent to Mock Server${NC}"
echo ""

if check_docker_mode; then
    echo "View Mock Server logs: docker logs ethereum-rpc-mock -f"
else
    echo "View Mock Server logs: journalctl -u ethereum-rpc-mock -f"
fi
