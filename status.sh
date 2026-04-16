#!/bin/bash
# Ethereum RPC Filter - 状态检查脚本

echo "=========================================="
echo "  Ethereum RPC Filter - 服务状态"
echo "=========================================="
echo ""

echo "容器状态:"
docker-compose ps

echo ""
echo "健康检查:"
curl -s http://localhost:8888/health && echo " [OK]" || echo " [FAILED]"

echo ""
echo "统计信息:"
curl -s http://localhost:8545/stats 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "无法获取统计信息"

echo ""
echo "最近日志 (Apache):"
docker logs apache-rpc-proxy --tail 5 2>&1 | sed 's/^/  /'

echo ""
echo "最近日志 (Mock):"
docker logs ethereum-rpc-mock --tail 5 2>&1 | sed 's/^/  /'