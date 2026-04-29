#!/bin/bash
# Ethereum RPC Filter - Status Check Script

echo "=========================================="
echo "  Ethereum RPC Filter - Service Status"
echo "=========================================="
echo ""

echo "Container status:"
docker-compose ps

echo ""
echo "Health check:"
curl -s http://localhost:8888/health && echo " [OK]" || echo " [FAILED]"

echo ""
echo "Statistics:"
stats=$(curl -s http://localhost:8545/stats 2>/dev/null)
if [ -n "$stats" ]; then
    if command -v jq >/dev/null 2>&1; then
        echo "$stats" | jq . 2>/dev/null || echo "$stats"
    else
        echo "$stats"
    fi
else
    echo "Unable to fetch statistics"
fi

echo ""
echo "Recent logs (Apache):"
docker logs apache-rpc-proxy --tail 5 2>&1 | sed 's/^/  /'

echo ""
echo "Recent logs (Mock):"
docker logs ethereum-rpc-mock --tail 5 2>&1 | sed 's/^/  /'