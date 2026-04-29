#!/usr/bin/env lua5.1

local socket = require("socket")
local cjson = require("cjson")

local stats = {
    allowed = {},
    blocked = {}
}

local function now_iso8601()
    return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function log_line(msg)
    io.stdout:write(msg .. "\n")
    io.stdout:flush()
end

local function log_request(source, method, params, rpc_id)
    local source_tag = (source == "blocked") and "BLOCKED RECORD" or "BACKEND PROCESSING"
    log_line(string.rep("=", 60))
    log_line(source_tag)
    log_line("    Source: " .. source)
    log_line("    Method: " .. tostring(method))

    local ok, params_json = pcall(cjson.encode, params or {})
    if not ok then
        params_json = "[]"
    end
    if #params_json > 300 then
        params_json = params_json:sub(1, 300)
    end
    log_line("    Params: " .. params_json)
    log_line("    ID: " .. tostring(rpc_id))
    log_line(string.rep("=", 60))
end

local function append_stats(source, method, params, client_ip)
    local target = source == "blocked" and stats.blocked or stats.allowed
    target[#target + 1] = {
        timestamp = now_iso8601(),
        method = method,
        params = params,
        client_ip = client_ip
    }
end

local function handle_rpc_request(req, source, client_ip)
    local method = (type(req) == "table" and req.method) or "unknown"
    local rpc_id = (type(req) == "table" and req.id) or 1
    local params = (type(req) == "table" and req.params) or {}

    log_request(source, method, params, rpc_id)
    append_stats(source, method, params, client_ip)

    if method == "eth_blockNumber" then
        return {jsonrpc = "2.0", id = rpc_id, result = "0x10d4f"}
    elseif method == "net_version" then
        return {jsonrpc = "2.0", id = rpc_id, result = "1337"}
    elseif method == "eth_chainId" then
        return {jsonrpc = "2.0", id = rpc_id, result = "0x539"}
    elseif method == "eth_getBalance" then
        return {jsonrpc = "2.0", id = rpc_id, result = "0x0"}
    elseif method == "eth_call" or method == "eth_getLogs" or method == "eth_getTransactionCount" then
        return {jsonrpc = "2.0", id = rpc_id, result = "0x"}
    elseif method == "eth_gasPrice" then
        return {jsonrpc = "2.0", id = rpc_id, result = "0x4A817C800"}
    end

    return {jsonrpc = "2.0", id = rpc_id, result = cjson.null}
end

local function send_response(client, code, body, content_type)
    local reason = {
        [200] = "OK",
        [400] = "Bad Request",
        [404] = "Not Found",
        [405] = "Method Not Allowed",
        [500] = "Internal Server Error"
    }

    local payload = body or ""
    local status_text = reason[code] or "OK"

    client:send(string.format("HTTP/1.1 %d %s\r\n", code, status_text))
    client:send(string.format("Content-Type: %s\r\n", content_type or "application/json"))
    client:send(string.format("Content-Length: %d\r\n", #payload))
    client:send("Connection: close\r\n")
    client:send("\r\n")
    client:send(payload)
end

local function read_request(client)
    local request_line = client:receive("*l")
    if not request_line then
        return nil
    end

    local method, target = request_line:match("^(%S+)%s+(%S+)%s+HTTP/%d%.%d$")
    if not method then
        return nil
    end

    local headers = {}
    while true do
        local line = client:receive("*l")
        if not line or line == "" then break end
        local k, v = line:match("^([^:]+):%s*(.*)$")
        if k then headers[k:lower()] = v end
    end

    local content_length = tonumber(headers["content-length"] or "0") or 0
    local body = ""
    if content_length > 0 then
        local chunk, err, partial = client:receive(content_length)
        body = chunk or partial or ""
        if err and err ~= "closed" then
            return nil
        end
    end

    local path = target:match("^[^?]+") or target
    return {
        method = method,
        path = path,
        body = body
    }
end

local function last_n(input, n)
    local out = {}
    local start = math.max(1, #input - n + 1)
    for i = start, #input do
        out[#out + 1] = input[i]
    end
    return out
end

local function handle_get(path)
    if path == "/health" then
        return 200, "OK", "text/plain"
    elseif path == "/stats" then
        local payload = cjson.encode({
            allowed_count = #stats.allowed,
            blocked_count = #stats.blocked,
            recent_blocked = last_n(stats.blocked, 10),
            recent_allowed = last_n(stats.allowed, 10)
        })
        return 200, payload, "application/json"
    elseif path == "/blocked" then
        return 200, cjson.encode(stats.blocked), "application/json"
    elseif path == "/allowed" then
        return 200, cjson.encode(stats.allowed), "application/json"
    end
    return 404, "", "text/plain"
end

local function handle_post(path, body, client_ip)
    if path == "/blocked" then
        local ok, decoded = pcall(cjson.decode, body)
        if not ok then
            return 200, cjson.encode({status = "error", message = "invalid json"}), "application/json"
        end

        if type(decoded) == "table" and decoded[1] then
            for _, req in ipairs(decoded) do
                handle_rpc_request(req, "blocked", client_ip)
            end
            return 200, cjson.encode({status = "recorded", count = #decoded}), "application/json"
        else
            handle_rpc_request(decoded, "blocked", client_ip)
            return 200, cjson.encode({status = "recorded"}), "application/json"
        end
    end

    local ok, rpc_data = pcall(cjson.decode, body)
    if not ok then
        return 200, cjson.encode({
            jsonrpc = "2.0",
            id = 1,
            error = {code = -32700, message = "Parse error"}
        }), "application/json"
    end

    if type(rpc_data) == "table" and rpc_data[1] then
        local responses = {}
        for _, req in ipairs(rpc_data) do
            responses[#responses + 1] = handle_rpc_request(req, "direct", client_ip)
        end
        if #responses == 1 then
            return 200, cjson.encode(responses[1]), "application/json"
        end
        return 200, cjson.encode(responses), "application/json"
    end

    local response = handle_rpc_request(rpc_data, "direct", client_ip)
    return 200, cjson.encode(response), "application/json"
end

local function run_server(port)
    local server = assert(socket.bind("*", port))
    log_line("Mock RPC Lua Server running on port " .. port)
    log_line("Endpoints:")
    log_line("  POST /          - Normal RPC requests (allowed)")
    log_line("  POST /blocked   - Record blocked requests")
    log_line("  GET  /health    - Health check")
    log_line("  GET  /stats     - Statistics")
    log_line("  GET  /blocked   - View blocked records (JSON)")
    log_line("  GET  /allowed   - View allowed records (JSON)")
    log_line(string.rep("-", 50))

    while true do
        local client = server:accept()
        if client then
            client:settimeout(2)
            local req = read_request(client)
            if req then
                local ip = client:getpeername() or "unknown"
                local code, body, content_type
                if req.method == "GET" then
                    code, body, content_type = handle_get(req.path)
                elseif req.method == "POST" then
                    code, body, content_type = handle_post(req.path, req.body, ip)
                else
                    code, body, content_type = 405, "", "text/plain"
                end
                send_response(client, code, body, content_type)
            end
            client:close()
        end
    end
end

local port = tonumber(arg[1]) or 8545
run_server(port)
