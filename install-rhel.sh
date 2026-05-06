#!/bin/bash
#
# install-rhel.sh - Ethereum RPC Filter Native Installation for RHEL/CentOS/Rocky Linux
# This script installs the Ethereum RPC Filter without Docker
#

set -e

# ============ Configuration ============
INSTALL_DIR="/opt/ethereum-rpc-filter"
LUA_SCRIPT_DIR="/etc/httpd/lua"
CONFIG_DIR="/etc/httpd/conf.d"
MOCK_DIR="/opt/ethereum-rpc-mock"
WHITELIST_PATH="/etc/httpd/conf.d/whitelist.json"
BACKEND_PORT=8545
PROXY_PORT=8888

# ============ Color Output ============
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }

# ============ Pre-flight Checks ============
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "This script must be run as root"
        echo "Please run: sudo $0"
        exit 1
    fi
}

check_os() {
    info "Detecting operating system..."

    if [ -f /etc/redhat-release ]; then
        OS_NAME=$(cat /etc/redhat-release)
    elif [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME="$NAME $VERSION"
    else
        error "Cannot detect OS. This script is for RHEL/CentOS/Rocky Linux only."
        exit 1
    fi

    if echo "$OS_NAME" | grep -qiE "Red Hat|CentOS|Rocky|AlmaLinux"; then
        success "Detected: $OS_NAME"
    else
        error "Unsupported OS: $OS_NAME"
        error "This script is designed for RHEL/CentOS/Rocky Linux"
        exit 1
    fi
}

# ============ Dependency Installation ============
install_dependencies() {
    info "Installing system dependencies..."

    # Install EPEL repository
    if ! rpm -q epel-release &>/dev/null; then
        yum install -y epel-release
    fi

    # Install Apache and Lua
    yum install -y \
        httpd \
        mod_ssl \
        lua \
        lua-devel \
        curl \
        git \
        gcc \
        make

    success "System packages installed"
}

install_lua_cjson() {
    info "Installing lua-cjson..."

    local CJSON_DIR="/tmp/lua-cjson"

    if [ -d "$CJSON_DIR" ]; then
        rm -rf "$CJSON_DIR"
    fi

    git clone https://github.com/mpx/lua-cjson.git "$CJSON_DIR" 2>/dev/null || {
        warn "Failed to clone lua-cjson, trying alternative method..."
        # Try to install from EPEL if available
        yum install -y lua-cjson 2>/dev/null && return 0
        warn "lua-cjson not available in repos, attempting manual build..."
    }

    cd "$CJSON_DIR"

    # Detect Lua version and adjust Makefile
    local LUA_VERSION=$(lua -v 2>&1 | grep -oP '\d+\.\d+' | head -1)
    sed -i "s/LUA_VERSION = 5\.1/LUA_VERSION = ${LUA_VERSION}/" Makefile 2>/dev/null || true

    make
    make install

    cd /tmp
    rm -rf "$CJSON_DIR"

    # Verify installation
    if lua -e "require('cjson')" 2>/dev/null; then
        success "lua-cjson installed"
    else
        # Try alternative installation path
        cp /usr/local/lib/lua/${LUA_VERSION}/cjson.so /usr/lib64/lua-${LUA_VERSION}/ 2>/dev/null || \
        cp /usr/local/lib/lua/5.1/cjson.so /usr/lib64/lua/5.1/ 2>/dev/null || \
        cp /usr/local/lib/lua/5.1/cjson.so /usr/lib/lua/5.1/ 2>/dev/null || true

        if lua -e "require('cjson')" 2>/dev/null; then
            success "lua-cjson installed (alternative path)"
        else
            warn "lua-cjson may need manual configuration"
        fi
    fi
}

install_lua_socket() {
    info "Installing lua-socket..."

    local SOCKET_DIR="/tmp/lua-socket"

    if [ -d "$SOCKET_DIR" ]; then
        rm -rf "$SOCKET_DIR"
    fi

    git clone https://github.com/lunixbochs/lua-socket.git "$SOCKET_DIR" 2>/dev/null || {
        warn "Failed to clone lua-socket, trying alternative method..."
        yum install -y lua-socket 2>/dev/null && return 0
    }

    cd "$SOCKET_DIR"
    make
    make install

    cd /tmp
    rm -rf "$SOCKET_DIR"

    # Verify installation
    if lua -e "require('socket')" 2>/dev/null; then
        success "lua-socket installed"
    else
        warn "lua-socket may need manual configuration"
    fi
}

install_lua_extensions() {
    info "Installing Lua extensions..."

    # Try EPEL first
    yum install -y lua-cjson 2>/dev/null || true

    # If EPEL version works, skip manual install
    if lua -e "require('cjson')" 2>/dev/null; then
        success "lua-cjson installed from EPEL"
    else
        install_lua_cjson
    fi

    # Try EPEL first for socket
    yum install -y lua-socket 2>/dev/null || true

    if lua -e "require('socket')" 2>/dev/null; then
        success "lua-socket installed from EPEL"
    else
        install_lua_socket
    fi
}

# ============ Directory Setup ============
setup_directories() {
    info "Creating directories..."

    mkdir -p "$INSTALL_DIR"
    mkdir -p "$LUA_SCRIPT_DIR"
    mkdir -p "$MOCK_DIR"
    mkdir -p "$CONFIG_DIR"

    success "Directories created"
}

# ============ Configuration Files ============
install_apache_config() {
    info "Installing Apache configuration..."

    # Copy RHEL-specific Apache configuration
    if [ -f "$INSTALL_DIR/apache/conf/httpd-rhel.conf" ]; then
        cp "$INSTALL_DIR/apache/conf/httpd-rhel.conf" "$CONFIG_DIR/rpc-proxy.conf"
    else
        # Fallback: create minimal config if file doesn't exist yet
        cat > "$CONFIG_DIR/rpc-proxy.conf" << 'APACHECONF'
# Ethereum RPC Proxy Configuration for RHEL
Define RPC_BACKEND 127.0.0.1:8545
Define WHITELIST_PATH /etc/httpd/conf.d/whitelist.json

Listen 8888

<VirtualHost *:8888>
    ServerName localhost

    ProxyRequests Off
    ProxyPreserveHost On

    ErrorLog /var/log/httpd/rpc-proxy-error.log
    CustomLog /var/log/httpd/rpc-proxy-access.log combined

    <Location /health>
        ProxyPass http://${RPC_BACKEND}/health
        ProxyPassReverse http://${RPC_BACKEND}/health
    </Location>

    <Location /stats>
        ProxyPass http://${RPC_BACKEND}/stats
        ProxyPassReverse http://${RPC_BACKEND}/stats
    </Location>

    <Location /rpc>
        SetHandler lua-script
        LuaMapHandler /rpc /etc/httpd/lua/rpc_proxy.lua rpc
    </Location>

    <Location />
        RewriteEngine On
        RewriteRule ^/rpc$ - [L]
        RewriteRule ^/$ http://${RPC_BACKEND}/ [P,L]
        ProxyPass http://${RPC_BACKEND}/
        ProxyPassReverse http://${RPC_BACKEND}/
    </Location>

    <IfModule mod_headers.c>
        Header always set Access-Control-Allow-Origin "*"
        Header always set Access-Control-Allow-Methods "GET, POST, OPTIONS"
        Header always set Access-Control-Allow-Headers "Content-Type"
    </IfModule>
</VirtualHost>
APACHECONF
    fi

    # Copy lua scripts
    cp "$INSTALL_DIR/scripts/rpc_proxy.lua" "$LUA_SCRIPT_DIR/"
    cp "$INSTALL_DIR/config/whitelist.json" "$CONFIG_DIR/"

    # Copy mock backend
    cp "$INSTALL_DIR/mock_rpc.lua" "$MOCK_DIR/"

    # Set permissions
    chown -R apache:apache "$MOCK_DIR" 2>/dev/null || true
    chown apache:apache "$CONFIG_DIR/whitelist.json" 2>/dev/null || true

    success "Configuration installed"
}

enable_apache_modules() {
    info "Enabling Apache modules..."

    # Create module configuration files if they don't exist
    MODULE_CONF_DIR="/etc/httpd/conf.modules.d"

    # Ensure required modules are loaded
    for module in lua proxy proxy_http rewrite headers; do
        if ! grep -q "mod_${module}" "$MODULE_CONF_DIR"/*.conf 2>/dev/null; then
            echo "LoadModule ${module}_module modules/mod_${module}.so" >> "$MODULE_CONF_DIR/00-${module}.conf"
        fi
    done

    success "Apache modules enabled"
}

configure_firewall() {
    info "Configuring firewall..."

    if command -v firewall-cmd &>/dev/null; then
        if systemctl is-active --quiet firewalld; then
            firewall-cmd --permanent --add-port=${PROXY_PORT}/tcp
            firewall-cmd --permanent --add-port=${BACKEND_PORT}/tcp
            firewall-cmd --reload
            success "Firewall configured"
        else
            warn "Firewalld is not running, skipping firewall configuration"
        fi
    else
        warn "firewall-cmd not found, skipping firewall configuration"
    fi
}

configure_selinux() {
    info "Configuring SELinux..."

    if command -v getenforce &>/dev/null; then
        if getenforce | grep -qi "Enforcing"; then
            # Allow Apache to make network connections
            setsebool -P httpd_can_network_connect 1
            # Allow Apache to execute Lua scripts
            setsebool -P httpd_enable_cgi 1
            success "SELinux configured"
        fi
    fi
}

# ============ Systemd Services ============
install_systemd_services() {
    info "Installing systemd services..."

    # Copy service files
    if [ -d "$INSTALL_DIR/systemd" ]; then
        cp "$INSTALL_DIR/systemd/"*.service /etc/systemd/system/
    else
        # Create mock service file
        cat > /etc/systemd/system/ethereum-rpc-mock.service << 'MOCKSERVICE'
[Unit]
Description=Ethereum RPC Mock Server
After=network.target

[Service]
Type=simple
User=apache
WorkingDirectory=/opt/ethereum-rpc-mock
ExecStart=/usr/bin/lua /opt/ethereum-rpc-mock/mock_rpc.lua 8545
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
MOCKSERVICE

        # Create proxy service file
        cat > /etc/systemd/system/ethereum-rpc-proxy.service << 'PROXYSERVICE'
[Unit]
Description=Ethereum RPC Apache Proxy
After=network.target ethereum-rpc-mock.service
Wants=ethereum-rpc-mock.service

[Service]
Type=simple
ExecStartPre=/usr/sbin/httpd -t
ExecStart=/usr/sbin/httpd -DFOREGROUND
ExecReload=/usr/sbin/httpd -k graceful
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
PROXYSERVICE
    fi

    # Reload systemd
    systemctl daemon-reload

    success "Systemd services installed"
}

# ============ Service Management ============
start_services() {
    info "Starting services..."

    # Start Mock Backend
    systemctl enable ethereum-rpc-mock
    systemctl start ethereum-rpc-mock

    # Start Apache Proxy
    systemctl enable httpd
    systemctl start httpd

    success "Services started"
}

# ============ Verification ============
verify_installation() {
    info "Verifying installation..."

    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  Installation Verification${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""

    local all_passed=true

    # Check Mock Service
    echo -n "  Mock Service (port ${BACKEND_PORT}): "
    if systemctl is-active --quiet ethereum-rpc-mock; then
        echo -e "${GREEN}Running${NC}"
    else
        echo -e "${RED}Failed${NC}"
        all_passed=false
    fi

    # Check Apache
    echo -n "  Apache Proxy (port ${PROXY_PORT}): "
    if systemctl is-active --quiet httpd; then
        echo -e "${GREEN}Running${NC}"
    else
        echo -e "${RED}Failed${NC}"
        all_passed=false
    fi

    # Check Health Endpoint
    echo -n "  Health Check: "
    sleep 2
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${PROXY_PORT}/health" | grep -q "200"; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${YELLOW}Pending${NC} (may need a few more seconds)"
        sleep 3
        if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${PROXY_PORT}/health" | grep -q "200"; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${RED}Failed${NC}"
            all_passed=false
        fi
    fi

    # Check Mock Stats
    echo -n "  Mock Stats: "
    if curl -s "http://localhost:${BACKEND_PORT}/stats" | grep -q "allowed_count"; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${YELLOW}Pending${NC}"
    fi

    echo ""
    echo -e "${CYAN}========================================${NC}"

    if $all_passed; then
        success "Installation completed successfully!"
        return 0
    else
        error "Some services failed to start"
        echo ""
        echo "Debug commands:"
        echo "  systemctl status ethereum-rpc-mock"
        echo "  systemctl status httpd"
        echo "  journalctl -u ethereum-rpc-mock -n 50"
        echo "  tail -f /var/log/httpd/rpc-proxy-error.log"
        return 1
    fi
}

# ============ Main ============
main() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  Ethereum RPC Filter - RHEL Installer${NC}"
    echo -e "${CYAN}  Native Installation (No Docker)${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""

    # Determine script directory
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    check_root
    check_os
    install_dependencies
    install_lua_extensions
    setup_directories

    # Update INSTALL_DIR to actual path
    INSTALL_DIR="$SCRIPT_DIR"

    install_apache_config
    enable_apache_modules
    configure_firewall
    configure_selinux
    install_systemd_services
    start_services

    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  Post-Installation Info${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    echo "  Installation Directory: $SCRIPT_DIR"
    echo "  RPC Proxy:              http://localhost:${PROXY_PORT}"
    echo "  Mock RPC:              http://localhost:${BACKEND_PORT}"
    echo ""
    echo "  Service Management:"
    echo "    systemctl start ethereum-rpc-mock"
    echo "    systemctl start httpd"
    echo "    systemctl restart ethereum-rpc-mock httpd"
    echo ""
    echo "  Or use convenience scripts:"
    echo "    ./start.sh    - Start services"
    echo "    ./stop.sh     - Stop services"
    echo "    ./restart.sh  - Restart services"
    echo "    ./status.sh   - Check status"
    echo ""
    echo "  Test the filter:"
    echo "    curl -X POST http://localhost:${PROXY_PORT}/rpc \\"
    echo "      -H 'Content-Type: application/json' \\"
    echo "      -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}'"
    echo ""

    verify_installation

    echo ""
    echo -e "${GREEN}Installation complete!${NC}"
}

main "$@"
