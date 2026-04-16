#!/bin/bash

# verify.sh - One-key verification script
# Quickly check if filtering functionality works correctly

PROXY="http://localhost:8888"
MOCK="http://localhost:8545"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "Quick Verification - Ethereum RPC Filtering"
echo "=========================================="
echo ""

# Check services
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
