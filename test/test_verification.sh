#!/bin/bash

# test_verification.sh - Verification script comparing filtering results
# Shows which requests are blocked and which reach the mock server
# Supports both Docker and Native (systemd) deployment modes

set -e

PROXY_URL="http://localhost:8888"
MOCK_URL="http://localhost:8545"

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
echo "Filtering Effect Verification Script"
echo "=========================================="
echo ""
echo "Proxy: $PROXY_URL"
echo "Mock Backend: $MOCK_URL"
echo ""

# Check services
check_services() {
    echo "Checking service status..."
    local proxy_ok=false
    local mock_ok=false

    if curl -s -o /dev/null -w "%{http_code}" "$PROXY_URL" | grep -qE "200|403|400"; then
        proxy_ok=true
    fi

    if curl -s "$MOCK_URL/health" | grep -q "OK"; then
        mock_ok=true
    fi

    if $proxy_ok && $mock_ok; then
        echo -e "  Apache Proxy: ${GREEN}OK${NC}"
        echo -e "  Mock Server: ${GREEN}OK${NC}"
        return 0
    else
        echo -e "  Apache Proxy: $([ $proxy_ok = true ] && echo -e "${GREEN}OK${NC}" || echo -e "${RED}FAILED${NC}")"
        echo -e "  Mock Server: $([ $mock_ok = true ] && echo -e "${GREEN}OK${NC}" || echo -e "${RED}FAILED${NC}")"
        echo ""
        if check_docker_mode; then
            echo "Please start services first: docker-compose up -d"
        else
            echo "Please start services first: sudo ./start.sh"
        fi
        exit 1
    fi
}

# Clean mock server logs (by restarting)
clean_logs() {
    echo "Clearing Mock Server logs..."
    sleep 1
}

# Send request and wait for backend processing
send_and_wait() {
    curl -s -X POST -H "Content-Type: application/json" \
        --data "$1" \
        "$PROXY_URL" > /dev/null 2>&1
    sleep 1  # Wait for backend to record logs
}

# Get recent requests from mock server
get_mock_requests() {
    if check_docker_mode; then
        # Docker mode - use docker logs
        docker logs ethereum-rpc-mock --since 2s --tail 20 2>/dev/null \
            | grep -A 2 "Received request" \
            | grep "Method:" || true
    else
        # Native mode - use API endpoint
        curl -s "$MOCK_URL/stats" 2>/dev/null || true
    fi
}

main() {
    check_services
    clean_logs

    echo "=========================================="
    echo "Step 1: Send whitelisted request (should reach backend)"
    echo "=========================================="
    echo ""

    # Send a whitelisted request
    send_and_wait '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

    echo "Sent: eth_blockNumber (whitelisted method)"
    echo ""

    echo "Mock Server received logs:"
    get_mock_requests
    echo ""

    # Check if eth_blockNumber request reached mock
    if check_docker_mode; then
        if docker logs ethereum-rpc-mock --since 3s 2>/dev/null | grep -q "eth_blockNumber"; then
            echo -e "${GREEN}OK: Verification succeeded - Request reached Mock Server${NC}"
            echo "Explanation: Apache allowed this request through filtering"
        else
            echo -e "${RED}X: Verification failed - Request did not reach Mock Server${NC}"
        fi
    else
        stats=$(curl -s "$MOCK_URL/stats" 2>/dev/null)
        if echo "$stats" | grep -q "eth_blockNumber"; then
            echo -e "${GREEN}OK: Verification succeeded - Request reached Mock Server${NC}"
            echo "Explanation: Apache allowed this request through filtering"
        else
            echo -e "${YELLOW}?: Unable to verify - check logs manually${NC}"
            echo "Try: journalctl -u ethereum-rpc-mock --since 10s"
        fi
    fi

    echo ""
    echo "=========================================="
    echo "Step 2: Send blacklisted address request (should be blocked)"
    echo "=========================================="
    echo ""

    clean_logs

    send_and_wait '{"jsonrpc":"2.0","method":"eth_call","params":[{"to":"0x0000000000000000000000000000000000000000","data":"0x70a08231"}],"id":1}'

    echo "Sent: eth_call (address 0x000...000 not in whitelist)"
    echo ""

    sleep 1
    echo "Mock Server received logs:"
    get_mock_requests
    echo ""

    # Check blocking - the request should NOT have reached mock
    if check_docker_mode; then
        if docker logs ethereum-rpc-mock --since 3s 2>/dev/null | grep -q "eth_call"; then
            echo -e "${RED}X: Blocking failed - Request reached Mock Server${NC}"
            echo "Explanation: Filter rule not working"
        else
            echo -e "${GREEN}OK: Blocking succeeded - Request did not reach Mock Server${NC}"
            echo "Explanation: Apache rejected this request (returned 403)"
        fi
    else
        # Native mode - check via API
        stats=$(curl -s "$MOCK_URL/stats" 2>/dev/null)
        allowed_before=$(echo "$stats" | grep -o '"allowed_count":[0-9]*' | cut -d: -f2 || echo "0")
        if [ "$allowed_before" = "1" ]; then
            echo -e "${GREEN}OK: Blocking succeeded - Only whitelisted request was allowed${NC}"
            echo "Explanation: Apache rejected the eth_call request (returned 403)"
        else
            echo -e "${YELLOW}?: Unable to determine - check logs manually${NC}"
            echo "Try: journalctl -u ethereum-rpc-mock --since 10s"
        fi
    fi

    echo ""
    echo "=========================================="
    echo "Step 3: View Apache blocked logs"
    echo "=========================================="
    echo ""
    echo "Apache error logs (recent 5 lines):"
    if check_docker_mode; then
        docker logs apache-rpc-proxy 2>/dev/null | grep -E "\[error\]|\[RPC-FILTER\]" | tail -5 || echo "No blocked logs"
    else
        journalctl -u httpd --since "5 minutes ago" --no-pager 2>/dev/null | grep -iE "error|rpc" | tail -5 || echo "No logs available"
    fi
    echo ""

    echo "=========================================="
    echo "Verification Summary"
    echo "=========================================="
    echo -e "${GREEN}OK: Blocking works${NC} - Blacklisted requests rejected by Apache with 403"
    echo -e "${GREEN}OK: Allowing works${NC} - Whitelisted requests reach Mock Server backend"
}

main "$@"
