# Ethereum RPC Filter Proxy

An Ethereum JSON-RPC filtering proxy built with **Apache + Lua** that implements whitelist-based access control.

## Architecture

```
Client → Apache Proxy (port 8888) → Lua Filter → Whitelist Check
                                              ↓
                              ┌───────────────┴───────────────┐
                              ↓                               ↓
                        Allowed (200)                  Blocked (403)
                              ↓                               ↓
                    Mock RPC Server                  Record to /blocked
                       (port 8545)
```

## Quick Start

### Prerequisites

- Docker 20.10+
- Docker Compose 1.29+
- Git

### Start Services

```bash
git clone https://github.com/JukLee0ira/Apache.git
cd Apache
./start.sh
```

### Test

```bash
# Health check
curl http://localhost:8888/health

# Whitelist method (allowed)
curl -X POST http://localhost:8888/rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# Non-whitelist method (blocked)
curl -i -X POST http://localhost:8888/rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"personal_sign","params":["msg","0x1234"],"id":1}'
```

## Version Information

| Component | Version |
|-----------|---------|
| Apache | 2.4.x |
| Lua | 5.1.x |
| Mock Backend | Lua 5.1 + LuaSocket |
| Debian | bookworm-slim |

## Project Structure

```
Apache/
├── apache/                  # Apache Docker build
│   ├── Dockerfile
│   └── conf/               # Apache configuration
├── config/
│   └── whitelist.json      # Whitelist configuration
├── scripts/
│   └── rpc_proxy.lua        # Main Lua filter script
├── test/                    # Test scripts
├── mock_rpc.lua            # Mock RPC server (Lua)
├── mock-backend/           # Mock backend image build files
├── docker-compose.yml      # Service orchestration
├── start.sh                # Quick start script
├── stop.sh                 # Stop script
├── restart.sh              # Restart script
├── status.sh               # Status check script
├── README.md               # Full documentation
└── DEPLOY.md               # Deployment guide
```

## Service Management

```bash
./start.sh                  # Start all services
./stop.sh                   # Stop all services
./restart.sh                # Restart all services
./status.sh                 # Check service status

# Docker Compose commands
docker-compose up -d        # Start
docker-compose down         # Stop
docker-compose restart       # Restart
```

## Configuration

### Whitelist Methods

Edit `config/whitelist.json`:

```json
{
  "allowed_methods": [
    "eth_call",
    "eth_getLogs",
    "eth_blockNumber",
    "net_version",
    "eth_chainId",
    "eth_getBalance",
    "sign_rawTransaction"
  ],
  "allowed_addresses": [
    "0x1234567890123456789012345678901234567890",
    "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd"
  ]
}
```

**Note:** After modifying whitelist, restart the service:
```bash
./restart.sh
```

## Testing

```bash
# Run full test suite (25 tests)
./test/comprehensive_test.sh

# View blocked requests
curl http://localhost:8545/blocked

# View statistics
curl http://localhost:8545/stats
```

## Ports

| Service | Port |
|---------|------|
| Apache Proxy | 8888 |
| Mock RPC | 8545 |

## Troubleshooting

### Port conflict

```bash
lsof -i :8888    # Check port 8888
lsof -i :8545    # Check port 8545
```

### View logs

```bash
docker logs -f apache-rpc-proxy
docker logs -f ethereum-rpc-mock
```

### Configuration not taking effect

```bash
./restart.sh
```

## License

MIT
