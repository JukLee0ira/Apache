#!/bin/bash
# Ethereum RPC Filter - 快速启动脚本
# 版本: Apache 2.4 + Lua 5.1
# 依赖: Docker, Docker Compose

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Ethereum RPC Filter - 快速启动${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# 检查 Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}错误: Docker 未安装${NC}"
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}错误: Docker Compose 未安装${NC}"
    exit 1
fi

# 检查端口占用
check_port() {
    local port=$1
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo -e "${YELLOW}警告: 端口 $port 已被占用${NC}"
        return 1
    fi
    return 0
}

echo -e "${YELLOW}[1/4] 检查环境...${NC}"
check_port 8888 || true
check_port 8545 || true

echo -e "${YELLOW}[2/4] 构建并启动服务...${NC}"
docker-compose up -d --build

echo -e "${YELLOW}[3/4] 等待服务就绪...${NC}"
sleep 3

# 健康检查
echo -e "${YELLOW}[4/4] 健康检查...${NC}"
for i in {1..10}; do
    if curl -s http://localhost:8888/health > /dev/null 2>&1; then
        echo -e "${GREEN}✓ 服务启动成功!${NC}"
        break
    fi
    if [ $i -eq 10 ]; then
        echo -e "${RED}✗ 健康检查失败${NC}"
        echo -e "${YELLOW}查看日志: docker logs apache-rpc-proxy${NC}"
        exit 1
    fi
    sleep 1
done

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  服务已就绪!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "  RPC 代理端口:   http://localhost:8888"
echo "  Mock RPC 端口:  http://localhost:8545"
echo ""
echo "  测试命令:"
echo "    curl http://localhost:8888/health"
echo "    curl -X POST http://localhost:8888/rpc -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}'"
echo ""
echo "  查看日志:"
echo "    docker logs -f apache-rpc-proxy"
echo "    docker logs -f ethereum-rpc-mock"
echo ""
echo -e "  停止服务: ${YELLOW}./stop.sh${NC}"
echo ""