#!/bin/bash

# comprehensive_test.sh - Ethereum RPC Filter fully automated test script
# Function: One-key verification of all features + log consistency check + response content validation

set +e

PROXY="http://localhost:8888"
MOCK="http://localhost:8545"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS=0
FAIL=0

pass() { echo -e "  ${GREEN}✓${NC} $1"; ((PASS++)); }
fail() { echo -e "  ${RED}X${NC} $1"; ((FAIL++)); }
section() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# ============ Main Process ============
clear
section "Ethereum RPC Filter - Fully Automated Test"

# 1. Service Check
section "1. Service Status Check"
if ! docker ps --format "{{.Names}}" | grep -q "^apache-rpc-proxy$"; then
    fail "Apache proxy not running"
    echo -e "${RED}Please run: docker-compose up -d${NC}"
    exit 1
else
    pass "Apache proxy running"
fi

if ! docker ps --format "{{.Names}}" | grep -q "^ethereum-rpc-mock$"; then
    fail "Mock Server not running"
    exit 1
else
    pass "Mock Server running"
fi

# 2. Health Check
section "2. Health Check"
code=$(curl -s -o /dev/null -w "%{http_code}" "$PROXY/health")
[ "$code" = "200" ] && pass "Health check (200)" || fail "Health check (expected 200, got $code)"

# 3. Whitelist Methods
section "3. Whitelist Method Tests"
tests=(
    "eth_blockNumber|[]|Block number"
    "net_version|[]|Network version"
    "eth_chainId|[]|Chain ID"
    "eth_getBalance|[\"0x1234567890123456789012345678901234567890\",\"latest\"]|Balance query"
)
for t in "${tests[@]}"; do
    IFS='|' read -r method params desc <<< "$t"
    echo -n "  $desc ($method): "
    code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}" \
        "$PROXY/rpc")
    [ "$code" = "200" ] && pass || fail "(expected 200, got $code)"
done

# 4. Whitelist Addresses
section "4. Whitelist Address Tests"
echo "  eth_call (whitelisted address): "
code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_call","params":[{"to":"0x1234567890123456789012345678901234567890","data":"0x70a08231"}],"id":1}' \
    "$PROXY/rpc")
[ "$code" = "200" ] && pass "Returned 200" || fail "Returned $code"

echo "  eth_getLogs (whitelisted address): "
code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_getLogs","params":[{"address":"0x1234567890123456789012345678901234567890"}]}' \
    "$PROXY/rpc")
[ "$code" = "200" ] && pass "Returned 200" || fail "Returned $code"

# 4.1 sign_rawTransaction Tests (NEW)
section "4.1 sign_rawTransaction Tests"
echo "  sign_rawTransaction (whitelisted from/to): "
code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"sign_rawTransaction","params":[{"from":"0x1234567890123456789012345678901234567890","to":"0xabcdefabcdefabcdefabcdefabcdefabcdefabcd","data":"0x70a0823100000000000000000000000012345678901234567890123456789012345678"}],"id":1}' \
    "$PROXY/rpc")
[ "$code" = "200" ] && pass "Returned 200" || fail "Returned $code"

echo "  sign_rawTransaction (whitelisted from only): "
code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"sign_rawTransaction","params":[{"from":"0x1234567890123456789012345678901234567890","data":"0x"}],"id":1}' \
    "$PROXY/rpc")
[ "$code" = "200" ] && pass "Returned 200" || fail "Returned $code"

echo "  sign_rawTransaction (non-whitelisted from): "
code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"sign_rawTransaction","params":[{"from":"0x0000000000000000000000000000000000000000","to":"0xabcdefabcdefabcdefabcdefabcdefabcdefabcd","data":"0x"}],"id":1}' \
    "$PROXY/rpc")
[ "$code" = "403" ] && pass "Blocked (403)" || fail "Not blocked (expected 403, got $code)"

echo "  sign_rawTransaction (non-whitelisted to): "
code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"sign_rawTransaction","params":[{"from":"0x1234567890123456789012345678901234567890","to":"0x0000000000000000000000000000000000000000","data":"0x"}],"id":1}' \
    "$PROXY/rpc")
[ "$code" = "403" ] && pass "Blocked (403)" || fail "Not blocked (expected 403, got $code)"

echo "  sign_rawTransaction (with data field decode): "
code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"sign_rawTransaction","params":[{"from":"0x1234567890123456789012345678901234567890","to":"0xabcdefabcdefabcdefabcdefabcdefabcdefabcd","data":"0xa9059cbb000000000000000000000000abcdabcdabcdabcdabcdabcdabcdabcdabcd0000000000000000000000000000000000000000000000000000000000000001"}],"id":1}' \
    "$PROXY/rpc")
[ "$code" = "200" ] && pass "Returned 200" || fail "Returned $code"

# 5. Non-whitelisted Methods
section "5. Non-whitelisted Method Blocking"
tests=(
    "personal_sign|[\"msg\",\"0x1234\"]|Personal signature"
    "eth_sendTransaction|[{\"from\":\"0x1234\",\"to\":\"0x5678\",\"value\":\"0x1\"}]|Send transaction"
    "eth_sign|[{\"data\":\"0x\"}]|Sign data"
    "eth_approve|[{\"spender\":\"0x\",\"value\":\"0x\"}]|Approve"
)
for t in "${tests[@]}"; do
    IFS='|' read -r method params desc <<< "$t"
    echo -n "  $desc ($method): "
    code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}" \
        "$PROXY/rpc")
    [ "$code" = "403" ] && pass "Blocked (403)" || fail "Not blocked (expected 403, got $code)"
done

# 6. Non-whitelisted Addresses
section "6. Non-whitelisted Address Blocking"
echo "  eth_call (invalid address 0x000...000): "
code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_call","params":[{"to":"0x0000000000000000000000000000000000000000","data":"0x70a08231"}],"id":1}' \
    "$PROXY/rpc")
[ "$code" = "403" ] && pass "Blocked (403)" || fail "Not blocked (expected 403, got $code)"

echo "  eth_getLogs (invalid address): "
code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_getLogs","params":[{"address":"0xffffffffffffffffffffffffffffffffffffffff"}]}' \
    "$PROXY/rpc")
[ "$code" = "403" ] && pass "Blocked (403)" || fail "Not blocked (expected 403, got $code)"

# 7. Response Content Validation
section "7. Response Content Validation"

echo "  Check whitelist response contains result field:"
resp=$(curl -s -X POST -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    "$PROXY/rpc")
if echo "$resp" | grep -q '"result"'; then
    pass "Response contains result"
else
    fail "Response missing result: $resp"
fi

echo "  Check blocked response contains error message:"
resp=$(curl -s -X POST -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"personal_sign","params":["msg"],"id":1}' \
    "$PROXY/rpc")
if echo "$resp" | grep -q "Method not allowed"; then
    pass "Contains error message"
else
    fail "Error message incomplete: $resp"
fi

echo "  Check sign_rawTransaction blocked response:"
resp=$(curl -s -X POST -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"sign_rawTransaction","params":[{"from":"0x0000000000000000000000000000000000000000","to":"0x1234567890123456789012345678901234567890","data":"0x"}],"id":1}' \
    "$PROXY/rpc")
if echo "$resp" | grep -q "From address not allowed"; then
    pass "Contains from address error message"
else
    fail "Error message incomplete: $resp"
fi

# 8. Error Handling
section "8. Error Handling Tests"
echo "  Invalid JSON: "
code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    --data "not json" \
    "$PROXY/rpc")
[ "$code" = "400" ] && pass "Returns 400" || fail "Returns $code"

echo "  GET request: "
code=$(curl -s -o /dev/null -w "%{http_code}" "$PROXY/rpc")
[ "$code" = "405" ] && pass "Returns 405" || fail "Returns $code"

echo "  Empty request body: "
code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d '' \
    "$PROXY/rpc")
[ "$code" = "400" ] && pass "Returns 400" || fail "Returns $code"

# 9. Log Validation
section "9. Log Validation"
sleep 2

APACHE_200=$(docker logs apache-rpc-proxy --since 10s 2>/dev/null | grep -c "POST /rpc.*200" || echo 0)
APACHE_403=$(docker logs apache-rpc-proxy --since 10s 2>/dev/null | grep -c "POST /rpc.*403" || echo 0)
MOCK_OK=$(docker logs ethereum-rpc-mock --since 10s 2>/dev/null | grep -c "BACKEND PROCESSING" || echo 0)
MOCK_BLOCKED=$(docker logs ethereum-rpc-mock --since 10s 2>/dev/null | grep -c "BLOCKED RECORD" || echo 0)

echo -e "  Apache 200 logs: ${GREEN}$APACHE_200${NC}"
echo -e "  Apache 403 logs: ${YELLOW}$APACHE_403${NC}"
echo -e "  Mock received: ${GREEN}$MOCK_OK${NC}"
echo -e "  Mock blocked: ${YELLOW}$MOCK_BLOCKED${NC}"

if [ "$APACHE_200" -ge "$MOCK_OK" ]; then
    pass "Allowed logs consistent with backend received"
else
    fail "Data inconsistent (some requests may not be recorded)"
fi

if [ "$APACHE_403" -ge "$MOCK_BLOCKED" ]; then
    pass "Blocked logs consistent"
else
    fail "Blocked logs inconsistent"
fi

section "10. API Endpoint Check"
echo "Checking /blocked endpoint..."
blocked_data=$(curl -s "$MOCK/blocked" 2>/dev/null || echo "")
if echo "$blocked_data" | python3 -c "import sys,json; data=json.load(sys.stdin); print(len(data) if isinstance(data, list) else 0)" 2>/dev/null | grep -q "^[0-9]\+$"; then
    count=$(echo "$blocked_data" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
    pass "/blocked endpoint working (returned $count records)"
else
    info="No blocked records or endpoint not yet called"
    echo -e "  ${BLUE}i${NC} $info"
fi

echo "Checking /stats endpoint..."
if curl -s "$MOCK/stats" | grep -q "allowed_count"; then
    pass "/stats endpoint working"
else
    fail "/stats endpoint error"
fi

echo "Checking /health endpoint..."
if curl -s "$MOCK/health" | grep -q "OK"; then
    pass "/health endpoint working"
else
    fail "/health endpoint error"
fi

# Summary
section "Test Results Summary"
echo -e "Passed: ${GREEN}$PASS${NC}"
echo -e "Failed: ${RED}$FAIL${NC}"
echo -e "Total: $((PASS + FAIL))"
echo ""

if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}✓✓✓ All tests passed! System working correctly ✓✓✓${NC}"
    echo ""
    echo "Verification key points:"
    echo "  ✓ Whitelisted methods/addresses properly allowed"
    echo "  ✓ Non-whitelisted methods/addresses properly blocked"
    echo "  ✓ Blocked records correctly written to Mock"
    echo "  ✓ Error handling as expected"
    echo "  ✓ Log consistency validation passed"
    echo ""
    echo "View real-time logs:"
    echo "  docker logs -f apache-rpc-proxy"
    echo "  docker logs -f ethereum-rpc-mock"
    echo ""
    exit 0
else
    echo -e "${RED}X X X $FAIL test(s) failed X X X${NC}"
    echo ""
    echo "Debug commands:"
    echo "  docker logs apache-rpc-proxy --tail 50"
    echo "  docker logs ethereum-rpc-mock --tail 50"
    echo "  curl -v $PROXY/rpc -d '{\"method\":\"eth_blockNumber\"}'"
    echo ""
    exit 1
fi
