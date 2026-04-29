#!/bin/bash
# Ethereum RPC Filter - Quick Start Script
# Version: Apache 2.4 + Lua 5.1
# Dependencies: Docker, Docker Compose

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Ethereum RPC Filter - Quick Start${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed${NC}"
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}Error: Docker Compose is not installed${NC}"
    exit 1
fi

# Check port usage
check_port() {
    local port=$1
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo -e "${YELLOW}Warning: Port $port is already in use${NC}"
        return 1
    fi
    return 0
}

echo -e "${YELLOW}[1/4] Checking environment...${NC}"
check_port 8888 || true
check_port 8545 || true

echo -e "${YELLOW}[2/4] Building and starting services...${NC}"
docker-compose up -d --build

echo -e "${YELLOW}[3/4] Waiting for services to be ready...${NC}"
sleep 3

# Health check
echo -e "${YELLOW}[4/4] Running health check...${NC}"
for i in {1..10}; do
    if curl -s http://localhost:8888/health > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Services started successfully!${NC}"
        break
    fi
    if [ $i -eq 10 ]; then
        echo -e "${RED}✗ Health check failed${NC}"
        echo -e "${YELLOW}View logs: docker logs apache-rpc-proxy${NC}"
        exit 1
    fi
    sleep 1
done

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Services are ready!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "  RPC proxy port:   http://localhost:8888"
echo "  Mock RPC port:    http://localhost:8545"
echo ""
echo "  Test commands:"
echo "    curl http://localhost:8888/health"
echo "    curl -X POST http://localhost:8888/rpc -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}'"
echo ""
echo "  View logs:"
echo "    docker logs -f apache-rpc-proxy"
echo "    docker logs -f ethereum-rpc-mock"
echo ""
echo -e "  Stop services: ${YELLOW}./stop.sh${NC}"
echo ""