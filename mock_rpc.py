#!/usr/bin/env python3
"""
mock_rpc.py - Ethereum JSON-RPC Mock Server
Used for POC validation, records all requests and provides blocking statistics
"""

import json
import sys
import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
from collections import defaultdict

# Global statistics
stats = {
    "allowed": [],
    "blocked": []
}

class RPCHandler(BaseHTTPRequestHandler):
    """Handles Ethereum JSON-RPC requests"""

    def log_message(self, format, *args):
        timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
        sys.stdout.write(f"[{timestamp}] {format % args}\n")
        sys.stdout.flush()

    def send_rpc_response(self, response):
        """Sends JSON-RPC response"""
        body = json.dumps(response).encode('utf-8')
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', len(body))
        self.end_headers()
        self.wfile.write(body)

    def handle_rpc_request(self, req, source="direct"):
        """Handles RPC request"""
        method = req.get('method', 'unknown')
        rpc_id = req.get('id', 1)
        params = req.get('params', [])

        source_tag = "BACKEND PROCESSING" if source == "direct" else "BLOCKED RECORD"

        self.log_message("=" * 60)
        self.log_message("%s", source_tag)
        self.log_message("    Source: %s", source)
        self.log_message("    Method: %s", method)
        self.log_message("    Params: %s", json.dumps(params)[:300])
        self.log_message("   ID: %s", rpc_id)
        self.log_message("=" * 60)

        # Record to statistics
        if source == "blocked":
            stats["blocked"].append({
                "timestamp": datetime.datetime.now().isoformat(),
                "method": method,
                "params": params,
                "client_ip": self.client_address[0]
            })
        else:
            stats["allowed"].append({
                "timestamp": datetime.datetime.now().isoformat(),
                "method": method,
                "params": params,
                "client_ip": self.client_address[0]
            })

        # Return response
        if method == 'eth_blockNumber':
            return {"jsonrpc": "2.0", "id": rpc_id, "result": "0x10d4f"}
        elif method == 'net_version':
            return {"jsonrpc": "2.0", "id": rpc_id, "result": "1337"}
        elif method == 'eth_chainId':
            return {"jsonrpc": "2.0", "id": rpc_id, "result": "0x539"}
        elif method == 'eth_getBalance':
            return {"jsonrpc": "2.0", "id": rpc_id, "result": "0x0"}
        elif method in ('eth_call', 'eth_getLogs', 'eth_getTransactionCount'):
            return {"jsonrpc": "2.0", "id": rpc_id, "result": "0x"}
        elif method == 'eth_gasPrice':
            return {"jsonrpc": "2.0", "id": rpc_id, "result": "0x4A817C800"}
        else:
            return {"jsonrpc": "2.0", "id": rpc_id, "result": None}

    def handle_blocked_request(self, req_data):
        """Records blocked requests"""
        try:
            data = json.loads(req_data)
            if isinstance(data, list):
                for req in data:
                    self.handle_rpc_request(req, source="blocked")
                response = {"status": "recorded", "count": len(data)}
            else:
                self.handle_rpc_request(data, source="blocked")
                response = {"status": "recorded"}
        except Exception as e:
            response = {"status": "error", "message": str(e)}

        body = json.dumps(response).encode('utf-8')
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', len(body))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length).decode('utf-8')

        if self.path == '/blocked':
            self.handle_blocked_request(body)
            return

        try:
            rpc_data = json.loads(body)
            if isinstance(rpc_data, list):
                responses = [self.handle_rpc_request(req, "direct") for req in rpc_data]
                response = responses if len(responses) > 1 else responses[0]
            else:
                response = self.handle_rpc_request(rpc_data, "direct")

            self.send_rpc_response(response)

        except json.JSONDecodeError as e:
            self.log_message("JSON parse error: %s", str(e))
            self.send_rpc_response({
                "jsonrpc": "2.0",
                "id": 1,
                "error": {"code": -32700, "message": "Parse error"}
            })
        except Exception as e:
            self.log_message("Processing error: %s", str(e))
            self.send_rpc_response({
                "jsonrpc": "2.0",
                "id": 1,
                "error": {"code": -32603, "message": str(e)}
            })

    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'OK')

        elif self.path == '/stats':
            """Returns statistics"""
            stats_data = {
                "allowed_count": len(stats["allowed"]),
                "blocked_count": len(stats["blocked"]),
                "recent_blocked": stats["blocked"][-10:],
                "recent_allowed": stats["allowed"][-10:]
            }
            body = json.dumps(stats_data, indent=2).encode('utf-8')
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', len(body))
            self.end_headers()
            self.wfile.write(body)

        elif self.path == '/blocked':
            """Returns all blocked records"""
            data = json.dumps(stats["blocked"], indent=2).encode('utf-8')
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', len(data))
            self.end_headers()
            self.wfile.write(data)

        elif self.path == '/allowed':
            """Returns all allowed records"""
            data = json.dumps(stats["allowed"], indent=2).encode('utf-8')
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', len(data))
            self.end_headers()
            self.wfile.write(data)

        else:
            self.send_response(404)
            self.end_headers()

def run(port=8545):
    server_address = ('', port)
    httpd = HTTPServer(server_address, RPCHandler)
    print(f"Mock RPC Server running on port {port}")
    print(f"Endpoints:")
    print(f"  POST /          - Normal RPC requests (allowed)")
    print(f"  POST /blocked   - Record blocked requests")
    print(f"  GET  /health    - Health check")
    print(f"  GET  /stats     - Statistics")
    print(f"  GET  /blocked   - View blocked records (JSON)")
    print(f"  GET  /allowed   - View allowed records (JSON)")
    print("-" * 50)
    sys.stdout.flush()
    httpd.serve_forever()

if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8545
    run(port)
