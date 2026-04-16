#!/bin/bash
# Quick Download & Start Script for Ethereum RPC Filter
# Run this on any machine with Docker installed

set -e

echo "=========================================="
echo "  Ethereum RPC Filter - Quick Setup"
echo "=========================================="
echo ""

# Step 1: Install Docker if not present
if ! command -v docker &> /dev/null; then
    echo "[1/5] Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    rm get-docker.sh
else
    echo "[1/5] Docker already installed ✓"
fi

# Step 2: Install Docker Compose if not present
if ! command -v docker-compose &> /dev/null; then
    echo "[2/5] Installing Docker Compose..."
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
else
    echo "[2/5] Docker Compose already installed ✓"
fi

# Step 3: Clone repository
echo "[3/5] Cloning repository..."
if [ -d "Apache" ]; then
    echo "  Directory exists, pulling latest..."
    cd Apache && git pull origin main
else
    git clone https://github.com/JukLee0ira/Apache.git
    cd Apache
fi

# Step 4: Start services
echo "[4/5] Starting services..."
docker-compose up -d --build

# Step 5: Verify
echo "[5/5] Verifying..."
sleep 3
if curl -s http://localhost:8888/health > /dev/null; then
    echo ""
    echo "=========================================="
    echo "  SUCCESS! Service is running!"
    echo "=========================================="
    echo ""
    echo "  RPC Proxy:  http://localhost:8888"
    echo "  Mock RPC:   http://localhost:8545"
    echo ""
    echo "  Test command:"
    echo "  curl -X POST http://localhost:8888/rpc \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}'"
    echo ""
else
    echo ""
    echo "Service may still be starting. Check status with:"
    echo "  docker-compose ps"
    echo "  docker logs apache-rpc-proxy"
fi