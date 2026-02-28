-- file: lua/mieru-backend-allinone.lua
-- Auto-generated from mieru-core.lua + mieru-backend.lua
local core = (function()
local M = {}

local floor = math.floor
local random = math.random
local min = math.min
local max = math.max
local char = string.char
local byte = string.byte
local sub = string.sub
local rep = string.rep
local concat = table.concat

local U32 = 4294967296
local bitlib = _G.bit32 or _G.bit
if not bitlib then
    local ok32, lib32 = pcall(require, 'bit32')
    if ok32 and lib32 then
        bitlib = lib32
    else
        local okb, libb = pcall(require, 'bit')
        if okb and libb then
            bitlib = libb
        end
    end
end
local band2, bor2, bxor2, bnot, lshift, rshift
local band, bor, bxor

if bitlib then
    band2 = bitlib.band
    bor2 = bitlib.bor
    bxor2 = bitlib.bxor
    bnot = bitlib.bnot
    lshift = bitlib.lshift
    rshift = bitlib.rshift
else
    local ok = pcall(load, 'return 1 & 1')
    if ok then
        band2 = assert(load('return function(a,b) return (a & b) end'))()
        bor2 = assert(load('return function(a,b) return (a | b) end'))()
        bxor2 = assert(load('return function(a,b) return (a ~ b) end'))()
        bnot = assert(load('return function(a) return (~a) end'))()
        lshift = assert(load('return function(a,b) return (a << b) end'))()
        rshift = assert(load('return function(a,b) return (a >> b) end'))()
    else
        local function norm32(n)
            n = n % U32
            if n < 0 then
                return n + U32
            end
            return n
        end
        local function bitbin2(a, b, mode)
            a = norm32(a)
            b = norm32(b)
            local out = 0
            local p = 1
            for _ = 1, 32 do
                local aa = a % 2
                local bb = b % 2
                local v = 0
                if mode == 'and' then
                    if aa == 1 and bb == 1 then v = 1 end
                elseif mode == 'or' then
                    if aa == 1 or bb == 1 then v = 1 end
                else
                    if aa ~= bb then v = 1 end
                end
                if v == 1 then
                    out = out + p
                end
                a = (a - aa) / 2
                b = (b - bb) / 2
                p = p * 2
            end
            return out
        end
        band2 = function(a, b) return bitbin2(a, b, 'and') end
        bor2 = function(a, b) return bitbin2(a, b, 'or') end
        bxor2 = function(a, b) return bitbin2(a, b, 'xor') end
        bnot = function(a) return norm32((U32 - 1) - norm32(a)) end
        lshift = function(a, b) return norm32(norm32(a) * (2 ^ b)) end
        rshift = function(a, b) return floor(norm32(a) / (2 ^ b)) end
    end
end

local function fold_bitop(fn, a, b, ...)
    if a == nil then
        return 0
    end
    if b == nil then
        return a
    end
    local res = fn(a, b)
    local n = select('#', ...)
    for i = 1, n do
        res = fn(res, select(i, ...))
    end
    return res
end

band = function(a, b, ...)
    return fold_bitop(band2, a, b, ...)
end
bor = function(a, b, ...)
    return fold_bitop(bor2, a, b, ...)
end
bxor = function(a, b, ...)
    return fold_bitop(bxor2, a, b, ...)
end

local function u32(x)
    x = x % U32
    if x < 0 then
        return x + U32
    end
    return x
end

local function rotl32(x, n)
    x = u32(x)
    return u32(bor(lshift(x, n), rshift(x, 32 - n)))
end

local function add32(a, b)
    return (a + b) % U32
end

local function add32_4(a, b, c, d)
    return (((a + b) % U32 + c) % U32 + d) % U32
end

local function be16(n)
    return char(band(rshift(n, 8), 0xff), band(n, 0xff))
end

local function be32(n)
    return char(
        band(rshift(n, 24), 0xff),
        band(rshift(n, 16), 0xff),
        band(rshift(n, 8), 0xff),
        band(n, 0xff)
    )
end

local function read_be16(s, i)
    local b1 = byte(s, i)
    local b2 = byte(s, i + 1)
    return b1 * 256 + b2
end

local function read_be32(s, i)
    local b1 = byte(s, i)
    local b2 = byte(s, i + 1)
    local b3 = byte(s, i + 2)
    local b4 = byte(s, i + 3)
    return ((b1 * 256 + b2) * 256 + b3) * 256 + b4
end

local function le32(n)
    return char(
        band(n, 0xff),
        band(rshift(n, 8), 0xff),
        band(rshift(n, 16), 0xff),
        band(rshift(n, 24), 0xff)
    )
end

local function read_le32(s, i)
    local b1 = byte(s, i)
    local b2 = byte(s, i + 1)
    local b3 = byte(s, i + 2)
    local b4 = byte(s, i + 3)
    return u32(b1 + b2 * 256 + b3 * 65536 + b4 * 16777216)
end

local function le64(n)
    local out = {}
    for i = 1, 8 do
        out[i] = char(n % 256)
        n = floor(n / 256)
    end
    return concat(out)
end

local function tohex(s, max_len)
    local n = #s
    if max_len and n > max_len then
        n = max_len
    end
    local out = {}
    for i = 1, n do
        out[i] = string.format('%02x', byte(s, i))
    end
    return concat(out)
end

local function nonce_inc_be(nonce)
    local b = {byte(nonce, 1, #nonce)}
    for i = #b, 1, -1 do
        b[i] = (b[i] + 1) % 256
        if b[i] ~= 0 then
            break
        end
    end
    local out = {}
    for i = 1, #b do
        out[i] = char(b[i])
    end
    return concat(out)
end

local rand_bytes
local urandom_ok = false
local urandom_file = io.open('/dev/urandom', 'rb')
if urandom_file then
    urandom_ok = true
end

if not urandom_ok then
    local seed = os.time()
    if os.clock then
        seed = seed + floor(os.clock() * 1000000)
    end
    local addr_hex = tostring({}):match('0x(%x+)')
    if addr_hex then
        local addr_num = tonumber(addr_hex, 16)
        if addr_num then
            seed = seed + (addr_num % 2147483647)
        end
    end
    math.randomseed(seed)
    for _ = 1, 8 do
        random()
    end
end

rand_bytes = function(n)
    if urandom_ok then
        local data = urandom_file:read(n)
        if data and #data == n then
            return data
        end
    end
    local out = {}
    for i = 1, n do
        out[i] = char(random(0, 255))
    end
    return concat(out)
end

local function new_log(debug_cb)
    if debug_cb then
        return function(msg)
            debug_cb('[mieru] ' .. msg)
        end
    end
    return function(_) end
end

local function bytes_to_u8_array(s)
    local out = {}
    for i = 1, #s do
        out[i] = byte(s, i)
    end
    return out
end

local function u8_array_to_bytes(t, n)
    local out = {}
    local lim = n or #t
    for i = 1, lim do
        out[i] = char(t[i] or 0)
    end
    return concat(out)
end

local function u8_trim(a)
    local i = #a
    while i > 0 and a[i] == 0 do
        a[i] = nil
        i = i - 1
    end
    return a
end

local function u8_clone(a)
    local b = {}
    for i = 1, #a do
        b[i] = a[i]
    end
    return b
end

local function u8_cmp(a, b)
    local la = #a
    local lb = #b
    if la ~= lb then
        return la < lb and -1 or 1
    end
    for i = la, 1, -1 do
        if a[i] ~= b[i] then
            return a[i] < b[i] and -1 or 1
        end
    end
    return 0
end

local function u8_add(a, b)
    local n = max(#a, #b)
    local out = {}
    local carry = 0
    for i = 1, n do
        local v = (a[i] or 0) + (b[i] or 0) + carry
        out[i] = v % 256
        carry = floor(v / 256)
    end
    if carry > 0 then
        out[n + 1] = carry
    end
    return u8_trim(out)
end

local function u8_sub(a, b)
    local out = {}
    local borrow = 0
    for i = 1, #a do
        local v = (a[i] or 0) - (b[i] or 0) - borrow
        if v < 0 then
            v = v + 256
            borrow = 1
        else
            borrow = 0
        end
        out[i] = v
    end
    return u8_trim(out)
end

local function u8_mul(a, b)
    if #a == 0 or #b == 0 then
        return {}
    end
    local out = {}
    for i = 1, #a + #b + 1 do
        out[i] = 0
    end
    for i = 1, #a do
        local carry = 0
        for j = 1, #b do
            local idx = i + j - 1
            local v = out[idx] + a[i] * b[j] + carry
            out[idx] = v % 256
            carry = floor(v / 256)
        end
        local k = i + #b
        while carry > 0 do
            local v = out[k] + carry
            out[k] = v % 256
            carry = floor(v / 256)
            k = k + 1
        end
    end
    return u8_trim(out)
end

local function u8_mul_small(a, n)
    if #a == 0 or n == 0 then
        return {}
    end
    local out = {}
    local carry = 0
    for i = 1, #a do
        local v = a[i] * n + carry
        out[i] = v % 256
        carry = floor(v / 256)
    end
    local idx = #a + 1
    while carry > 0 do
        out[idx] = carry % 256
        carry = floor(carry / 256)
        idx = idx + 1
    end
    return u8_trim(out)
end

local function u8_shr_bits(a, k)
    if #a == 0 then
        return {}
    end
    local out = {}
    local carry = 0
    local scale = 2 ^ k
    local carry_scale = 2 ^ (8 - k)
    for i = #a, 1, -1 do
        local cur = a[i]
        out[i] = floor(cur / scale) + carry
        carry = (cur % scale) * carry_scale
    end
    return u8_trim(out)
end

local function u8_split_130(x)
    local low = {}
    for i = 1, 16 do
        low[i] = x[i] or 0
    end
    local b17 = x[17] or 0
    local low17 = b17 % 4
    if low17 > 0 then
        low[17] = low17
    end
    low = u8_trim(low)

    local subset = {}
    for i = 17, #x do
        subset[#subset + 1] = x[i]
    end
    local high = u8_shr_bits(subset, 2)
    return low, high
end

local P1305 = {251}
for i = 2, 16 do
    P1305[i] = 255
end
P1305[17] = 3

local function mod_p1305(x)
    local v = u8_clone(x)
    while #v > 17 or ((v[17] or 0) >= 4) do
        local low, high = u8_split_130(v)
        if #high == 0 then
            v = low
            break
        end
        v = u8_add(low, u8_mul_small(high, 5))
    end
    while u8_cmp(v, P1305) >= 0 do
        v = u8_sub(v, P1305)
    end
    return v
end

local function poly1305_auth(msg, key32)
    local r = {byte(key32, 1, 16)}
    r[4] = band(r[4], 15)
    r[8] = band(r[8], 15)
    r[12] = band(r[12], 15)
    r[16] = band(r[16], 15)
    r[5] = band(r[5], 252)
    r[9] = band(r[9], 252)
    r[13] = band(r[13], 252)

    local r_int = u8_trim(r)
    local s_int = bytes_to_u8_array(sub(key32, 17, 32))
    local h = {}

    local pos = 1
    while pos <= #msg do
        local block = sub(msg, pos, pos + 15)
        local block_len = #block
        local n = bytes_to_u8_array(block)
        n[block_len + 1] = 1
        h = mod_p1305(u8_mul(u8_add(h, n), r_int))
        pos = pos + 16
    end

    local tag = u8_add(h, s_int)
    return u8_array_to_bytes(tag, 16)
end

local function qr(state, a, b, c, d)
    state[a] = add32(state[a], state[b])
    state[d] = rotl32(bxor(state[d], state[a]), 16)

    state[c] = add32(state[c], state[d])
    state[b] = rotl32(bxor(state[b], state[c]), 12)

    state[a] = add32(state[a], state[b])
    state[d] = rotl32(bxor(state[d], state[a]), 8)

    state[c] = add32(state[c], state[d])
    state[b] = rotl32(bxor(state[b], state[c]), 7)
end

local function chacha20_core(state)
    local x = {}
    for i = 1, 16 do
        x[i] = state[i]
    end

    for _ = 1, 10 do
        qr(x, 1, 5, 9, 13)
        qr(x, 2, 6, 10, 14)
        qr(x, 3, 7, 11, 15)
        qr(x, 4, 8, 12, 16)

        qr(x, 1, 6, 11, 16)
        qr(x, 2, 7, 12, 13)
        qr(x, 3, 8, 9, 14)
        qr(x, 4, 5, 10, 15)
    end

    for i = 1, 16 do
        x[i] = add32(x[i], state[i])
    end
    return x
end

local function serialize_words_le(words)
    local out = {}
    for i = 1, #words do
        out[i] = le32(words[i])
    end
    return concat(out)
end

local function chacha20_block(key32, counter, nonce12)
    local st = {
        0x61707865, 0x3320646e, 0x79622d32, 0x6b206574,
        read_le32(key32, 1),
        read_le32(key32, 5),
        read_le32(key32, 9),
        read_le32(key32, 13),
        read_le32(key32, 17),
        read_le32(key32, 21),
        read_le32(key32, 25),
        read_le32(key32, 29),
        counter,
        read_le32(nonce12, 1),
        read_le32(nonce12, 5),
        read_le32(nonce12, 9)
    }
    local out_words = chacha20_core(st)
    return serialize_words_le(out_words)
end

local function hchacha20(key32, nonce16)
    local st = {
        0x61707865, 0x3320646e, 0x79622d32, 0x6b206574,
        read_le32(key32, 1),
        read_le32(key32, 5),
        read_le32(key32, 9),
        read_le32(key32, 13),
        read_le32(key32, 17),
        read_le32(key32, 21),
        read_le32(key32, 25),
        read_le32(key32, 29),
        read_le32(nonce16, 1),
        read_le32(nonce16, 5),
        read_le32(nonce16, 9),
        read_le32(nonce16, 13)
    }

    for _ = 1, 10 do
        qr(st, 1, 5, 9, 13)
        qr(st, 2, 6, 10, 14)
        qr(st, 3, 7, 11, 15)
        qr(st, 4, 8, 12, 16)

        qr(st, 1, 6, 11, 16)
        qr(st, 2, 7, 12, 13)
        qr(st, 3, 8, 9, 14)
        qr(st, 4, 5, 10, 15)
    end

    local out = {
        st[1], st[2], st[3], st[4],
        st[13], st[14], st[15], st[16]
    }
    return serialize_words_le(out)
end

local function chacha20_xor(key32, nonce12, counter, text)
    local out = {}
    local pos = 1
    local ctr = counter
    while pos <= #text do
        local block = chacha20_block(key32, ctr, nonce12)
        local chunk = sub(text, pos, pos + 63)
        local x = {}
        for i = 1, #chunk do
            x[i] = char(bxor(byte(chunk, i), byte(block, i)))
        end
        out[#out + 1] = concat(x)
        pos = pos + #chunk
        ctr = add32(ctr, 1)
    end
    return concat(out)
end

local function xchacha20_poly1305_encrypt_lua(key32, nonce24, plaintext, aad)
    aad = aad or ''
    local subkey = hchacha20(key32, sub(nonce24, 1, 16))
    local nonce12 = '\0\0\0\0' .. sub(nonce24, 17, 24)

    local poly_key = sub(chacha20_block(subkey, 0, nonce12), 1, 32)
    local ciphertext = chacha20_xor(subkey, nonce12, 1, plaintext)

    local aad_pad_len = (16 - (#aad % 16)) % 16
    local ct_pad_len = (16 - (#ciphertext % 16)) % 16

    local mac_data = aad .. rep('\0', aad_pad_len)
        .. ciphertext .. rep('\0', ct_pad_len)
        .. le64(#aad) .. le64(#ciphertext)

    local tag = poly1305_auth(mac_data, poly_key)
    return ciphertext .. tag
end

local function ct_eq(a, b)
    if #a ~= #b then
        return false
    end
    local v = 0
    for i = 1, #a do
        v = bor(v, bxor(byte(a, i), byte(b, i)))
    end
    return v == 0
end

local function xchacha20_poly1305_decrypt_lua(key32, nonce24, ciphertext_tag, aad)
    aad = aad or ''
    if #ciphertext_tag < 16 then
        return nil, 'ciphertext too short'
    end

    local ciphertext = sub(ciphertext_tag, 1, #ciphertext_tag - 16)
    local tag = sub(ciphertext_tag, #ciphertext_tag - 15)

    local subkey = hchacha20(key32, sub(nonce24, 1, 16))
    local nonce12 = '\0\0\0\0' .. sub(nonce24, 17, 24)
    local poly_key = sub(chacha20_block(subkey, 0, nonce12), 1, 32)

    local aad_pad_len = (16 - (#aad % 16)) % 16
    local ct_pad_len = (16 - (#ciphertext % 16)) % 16

    local mac_data = aad .. rep('\0', aad_pad_len)
        .. ciphertext .. rep('\0', ct_pad_len)
        .. le64(#aad) .. le64(#ciphertext)

    local expected = poly1305_auth(mac_data, poly_key)
    if not ct_eq(expected, tag) then
        return nil, 'auth failed'
    end

    local plaintext = chacha20_xor(subkey, nonce12, 1, ciphertext)
    return plaintext, nil
end

local function chacha20_poly1305_encrypt_lua(key32, nonce12, plaintext, aad)
    aad = aad or ''
    local poly_key = sub(chacha20_block(key32, 0, nonce12), 1, 32)
    local ciphertext = chacha20_xor(key32, nonce12, 1, plaintext)

    local aad_pad_len = (16 - (#aad % 16)) % 16
    local ct_pad_len = (16 - (#ciphertext % 16)) % 16

    local mac_data = aad .. rep('\0', aad_pad_len)
        .. ciphertext .. rep('\0', ct_pad_len)
        .. le64(#aad) .. le64(#ciphertext)

    local tag = poly1305_auth(mac_data, poly_key)
    return ciphertext .. tag
end

local function chacha20_poly1305_decrypt_lua(key32, nonce12, ciphertext_tag, aad)
    aad = aad or ''
    if #ciphertext_tag < 16 then
        return nil, 'ciphertext too short'
    end

    local ciphertext = sub(ciphertext_tag, 1, #ciphertext_tag - 16)
    local tag = sub(ciphertext_tag, #ciphertext_tag - 15)

    local poly_key = sub(chacha20_block(key32, 0, nonce12), 1, 32)
    local aad_pad_len = (16 - (#aad % 16)) % 16
    local ct_pad_len = (16 - (#ciphertext % 16)) % 16

    local mac_data = aad .. rep('\0', aad_pad_len)
        .. ciphertext .. rep('\0', ct_pad_len)
        .. le64(#aad) .. le64(#ciphertext)

    local expected = poly1305_auth(mac_data, poly_key)
    if not ct_eq(expected, tag) then
        return nil, 'auth failed'
    end

    local plaintext = chacha20_xor(key32, nonce12, 1, ciphertext)
    return plaintext, nil
end

local K256 = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local function rotr32(x, n)
    x = u32(x)
    return u32(bor(rshift(x, n), lshift(x, 32 - n)))
end

local function sha256(msg)
    local h0 = 0x6a09e667
    local h1 = 0xbb67ae85
    local h2 = 0x3c6ef372
    local h3 = 0xa54ff53a
    local h4 = 0x510e527f
    local h5 = 0x9b05688c
    local h6 = 0x1f83d9ab
    local h7 = 0x5be0cd19

    local ml = #msg
    local bit_len = ml * 8

    msg = msg .. char(0x80)
    local pad_len = (56 - (#msg % 64)) % 64
    msg = msg .. rep('\0', pad_len)

    local high = floor(bit_len / U32)
    local low = bit_len % U32
    msg = msg .. be32(high) .. be32(low)

    local w = {}
    for i = 1, #msg, 64 do
        for j = 0, 15 do
            w[j] = read_be32(msg, i + j * 4)
        end
        for j = 16, 63 do
            local s0 = bxor(rotr32(w[j - 15], 7), rotr32(w[j - 15], 18), rshift(w[j - 15], 3))
            local s1 = bxor(rotr32(w[j - 2], 17), rotr32(w[j - 2], 19), rshift(w[j - 2], 10))
            w[j] = add32_4(w[j - 16], s0, w[j - 7], s1)
        end

        local a = h0
        local b = h1
        local c = h2
        local d = h3
        local e = h4
        local f = h5
        local g = h6
        local h = h7

        for j = 0, 63 do
            local S1 = bxor(rotr32(e, 6), rotr32(e, 11), rotr32(e, 25))
            local ch = bxor(band(e, f), band(bnot(e), g))
            local temp1 = add32_4(h, S1, ch, K256[j + 1])
            temp1 = add32(temp1, w[j])
            local S0 = bxor(rotr32(a, 2), rotr32(a, 13), rotr32(a, 22))
            local maj = bxor(band(a, b), band(a, c), band(b, c))
            local temp2 = add32(S0, maj)

            h = g
            g = f
            f = e
            e = add32(d, temp1)
            d = c
            c = b
            b = a
            a = add32(temp1, temp2)
        end

        h0 = add32(h0, a)
        h1 = add32(h1, b)
        h2 = add32(h2, c)
        h3 = add32(h3, d)
        h4 = add32(h4, e)
        h5 = add32(h5, f)
        h6 = add32(h6, g)
        h7 = add32(h7, h)
    end

    return be32(h0) .. be32(h1) .. be32(h2) .. be32(h3)
        .. be32(h4) .. be32(h5) .. be32(h6) .. be32(h7)
end

local function hmac_sha256(key, msg)
    local block = 64
    if #key > block then
        key = sha256(key)
    end
    if #key < block then
        key = key .. rep('\0', block - #key)
    end

    local ipad = {}
    local opad = {}
    for i = 1, block do
        local kb = byte(key, i)
        ipad[i] = char(bxor(kb, 0x36))
        opad[i] = char(bxor(kb, 0x5c))
    end

    local inner = sha256(concat(ipad) .. msg)
    return sha256(concat(opad) .. inner)
end

local function pbkdf2_sha256(password, salt, iter, dk_len)
    local h_len = 32
    local blocks = floor((dk_len + h_len - 1) / h_len)
    local out = {}

    for i = 1, blocks do
        local u = hmac_sha256(password, salt .. be32(i))
        local t = {byte(u, 1, #u)}
        for _ = 2, iter do
            u = hmac_sha256(password, u)
            for j = 1, h_len do
                t[j] = bxor(t[j], byte(u, j))
            end
        end
        out[#out + 1] = u8_array_to_bytes(t, h_len)
    end

    local dk = concat(out)
    return sub(dk, 1, dk_len)
end

local function hash_password(password, username)
    return sha256(password .. '\0' .. username)
end

local key_cache = {}

local function key_slot_time(unix_time, refresh_interval)
    local half = floor(refresh_interval / 2)
    return floor((unix_time + half) / refresh_interval) * refresh_interval
end

local function salt_from_unix_time(unix_time, refresh_interval)
    local rounded = key_slot_time(unix_time, refresh_interval)
    local salts = {}
    for _, t in ipairs({rounded - refresh_interval, rounded, rounded + refresh_interval}) do
        local hi = floor(t / U32)
        local lo = t % U32
        salts[#salts + 1] = sha256(be32(hi) .. be32(lo))
    end
    return salts, rounded
end

local function derive_key(hashed_password, unix_time, iter, refresh_interval, profile_version)
    local _, rounded = salt_from_unix_time(unix_time, refresh_interval)
    local cache_key = profile_version .. ':' .. tostring(iter) .. ':' .. tostring(refresh_interval) .. ':' .. tostring(rounded) .. ':' .. hashed_password
    local cached = key_cache[cache_key]
    if cached then
        return cached.key, cached.salts
    end

    local salts = salt_from_unix_time(unix_time, refresh_interval)
    local key = pbkdf2_sha256(hashed_password, salts[2], iter, 32)
    key_cache[cache_key] = {
        key = key,
        salts = salts,
    }
    return key, salts
end

local function resolve_protocol_profile(protocol_version)
    local v = tostring(protocol_version or 'v3'):lower()
    if v ~= '' and v ~= '3' and v ~= 'v3' then
        error('unsupported protocol_version "' .. tostring(protocol_version) .. '" (only v3 is supported)')
    end
    return {
        protocol_version = 'v3',
        key_iter = 64,
        key_refresh_interval = 120,
        nonce_size = 24,
        aead_kind = 'xchacha20-poly1305',
    }
end

local function make_aead(log, profile)
    log('using pure-lua ' .. profile.aead_kind .. ' implementation')
    return {
        mode = 'lua',
        nonce_size = profile.nonce_size,
        encrypt = function(key, nonce, plaintext)
            return xchacha20_poly1305_encrypt_lua(key, nonce, plaintext, '')
        end,
        decrypt = function(key, nonce, ciphertext)
            return xchacha20_poly1305_decrypt_lua(key, nonce, ciphertext, '')
        end,
    }
end

local PROTO = {
    OPEN_REQ = 2,
    OPEN_RESP = 3,
    CLOSE_REQ = 4,
    CLOSE_RESP = 5,
    DATA_C2S = 6,
    DATA_S2C = 7,
    ACK_C2S = 8,
    ACK_S2C = 9,
}

local function build_session_metadata(proto, session_id, seq, status, payload_len, suffix_len)
    local b = {}
    b[1] = char(proto)
    b[2] = '\0'
    b[3] = be32(floor(os.time() / 60))
    b[4] = be32(session_id)
    b[5] = be32(seq)
    b[6] = char(status or 0)
    b[7] = be16(payload_len or 0)
    b[8] = char(suffix_len or 0)
    b[9] = rep('\0', 14)
    return concat(b)
end

local function build_data_metadata(proto, session_id, seq, unack_seq, window_size, fragment, prefix_len, payload_len, suffix_len)
    local b = {}
    b[1] = char(proto)
    b[2] = '\0'
    b[3] = be32(floor(os.time() / 60))
    b[4] = be32(session_id)
    b[5] = be32(seq)
    b[6] = be32(unack_seq or 0)
    b[7] = be16(window_size or 16)
    b[8] = char(fragment or 0)
    b[9] = char(prefix_len or 0)
    b[10] = be16(payload_len or 0)
    b[11] = char(suffix_len or 0)
    b[12] = rep('\0', 7)
    return concat(b)
end

local function parse_metadata(md)
    if #md ~= 32 then
        return nil, 'metadata length invalid'
    end
    local p = byte(md, 1)
    if p == PROTO.OPEN_REQ or p == PROTO.OPEN_RESP or p == PROTO.CLOSE_REQ or p == PROTO.CLOSE_RESP then
        return {
            proto = p,
            timestamp = read_be32(md, 3),
            session_id = read_be32(md, 7),
            seq = read_be32(md, 11),
            status = byte(md, 15),
            payload_len = read_be16(md, 16),
            suffix_len = byte(md, 18),
            prefix_len = 0,
        }, nil
    end
    if p == PROTO.DATA_C2S or p == PROTO.DATA_S2C or p == PROTO.ACK_C2S or p == PROTO.ACK_S2C then
        return {
            proto = p,
            timestamp = read_be32(md, 3),
            session_id = read_be32(md, 7),
            seq = read_be32(md, 11),
            unack = read_be32(md, 15),
            window_size = read_be16(md, 19),
            fragment = byte(md, 21),
            prefix_len = byte(md, 22),
            payload_len = read_be16(md, 23),
            suffix_len = byte(md, 25),
        }, nil
    end
    return nil, 'unknown protocol ' .. tostring(p)
end

local function socks5_connect_request(atype, host, addr_bytes, port)
    local out = {char(0x05, 0x01, 0x00)}
    out[#out + 1] = char(atype)
    if atype == 3 then
        out[#out + 1] = char(#host)
        out[#out + 1] = host
    else
        out[#out + 1] = addr_bytes
    end
    out[#out + 1] = be16(port)
    return concat(out)
end

local function parse_socks5_response(buf)
    if #buf < 5 then
        return nil, nil, nil
    end
    if byte(buf, 1) ~= 0x05 then
        return nil, nil, 'invalid socks version'
    end
    local rep_code = byte(buf, 2)
    local atyp = byte(buf, 4)
    local need
    if atyp == 0x01 then
        need = 4 + 4 + 2
    elseif atyp == 0x04 then
        need = 4 + 16 + 2
    elseif atyp == 0x03 then
        local dlen = byte(buf, 5)
        need = 4 + 1 + dlen + 2
    else
        return nil, nil, 'invalid socks atyp ' .. tostring(atyp)
    end
    if #buf < need then
        return nil, nil, nil
    end
    return need, rep_code, nil
end

local function build_cipher_state(aead, key, nonce_size)
    return {
        aead = aead,
        key = key,
        nonce_size = nonce_size,
        nonce = nil,
    }
end

local function encrypt_implicit(cs, plaintext)
    if not cs.nonce then
        local nonce = rand_bytes(cs.nonce_size)
        cs.nonce = nonce
        local ct = cs.aead.encrypt(cs.key, nonce, plaintext)
        return nonce .. ct
    end
    cs.nonce = nonce_inc_be(cs.nonce)
    return cs.aead.encrypt(cs.key, cs.nonce, plaintext)
end

local function decrypt_implicit(cs, ciphertext)
    if not cs.nonce then
        if #ciphertext < cs.nonce_size + 16 then
            return nil, 'ciphertext too short for first decrypt'
        end
        local nonce = sub(ciphertext, 1, cs.nonce_size)
        local body = sub(ciphertext, cs.nonce_size + 1)
        local plain, err = cs.aead.decrypt(cs.key, nonce, body)
        if not plain then
            return nil, err
        end
        cs.nonce = nonce
        return plain, nil
    end
    cs.nonce = nonce_inc_be(cs.nonce)
    return cs.aead.decrypt(cs.key, cs.nonce, ciphertext)
end

function M.new_client(opts)
    opts = opts or {}
    local log = new_log(opts.debug_cb)

    local hashed_pw = hash_password(opts.password or '', opts.username or '')
    local profile = resolve_protocol_profile(opts.protocol_version)
    local unix_time = opts.unix_time or os.time()
    if opts.time_offset_sec then
        local off = tonumber(opts.time_offset_sec) or 0
        unix_time = unix_time + off
    end
    local key, _ = derive_key(hashed_pw, unix_time, profile.key_iter, profile.key_refresh_interval, profile.protocol_version)
    local aead = make_aead(log, profile)

    local state = {
        log = log,
        username = opts.username,
        password = opts.password,
        hashed_password = hashed_pw,
        key = key,
        protocol_version = profile.protocol_version,
        nonce_size = profile.nonce_size,
        aead_mode = aead.mode,
        send = build_cipher_state(aead, key, profile.nonce_size),
        recv = build_cipher_state(aead, key, profile.nonce_size),
        session_id = read_be32(rand_bytes(4), 1),
        send_seq = 0,
        recv_seq = 0,
        stage = 'init',
        established = false,
        rx_buf = '',
        pending = nil,
        socks_resp_buf = '',
        plaintext_queue = '',
    }
    if state.session_id == 0 then
        state.session_id = 1
    end
    log('client initialized with version=' .. state.protocol_version .. ' aead=' .. state.aead_mode .. ' nonce=' .. tostring(state.nonce_size) .. ' session_id=' .. tostring(state.session_id))
    return state
end

function M.socks5_connect_request(atype, host, addr_bytes, port)
    return socks5_connect_request(atype, host, addr_bytes, port)
end

local function build_segment_bytes(state, meta, payload)
    local out = {}
    out[#out + 1] = encrypt_implicit(state.send, meta)
    if payload and #payload > 0 then
        out[#out + 1] = encrypt_implicit(state.send, payload)
    end
    return concat(out)
end

function M.begin_handshake(state, socks_req)
    local payload_len = #socks_req
    local meta = build_session_metadata(PROTO.OPEN_REQ, state.session_id, state.send_seq, 0, payload_len, 0)
    state.send_seq = state.send_seq + 1
    state.stage = 'wait_open'
    local pkt = build_segment_bytes(state, meta, socks_req)
    state.log('sent openSessionRequest payload=' .. tostring(payload_len))
    return pkt
end

function M.wrap_app_data(state, plaintext)
    local pos = 1
    local out = {}
    while pos <= #plaintext do
        local chunk = sub(plaintext, pos, pos + 32767)
        local meta = build_data_metadata(PROTO.DATA_C2S, state.session_id, state.send_seq, state.recv_seq, 1024, 0, 0, #chunk, 0)
        state.send_seq = state.send_seq + 1
        out[#out + 1] = build_segment_bytes(state, meta, chunk)
        pos = pos + #chunk
    end
    return concat(out)
end

function M.build_close(state)
    local meta = build_session_metadata(PROTO.CLOSE_REQ, state.session_id, state.send_seq, 0, 0, 0)
    state.send_seq = state.send_seq + 1
    return build_segment_bytes(state, meta, '')
end

local function consume_segment(state)
    local meta_len = (state.recv.nonce == nil) and (state.nonce_size + 32 + 16) or (32 + 16)

    if not state.pending then
        if #state.rx_buf < meta_len then
            return nil, nil
        end
        local enc_meta = sub(state.rx_buf, 1, meta_len)
        local plain_meta, err = decrypt_implicit(state.recv, enc_meta)
        if not plain_meta then
            return nil, 'metadata decrypt failed: ' .. tostring(err)
        end

        local md, perr = parse_metadata(plain_meta)
        if not md then
            return nil, 'metadata parse failed: ' .. tostring(perr)
        end

        local total = meta_len + md.prefix_len + md.suffix_len
        if md.payload_len > 0 then
            total = total + md.payload_len + 16
        end

        state.pending = {
            meta = md,
            meta_len = meta_len,
            total_len = total,
        }
    end

    local p = state.pending
    if #state.rx_buf < p.total_len then
        return nil, nil
    end

    local seg_raw = sub(state.rx_buf, 1, p.total_len)
    state.rx_buf = sub(state.rx_buf, p.total_len + 1)
    state.pending = nil

    local md = p.meta
    local off = p.meta_len + 1

    if md.prefix_len > 0 then
        off = off + md.prefix_len
    end

    local payload = ''
    if md.payload_len > 0 then
        local enc_payload = sub(seg_raw, off, off + md.payload_len + 16 - 1)
        off = off + md.payload_len + 16
        local plain_payload, err = decrypt_implicit(state.recv, enc_payload)
        if not plain_payload then
            return nil, 'payload decrypt failed: ' .. tostring(err)
        end
        payload = plain_payload
    end

    if md.seq and md.seq >= state.recv_seq then
        state.recv_seq = md.seq + 1
    end

    return {meta = md, payload = payload}, nil
end

local function handle_incoming_segment(state, seg)
    local md = seg.meta
    local p = seg.payload

    if md.proto == PROTO.OPEN_RESP then
        if md.status ~= 0 then
            return nil, 'openSessionResponse status=' .. tostring(md.status)
        end
        state.stage = 'wait_socks'
        state.log('received openSessionResponse seq=' .. tostring(md.seq))
        return '', nil
    end

    if md.proto == PROTO.DATA_S2C then
        if not state.established then
            state.socks_resp_buf = state.socks_resp_buf .. p
            local consumed, rep_code, perr = parse_socks5_response(state.socks_resp_buf)
            if perr then
                return nil, perr
            end
            if consumed then
                if rep_code ~= 0 then
                    return nil, 'socks5 reply=' .. tostring(rep_code)
                end
                state.established = true
                state.stage = 'established'
                state.log('socks5 CONNECT established')
                local extra = sub(state.socks_resp_buf, consumed + 1)
                state.socks_resp_buf = ''
                return extra, nil
            end
            return '', nil
        end
        return p, nil
    end

    if md.proto == PROTO.ACK_S2C then
        return '', nil
    end

    if md.proto == PROTO.CLOSE_REQ or md.proto == PROTO.CLOSE_RESP then
        state.stage = 'closed'
        state.remote_closed = true
        return '', nil
    end

    return '', nil
end

function M.feed_encrypted(state, data)
    state.rx_buf = state.rx_buf .. data
    local plain_out = {}

    while true do
        local seg, err = consume_segment(state)
        if err then
            return nil, err
        end
        if not seg then
            break
        end

        local plain, herr = handle_incoming_segment(state, seg)
        if herr then
            return nil, herr
        end
        if plain and #plain > 0 then
            plain_out[#plain_out + 1] = plain
        end
    end

    local out = concat(plain_out)
    if #out > 0 then
        state.plaintext_queue = state.plaintext_queue .. out
    end
    return out, nil
end

function M.pull_plaintext(state)
    local out = state.plaintext_queue
    state.plaintext_queue = ''
    return out
end

function M.is_established(state)
    return state.established
end

function M.aead_mode(state)
    return state.aead_mode
end

function M.debug_snapshot(state)
    return {
        stage = state.stage,
        established = state.established,
        send_seq = state.send_seq,
        recv_seq = state.recv_seq,
        protocol_version = state.protocol_version,
        nonce_size = state.nonce_size,
        aead_mode = state.aead_mode,
        session_id = state.session_id,
        rx_buf_len = #state.rx_buf,
    }
end

M.PROTO = PROTO
M.hash_password = hash_password
M.pbkdf2_sha256 = pbkdf2_sha256
M.sha256 = sha256
M.chacha20_poly1305_encrypt_lua = chacha20_poly1305_encrypt_lua
M.chacha20_poly1305_decrypt_lua = chacha20_poly1305_decrypt_lua
M.xchacha20_poly1305_encrypt_lua = xchacha20_poly1305_encrypt_lua
M.xchacha20_poly1305_decrypt_lua = xchacha20_poly1305_decrypt_lua
M.tohex = tohex

return M
end)()
-- file: lua/mieru-backend.lua
-- Shadowrocket lua-backend adapter for mieru TCP protocol.

local backend = require 'backend'

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
