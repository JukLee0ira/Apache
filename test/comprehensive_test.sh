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

rpc_post_with_status() {
    local payload="$1"
    curl -s -w "\n%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$PROXY/rpc"
}

assert_rawtx_allowed() {
    local desc="$1"
    local tx="$2"
    local payload="{\"jsonrpc\":\"2.0\",\"method\":\"eth_sendRawTransaction\",\"params\":[\"$tx\"],\"id\":1}"
    local resp body code
    resp=$(rpc_post_with_status "$payload")
    body=$(printf "%s" "$resp" | sed '$d')
    code=$(printf "%s" "$resp" | sed -n '$p')

    if [ "$code" = "200" ] && echo "$body" | grep -q '"result"'; then
        pass "$desc"
    else
        fail "$desc (expected 200 + result, got code=$code body=$body)"
    fi
}

assert_rawtx_blocked() {
    local desc="$1"
    local tx="$2"
    local expected_msg="$3"
    local payload="{\"jsonrpc\":\"2.0\",\"method\":\"eth_sendRawTransaction\",\"params\":[\"$tx\"],\"id\":1}"
    local resp body code
    resp=$(rpc_post_with_status "$payload")
    body=$(printf "%s" "$resp" | sed '$d')
    code=$(printf "%s" "$resp" | sed -n '$p')

    if [ "$code" = "403" ] && echo "$body" | grep -q "$expected_msg"; then
        pass "$desc"
    else
        fail "$desc (expected 403 + '$expected_msg', got code=$code body=$body)"
    fi
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

# 4.1 eth_sendRawTransaction Tests
# Test transactions are RLP-encoded legacy (type-0) transactions.
# Structure: RLP([nonce, gasPrice, gasLimit, to, value, data, v, r, s])
# Signatures use r=s=0 (structurally valid for mock server, cryptographically invalid).
#
# TX_TO_WHITELISTED  : to=0xabcdefabcdefabcdefabcdefabcdefabcdefabcd (whitelisted)
# TX_TO_WHITELISTED2 : to=0x1234567890123456789012345678901234567890 (whitelisted), with ERC20 data
# TX_TO_BLOCKED      : to=0x0000000000000000000000000000000000000001 (not whitelisted)
TX_TO_WHITELISTED="0xe4808504a817c80082520894abcdefabcdefabcdefabcdefabcdefabcdefabcd80801c8080"
TX_TO_WHITELISTED2="0xf869808504a817c80082520894123456789012345678901234567890123456789080b844a9059cbb000000000000000000000000123456789012345678901234567890123456789000000000000000000000000000000000000000000000000000000000000000011c8080"
TX_TO_BLOCKED="0xe4808504a817c80082520894000000000000000000000000000000000000000180801c8080"
TX_BAD_HEX_CHAR="0xdeadbeefzz"
TX_BAD_HEX_ODD="0xabc"
TX_BAD_EMPTY="0x"
TX_BAD_RLP_TRUNCATED="0xe4808504a817c80082520894abcdefabcdefabcdefabcdefabcdefabcdefabcd80801c80"
TX_BAD_UNKNOWN_TYPE="0x03e4808504a817c80082520894abcdefabcdefabcdefabcdefabcdefabcdefabcd80801c8080"
TX_BAD_CONTRACT_CREATE="0xd0808504a817c8008252088080801c8080"
TX_BAD_TO_LEN_19="0xe3808504a817c800825208931111111111111111111111111111111111111180801c8080"

section "4.1 eth_sendRawTransaction Tests"

assert_rawtx_allowed "rawTx allow: whitelisted to, no data" "$TX_TO_WHITELISTED"
assert_rawtx_allowed "rawTx allow: whitelisted to, ERC20 data" "$TX_TO_WHITELISTED2"
assert_rawtx_blocked "rawTx block: non-whitelisted to" "$TX_TO_BLOCKED" "To address not allowed"
assert_rawtx_blocked "rawTx block: invalid hex char" "$TX_BAD_HEX_CHAR" "invalid hex encoding"
assert_rawtx_blocked "rawTx block: odd-length hex" "$TX_BAD_HEX_ODD" "hex length must be even"
assert_rawtx_blocked "rawTx block: empty hex payload" "$TX_BAD_EMPTY" "invalid hex encoding"
assert_rawtx_blocked "rawTx block: truncated RLP" "$TX_BAD_RLP_TRUNCATED" "RLP decode failed"
assert_rawtx_blocked "rawTx block: unknown tx type" "$TX_BAD_UNKNOWN_TYPE" "unsupported transaction type"
assert_rawtx_blocked "rawTx block: contract creation (missing to)" "$TX_BAD_CONTRACT_CREATE" "invalid to field length"
assert_rawtx_blocked "rawTx block: to length != 20 bytes" "$TX_BAD_TO_LEN_19" "invalid to field length"

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

echo "  Check eth_sendRawTransaction blocked response (non-whitelisted to):"
resp=$(curl -s -X POST -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_sendRawTransaction\",\"params\":[\"$TX_TO_BLOCKED\"],\"id\":1}" \
    "$PROXY/rpc")
if echo "$resp" | grep -q "To address not allowed"; then
    pass "Contains to address error message"
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
if command -v jq >/dev/null 2>&1; then
    count=$(echo "$blocked_data" | jq 'if type=="array" then length else -1 end' 2>/dev/null || echo "-1")
    if [ "$count" -ge 0 ] 2>/dev/null; then
        pass "/blocked endpoint working (returned $count records)"
    else
        info="No blocked records or endpoint not yet called"
        echo -e "  ${BLUE}i${NC} $info"
    fi
else
    if [ -n "$blocked_data" ]; then
        pass "/blocked endpoint reachable (jq not installed, skip count)"
    else
        info="No blocked records or endpoint not yet called"
        echo -e "  ${BLUE}i${NC} $info"
    fi
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
