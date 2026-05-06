#!/bin/bash
#
# quick_start.sh - Ethereum RPC Filter Quick Start Script
# Supports both Docker and Native (RHEL/CentOS/Rocky) deployment
#

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Detect deployment mode
detect_mode() {
    if command -v docker &> /dev/null && docker ps &> /dev/null 2>&1; then
        echo "docker"
    elif grep -qiE "Red Hat|CentOS|Rocky|AlmaLinux" /etc/os-release 2>/dev/null; then
        echo "rhel"
    else
        echo "unknown"
    fi
}

# Main
main() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  Ethereum RPC Filter - Quick Start${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""

    MODE=$(detect_mode)

    case "$MODE" in
        docker)
            echo -e "${GREEN}[MODE] Docker Deployment Detected${NC}"
            echo ""
            echo "This script will:"
            echo "  1. Install Docker (if not present)"
            echo "  2. Clone repository"
            echo "  3. Start services"
            echo "  4. Verify installation"
            echo ""

            # Step 1: Install Docker if not present
            echo -e "${YELLOW}[Step 1/4] Checking Docker...${NC}"
            if ! command -v docker &> /dev/null; then
                echo "Installing Docker..."
                curl -fsSL https://get.docker.com -o get-docker.sh
                sudo sh get-docker.sh
                rm -f get-docker.sh
                sudo usermod -aG docker $USER
                echo -e "${GREEN}Docker installed${NC}"
            else
                echo -e "${GREEN}Docker already installed${NC}"
            fi

            # Step 2: Install Docker Compose if not present
            echo -e "${YELLOW}[Step 2/4] Checking Docker Compose...${NC}"
            if ! command -v docker-compose &> /dev/null && ! docker compose version &>/dev/null 2>&1; then
                echo "Installing Docker Compose..."
                sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
                sudo chmod +x /usr/local/bin/docker-compose
                echo -e "${GREEN}Docker Compose installed${NC}"
            else
                echo -e "${GREEN}Docker Compose already installed${NC}"
            fi

            # Step 3: Clone repository
            echo -e "${YELLOW}[Step 3/4] Preparing repository...${NC}"
            if [ -d "Apache" ]; then
                echo "Directory exists, pulling latest..."
                cd Apache && git pull origin main
            else
                git clone https://github.com/JukLee0ira/Apache.git
                cd Apache
            fi

            # Step 4: Start services
            echo -e "${YELLOW}[Step 4/4] Starting services...${NC}"
            ./start.sh

            # Verify
            sleep 3
            echo ""
            if curl -s http://localhost:8888/health > /dev/null; then
                echo ""
                echo -e "${GREEN}========================================${NC}"
                echo -e "${GREEN}  SUCCESS! Service is running!${NC}"
                echo -e "${GREEN}========================================${NC}"
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
                echo -e "${YELLOW}Service may still be starting. Check status with:${NC}"
                echo "  docker-compose ps"
                echo "  docker logs apache-rpc-proxy"
            fi
            ;;

        rhel)
            echo -e "${GREEN}[MODE] RHEL/CentOS/Rocky Native Installation Detected${NC}"
            echo ""
            echo "This script will:"
            echo "  1. Run the native installation script"
            echo "  2. Install all dependencies"
            echo "  3. Configure and start services"
            echo ""

            # Run the RHEL installer
            echo -e "${YELLOW}Starting native installation...${NC}"
            ./install-rhel.sh
            ;;

        *)
            echo -e "${RED}[ERROR] Unable to detect deployment environment${NC}"
            echo ""
            echo "Supported environments:"
            echo "  - Docker on any Linux distribution"
            echo "  - RHEL/CentOS/Rocky Linux (native installation)"
            echo ""
            echo "For other distributions, please install Docker first:"
            echo "  https://docs.docker.com/engine/install/"
            exit 1
            ;;
    esac
}

main "$@"
