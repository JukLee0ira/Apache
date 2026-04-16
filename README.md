# Ethereum RPC Filter POC

## Project Goal

Build an Ethereum JSON-RPC filtering proxy based on **Apache + Lua** to implement a whitelist mechanism:
- Whitelist requests (e.g., `eth_blockNumber`) return 200 and reach the backend
- Non-whitelist requests (e.g., invalid `eth_call` addresses) return 403 and record interceptions

## Table of Contents

- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [File Description](#file-description)
- [Whitelist Configuration](#whitelist-configuration)
- [Forbidden Operations Guide](#forbidden-operations-guide)
- [View Logs](#view-logs)
- [Test Verification](#test-verification)
- [FAQ](#faq)
- [Pitfalls Encountered](#pitfalls-encountered)
- [Notes](#notes)

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Client                                         │
│                    DApp / Wallet / curl / Browser                         │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │ POST /rpc
                                 │ JSON-RPC Request
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                     Apache Proxy (Port 8888:80)                          │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │                    LuaMapHandler /rpc                            │    │
│  │                         ↓                                        │    │
│  │              ┌──────────────────────┐                           │    │
│  │              │   rpc_proxy.lua      │ ← Whitelist filter script │    │
│  │              │   (Lua Script)         │                           │    │
│  │              └──────────────────────┘                           │    │
│  │                         ↓                                        │    │
│  │              ┌──────────────────────┐                           │    │
│  │              │  whitelist.json      │ ← Config file (read-only) │    │
│  │              └──────────────────────┘                           │    │
│  └─────────────────────────────────────────────────────────────────┘    │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
              ┌──────────────────┴��──────────────────┐
              │                                     │
              ▼                                     ▼
     ┌────────────────┐                   ┌────────────────┐
     │    Allowed (200)│                   │   Blocked (403)│
     │                │                   │                │
     │  curl POST     │                   │  Do not request│
     │  to backend    │                   │  Record in     │
     │                │                   │  blocked       │
     └────────┬───────┘                   └────────┬───────┘
              │                                     │
              ▼                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                     Mock RPC Server (Port 8545)                          │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │  POST /          - Receive allowed RPC requests                  │    │
│  │  POST /blocked   - Record blocked requests                       │    │
│  │  GET /health     - Health check                                  │    │
│  │  GET /stats      - Statistics                                    │    │
│  └─────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
```

**Filtering Process:**

1. Client sends JSON-RPC request to `http://localhost:8888/rpc`
2. Apache's `LuaMapHandler` routes the request to `rpc_proxy.lua`
3. Lua script loads whitelist configuration from `whitelist.json`
4. Verify if `method` is in `allowed_methods`
5. If method is `eth_call` or `eth_getLogs`, additionally verify if address is in `allowed_addresses`
6. Verification passed → Forward to Mock RPC Server (port 8545) → Return 200
7. Verification failed → Return 403 and asynchronously record to Mock's `/blocked` endpoint

---

## Quick Start

### 1. Start Services

```bash
cd /root/apache
docker-compose up -d

# Wait for services to be ready
sleep 3

# Check container status
docker-compose ps
# Expected: apache-rpc-proxy and ethereum-rpc-mock are both Up
```

### 2. Health Check

```bash
curl -i http://localhost:8888/health
```

**Expected Output:**
```
HTTP/1.1 200 OK
OK
```

### 3. Test Whitelist Request (Should Pass)

```bash
# Test eth_blockNumber method
curl -sS -X POST http://localhost:8888/rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

**Expected Output:**
```json
{"jsonrpc": "2.0", "id": 1, "result": "0x10d4f"}
```

### 4. Test Non-Whitelist Method (Should Be Blocked)

```bash
# Test personal_sign method (not in whitelist)
curl -i -X POST http://localhost:8888/rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"personal_sign","params":["msg","0x1234"],"id":1}'
```

**Expected Output:**
```
HTTP/1.1 403 Forbidden
{"jsonrpc":"2.0","error":{"code":-32000,"message":"Method not allowed: personal_sign"}}
```

### 5. Test Non-Whitelist Address (Should Be Blocked)

```bash
# Test eth_call with invalid address
curl -i -X POST http://localhost:8888/rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_call","params":[{"to":"0x0000000000000000000000000000000000000000","data":"0x70a08231"}],"id":1}'
```

**Expected Output:**
```
HTTP/1.1 403 Forbidden
{"jsonrpc":"2.0","error":{"code":-32000,"message":"Contract address not allowed: 0x0000000000000000000000000000000000000000"}}
```

### 6. Test Whitelist Address (Should Pass)

```bash
# Call eth_call with whitelisted address
curl -sS -X POST http://localhost:8888/rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_call","params":[{"to":"0x1234567890123456789012345678901234567890","data":"0x70a08231"}],"id":1}'
```

**Expected Output:**
```json
{"jsonrpc": "2.0", "id": 1, "result": "0x"}
```

### 7. Test sign_rawTransaction (Should Pass)

```bash
# Call sign_rawTransaction with whitelisted from/to addresses
curl -sS -X POST http://localhost:8888/rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"sign_rawTransaction","params":[{"from":"0x1234567890123456789012345678901234567890","to":"0xabcdefabcdefabcdefabcdefabcdefabcdefabcd","data":"0x70a08231"}],"id":1}'
```

**Expected Output:**
```json
{"jsonrpc": "2.0", "id": 1, "result": "mock-signed-tx-hash"}
```

### 8. Test sign_rawTransaction with Non-Whitelist Address (Should Block)

```bash
# Call sign_rawTransaction with non-whitelisted from address
curl -i -X POST http://localhost:8888/rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"sign_rawTransaction","params":[{"from":"0x0000000000000000000000000000000000000000","to":"0x1234567890123456789012345678901234567890","data":"0x"}],"id":1}'
```

**Expected Output:**
```
HTTP/1.1 403 Forbidden
{"jsonrpc":"2.0","error":{"code":-32000,"message":"From address not allowed: 0x0000000000000000000000000000000000000000"}}
```

---

## File Description

### Core Files

| File Path | Description |
|-----------|-------------|
| `docker-compose.yml` | Container orchestration file defining two services: apache-proxy and rpc-backend |
| `mock_rpc.py` | Python Mock RPC server simulating an Ethereum node, returning fake data and recording all requests |
| `apache/Dockerfile` | Apache image build file installing lua, curl, cjson and other dependencies |

### Configuration Files

| File Path | Description |
|-----------|-------------|
| `config/whitelist.json` | **Whitelist configuration file** defining allowed addresses and methods |
| `apache/conf/sites-enabled/rpc-proxy.conf` | Apache site configuration defining proxy rules, ports, Lua routing |

### Lua Scripts

| File Path | Description |
|-----------|-------------|
| `scripts/rpc_proxy.lua` | **Main filtering script** handling `/rpc` requests, performing whitelist verification and forwarding or blocking |
| `scripts/validate_rpc.lua` | Legacy verification script (backup), not used in current configuration |

### Test Files

| File Path | Description |
|-----------|-------------|
| `test/test_verification.sh` | Verification script comparing allowed and blocked results |
| `test/test_rpc.sh` | Complete test suite |
| `test/test_mock_direct.sh` | Direct test of Mock Server (bypassing proxy) |

### Documentation

| File Path | Description |
|-----------|-------------|
| `README.md` | Project main documentation (this document) |
| `guide.md` | Quick verification guide |
| `architecture.html` | Interactive architecture diagram (open in browser) |

---

## Whitelist Configuration

The whitelist configuration file is located at `config/whitelist.json`.

### Configuration Structure

```json
{
  "allowed_addresses": [
    "0x1234567890123456789012345678901234567890",
    "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd"
  ],
  "allowed_methods": [
    "eth_call",
    "eth_getLogs",
    "eth_blockNumber",
    "net_version",
    "eth_chainId",
    "eth_getBalance",
    "sign_rawTransaction"
  ],
  "allowed_events": [
    "Transfer(address,address,uint256)",
    "Approval(address,address,uint256)",
    "Deposit(address,uint256)",
    "Withdraw(address,uint256)"
  ]
}
```

### Field Description

| Field | Type | Description |
|-------|------|-------------|
| `allowed_addresses` | String array | Contract addresses allowed to call `eth_call` and `eth_getLogs` |
| `allowed_methods` | String array | Allowed RPC methods (all uppercase, e.g., `eth_call`) |
| `allowed_events` | String array | Allowed event signatures (optional, for documentation reference) |

### Filtering Rules

| Method | Verification Logic |
|--------|-------------------|
| `eth_call` | Must use `to` address from `allowed_addresses` |
| `eth_getLogs` | Must use `address` parameter from `allowed_addresses` |
| `sign_rawTransaction` | Must use `from` and `to` addresses from `allowed_addresses`, validates `data` field |
| Other methods | Check directly in `allowed_methods`, pass if found |

### Restart After Modification

```bash
# Must restart Apache after modifying configuration
docker-compose restart apache-proxy

# Verify restart succeeded
docker-compose ps
# Should show apache-rpc-proxy as Up
```

---

## Forbidden Operations Guide

### 1. Block a Specific IP Address

Implement IP access control via Apache configuration.

#### Option A: Deny Specific IP

Edit `apache/conf/sites-enabled/rpc-proxy.conf`, add inside `<VirtualHost>`:

```apache
<Location /rpc>
    # Deny single IP
    Require not ip 192.168.1.100

    # Deny entire subnet
    Require not ip 10.0.0.0/8
</Location>
```

#### Option B: Allow Only Specific IP (Whitelist Mode)

```apache
<Location /rpc>
    # Only allow specific subnet
    Require ip 192.168.1.0/24
</Location>
```

Rebuild containers after modification:

```bash
docker-compose down
docker-compose build apache-proxy
docker-compose up -d
```

---

### 2. Block a Specific Contract Address

Remove the address from `allowed_addresses`.

```bash
vim config/whitelist.json
```

**Example: Block address `0x1111111111111111111111111111111111111111`**

```json
{
  "allowed_addresses": [
    "0x1234567890123456789012345678901234567890",
    "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd"
    // Delete or comment out the address to block
  ],
  "allowed_methods": [...]
}
```

Then restart:
```bash
docker-compose restart apache-proxy
```

**Test:**
```bash
curl -i -X POST http://localhost:8888/rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_call","params":[{"to":"0x1111111111111111111111111111111111111111","data":"0x70a08231"}],"id":1}'
# Expected: HTTP 403, error message "Contract address not allowed"
```

---

### 3. Block a Specific RPC Method

Remove the method from `allowed_methods`.

```bash
vim config/whitelist.json
```

**Example: Block `eth_sendTransaction` method**

```json
{
  "allowed_addresses": [...],
  "allowed_methods": [
    "eth_call",
    "eth_getLogs",
    "eth_blockNumber",
    "net_version",
    "eth_chainId",
    "eth_getBalance"
    // Delete the method to block
  ]
}
```

Restart:
```bash
docker-compose restart apache-proxy
```

**Test:**
```bash
curl -i -X POST http://localhost:8888/rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_sendTransaction","params":[{"from":"0x1234","to":"0x5678","value":"0x1"}],"id":1}'
# Expected: HTTP 403, error message "Method not allowed: eth_sendTransaction"
```

---

### 4. Block Specific Parameter Combinations (Advanced)

To block specific parameter combinations (e.g., a method + a function signature), modify `scripts/rpc_proxy.lua`.

**Example: Block `eth_call` calling `transfer` function**

Edit `scripts/rpc_proxy.lua`, add custom rule in `validate()` function:

```lua
if method == "eth_call" then
    local obj = params[1]
    if obj and obj.to then
        if not check_address(obj.to) then
            return false, "Contract address not allowed: " .. obj.to
        end

        -- Custom: block transfer function calls (function signature 0xa9059cbb)
        if obj.data and obj.data:sub(1, 10) == "0xa9059cbb" then
            return false, "transfer function calls are blocked"
        end
    end
end
```

Restart:
```bash
docker-compose restart apache-proxy
```

---

## View Logs

### Real-time Viewing

```bash
# Apache proxy logs (all HTTP requests)
docker logs -f apache-rpc-proxy

# Mock RPC logs (RPC request processing details)
docker logs -f ethereum-rpc-mock
```

### View Blocked Records

#### Method 1: Docker Log Filtering

```bash
# View recent blocked records
docker logs ethereum-rpc-mock --tail 100 | grep -A 5 "blocked"
```

#### Method 2: Mock API Query

```bash
# View all blocked records (JSON format)
curl -s http://localhost:8545/blocked | python3 -m json.tool

# View statistics (allowed count, blocked count)
curl -s http://localhost:8545/stats | python3 -m json.tool
```

**Statistics output example:**
```json
{
  "allowed_count": 5,
  "blocked_count": 3,
  "recent_blocked": [...],
  "recent_allowed": [...]
}
```

#### Method 3: Apache Error Logs

```bash
# View all errors and warnings
docker logs apache-rpc-proxy 2>&1 | grep -i "error\|warn\|block"
```

### Log Format Description

#### Apache Access Log

```
172.19.0.1 - - [15/Apr/2026:12:26:31 +0000] "POST /rpc HTTP/1.1" 200 314 "-" "curl/7.81.0"
                ↑                    ↑           ↑    ↑
                IP                   Method    Status Code  Response Size
```

- `200` = allowed, request reached backend
- `403` = blocked, request rejected
- `500` = Lua script execution error

#### Mock Server Processing Log

```
============================================================
BACKEND PROCESSING          ← Source: direct (allowed)
    Method: eth_blockNumber
    Params: []
============================================================

============================================================
BLOCKED RECORD              ← Source: blocked (blocked)
    Method: personal_sign
    Params: ["msg", "0x1234"]
============================================================
```

---

## Test Verification

### Recommended: Fully Automated Comprehensive Test

```bash
# Run fully automated comprehensive test (25 test items)
./test/comprehensive_test.sh

# Test items include:
#   ✓ Service status check
#   ✓ Health check
#   ✓ Whitelist method tests (4 methods)
#   ✓ Whitelist address tests (2 addresses)
#   ✓ Non-whitelist method blocking (4 methods)
#   ✓ Non-whitelist address blocking (2 addresses)
#   ✓ Response content validation
#   ✓ Error handling tests (invalid JSON, GET requests, empty body)
#   ✓ Log consistency validation
#   ✓ API endpoint checks (/blocked, /stats, /health)

# Expected output: All passed (25/25)
```

### Other Test Scripts

| Script | Description |
|--------|-------------|
| `test/comprehensive_test.sh` | Recommended: Fully automated comprehensive test (25 items) |
| `test/test_verification.sh` | Verification script comparing allowed and blocked results |
| `test/test_rpc.sh` | Complete test suite (10 items) |
| `test/test_mock_direct.sh` | Direct test of Mock Server (bypassing proxy) |
| `test/check_logs.sh` | View interception and request logs |

### Test Case Checklist

| # | Test Scenario | Expected Result |
|---|---------------|----------------|
| 1 | Health check `GET /health` | `200 OK` |
| 2 | Whitelist method `eth_blockNumber` | `200` + block number |
| 3 | Whitelist method `net_version` | `200` + network version |
| 4 | Whitelist method `eth_chainId` | `200` + chain ID |
| 5 | Whitelist method `eth_getBalance` | `200` + balance |
| 6 | Whitelist address `eth_call` | `200` + `0x` |
| 7 | Whitelist address `eth_getLogs` | `200` + logs array |
| 8 | Non-whitelist method `personal_sign` | `403` + "Method not allowed" |
| 9 | Non-whitelist method `eth_sendTransaction` | `403` |
| 10 | Non-whitelist method `eth_sign` | `403` |
| 11 | Non-whitelist method `eth_approve` | `403` |
| 12 | Non-whitelist address `eth_call` (0x000...) | `403` + "Address not allowed" |
| 13 | Non-whitelist address `eth_getLogs` | `403` |
| 14 | Invalid JSON format | `400` |
| 15 | GET request | `405` |
| 16 | Empty request body | `400` |
| 17 | Log consistency check | Apache logs match Mock records |
| 18 | `/blocked` API | Returns JSON array |
| 19 | `/stats` API | Contains `allowed_count` and `blocked_count` |
| 20 | `/health` API | Returns `OK` |
| 21-25 | Response content validation | Whitelist responses contain `result`, blocked responses contain error message |

### Manual Test Command Summary

```bash
# 1. Health check
curl http://localhost:8888/health

# 2. Whitelist method (allowed)
curl -sS -X POST http://localhost:8888/rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# 3. Whitelist address eth_call (allowed)
curl -sS -X POST http://localhost:8888/rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_call","params":[{"to":"0x1234567890123456789012345678901234567890","data":"0x70a08231"}],"id":1}'

# 4. Non-whitelist method (blocked)
curl -i -X POST http://localhost:8888/rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"personal_sign","params":["msg","0x1234"],"id":1}'

# 5. Non-whitelist address (blocked)
curl -i -X POST http://localhost:8888/rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_call","params":[{"to":"0x0000000000000000000000000000000000000000","data":"0x70a08231"}],"id":1}'

# 6. Invalid JSON
curl -i -X POST http://localhost:8888/rpc \
  -H "Content-Type: application/json" \
  -d 'invalid json'
```

---

## FAQ

### Q: Modifying `whitelist.json` doesn't take effect?

**A:** Must restart Apache proxy:
```bash
docker-compose restart apache-proxy
```

---

### Q: Request returns 500 error?

**A:** Check Lua script for syntax errors:
```bash
docker logs apache-rpc-proxy --tail 50
```
Look for `[error]` or Lua exception stack traces.

---

### Q: Wrong port? Getting errors on 8080

**A:** Current configured ports are **8888**, not 8080:
- Proxy entry: `http://localhost:8888`
- Mock backend: `http://localhost:8545`

---

### Q: How to completely clear statistics?

**A:** Restart Mock Server (statistics are kept in memory):
```bash
docker-compose restart ethereum-rpc-mock
```

---

### Q: How to view specific block reasons?

**A:** Check Mock Server's `/blocked` endpoint:
```bash
curl -s http://localhost:8545/blocked | python3 -m json.tool
```
Output includes `error` field which is the block reason.

---

### Q: What's the difference between `scripts/` and `apache/scripts/` directories?

**A:**
- `scripts/` is the source directory, Volume mounted into container
- `apache/scripts/` is a copy inside Docker build context (old version)
- **Runtime in container uses `scripts/` directory content** (mounted via volume)
- Only need to modify `scripts/` when updating scripts, then restart container

---

## Pitfalls Encountered

### 1. Port Confusion

- **Problem**: `docker-compose.yml` maps `8888:80`, using `8080` causes connection failure
- **Solution**: Always use `localhost:8888` for proxy testing, `localhost:8545` for Mock

---

### 2. Lua Script Path Mismatch

- **Problem**: `LuaMapHandler` points to script path that doesn't match actual filename, requests cannot enter filtering logic
- **Solution**: Configuration aligned to `/usr/local/apache2/scripts/rpc_proxy.lua`

---

### 3. Docker Build Context Misuse

- **Problem**: `apache-proxy` build context is `./apache`, Dockerfile cannot use `../` to copy root directory files
- **Solution**: Use Volume mount for runtime files (`scripts/`, `config/`), not copy during build

---

### 4. Documentation and Configuration Drift

- **Problem**: Ports and paths in documentation don't match actual code configuration, causing troubleshooting difficulties
- **Solution**: Keep documentation synchronized with configuration, use consistent port numbers (8888)

---

### 5. Filter Entry Path Misunderstanding

- **Problem**: `/rpc` is the path that goes through Lua filtering, `/` is direct proxy logic, testing wrong path yields "seemingly working but not filtered" results
- **Solution**: Always use `/rpc` path for filtering tests

---

## Notes

1. **Must restart proxy after each whitelist change**
   ```bash
   docker-compose restart apache-proxy
   ```

2. **Check container status before testing**
   ```bash
   docker-compose ps
   docker logs apache-rpc-proxy --tail 100
   docker logs ethereum-rpc-mock --tail 100
   ```

3. **Use consistent test endpoint addresses**
   - Proxy entry: `http://localhost:8888`
   - Mock backend: `http://localhost:8545`

4. **Confirm requests actually go through filtering chain**
   - Always use `/rpc` path
   - Check Apache logs for allow/block records
   - Combine with Mock logs to confirm if reached backend

5. **Script changes require container restart**
   - Volume mount ensures container sees changes, but need to restart Apache to load new config

---

## Current Status

**POC Fully Working**

| Test Scenario | Expected | Actual Result | Status |
|---------------|----------|---------------|--------|
| `/health` health check | 200 | 200 | PASS |
| Whitelist method `eth_blockNumber` | 200 | 200 + result | PASS |
| Whitelist address `eth_call` | 200 | 200 + `0x` | PASS |
| Non-whitelist method `personal_sign` | 403 | 403 + error message | PASS |
| Non-whitelist address `eth_call` | 403 | 403 + error message | PASS |
| Blocked record | Sent to `/blocked` | Mock received normally | PASS |
| sign_rawTransaction whitelist | 200 | 200 + signed hash | PASS |
| sign_rawTransaction non-whitelist | 403 | 403 + address error | PASS |

---

## Links

- **Architecture Diagram**: Open `architecture.html` to view interactive architecture diagram
- **Test Scripts**: Complete test cases in `test/` directory
- **Feedback**: Check FAQ chapter or check container logs