-- validate_rpc.lua - Ethereum JSON-RPC Request Validation Script
-- Uses Apache LuaHookPostReadRequest hook for request interception

local whitelist_path = "/etc/apache2/config/whitelist.json"
local whitelist = nil

-- Apache log function
local function log_msg(r, msg)
    r:log_error("[RPC-FILTER] " .. msg)
end

-- Read whitelist configuration
local function read_whitelist()
    if whitelist then return whitelist end

    local f = io.open(whitelist_path, "r")
    if not f then
        log_msg(r, "Cannot open whitelist file: " .. whitelist_path)
        return nil
    end

    local content = f:read("*all")
    f:close()

    local ok, data = pcall(require("cjson").decode, content)
    if not ok then
        log_msg(r, "Whitelist JSON parse failed: " .. tostring(data))
        return nil
    end

    whitelist = data
    return whitelist
end

-- Check if address is in whitelist
local function is_address_allowed(address)
    if not address then return false end
    local wl = read_whitelist()
    if not wl or not wl.allowed_addresses then return false end

    for _, addr in ipairs(wl.allowed_addresses) do
        if addr:lower() == address:lower() then
            return true
        end
    end
    return false
end

-- Check if method is in whitelist
local function is_method_allowed(method)
    if not method then return false end
    local wl = read_whitelist()
    if not wl or not wl.allowed_methods then return false end

    for _, m in ipairs(wl.allowed_methods) do
        if m == method then
            return true
        end
    end
    return false
end

-- Validate single RPC request
local function validate_single_request(r, rpc_obj)
    local method = rpc_obj.method
    local params = rpc_obj.params or {}

    -- Check method
    if not is_method_allowed(method) then
        return false, "Method not in whitelist: " .. tostring(method)
    end

    -- eth_call - Check target address
    if method == "eth_call" then
        local call_obj = params[1]
        if call_obj and call_obj.to then
            if not is_address_allowed(call_obj.to) then
                return false, "Address not in whitelist: " .. call_obj.to
            end
        end

    -- eth_getLogs - Check address and topics
    elseif method == "eth_getLogs" then
        local filter = params[1]
        if filter then
            local addresses = filter.address
            if addresses then
                if type(addresses) == "string" then
                    if not is_address_allowed(addresses) then
                        return false, "Address not in whitelist: " .. addresses
                    end
                elseif type(addresses) == "table" then
                    for _, addr in ipairs(addresses) do
                        if not is_address_allowed(addr) then
                            return false, "Address not in whitelist: " .. addr
                        end
                    end
                end
            end
        end
    end

    return true, nil
end

-- Generate error response
local function send_error_response(r, code, message)
    r.status = code
    r:err_headers_out()["Content-Type"] = "application/json"
    local resp = string.format('{"jsonrpc":"2.0","error":{"code":%d,"message":"%s"}}', code, message)
    r:puts(resp)
    return true
end

-- Apache hook entry point
function validate_request(r)
    -- Only handle POST requests
    if r.method ~= "POST" then
        return apache2.DECLINED
    end

    -- Read request body
    local data = r:read()
    if not data or data == "" then
        return apache2.DECLINED
    end

    -- Parse JSON
    local cjson = require("cjson")
    local ok, rpc_obj = pcall(cjson.decode, data)
    if not ok then
        log_msg(r, "JSON parse failed")
        r.status = 400
        r:puts('{"jsonrpc":"2.0","error":{"code":-32700,"message":"Parse error"}}')
        return apache2.OK
    end

    -- Validate request
    local valid, err_msg

    if type(rpc_obj) == "table" and rpc_obj[1] then
        -- Batch request
        for i, req in ipairs(rpc_obj) do
            valid, err_msg = validate_single_request(r, req)
            if not valid then
                log_msg(r, string.format("Batch request #%d validation failed: %s", i, err_msg))
                break
            end
        end
    else
        -- Single request
        valid, err_msg = validate_single_request(r, rpc_obj)
    end

    if not valid then
        log_msg(r, "Request blocked: " .. tostring(err_msg))
        r.status = 403
        r:puts('{"jsonrpc":"2.0","error":{"code":-32000,"message":"' .. tostring(err_msg) .. '"}}')
        return apache2.OK
    end

    log_msg(r, "Validation passed, allowing request")

    -- Store original request body in notes for subsequent processing
    r:set PassengerTempData(data)

    return apache2.DECLINED
end
