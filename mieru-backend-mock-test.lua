local socket = require 'socket'

package.path = './?.lua;./lua-backend/?.lua;' .. package.path

local USAGE = 'Usage: lua mieru-backend-mock-test.lua <host> <port> <username> <password> [script_path] [protocol_version] [time_offset_sec]'

settings = {
    username = arg[3] or error(USAGE),
    password = arg[4] or error(USAGE),
    debug = 'true',
    protocol_version = arg[6] or 'v3',
    time_offset_sec = arg[7] or '0',
}

if settings.protocol_version ~= 'v3' and settings.protocol_version ~= '3' then
    error('unsupported protocol_version "' .. tostring(settings.protocol_version) .. '" (only v3 is supported)')
end

package.preload['backend'] = function()
    local b = {}
    b.ADDRESS = {
        DOMAIN = 3,
    }
    b.RESULT = {
        SUCCESS = 0,
        HANDSHAKE = 1,
        ERROR = 2,
        IGNORE = 3,
    }

    b.get_uuid = function(ctx) return ctx.uuid end
    b.get_address_type = function(ctx) return ctx.atype end
    b.get_address_host = function(ctx) return ctx.host end
    b.get_address_bytes = function(ctx) return ctx.addr_bytes end
    b.get_address_port = function(ctx) return ctx.port end
    b.write = function(ctx, data)
        local ok, err = ctx.sock:send(data)
        if not ok then
            error('backend.write failed: ' .. tostring(err))
        end
    end
    b.free = function(_) end
    b.debug = function(msg)
        io.stdout:write('[mock-debug] ' .. tostring(msg) .. '\n')
    end

    return b
end

local server_host = arg[1] or '127.0.0.1'
local server_port = tonumber(arg[2] or '10910')
local script_path = arg[5] or 'mieru-backend.lua'

dofile(script_path)

local sock = assert(socket.tcp())
assert(sock:connect(server_host, server_port))

local ctx = {
    uuid = 'mock-ctx-1',
    atype = 3,
    host = 'example.com',
    addr_bytes = '',
    port = 80,
    sock = sock,
}

local function recv_loop(seconds, on_chunk)
    sock:settimeout(0)
    local deadline = socket.gettime() + seconds
    while socket.gettime() < deadline do
        local rd = socket.select({sock}, nil, 0.2)
        if #rd > 0 then
            local data, err, partial = sock:receive(4096)
            local chunk = data or partial
            if chunk and #chunk > 0 then
                local stop = on_chunk(chunk)
                if stop then return true end
            elseif err == 'closed' then
                return false
            end
        end
    end
    return false
end

wa_lua_on_flags_cb(settings)

local established = wa_lua_on_handshake_cb(ctx)
if established then
    error('unexpected immediate established')
end

local hs_ok = recv_loop(10, function(chunk)
    local code, plain = wa_lua_on_read_cb(ctx, chunk)
    if code == 2 then
        error('on_read returned ERROR during handshake')
    end
    if code == 1 then
        if wa_lua_on_handshake_cb(ctx) then
            return true
        end
    elseif code == 0 and plain and #plain > 0 then
        return true
    end
    return false
end)

if not hs_ok then
    error('handshake did not complete in time')
end

local req = 'GET / HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\n\r\n'
local code, wrapped = wa_lua_on_write_cb(ctx, req)
if code ~= 0 or not wrapped then
    error('on_write failed')
end
assert(sock:send(wrapped))

local plain_buf = {}
recv_loop(12, function(chunk)
    local rcode, out = wa_lua_on_read_cb(ctx, chunk)
    if rcode == 2 then
        error('on_read returned ERROR during data phase')
    end
    if rcode == 0 and out and #out > 0 then
        plain_buf[#plain_buf + 1] = out
        if table.concat(plain_buf):find('\r\n\r\n', 1, true) then
            return true
        end
    end
    return false
end)

local payload = table.concat(plain_buf)
if #payload == 0 then
    error('no plaintext returned by backend callbacks')
end

print(payload:sub(1, 240))
if not payload:find('HTTP/', 1, true) then
    error('mock backend test failed: no HTTP response')
end
print('[mock-test] TEST_PASS')

pcall(function() wa_lua_on_close_cb(ctx) end)
pcall(function() sock:close() end)
