#!/bin/bash

# test_mock_direct.sh - Directly test Mock RPC Server
# Verify requests can reach backend directly (bypassing Apache proxy)

set -e

MOCK_URL="http://localhost:8545"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo "=========================================="
echo "Direct Test of Mock RPC Server"
echo "=========================================="
echo ""

echo -n "Checking if Mock Server is running... "
if curl -s -o /dev/null "$MOCK_URL/health"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}X Not running${NC}"
    echo "Start with: docker-compose up -d rpc-backend"
    exit 1
fi

echo ""
echo "Sending test requests to Mock Server:"
echo ""

# Test 1: eth_blockNumber
echo "1. eth_blockNumber"
curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    "$MOCK_URL" | jq .

# Test 2: eth_call
echo ""
echo "2. eth_call"
curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_call","params":[{"to":"0x1234567890123456789012345678901234567890","data":"0x70a08231"}],"id":1}' \
    "$MOCK_URL" | jq .

# Test 3: Non-standard method (verify backend responds)
echo ""
echo "3. Any method (e.g., personal_sign) - Mock Server will also respond"
curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"personal_sign","params":["test","0x1234"],"id":1}' \
    "$MOCK_URL" | jq .

echo ""
echo -e "${GREEN}✓ All requests sent to Mock Server${NC}"
echo "View Mock Server logs: docker logs ethereum-rpc-mock -f"
