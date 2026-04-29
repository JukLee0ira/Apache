# Deployment Guide - Ethereum RPC Filter

## Requirements

### Required software

| Software | Version | Purpose |
|------|------|------|
| **Docker** | 20.10+ | Container runtime |
| **Docker Compose** | 1.29+ | Service orchestration |
| **Git** | 2.0+ | Version control |

### Optional tools

| Tool | Purpose |
|------|------|
| `curl` | API testing |
| `jq` | JSON formatting |
| `lsof` | Port conflict checks |

### Quick install verification

```bash
docker --version
# Expected: Docker version 20.10.x

docker-compose --version
# Expected: Docker Compose version 1.29.x

git --version
# Expected: git version 2.x.x
```

---

## Version details

### Versions used by this project

| Component | Version | Notes |
|------|------|------|
| **Apache** | 2.4.x | Debian Bookworm build |
| **Lua** | 5.1.x | Apache Lua module version |
| **Lua-cjson** | 2.1.x | JSON encode/decode library |
| **Lua (Mock Server)** | 5.1.x + LuaSocket | Mock RPC backend |
| **Debian** | bookworm-slim | Base image |

### Compatibility notes

- **Lua 5.1** is the officially supported version for Apache `mod_lua`.
- Scripts use Lua 5.1 syntax and do not rely on Lua 5.2+ features.
- Apache module paths may differ by distro and version; this project uses Debian-standard paths.

---

## 1) Get the code from GitHub

### Method 1: Git clone (recommended)

```bash
git clone https://github.com/JukLee0ira/Apache.git
cd Apache
```

### Method 2: Download ZIP

1. Open [https://github.com/JukLee0ira/Apache](https://github.com/JukLee0ira/Apache)
2. Click the green **Code** button
3. Select **Download ZIP**
4. Extract it locally

---

## 2) Quick start (3 steps)

### Step 1: Start services

```bash
cd /path/to/Apache

# Option A: use startup script (recommended)
./start.sh

# Option B: run Docker Compose directly
docker-compose up -d
```

### Step 2: Verify service status

```bash
# Use status script
./status.sh

# Or check manually
curl http://localhost:8888/health
# Expected output: OK
```

### Step 3: Run tests

```bash
# Full test suite (25 tests)
./test/comprehensive_test.sh

# Or single manual test
curl -X POST http://localhost:8888/rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

Expected success output:

```json
{"jsonrpc": "2.0", "id": 1, "result": "0x10d4f"}
```

---

## 3) Configuration files

### Core files

| File | Description | Restart required |
|------|------|----------------|
| `config/whitelist.json` | Whitelist entries (addresses and methods) | **Yes** - restart Apache |
| `apache/conf/sites-enabled/rpc-proxy.conf` | Apache virtual host config | **Yes** - rebuild image |
| `scripts/rpc_proxy.lua` | Request filtering logic | **Yes** - restart Apache |

### Update whitelist config

```bash
vim config/whitelist.json
./restart.sh
# or: docker-compose restart apache-proxy
```

---

## 4) Service management commands

### Start services
```bash
./start.sh
docker-compose up -d
```

### Stop services
```bash
./stop.sh
docker-compose down
```

### Restart services
```bash
./restart.sh
docker-compose restart apache-proxy
docker-compose restart ethereum-rpc-mock
```

### Check status
```bash
./status.sh
docker-compose ps
curl http://localhost:8888/health
```

### View logs
```bash
docker logs -f apache-rpc-proxy
docker logs -f ethereum-rpc-mock
docker logs --tail 100 apache-rpc-proxy
```

---

## 5) Test verification

### Quick validation (about 5 minutes)

Run the full suite:

```bash
./test/comprehensive_test.sh
```

Coverage includes:
- Service health checks
- Whitelisted method checks
- Whitelisted address checks
- Non-whitelisted method blocking
- Non-whitelisted address blocking
- Response format validation
- Error handling checks
- Log consistency checks

Expected result: `All passed (25/25)` or each item marked `[PASS]`.

### Manual test commands

```bash
# 1) Health check
curl http://localhost:8888/health

# 2) Whitelisted method (should pass)
curl -X POST http://localhost:8888/rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# 3) Non-whitelisted method (should be blocked)
curl -i -X POST http://localhost:8888/rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"personal_sign","params":["msg","0x1234"],"id":1}'
# Expected: HTTP 403 Forbidden

# 4) Check blocked records
curl http://localhost:8545/blocked | jq .
```

---

## 6) Troubleshooting

### Port conflict

Problem: Port `8888` or `8545` is already in use.

```bash
lsof -i :8888
lsof -i :8545
```

Fix options:
- Stop the process using the port: `kill <PID>`
- Adjust port mappings in `docker-compose.yml`

### Docker build failure

Problem: `docker-compose up` fails during build/start.

```bash
docker-compose build apache-proxy
docker logs apache-rpc-proxy
```

Common causes:
- Network or registry configuration issue
- Package source issue during image build

### HTTP 500 response

```bash
# 1) Apache error logs
docker logs apache-rpc-proxy --tail 50 | grep "\[error\]"

# 2) Lua script syntax check
docker exec -it apache-rpc-proxy lua -e "dofile('/usr/local/apache2/scripts/rpc_proxy.lua')"

# 3) Verify config file inside container
docker exec -it apache-rpc-proxy cat /etc/apache2/config/whitelist.json
```

### Config changes not applied

Problem: `whitelist.json` was changed but rules did not update.

Fix:

```bash
docker-compose restart apache-proxy
# or
./restart.sh
```

### Container unreachable

Problem: `curl: (7) Failed to connect`.

```bash
# 1) Check container status
docker-compose ps

# 2) Check logs
docker logs apache-rpc-proxy

# 3) Test from inside container
docker exec -it apache-rpc-proxy curl http://localhost:80/health
```

---

## 7) Production recommendations

### Whitelist management
- Review `config/whitelist.json` regularly.
- Follow least-privilege policy.
- Prefer explicit addresses over wildcards.

### Logging

```bash
curl http://localhost:8545/stats | jq .
curl http://localhost:8545/blocked | jq .
```

### Monitoring

Track these metrics:
- Container health and uptime
- HTTP status code distribution (`200` vs `403`)
- Growth of `blocked_count` on the mock service

### Security hardening
- Enable HTTPS in `rpc-proxy.conf`
- Restrict source IPs with Apache `Require ip`
- Enable basic auth if needed

---

## 8) Updates

### Upgrade steps

```bash
# 1) Pull latest code
git pull origin main

# 2) Rebuild image
docker-compose build apache-proxy

# 3) Restart services
docker-compose up -d
```

### Version notes

This project pins versions for environment consistency. If you need upgrades, update:

- `apache/Dockerfile` (base image)
- `docker-compose.yml` (service images/config)
- `mock-backend/Dockerfile` (mock backend dependencies)

---

## 9) FAQ

### Q1: Why Lua 5.1 instead of the latest Lua?

A: Apache `mod_lua` currently targets the Lua 5.1 API.

### Q2: How do I add a new whitelisted address?

A: Edit `config/whitelist.json`, add to `allowed_addresses`, then restart Apache.

### Q3: What is the difference between the mock service and a real node?

A: The mock service returns simulated data for testing and demos. For production, replace `http://rpc-backend:8545` with a real Ethereum node endpoint.

### Q4: How do I forward traffic to a real node?

A: Update the backend URL in `scripts/rpc_proxy.lua`:

```lua
local cmd = string.format(
    "curl -s -X POST -H 'Content-Type: application/json' --data '%s' http://YOUR_REAL_NODE:8545/",
    escaped_body
)
```

### Q5: Where are logs stored?

A: By default, Docker logs are managed by the Docker logging driver. Configure volumes or logging drivers in `docker-compose.yml` if persistence is required.

---

## 10) Getting help

- Full project docs: `README.md`
- Run test suite: `./test/comprehensive_test.sh`
- View proxy logs: `docker logs -f apache-rpc-proxy`
- GitHub issues: [https://github.com/JukLee0ira/Apache/issues](https://github.com/JukLee0ira/Apache/issues)

---

**Deployment complete!** You can now use Ethereum RPC Filter.
