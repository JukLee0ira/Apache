#!/bin/bash
#
# start.sh - Ethereum RPC Filter Start Script
# Supports both Docker and Native (systemd) deployment modes
#

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "${GREEN}[START]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Ethereum RPC Filter - Start Services${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# Detect deployment mode
if command -v docker &> /dev/null && docker ps &> /dev/null 2>&1; then
    # Docker mode
    info "Docker detected, using Docker deployment"

    # Check port usage
    check_port() {
        local port=$1
        if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
            warn "Port $port is already in use"
            return 1
        fi
        return 0
    }

    check_port 8888 || true
    check_port 8545 || true

    info "Building and starting Docker services..."
    docker-compose up -d --build

    info "Waiting for services to be ready..."
    sleep 3

    # Health check
    for i in {1..10}; do
        if curl -s http://localhost:8888/health > /dev/null 2>&1; then
            info "Services started successfully!"
            break
        fi
        if [ $i -eq 10 ]; then
            echo -e "${RED}[ERROR] Health check failed${NC}"
            echo "View logs: docker logs apache-rpc-proxy"
            exit 1
        fi
        sleep 1
    done

    echo ""
    echo "  RPC proxy port:   http://localhost:8888"
    echo "  Mock RPC port:    http://localhost:8545"
    echo ""
    echo "  View logs:"
    echo "    docker logs -f apache-rpc-proxy"
    echo "    docker logs -f ethereum-rpc-mock"
    echo ""

else
    # Native (systemd) mode
    info "Using native systemd deployment"

    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}[ERROR] Native deployment requires root privileges${NC}"
        echo "Please run: sudo ./start.sh"
        exit 1
    fi

    # Check port usage
    check_port() {
        local port=$1
        if ss -tlnp | grep -q ":$port "; then
            warn "Port $port is already in use"
            return 1
        fi
        return 0
    }

    check_port 8888 || true
    check_port 8545 || true

    # Start services
    info "Starting Mock Backend..."
    systemctl enable ethereum-rpc-mock 2>/dev/null || true
    systemctl start ethereum-rpc-mock

    info "Starting Apache Proxy..."
    systemctl enable httpd 2>/dev/null || true
    systemctl start httpd

    # Wait for services
    info "Waiting for services to be ready..."
    sleep 3

    # Health check
    for i in {1..10}; do
        if curl -s http://localhost:8888/health > /dev/null 2>&1; then
            info "Services started successfully!"
            break
        fi
        if [ $i -eq 10 ]; then
            echo -e "${RED}[ERROR] Health check failed${NC}"
            echo "Debug commands:"
            echo "  systemctl status ethereum-rpc-mock"
            echo "  systemctl status httpd"
            echo "  journalctl -u ethereum-rpc-mock -n 50"
            echo "  tail -f /var/log/httpd/rpc-proxy-error.log"
            exit 1
        fi
        sleep 1
    done

    echo ""
    echo "  RPC proxy port:   http://localhost:8888"
    echo "  Mock RPC port:    http://localhost:8545"
    echo ""
    echo "  View logs:"
    echo "    journalctl -u ethereum-rpc-mock -f"
    echo "    tail -f /var/log/httpd/rpc-proxy-access.log"
    echo ""
    echo "  Service management:"
    echo "    systemctl stop ethereum-rpc-mock httpd"
    echo "    systemctl restart ethereum-rpc-mock httpd"
    echo ""

fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Services are ready!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "  Test commands:"
echo "    curl http://localhost:8888/health"
echo "    curl -X POST http://localhost:8888/rpc -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}'"
echo ""
