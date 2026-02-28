-- file: lua/mieru-backend-diagnostic.lua
-- Diagnostic variant of mieru backend for Shadowrocket.

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

local function user_name()
    if settings.username and settings.username ~= '' then return settings.username end
    if settings.name and settings.name ~= '' then return settings.name end
    if settings.user and settings.user ~= '' then return settings.user end
    return ''
end

local function socks_atype(atype, addr_bytes)
    if atype == ADDRESS.DOMAIN then return 0x03 end
    if #addr_bytes == 16 then return 0x04 end
    return 0x01
end

local function snapshot_str(st)
    local x = core.debug_snapshot(st.c)
    return string.format('stage=%s established=%s send_seq=%d recv_seq=%d version=%s mode=%s nonce=%s sid=%u rx_buf=%d',
        tostring(x.stage), tostring(x.established), x.send_seq, x.recv_seq,
        tostring(x.protocol_version), tostring(x.aead_mode), tostring(x.nonce_size),
        x.session_id, x.rx_buf_len)
end

local function get_or_create(ctx)
    local uuid = ctx_uuid(ctx)
    local st = states[uuid]
    if st then return st end

    local debug_on = true
    local function dbg(msg)
        if debug_on then
            ctx_debug('[mieru-diag][' .. tostring(uuid) .. '] ' .. msg)
        end
    end

    st = {
        c = core.new_client({
            username = user_name(),
            password = settings.password or '',
            protocol_version = settings.protocol_version or settings.version or settings.mieru_version,
            time_offset_sec = settings.time_offset_sec,
            debug_cb = dbg,
        }),
        started = false,
        handshake_notified = false,
        pending_plain = '',
        closed = false,
        dbg = dbg,
    }
    st.dbg('created; ' .. snapshot_str(st))
    states[uuid] = st
    return st
end

function wa_lua_on_flags_cb(_)
    return 0
end

function wa_lua_on_handshake_cb(ctx)
    local st = get_or_create(ctx)
    st.dbg('on_handshake begin; ' .. snapshot_str(st))

    if core.is_established(st.c) then
        st.dbg('on_handshake done (already established)')
        return true
    end

    if not st.started then
        local atype = ctx_address_type(ctx)
        local host = ctx_address_host(ctx) or ''
        local addr = ctx_address_bytes(ctx) or ''
        local port = ctx_address_port(ctx)
        local req = core.socks5_connect_request(socks_atype(atype, addr), host, addr, port)
        local pkt = core.begin_handshake(st.c, req)
        ctx_write(ctx, pkt)
        st.started = true
        st.dbg(string.format('sent handshake bytes=%d dst=%s:%d atyp=%d', #pkt, host, port, atype))
    end

    local ok = core.is_established(st.c)
    st.dbg('on_handshake end established=' .. tostring(ok))
    return ok
end

function wa_lua_on_read_cb(ctx, buf)
    local st = get_or_create(ctx)
    st.dbg('on_read encrypted_len=' .. tostring(#buf))

    local plain, err = core.feed_encrypted(st.c, buf)
    if err then
        st.dbg('on_read error=' .. tostring(err) .. '; ' .. snapshot_str(st))
        return ERROR, nil
    end

    if core.is_established(st.c) and not st.handshake_notified then
        st.handshake_notified = true
        if plain and #plain > 0 then
            st.pending_plain = st.pending_plain .. plain
        end
        st.dbg('on_read handshake complete; pending_plain=' .. tostring(#st.pending_plain))
        return HANDSHAKE, nil
    end

    if not core.is_established(st.c) then
        st.dbg('on_read waiting handshake; ' .. snapshot_str(st))
        return HANDSHAKE, nil
    end

    if #st.pending_plain > 0 then
        plain = st.pending_plain .. (plain or '')
        st.pending_plain = ''
    end

    if plain and #plain > 0 then
        st.dbg('on_read plain_len=' .. tostring(#plain))
        return SUCCESS, plain
    end

    st.dbg('on_read no-plain; ' .. snapshot_str(st))
    return IGNORE, nil
end

function wa_lua_on_write_cb(ctx, buf)
    local st = get_or_create(ctx)
    st.dbg('on_write plain_len=' .. tostring(#buf) .. '; ' .. snapshot_str(st))

    if not core.is_established(st.c) then
        st.dbg('on_write ignored (not established)')
        return IGNORE, nil
    end

    local pkt = core.wrap_app_data(st.c, buf)
    st.dbg('on_write wrapped_len=' .. tostring(#pkt))
    return SUCCESS, pkt
end

function wa_lua_on_close_cb(ctx)
    local uuid = ctx_uuid(ctx)
    local st = states[uuid]
    if st and not st.closed then
        st.closed = true
        st.dbg('on_close; ' .. snapshot_str(st))
        if st.started then
            local ok, pkt = pcall(core.build_close, st.c)
            if ok and pkt and #pkt > 0 then
                pcall(ctx_write, ctx, pkt)
                st.dbg('sent close packet len=' .. tostring(#pkt))
            end
        end
    end
    states[uuid] = nil
    ctx_free(ctx)
    return SUCCESS
end
