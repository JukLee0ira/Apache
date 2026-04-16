#!/bin/bash

# test_rpc.sh - Ethereum JSON-RPC Filtering POC Test Script

set -e

PROXY_URL="http://localhost:8888"
RPC_BACKEND_URL="http://localhost:8545"

# Colored output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Ethereum RPC Filtering POC Test Script"
echo "=========================================="
echo ""

# Check if services are running
check_service() {
    echo -n "Checking backend RPC node... "
    if curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "$RPC_BACKEND_URL" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
        return 0
    else
        echo -e "${RED}X${NC}"
        return 1
    fi
}

check_proxy() {
    echo -n "Checking Apache proxy... "
    if curl -s -o /dev/null -w "%{http_code}" "$PROXY_URL" | grep -q "200|403|400"; then
        echo -e "${GREEN}✓${NC}"
        return 0
    else
        echo -e "${RED}X${NC}"
        return 1
    fi
}

# Wait for services to be ready
wait_for_services() {
    echo "Waiting for services to start..."
    for i in $(seq 1 30); do
        if check_service && check_proxy; then
            echo "Services are ready!"
            return 0
        fi
        echo -n "."
        sleep 2
    done
    echo -e "\n${RED}Service startup timeout${NC}"
    exit 1
}

# Test function: Send JSON-RPC request
send_rpc_request() {
    local method="$1"
    local params="$2"
    local description="$3"
    local expected="$4"  # expected: "allowed" or "denied"

    echo ""
    echo "-------------------------------------------"
    echo "Test: $description"
    echo "Method: $method"
    echo "Params: $params"
    echo "Expected: $expected"
    echo "-------------------------------------------"

    local response
    local http_code

    response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}" \
        "$PROXY_URL" 2>/dev/null || true)

    http_code=$(echo "$response" | grep "HTTP_STATUS:" | cut -d: -f2)
    body=$(echo "$response" | sed '/HTTP_STATUS:/d')

    echo "Response code: $http_code"
    echo "Response body: $body"

    if [ "$expected" = "allowed" ]; then
        if [ "$http_code" = "200" ] || [ "$http_code" = "0" ]; then
            echo -e "${GREEN}✓ Passed - Request was allowed${NC}"
            return 0
        else
            echo -e "${RED}X Failed - Request was rejected (expected allowed)${NC}"
            return 1
        fi
    else
        if [ "$http_code" = "403" ]; then
            echo -e "${GREEN}✓ Passed - Request was rejected${NC}"
            return 0
        else
            echo -e "${RED}X Failed - Request was allowed (expected rejected)${NC}"
            return 1
        fi
    fi
}

# Main test flow
main() {
    # Wait for services
    wait_for_services

    local passed=0
    local failed=0

    # Test 1: eth_blockNumber - whitelisted method, should pass
    send_rpc_request "eth_blockNumber" "[]" "Query block height (whitelisted method)" "allowed" && ((passed++)) || ((failed++))

    # Test 2: net_version - whitelisted method, should pass
    send_rpc_request "net_version" "[]" "Query network version (whitelisted method)" "allowed" && ((passed++)) || ((failed++))

    # Test 3: eth_chainId - whitelisted method, should pass
    send_rpc_request "eth_chainId" "[]" "Query chain ID (whitelisted method)" "allowed" && ((passed++)) || ((failed++))

    # Test 4: eth_getBalance - whitelisted method, should pass
    send_rpc_request "eth_getBalance" '["0x1234567890123456789012345678901234567890","latest"]' "Balance query (whitelisted address)" "allowed" && ((passed++)) || ((failed++))

    # Test 5: eth_call - whitelisted address, should pass
    send_rpc_request "eth_call" '[{"to":"0x1234567890123456789012345678901234567890","data":"0x70a08231"}]' "Contract call (whitelisted address)" "allowed" && ((passed++)) || ((failed++))

    # Test 6: eth_call - non-whitelisted address, should be rejected
    send_rpc_request "eth_call" '[{"to":"0xffffffffffffffffffffffffffffffffffffffff","data":"0x70a08231"}]' "Contract call (non-whitelisted address)" "denied" && ((passed++)) || ((failed++))

    # Test 7: eth_getLogs - whitelisted address, should pass
    send_rpc_request "eth_getLogs" '[{"address":"0x1234567890123456789012345678901234567890"}]' "Query logs (whitelisted address)" "allowed" && ((passed++)) || ((failed++))

    # Test 8: eth_getLogs - non-whitelisted address, should be rejected
    send_rpc_request "eth_getLogs" '[{"address":"0x0000000000000000000000000000000000000000"}]' "Query logs (non-whitelisted address)" "denied" && ((passed++)) || ((failed++))

    # Test 9: Non-whitelisted method (e.g., personal_sign), should be rejected
    send_rpc_request "personal_sign" '["test","0x1234567890123456789012345678901234567890"]' "Personal signature (non-whitelisted method)" "denied" && ((passed++)) || ((failed++))

    # Test 10: Invalid JSON, should return 400
    echo ""
    echo "-------------------------------------------"
    echo "Test: Invalid JSON format"
    echo "Expected: 400 Bad Request"
    echo "-------------------------------------------"
    response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        --data "not valid json" \
        "$PROXY_URL" 2>/dev/null || true)
    http_code=$(echo "$response" | grep "HTTP_STATUS:" | cut -d: -f2)
    echo "Response code: $http_code"
    if [ "$http_code" = "400" ]; then
        echo -e "${GREEN}✓ Passed - Returned 400${NC}"
        ((passed++))
    else
        echo -e "${RED}X Failed - Expected 400${NC}"
        ((failed++))
    fi

    # Summary
    echo ""
    echo "=========================================="
    echo "Test Results"
    echo "=========================================="
    echo -e "Passed: ${GREEN}$passed${NC}"
    echo -e "Failed: ${RED}$failed${NC}"
    echo "Total: $((passed + failed))"

    if [ $failed -eq 0 ]; then
        echo -e "\n${GREEN}✓ All tests passed!${NC}"
        exit 0
    else
        echo -e "\n${RED}X Some tests failed${NC}"
        exit 1
    fi
}

main "$@"
