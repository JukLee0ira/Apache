-- rpc_proxy.lua - Ethereum RPC Proxy + Whitelist Filtering
-- Verify requests -> Record logs -> Allow or block
-- Blocked requests also notify Mock Server to record

local whitelist_path = "/etc/apache2/config/whitelist.json"
local whitelist = nil

-- Get timestamp
local function get_timestamp()
    local f = io.popen("date '+%Y-%m-%d %H:%M:%S'")
    local ts = f:read("*all"):gsub("%s+$", "")
    f:close()
    return ts
end

-- Load whitelist
function load_whitelist()
    if whitelist then return whitelist end

    local f = io.open(whitelist_path, "r")
    if not f then
        return nil
    end

    local data = f:read("*all")
    f:close()

    local ok, wl = pcall(require("cjson").decode, data)
    if ok then
        whitelist = wl
    end
    return whitelist
end

-- Check address whitelist
function check_address(addr)
    local wl = load_whitelist()
    if not wl or not wl.allowed_addresses then return false end
    addr = addr:lower()
    for _, a in ipairs(wl.allowed_addresses) do
        if a:lower() == addr then return true end
    end
    return false
end

-- Check method whitelist
function check_method(method)
    local wl = load_whitelist()
    if not wl or not wl.allowed_methods then return false end
    for _, m in ipairs(wl.allowed_methods) do
        if m == method then return true end
    end
    return false
end

-- ============ RLP Decoder for eth_sendRawTransaction ============

local function hex_to_bytes(hex)
    if hex:sub(1, 2) == "0x" or hex:sub(1, 2) == "0X" then hex = hex:sub(3) end
    local bytes = {}
    for i = 1, #hex, 2 do
        local v = tonumber(hex:sub(i, i + 1), 16)
        if not v then return nil end
        bytes[#bytes + 1] = v
    end
    return bytes
end

local function read_uint(bytes, pos, len)
    if len <= 0 then return nil end
    if pos + len - 1 > #bytes then return nil end
    local n = 0
    for i = pos, pos + len - 1 do n = n * 256 + (bytes[i] or 0) end
    return n
end

local function rlp_decode_item(bytes, pos)
    local first = bytes[pos]
    if not first then return nil, pos end

    if first < 0x80 then
        return {_t = "bytes", d = {first}}, pos + 1

    elseif first <= 0xb7 then
        local len = first - 0x80
        if pos + len > #bytes then return nil, pos end
        local d = {}
        for i = pos + 1, pos + len do d[#d + 1] = bytes[i] end
        return {_t = "bytes", d = d}, pos + 1 + len

    elseif first <= 0xbf then
        local lb = first - 0xb7
        if pos + lb > #bytes then return nil, pos end
        local len = read_uint(bytes, pos + 1, lb)
        if not len then return nil, pos end
        local data_start = pos + 1 + lb
        local data_end = data_start + len - 1
        if data_end > #bytes then return nil, pos end
        local d = {}
        for i = data_start, data_end do d[#d + 1] = bytes[i] end
        return {_t = "bytes", d = d}, pos + 1 + lb + len

    elseif first <= 0xf7 then
        local total_len = first - 0xc0
        if pos + total_len > #bytes then return nil, pos end
        local items, cur = {}, pos + 1
        local end_pos = pos + 1 + total_len
        while cur < end_pos do
            local item, np = rlp_decode_item(bytes, cur)
            if not item or not np or np <= cur or np > end_pos then return nil, pos end
            items[#items + 1] = item; cur = np
        end
        if cur ~= end_pos then return nil, pos end
        return {_t = "list", items = items}, end_pos

    else
        local lb = first - 0xf7
        if pos + lb > #bytes then return nil, pos end
        local total_len = read_uint(bytes, pos + 1, lb)
        if not total_len then return nil, pos end
        local items, cur = {}, pos + 1 + lb
        local end_pos = cur + total_len
        if end_pos - 1 > #bytes then return nil, pos end
        while cur < end_pos do
            local item, np = rlp_decode_item(bytes, cur)
            if not item or not np or np <= cur or np > end_pos then return nil, pos end
            items[#items + 1] = item; cur = np
        end
        if cur ~= end_pos then return nil, pos end
        return {_t = "list", items = items}, end_pos
    end
end

local function bytes_to_hex_str(d)
    if not d or #d == 0 then return "0x" end
    local s = "0x"
    for _, b in ipairs(d) do s = s .. string.format("%02x", b) end
    return s
end

-- Parse eth_sendRawTransaction hex param.
-- Supports legacy (type 0), EIP-2930 (type 1), EIP-1559 (type 2).
-- Returns {to, data, tx_type} or nil, err.
-- NOTE: `from` address recovery requires secp256k1 ecrecover and is not
-- implemented in pure Lua. Validate `from` via an off-chain service if needed.
function parse_raw_transaction(raw_hex)
    if type(raw_hex) ~= "string" then
        return nil, "param must be a hex string"
    end
    if raw_hex == "" then
        return nil, "empty raw transaction"
    end
    if not raw_hex:match("^0[xX][0-9a-fA-F]+$") then
        return nil, "invalid hex encoding"
    end
    local payload = raw_hex:sub(3)
    if #payload % 2 ~= 0 then
        return nil, "hex length must be even"
    end
    local bytes = hex_to_bytes(raw_hex)
    if not bytes or #bytes == 0 then
        return nil, "invalid hex encoding"
    end

    local tx_type, start_pos = 0, 1
    if bytes[1] < 0x80 then
        if bytes[1] == 0x01 then
            tx_type = 1
            start_pos = 2
        elseif bytes[1] == 0x02 then
            tx_type = 2
            start_pos = 2
        else
            return nil, "unsupported transaction type"
        end
    end

    local decoded, end_pos = rlp_decode_item(bytes, start_pos)
    if not decoded or decoded._t ~= "list" then
        return nil, "RLP decode failed: not a transaction list"
    end
    if not end_pos or end_pos ~= #bytes + 1 then
        return nil, "RLP decode failed: trailing or truncated bytes"
    end

    -- `to` field index (1-based):
    -- legacy (0): [nonce, gasPrice, gasLimit, TO, value, data, v, r, s]
    -- EIP-2930 (1): [chainId, nonce, gasPrice, gasLimit, TO, value, data, ...]
    -- EIP-1559 (2): [chainId, nonce, maxPriorityFee, maxFee, gasLimit, TO, value, data, ...]
    local to_idx, data_idx
    if tx_type == 0 then
        to_idx = 4; data_idx = 6
    elseif tx_type == 1 then
        to_idx = 5; data_idx = 7
    else
        to_idx = 6; data_idx = 8
    end

    local to_item   = decoded.items[to_idx]
    local data_item = decoded.items[data_idx]
    if not to_item or to_item._t ~= "bytes" then
        return nil, "missing to field"
    end
    if #to_item.d ~= 20 then
        return nil, "invalid to field length"
    end

    local to_addr = bytes_to_hex_str(to_item.d)

    local tx_data = nil
    if not data_item or data_item._t ~= "bytes" then
        return nil, "missing data field"
    end
    if data_item and data_item._t == "bytes" then
        tx_data = bytes_to_hex_str(data_item.d)
    end

    return {to = to_addr, data = tx_data, tx_type = tx_type}
end

-- Validate single request
function validate(rpc)
    local method = rpc.method
    if not method then
        return false, "Missing method field"
    end

    if not check_method(method) then
        return false, "Method not allowed: " .. method
    end

    local params = rpc.params or {}

    if method == "eth_call" then
        local obj = params[1]
        if obj and obj.to then
            if not check_address(obj.to) then
                return false, "Contract address not allowed: " .. obj.to
            end
        end

    elseif method == "eth_getLogs" then
        local filter = params[1]
        if filter then
            local addr = filter.address
            if addr then
                if type(addr) == "string" then
                    if not check_address(addr) then
                        return false, "Contract address not allowed: " .. addr
                    end
                elseif type(addr) == "table" then
                    for _, a in ipairs(addr) do
                        if not check_address(a) then
                            return false, "Contract address not allowed: " .. a
                        end
                    end
                end
            end
        end

    elseif method == "eth_sendRawTransaction" then
        local raw_hex = params[1]
        if not raw_hex then
            return false, "eth_sendRawTransaction requires a hex-encoded signed transaction param"
        end
        local tx, err = parse_raw_transaction(raw_hex)
        if not tx then
            return false, "Invalid raw transaction: " .. (err or "decode error")
        end
        if not tx.to then
            return false, "Invalid raw transaction: missing to address"
        end
        if not check_address(tx.to) then
            return false, "To address not allowed: " .. tx.to
        end
    end

    return true, nil
end

-- Record blocking event to backend
function record_blocked(rpc, client_ip, err)
    local record = {
        type = "blocked",
        timestamp = get_timestamp(),
        client_ip = client_ip,
        error = err,
        method = rpc.method,
        params = rpc.params
    }

    local cjson = require("cjson")
    local data = cjson.encode(record)

    -- Asynchronously send to mock server /blocked endpoint
    local escaped = data:gsub("'", "'\"'\"'")
    local cmd = string.format(
        "curl -s -X POST -H 'Content-Type: application/json' --data '%s' http://rpc-backend:8545/blocked > /dev/null 2>&1 &",
        escaped
    )
    os.execute(cmd)
end

-- Apache main handler
function rpc(r)
    local client_ip = r.useragent_ip or "unknown"
    if r.connection and r.connection.client_ip then
        client_ip = r.connection.client_ip
    end
    local timestamp = get_timestamp()

    if r.method ~= "POST" then
        r.status = 405
        r:puts('{"error":"Method Not Allowed"}')
        return apache2.OK
    end

    local body = r:requestbody()
    if not body or body == "" then
        r.status = 400
        r:puts('{"jsonrpc":"2.0","error":{"code":-32700,"message":"Empty body"}}')
        return apache2.OK
    end

    local cjson = require("cjson")
    local ok, rpc_data = pcall(cjson.decode, body)
    if not ok then
        r.status = 400
        r:puts('{"jsonrpc":"2.0","error":{"code":-32700,"message":"Invalid JSON"}}')
        return apache2.OK
    end

    -- Handle batch requests
    if type(rpc_data) == "table" and rpc_data[1] then
        local valid = true
        for i, req in ipairs(rpc_data) do
            local v, err = validate(req)
            if not v then
                valid = false
                -- Record each blocked request
                record_blocked(req, client_ip, err)
            end
        end

        if not valid then
            r.status = 403
            r:puts('{"jsonrpc":"2.0","error":{"code":-32000,"message":"Batch request contains invalid requests"}}')
            return apache2.OK
        end

    else
        local valid, err = validate(rpc_data)

        if not valid then
            record_blocked(rpc_data, client_ip, err)
            r.status = 403
            r:puts('{"jsonrpc":"2.0","error":{"code":-32000,"message":"' .. err .. '"}}')
            return apache2.OK
        end
    end

    -- Forward to backend
    local escaped_body = body:gsub("'", "'\"'\"'")
    local cmd = string.format(
        "curl -s -X POST -H 'Content-Type: application/json' --data '%s' http://rpc-backend:8545/",
        escaped_body
    )
    local result = io.popen(cmd):read("*all")

    r.content_type = "application/json"
    r:puts(result)
    return apache2.OK
end
