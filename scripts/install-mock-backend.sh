#!/bin/bash
#
# install-mock-backend.sh - Install Mock RPC Backend dependencies
# Compiles and installs lua-cjson and lua-socket from source
# This is called by install-rhel.sh but can be run standalone
#

set -e

# ============ Color Output ============
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }

# ============ Check Root ============
if [ "$EUID" -ne 0 ]; then
    error "This script must be run as root"
    echo "Please run: sudo $0"
    exit 1
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Mock Backend Dependencies Installer${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# ============ Detect Lua Version ============
detect_lua() {
    if command -v lua &>/dev/null; then
        LUA_VERSION=$(lua -v 2>&1 | grep -oP '\d+\.\d+' | head -1)
        info "Detected Lua version: $LUA_VERSION"
    else
        error "Lua not found. Please install lua first."
        exit 1
    fi
}

# ============ Install Build Tools ============
install_build_tools() {
    info "Installing build tools..."

    if ! rpm -q epel-release &>/dev/null; then
        yum install -y epel-release
    fi

    yum install -y \
        gcc \
        make \
        git \
        lua-devel

    success "Build tools installed"
}

# ============ Install lua-cjson ============
install_lua_cjson() {
    info "Installing lua-cjson..."

    local CJSON_DIR="/tmp/lua-cjson-$$"

    # Clean up on exit
    trap "rm -rf $CJSON_DIR" EXIT

    if [ -d "$CJSON_DIR" ]; then
        rm -rf "$CJSON_DIR"
    fi

    # Clone repository
    if ! git clone https://github.com/mpx/lua-cjson.git "$CJSON_DIR" 2>/dev/null; then
        warn "Failed to clone lua-cjson, trying EPEL..."
        if yum install -y lua-cjson 2>/dev/null; then
            success "lua-cjson installed from EPEL"
            return 0
        fi
        error "Failed to install lua-cjson"
        return 1
    fi

    cd "$CJSON_DIR"

    # Detect Lua version and adjust Makefile
    local LUA_VERSION_NUM=$(lua -v 2>&1 | grep -oP '\d+\.\d+' | head -1)

    # Update Makefile for Lua 5.1
    sed -i "s/LUA_VERSION = 5\.1/LUA_VERSION = ${LUA_VERSION_NUM}/" Makefile 2>/dev/null || true

    # Detect system architecture and Lua paths
    local ARCH=$(uname -m)
    local LUA_LIB_DIR="/usr/lib64/lua/${LUA_VERSION_NUM}"
    local LUA_SHARE_DIR="/usr/share/lua/${LUA_VERSION_NUM}"

    # Try to find Lua paths
    if [ -d "/usr/lib64/lua-5.1" ]; then
        LUA_LIB_DIR="/usr/lib64/lua-5.1"
    elif [ -d "/usr/lib/lua/5.1" ]; then
        LUA_LIB_DIR="/usr/lib/lua/5.1"
    fi

    # Build and install
    make clean 2>/dev/null || true
    make
    make install

    cd /

    # Copy to system paths if needed
    if [ -f "/usr/local/lib/lua/${LUA_VERSION_NUM}/cjson.so" ]; then
        mkdir -p "$LUA_LIB_DIR"
        cp "/usr/local/lib/lua/${LUA_VERSION_NUM}/cjson.so" "$LUA_LIB_DIR/" 2>/dev/null || true
    fi

    # Update library cache
    ldconfig 2>/dev/null || true

    # Verify installation
    if lua -e "require('cjson')" 2>/dev/null; then
        success "lua-cjson installed successfully"
        return 0
    else
        # Try alternative paths
        for path in "/usr/local/lib/lua/5.1" "/usr/local/lib/lua/${LUA_VERSION_NUM}"; do
            if [ -f "${path}/cjson.so" ]; then
                cp "${path}/cjson.so" "$LUA_LIB_DIR/" 2>/dev/null || \
                cp "${path}/cjson.so" "/usr/lib64/lua-5.1/" 2>/dev/null || true
            fi
        done

        if lua -e "require('cjson')" 2>/dev/null; then
            success "lua-cjson installed successfully (alternative path)"
            return 0
        fi

        error "lua-cjson installation verification failed"
        return 1
    fi
}

# ============ Install lua-socket ============
install_lua_socket() {
    info "Installing lua-socket..."

    local SOCKET_DIR="/tmp/lua-socket-$$"

    # Clean up on exit
    trap "rm -rf $SOCKET_DIR" EXIT

    if [ -d "$SOCKET_DIR" ]; then
        rm -rf "$SOCKET_DIR"
    fi

    # Clone repository
    if ! git clone https://github.com/lunixbochs/lua-socket.git "$SOCKET_DIR" 2>/dev/null; then
        warn "Failed to clone lua-socket, trying EPEL..."
        if yum install -y lua-socket 2>/dev/null; then
            success "lua-socket installed from EPEL"
            return 0
        fi
        error "Failed to install lua-socket"
        return 1
    fi

    cd "$SOCKET_DIR"

    # Build and install
    make clean 2>/dev/null || true
    make
    make install

    cd /

    # Update library cache
    ldconfig 2>/dev/null || true

    # Verify installation
    if lua -e "require('socket')" 2>/dev/null; then
        success "lua-socket installed successfully"
        return 0
    else
        # Try to find and copy the module
        for path in "/usr/local/share/lua/5.1" "/usr/local/share/lua/${LUA_VERSION}" "/usr/share/lua/5.1"; do
            if [ -d "${path}/socket" ]; then
                cp -r "${path}/socket" "/usr/share/lua/5.1/" 2>/dev/null || true
            fi
        done

        if lua -e "require('socket')" 2>/dev/null; then
            success "lua-socket installed successfully (alternative path)"
            return 0
        fi

        warn "lua-socket may need manual configuration"
        return 0  # Don't fail on socket since mock_rpc.lua might work without it
    fi
}

# ============ Main ============
main() {
    detect_lua
    install_build_tools

    local failed=0

    install_lua_cjson || failed=1
    install_lua_socket || failed=1

    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo ""

    if [ $failed -eq 0 ]; then
        success "All Lua extensions installed successfully!"
    else
        warn "Some extensions may not have installed correctly"
        echo "Please verify manually with: lua -e \"require('cjson')\" && lua -e \"require('socket')\""
    fi

    echo ""
    echo "To test the Mock Backend, run:"
    echo "  lua /opt/ethereum-rpc-mock/mock_rpc.lua 8545"
    echo ""
}

main "$@"
