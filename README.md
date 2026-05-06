# Ethereum RPC Filter Proxy

An Ethereum JSON-RPC filtering proxy built with **Apache + Lua** that implements whitelist-based access control.

## Architecture

```
Client -> Apache Proxy (port 8888) -> Lua Filter -> Whitelist Check
                                              |
                              +---------------+---------------+
                              |                               |
                        Allowed (200)                  Blocked (403)
                              |                               |
                    Mock RPC Server                  Record to /blocked
                       (port 8545)
```

## Deployment Methods

### Method A: Docker (Recommended for quick setup)

**Prerequisites:**
- Docker 20.10+
- Docker Compose 1.29+
- Git

```bash
git clone https://github.com/JukLee0ira/Apache.git
cd Apache
./start.sh
```

### Method B: Native Installation (RHEL/CentOS/Rocky Linux)

**Prerequisites:**
- RHEL/CentOS/Rocky Linux 8+
- Root access (sudo)
- Internet connection

```bash
git clone https://github.com/JukLee0ira/Apache.git
cd Apache
sudo ./install-rhel.sh
```

The installer will:
1. Detect your operating system
2. Install Apache, Lua, and required dependencies
3. Compile and install Lua extensions (lua-cjson, lua-socket)
4. Configure Apache with RPC proxy settings
5. Set up systemd services
6. Configure firewall (if firewalld is running)
7. Configure SELinux (if Enforcing)
8. Start all services
9. Run verification tests

**Alternative: Use convenience scripts after installation:**
```bash
./start.sh          # Start services
./stop.sh           # Stop services
./restart.sh        # Restart services
./status.sh         # Check status
```

## Quick Start (After Installation)

### Test the Filter

```bash
# Health check
curl http://localhost:8888/health

# Whitelist method (allowed)
curl -X POST http://localhost:8888/rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# Non-whitelist method (blocked - returns 403)
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

## Project Structure

```
Apache/
├── apache/                  # Apache Docker build
│   ├── Dockerfile           # Docker build file
│   ├── conf/                # Apache configuration
│   │   ├── httpd-rhel.conf  # RHEL native Apache config
│   │   └── sites-enabled/   # Debian-style sites config
│   └── scripts/             # Apache Lua scripts (Docker)
├── config/
│   └── whitelist.json       # Whitelist configuration
├── scripts/
│   ├── rpc_proxy.lua        # Main Lua filter script
│   └── install-mock-backend.sh  # Lua extensions installer
├── systemd/
│   ├── ethereum-rpc-mock.service   # Mock backend service
│   └── ethereum-rpc-proxy.service  # Apache proxy service
├── test/                    # Test scripts
├── mock_rpc.lua            # Mock RPC server (Lua)
├── mock-backend/           # Mock backend Docker build
├── docker-compose.yml      # Docker orchestration
├── install-rhel.sh        # RHEL native installer
├── deploy.sh               # Auto-deploy script
├── start.sh                # Start script (auto-detects Docker/systemd)
├── stop.sh                 # Stop script (auto-detects Docker/systemd)
├── restart.sh              # Restart script
├── status.sh               # Status check script
├── README.md               # This file
└── DEPLOY.md               # Detailed deployment guide
```

## Service Management

### Docker Mode
```bash
./start.sh                  # Start all services
./stop.sh                   # Stop all services
./restart.sh                # Restart all services
./status.sh                 # Check service status

# Direct Docker commands
docker-compose up -d        # Start
docker-compose down         # Stop
docker-compose restart      # Restart
```

### Native (systemd) Mode
```bash
# Using convenience scripts
./start.sh                  # Start services
./stop.sh                   # Stop services
./restart.sh                # Restart services
./status.sh                 # Check status

# Direct systemctl commands
sudo systemctl start ethereum-rpc-mock
sudo systemctl start httpd
sudo systemctl stop ethereum-rpc-mock httpd
sudo systemctl restart ethereum-rpc-mock httpd
sudo systemctl status ethereum-rpc-mock httpd

# View logs
journalctl -u ethereum-rpc-mock -f           # Mock backend logs
tail -f /var/log/httpd/rpc-proxy-access.log  # Apache access logs
tail -f /var/log/httpd/rpc-proxy-error.log   # Apache error logs
```

## Configuration

### Whitelist Methods

Edit `config/whitelist.json`:

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
    "eth_sendRawTransaction"
  ],
  "allowed_events": [
    "Transfer(address,address,uint256)",
    "Approval(address,address,uint256)",
    "Deposit(address,uint256)",
    "Withdraw(address,uint256)"
  ]
}
```

**Note:** After modifying whitelist, restart the service:

**Docker mode:**
```bash
./restart.sh
```

**Native mode:**
```bash
sudo ./restart.sh
# Or:
sudo systemctl restart ethereum-rpc-mock httpd
```

## Testing

```bash
# Run full test suite (25 tests)
./test/comprehensive_test.sh

# Quick verification
./test/verify.sh

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

**Docker mode:**
```bash
lsof -i :8888    # Check port 8888
lsof -i :8545    # Check port 8545
```

**Native mode:**
```bash
ss -tlnp | grep 8888
ss -tlnp | grep 8545
```

### View logs

**Docker mode:**
```bash
docker logs -f apache-rpc-proxy
docker logs -f ethereum-rpc-mock
```

**Native mode:**
```bash
journalctl -u ethereum-rpc-mock -f
tail -f /var/log/httpd/rpc-proxy-access.log
```

### Configuration not taking effect

```bash
# Docker mode
./restart.sh

# Native mode
sudo ./restart.sh
```

### SELinux issues (RHEL/CentOS)

If you encounter permission denied errors:

```bash
# Allow Apache to make network connections
sudo setsebool -P httpd_can_network_connect 1

# Allow Apache to execute CGI/Lua scripts
sudo setsebool -P httpd_enable_cgi 1

# Verify
sudo getenforce
```

### Firewall issues (RHEL/CentOS)

```bash
# Check firewall status
sudo systemctl status firewalld

# Open ports if needed
sudo firewall-cmd --permanent --add-port=8888/tcp
sudo firewall-cmd --permanent --add-port=8545/tcp
sudo firewall-cmd --reload

# Or disable firewall temporarily (not recommended for production)
sudo systemctl stop firewalld
```

## License

MIT
