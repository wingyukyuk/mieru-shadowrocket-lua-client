#!/usr/bin/env lua
-- build.lua
-- Merges mieru-core.lua + mieru-backend.lua         => mieru-backend-allinone.lua
-- Merges mieru-core.lua + mieru-backend-diagnostic.lua => mieru-backend-diagnostic-allinone.lua

local function read_file(path)
    local f = assert(io.open(path, 'r'), 'cannot open ' .. path)
    local content = f:read('*a')
    f:close()
    return content
end

local function write_file(path, content)
    local f = assert(io.open(path, 'w'), 'cannot open ' .. path .. ' for writing')
    f:write(content)
    f:close()
end

local function strip_require_core(src)
    -- Remove "local core = require 'mieru-core'" or similar require lines
    src = src:gsub("[^\n]*require%s*['\"]mieru%-core['\"][^\n]*\n?", '')
    return src
end

local function build_allinone(core_path, backend_path, output_path, label)
    local core_src = read_file(core_path)
    local backend_src = read_file(backend_path)

    -- Strip the backend's require of mieru-core
    backend_src = strip_require_core(backend_src)

    local header = string.format(
        '-- file: %s\n-- Auto-generated from %s + %s\n',
        output_path, core_path, backend_path
    )

    -- Wrap core in a closure that returns the module table
    local merged = header
        .. 'local core = (function()\n'
        .. core_src
        .. 'end)()\n'
        .. backend_src

    write_file(output_path, merged)
    io.write('[build] ' .. label .. ' -> ' .. output_path .. '\n')
end

-- Build normal allinone
build_allinone(
    'mieru-core.lua',
    'mieru-backend.lua',
    'mieru-backend-allinone.lua',
    'mieru-core + mieru-backend'
)

-- Build diagnostic allinone
build_allinone(
    'mieru-core.lua',
    'mieru-backend-diagnostic.lua',
    'mieru-backend-diagnostic-allinone.lua',
    'mieru-core + mieru-backend-diagnostic'
)

io.write('[build] Done.\n')
