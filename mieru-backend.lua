-- file: lua/mieru-backend.lua
-- Shadowrocket lua-backend adapter for mieru TCP protocol.

local backend = require 'backend'
local core = require 'mieru-core'

local ADDRESS = backend.ADDRESS
local RESULT = backend.RESULT

local SUCCESS = RESULT.SUCCESS
local HANDSHAKE = RESULT.HANDSHAKE
local ERROR = RESULT.ERROR
local IGNORE = RESULT.IGNORE

local ctx_uuid = backend.get_uuid
local ctx_address_type = backend.get_address_type
local ctx_address_host = backend.get_address_host
local ctx_address_bytes = backend.get_address_bytes
local ctx_address_port = backend.get_address_port
local ctx_write = backend.write
local ctx_free = backend.free
local ctx_debug = backend.debug

local states = {}

local function truthy(v)
    if v == true then return true end
    if v == false or v == nil then return false end
    local s = tostring(v):lower()
    return s == '1' or s == 'true' or s == 'yes' or s == 'on'
end

local function get_username()
    if settings.username and settings.username ~= '' then
        return settings.username
    end
    if settings.name and settings.name ~= '' then
        return settings.name
    end
    if settings.user and settings.user ~= '' then
        return settings.user
    end
    return ''
end

local function to_socks_atype(atype, addr_bytes)
    if atype == ADDRESS.DOMAIN then
        return 0x03
    end
    if #addr_bytes == 16 then
        return 0x04
    end
    return 0x01
end

local function get_or_create_state(ctx)
    local uuid = ctx_uuid(ctx)
    local st = states[uuid]
    if st then
        return st
    end

    local username = get_username()
    local password = settings.password or ''
    local debug_on = truthy(settings.debug)
    local debug_cb = nil
    if debug_on then
        debug_cb = function(msg)
            ctx_debug(msg)
        end
    end

    st = {
        c = core.new_client({
            username = username,
            password = password,
            protocol_version = settings.protocol_version or settings.version or settings.mieru_version,
            time_offset_sec = settings.time_offset_sec,
            debug_cb = debug_cb,
        }),
        started = false,
        handshake_notified = false,
        pending_plain = '',
        closed = false,
    }
    states[uuid] = st
    return st
end

function wa_lua_on_flags_cb(_)
    return 0
end

function wa_lua_on_handshake_cb(ctx)
    local st = get_or_create_state(ctx)

    if core.is_established(st.c) then
        return true
    end

    if not st.started then
        local atype = ctx_address_type(ctx)
        local host = ctx_address_host(ctx) or ''
        local addr_bytes = ctx_address_bytes(ctx) or ''
        local port = ctx_address_port(ctx)

        local socks_atype = to_socks_atype(atype, addr_bytes)
        local socks_req = core.socks5_connect_request(socks_atype, host, addr_bytes, port)
        local pkt = core.begin_handshake(st.c, socks_req)
        ctx_write(ctx, pkt)
        st.started = true
    end

    return core.is_established(st.c)
end

function wa_lua_on_read_cb(ctx, buf)
    local st = get_or_create_state(ctx)

    local plain, err = core.feed_encrypted(st.c, buf)
    if err then
        ctx_debug('[mieru] read error: ' .. tostring(err))
        return ERROR, nil
    end

    if core.is_established(st.c) and not st.handshake_notified then
        st.handshake_notified = true
        if plain and #plain > 0 then
            st.pending_plain = st.pending_plain .. plain
        end
        return HANDSHAKE, nil
    end

    if not core.is_established(st.c) then
        return HANDSHAKE, nil
    end

    if #st.pending_plain > 0 then
        plain = st.pending_plain .. (plain or '')
        st.pending_plain = ''
    end

    if plain and #plain > 0 then
        return SUCCESS, plain
    end
    return IGNORE, nil
end

function wa_lua_on_write_cb(ctx, buf)
    local st = get_or_create_state(ctx)
    if not core.is_established(st.c) then
        return IGNORE, nil
    end

    local pkt = core.wrap_app_data(st.c, buf)
    return SUCCESS, pkt
end

function wa_lua_on_close_cb(ctx)
    local uuid = ctx_uuid(ctx)
    local st = states[uuid]
    if st and not st.closed then
        st.closed = true
        if st.started then
            local ok, close_pkt = pcall(core.build_close, st.c)
            if ok and close_pkt and #close_pkt > 0 then
                pcall(ctx_write, ctx, close_pkt)
            end
        end
    end

    states[uuid] = nil
    ctx_free(ctx)
    return SUCCESS
end
