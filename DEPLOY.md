# Deployment Guide - Ethereum RPC Filter

## Table of Contents

- [Method A: Docker Deployment](#method-a-docker-deployment)
- [Method B: Native RHEL/CentOS/Rocky Linux Installation](#method-b-native-rhelcentosrocky-linux-installation)
- [Configuration](#configuration)
- [Service Management](#service-management)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)

---

## Method A: Docker Deployment

### Requirements

| Software | Version | Purpose |
|----------|---------|---------|
| **Docker** | 20.10+ | Container runtime |
| **Docker Compose** | 1.29+ | Service orchestration |
| **Git** | 2.0+ | Version control |

### Quick Start

```bash
# 1. Get the code
git clone https://github.com/JukLee0ira/Apache.git
cd Apache

# 2. Start services
./start.sh

# 3. Verify
curl http://localhost:8888/health
```

---

## Method B: Native RHEL/CentOS/Rocky Linux Installation

### Requirements

| Software | Version | Purpose |
|----------|---------|---------|
| **OS** | RHEL/CentOS/Rocky 8+ | Operating system |
| **Root Access** | Required | Installation requires sudo |
| **Internet** | Required | To download packages |

### Supported Distributions

- Red Hat Enterprise Linux (RHEL) 8.x / 9.x
- CentOS Linux 8.x
- Rocky Linux 8.x / 9.x
- AlmaLinux 8.x / 9.x

### Prerequisites

The installer will automatically detect and install required packages:

- Apache HTTPD 2.4
- Lua 5.1
- lua-cjson (JSON library)
- lua-socket (Socket library)
- Required build tools (gcc, make, git)

### Installation Steps

#### Step 1: Get the Code

```bash
git clone https://github.com/JukLee0ira/Apache.git
cd Apache
```

#### Step 2: Run the Installer

```bash
sudo ./install-rhel.sh
```

The installer will:

1. **Detect OS** - Verify RHEL/CentOS/Rocky Linux
2. **Install Dependencies** - Apache, Lua, build tools
3. **Compile Lua Extensions** - lua-cjson, lua-socket
4. **Configure Apache** - Copy config files to /etc/httpd/
5. **Install Services** - Create systemd unit files
6. **Configure Firewall** - Open ports 8888 and 8545
7. **Configure SELinux** - Set required boolean values
8. **Start Services** - Enable and start all services
9. **Verify Installation** - Run health checks

#### Step 3: Verify Installation

```bash
# Check service status
./status.sh

# Run test suite
./test/comprehensive_test.sh
```

### RHEL-Specific Paths

| Item | Docker (Debian) | RHEL Native |
|------|----------------|-------------|
| Apache Config | `/etc/apache2/` | `/etc/httpd/` |
| Lua Scripts | `/usr/local/apache2/scripts/` | `/etc/httpd/lua/` |
| Whitelist Config | `/etc/apache2/config/whitelist.json` | `/etc/httpd/conf.d/whitelist.json` |
| Error Log | `/dev/stderr` | `/var/log/httpd/rpc-proxy-error.log` |
| Access Log | `/dev/stdout` | `/var/log/httpd/rpc-proxy-access.log` |
| Apache User | `www-data` | `apache` |

### SELinux Configuration

The installer automatically configures SELinux, but if you need to do it manually:

```bash
# Allow Apache to make network connections
sudo setsebool -P httpd_can_network_connect 1

# Allow Apache to execute Lua/CGI scripts
sudo setsebool -P httpd_enable_cgi 1

# Allow Apache to listen on non-standard ports
sudo semanage port -a -t http_port_t -p tcp 8545
sudo semanage port -a -t http_port_t -p tcp 8888
```

### Firewall Configuration

The installer automatically configures firewalld, but if you need to do it manually:

```bash
# Check firewall status
sudo systemctl status firewalld

# Open required ports
sudo firewall-cmd --permanent --add-port=8888/tcp
sudo firewall-cmd --permanent --add-port=8545/tcp
sudo firewall-cmd --reload

# List open ports
sudo firewall-cmd --list-ports
```

---

## Configuration

### Whitelist Configuration

Edit the whitelist file:

**Docker mode:** `config/whitelist.json`
**RHEL native mode:** `/etc/httpd/conf.d/whitelist.json`

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
  ]
}
```

### Apply Configuration Changes

**Docker mode:**
```bash
./restart.sh
```

**RHEL native mode:**
```bash
sudo ./restart.sh
# Or:
sudo systemctl restart ethereum-rpc-mock httpd
```

---

## Service Management

### Docker Mode

```bash
./start.sh           # Start all services
./stop.sh            # Stop all services
./restart.sh         # Restart all services
./status.sh          # Check status

# Direct commands
docker-compose up -d
docker-compose down
docker-compose restart
```

### RHEL Native Mode

```bash
# Using scripts
./start.sh           # Start all services
./stop.sh            # Stop all services
./restart.sh         # Restart all services
./status.sh          # Check status

# Direct systemctl commands
sudo systemctl start ethereum-rpc-mock
sudo systemctl start httpd
sudo systemctl stop ethereum-rpc-mock httpd
sudo systemctl restart ethereum-rpc-mock httpd
sudo systemctl status ethereum-rpc-mock
sudo systemctl status httpd

# Enable services to start on boot
sudo systemctl enable ethereum-rpc-mock
sudo systemctl enable httpd
```

### View Logs

**Docker mode:**
```bash
docker logs -f apache-rpc-proxy
docker logs -f ethereum-rpc-mock
```

**RHEL native mode:**
```bash
# Systemd journal (all services)
journalctl -u ethereum-rpc-mock -f
journalctl -u httpd -f

# Apache logs
tail -f /var/log/httpd/rpc-proxy-access.log
tail -f /var/log/httpd/rpc-proxy-error.log
```

---

## Testing

### Quick Test

```bash
./test/verify.sh
```

### Full Test Suite (25 tests)

```bash
./test/comprehensive_test.sh
```

### Manual Tests

```bash
# Health check
curl http://localhost:8888/health

# Whitelist method (allowed - 200)
curl -X POST http://localhost:8888/rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# Non-whitelist method (blocked - 403)
curl -i -X POST http://localhost:8888/rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"personal_sign","params":["msg","0x1234"],"id":1}'

# View blocked records
curl http://localhost:8545/blocked

# View statistics
curl http://localhost:8545/stats
```

---

## Troubleshooting

### Port Conflict

**Docker mode:**
```bash
lsof -i :8888
lsof -i :8545
```

**RHEL native mode:**
```bash
ss -tlnp | grep 8888
ss -tlnp | grep 8545
netstat -tlnp | grep 8888
```

### Service Won't Start

**Docker mode:**
```bash
docker-compose logs apache-rpc-proxy
docker-compose logs ethereum-rpc-mock
docker-compose restart
```

**RHEL native mode:**
```bash
# Check service status
sudo systemctl status ethereum-rpc-mock
sudo systemctl status httpd

# Check logs
sudo journalctl -u ethereum-rpc-mock -n 50
sudo tail -50 /var/log/httpd/rpc-proxy-error.log

# Test configuration
sudo httpd -t
```

### Lua Script Errors

**Docker mode:**
```bash
docker exec -it apache-rpc-proxy lua -e "dofile('/usr/local/apache2/scripts/rpc_proxy.lua')"
```

**RHEL native mode:**
```bash
sudo lua -e "dofile('/etc/httpd/lua/rpc_proxy.lua')"
```

### Configuration Not Applied

```bash
# Docker mode
./restart.sh

# RHEL native mode
sudo ./restart.sh
```

### SELinux Denials

Check for SELinux denials:
```bash
sudo sealert -a /var/log/audit/audit.log
```

Common fixes:
```bash
sudo setsebool -P httpd_can_network_connect 1
sudo setsebool -P httpd_enable_cgi 1
sudo restorecon -Rv /etc/httpd/
```

### Connection Refused

Check if services are listening:
```bash
# Docker mode
docker exec -it apache-rpc-proxy curl http://localhost:80/health

# RHEL native mode
curl http://localhost:8888/health
curl http://localhost:8545/health
```

---

## Production Recommendations

### Whitelist Management
- Review `whitelist.json` regularly
- Follow least-privilege policy
- Prefer explicit addresses over wildcards

### Security Hardening (RHEL)
```bash
# Enable HTTPS
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload

# Restrict source IPs in Apache config
# Add to /etc/httpd/conf.d/rpc-proxy.conf:
# <RequireAll>
#     Require ip 10.0.0.0/8
# </RequireAll>

# Enable ModSecurity (if needed)
sudo yum install -y mod_security
sudo systemctl restart httpd
```

### Monitoring

```bash
# Check statistics via API
curl http://localhost:8545/stats | jq .

# View blocked requests
curl http://localhost:8545/blocked | jq .

# Set up systemd timer for log rotation
sudo journalctl -u ethereum-rpc-mock --rotate
sudo journalctl -u ethereum-rpc-mock --vacuum-time=7d
```

---

## Uninstallation

### Docker Mode
```bash
./stop.sh
cd ..
rm -rf Apache
```

### RHEL Native Mode
```bash
sudo systemctl stop ethereum-rpc-mock httpd
sudo systemctl disable ethereum-rpc-mock httpd
sudo rm /etc/systemd/system/ethereum-rpc-mock.service
sudo rm /etc/systemd/system/ethereum-rpc-proxy.service
sudo systemctl daemon-reload
sudo rm -rf /opt/ethereum-rpc-mock
sudo rm -rf /opt/ethereum-rpc-filter
cd ..
rm -rf Apache
```

---

**Deployment complete!** If you have any issues, please open an issue on GitHub.
