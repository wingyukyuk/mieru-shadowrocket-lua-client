local socket = require 'socket'
package.path = './?.lua;./lua-backend/?.lua;' .. package.path
local core = require 'mieru-core'

local USAGE = 'Usage: lua mieru-standalone-test.lua <host> <port> <username> <password> [target_host] [target_port] [protocol_version] [time_offset_sec]'

local server_host = arg[1] or error(USAGE)
local server_port = tonumber(arg[2] or error(USAGE))
local username = arg[3] or error(USAGE)
local password = arg[4] or error(USAGE)
local target_host = arg[5] or 'example.com'
local target_port = tonumber(arg[6] or '80')
local protocol_version = arg[7] or 'v3'
local time_offset_sec = tonumber(arg[8] or '0')

if protocol_version ~= 'v3' and protocol_version ~= '3' then
    error('unsupported protocol_version "' .. tostring(protocol_version) .. '" (only v3 is supported)')
end

local function log(msg)
    io.stdout:write('[test] ' .. msg .. '\n')
    io.stdout:flush()
end

local c = core.new_client({
    username = username,
    password = password,
    protocol_version = protocol_version,
    time_offset_sec = time_offset_sec,
    debug_cb = function(msg)
        log(msg)
    end,
})

log('aead_mode=' .. core.aead_mode(c))

local tcp, err = socket.tcp()
if not tcp then
    error('socket.tcp failed: ' .. tostring(err))
end

tcp:settimeout(5)
local ok, cerr = tcp:connect(server_host, server_port)
if not ok then
    error('connect failed: ' .. tostring(cerr))
end
log('connected to ' .. server_host .. ':' .. tostring(server_port))

local req = core.socks5_connect_request(0x03, target_host, '', target_port)
local handshake_pkt = core.begin_handshake(c, req)
local sent, serr = tcp:send(handshake_pkt)
if not sent then
    error('send handshake failed: ' .. tostring(serr))
end
log('sent openSessionRequest bytes=' .. tostring(#handshake_pkt))

local function recv_loop(seconds, on_chunk)
    tcp:settimeout(0)
    local deadline = socket.gettime() + seconds
    while socket.gettime() < deadline do
        local rd = socket.select({tcp}, nil, 0.2)
        if #rd > 0 then
            local data, rerr, partial = tcp:receive(4096)
            local chunk = data or partial
            if chunk and #chunk > 0 then
                local stop = on_chunk(chunk)
                if stop then
                    return true
                end
            elseif rerr == 'closed' then
                return false
            end
        end
    end
    return false
end

local established = false
local handshake_ok = recv_loop(8, function(chunk)
    local plain, perr = core.feed_encrypted(c, chunk)
    if not plain and perr then
        error('feed during handshake failed: ' .. tostring(perr))
    end
    if core.is_established(c) then
        established = true
        return true
    end
    return false
end)

if not handshake_ok or not established then
    error('handshake timeout/failure')
end
log('handshake established')

local http_req = 'GET / HTTP/1.1\r\nHost: ' .. target_host .. '\r\nConnection: close\r\n\r\n'
local wrapped = core.wrap_app_data(c, http_req)
local ws, werr = tcp:send(wrapped)
if not ws then
    error('send app data failed: ' .. tostring(werr))
end
log('sent wrapped app bytes=' .. tostring(#wrapped))

local app_data = {}
recv_loop(12, function(chunk)
    local plain, perr = core.feed_encrypted(c, chunk)
    if not plain and perr then
        error('feed app data failed: ' .. tostring(perr))
    end
    local pulled = core.pull_plaintext(c)
    if pulled and #pulled > 0 then
        app_data[#app_data + 1] = pulled
        if table.concat(app_data):find('\r\n\r\n', 1, true) then
            return true
        end
    end
    return false
end)

local payload = table.concat(app_data)
if #payload == 0 then
    error('no decrypted app payload received')
end

log('received decrypted bytes=' .. tostring(#payload))
local preview = payload:sub(1, 240)
print(preview)

if preview:find('HTTP/', 1, true) then
    log('TEST_PASS: decrypted HTTP response detected')
else
    error('TEST_FAIL: response does not look like HTTP')
end

local close_pkt = core.build_close(c)
pcall(function() tcp:send(close_pkt) end)
pcall(function() tcp:close() end)
