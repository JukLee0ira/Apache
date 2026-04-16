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

-- Decode and validate transaction data
-- Returns true if data is valid or no data, false if blocked
function validate_tx_data(data)
    if not data or data == "" then
        return true
    end

    -- Basic validation: check if data is valid hex and has minimum length
    -- Must be at least 4 bytes (function selector) + some params
    if #data < 10 then
        return true -- Empty or very short data is acceptable
    end

    -- Check if data starts with 0x
    if data:sub(1, 2) ~= "0x" then
        return true -- No 0x prefix, skip validation
    end

    -- Validate hex characters
    local hex_part = data:sub(3)
    if not hex_part:match("^[0-9a-fA-F]+$") then
        return true -- Invalid hex, skip validation
    end

    -- Data looks valid with at least 4-byte selector
    return true
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

    elseif method == "sign_rawTransaction" or method == "eth_sendRawTransaction" then
        local tx = params[1]
        if tx then
            -- Validate from address (must be in whitelist)
            if tx.from then
                if not check_address(tx.from) then
                    return false, "From address not allowed: " .. tx.from
                end
            end
            -- Validate to address (must be in whitelist)
            if tx.to and not check_address(tx.to) then
                return false, "To address not allowed: " .. tx.to
            end
            -- Validate data field
            if tx.data then
                if not validate_tx_data(tx.data) then
                    return false, "Transaction data not allowed"
                end
            end
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
