-- tests/test_footnotes.lua
-- Tests for footnote reference support ([^label] and [^label]: text)

local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

-- Helper to set buffer content
local function set_lines(lines)
    child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, ' .. vim.inspect(lines) .. ')')
end

-- Helper to get a specific line
local function get_line(n)
    return child.lua_get('vim.api.nvim_buf_get_lines(0, ' .. (n - 1) .. ', ' .. n .. ', false)[1]')
end

-- Helper to set cursor position (1-indexed row, 0-indexed col)
local function set_cursor(row, col)
    child.lua('vim.api.nvim_win_set_cursor(0, {' .. row .. ', ' .. col .. '})')
end

-- Helper to get cursor position
local function get_cursor()
    return child.lua_get('vim.api.nvim_win_get_cursor(0)')
end

-- Helper to get extmarks with virtual text in the ref_hint namespace
local function get_hint_extmarks()
    child.lua([[
        local ns = vim.api.nvim_create_namespace('mkdnflow_ref_hint')
        local marks = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
        _G._hint_marks = {}
        for _, mark in ipairs(marks) do
            local details = mark[4]
            if details.virt_text then
                local text = ''
                for _, chunk in ipairs(details.virt_text) do
                    text = text .. chunk[1]
                end
                table.insert(_G._hint_marks, { row = mark[2] + 1, text = text })
            end
        end
    ]])
    return child.lua_get('_G._hint_marks')
end

-- Helper to wait for debounced hint to appear
local function wait_for_hint()
    child.lua('vim.cmd("doautocmd CursorMoved")')
    vim.loop.sleep(100)
    child.lua('vim.wait(50, function() return false end)')
end

local T = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
                require('mkdnflow').setup({
                    links = {
                        transform_on_create = false,
                    }
                })
            ]])
        end,
        post_once = child.stop,
    },
})

-- =============================================================================
-- Detection: footnote_ref
-- =============================================================================
T['detection'] = new_set()

T['detection']['[^1] detected as footnote_ref'] = function()
    set_lines({ 'Some text[^1] here.', '', '[^1]: Footnote text' })
    set_cursor(1, 10) -- on [^1]
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'footnote_ref')
end

T['detection']['[^footnoteref] detected as footnote_ref'] = function()
    set_lines({ 'Some text[^footnoteref] here.' })
    set_cursor(1, 12)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'footnote_ref')
end

T['detection']['[^1] at start of line detected as footnote_ref'] = function()
    set_lines({ '[^1] some text.' })
    set_cursor(1, 1)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'footnote_ref')
end

T['detection']['[^1]: text detected as footnote_definition'] = function()
    set_lines({ '[^1]: Footnote text' })
    set_cursor(1, 3)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'footnote_definition')
end

T['detection']['footnote definition with leading spaces'] = function()
    set_lines({ '   [^1]: Footnote text' })
    set_cursor(1, 5)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'footnote_definition')
end

T['detection']['[^1] NOT detected as shortcut_ref_link'] = function()
    set_lines({ 'Text [^1] here.' })
    set_cursor(1, 6)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'footnote_ref')
end

T['detection']['regular [label] still detected as shortcut_ref_link'] = function()
    set_lines({ 'See [gh] for details.', '', '[gh]: https://github.com/' })
    set_cursor(1, 5)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'shortcut_ref_link')
end

T['detection']['[ref]: url still detected as ref_definition'] = function()
    set_lines({ '[ref]: https://example.com' })
    set_cursor(1, 3)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'ref_definition')
end

T['detection']['extracts footnote label as name'] = function()
    set_lines({ 'Text [^myref] here.' })
    set_cursor(1, 7)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.test_name = require("mkdnflow.links").getLinkPart(_G.test_link, "name")')
    local result = child.lua_get('_G.test_name')
    eq(result, 'myref')
end

T['detection']['extracts footnote definition label as name'] = function()
    set_lines({ '[^myref]: Some footnote text.' })
    set_cursor(1, 3)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.test_name = require("mkdnflow.links").getLinkPart(_G.test_link, "name")')
    local result = child.lua_get('_G.test_name')
    eq(result, 'myref')
end

-- =============================================================================
-- Source resolution
-- =============================================================================
T['source'] = new_set()

T['source']['footnote_ref source points to definition row'] = function()
    set_lines({ 'Text[^1] here.', '', '[^1]: Footnote text' })
    set_cursor(1, 5)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua([[
        _G.src = _G.test_link:get_source()
    ]])
    local start_row = child.lua_get('_G.src.start_row')
    eq(start_row, 3)
end

T['source']['footnote_definition source points to first ref row'] = function()
    set_lines({ 'Text[^1] here.', '', '[^1]: Footnote text' })
    set_cursor(3, 3)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua([[
        _G.src = _G.test_link:get_source()
    ]])
    local start_row = child.lua_get('_G.src.start_row')
    eq(start_row, 1)
end

T['source']['footnote_ref with no definition has zero position'] = function()
    set_lines({ 'Text[^orphan] here.' })
    set_cursor(1, 5)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua([[
        _G.src = _G.test_link:get_source()
    ]])
    local start_row = child.lua_get('_G.src.start_row')
    eq(start_row, 0)
end

T['source']['footnote_definition with no ref has zero position'] = function()
    set_lines({ '[^orphan]: Unused footnote.' })
    set_cursor(1, 5)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua([[
        _G.src = _G.test_link:get_source()
    ]])
    local start_row = child.lua_get('_G.src.start_row')
    eq(start_row, 0)
end

-- =============================================================================
-- Follow behavior (integration)
-- =============================================================================
T['follow'] = new_set()

T['follow']['followLink on [^1] jumps to definition line'] = function()
    set_lines({ 'Text[^1] here.', '', '[^1]: Footnote text' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.links').followLink()]])
    local cursor = get_cursor()
    eq(cursor[1], 3) -- jumped to definition row
end

T['follow']['followLink on [^1]: jumps to first reference'] = function()
    set_lines({ 'Text[^1] here.', '', '[^1]: Footnote text' })
    set_cursor(3, 3)
    child.lua([[require('mkdnflow.links').followLink()]])
    local cursor = get_cursor()
    eq(cursor[1], 1) -- jumped to reference row
end

T['follow']['followLink on orphan [^1] shows warning'] = function()
    set_lines({ 'Text[^orphan] here.' })
    set_cursor(1, 5)
    child.lua([[
        _G._notify_msg = nil
        _G._notify_level = nil
        local orig = vim.notify
        vim.notify = function(msg, level)
            _G._notify_msg = msg
            _G._notify_level = level
        end
        require('mkdnflow.links').followLink()
        vim.notify = orig
    ]])
    local msg = child.lua_get('_G._notify_msg')
    eq(msg, "Couldn't find footnote definition!")
end

T['follow']['followLink on orphan definition shows warning'] = function()
    set_lines({ '[^orphan]: Unused footnote.' })
    set_cursor(1, 5)
    child.lua([[
        _G._notify_msg = nil
        local orig = vim.notify
        vim.notify = function(msg, level)
            _G._notify_msg = msg
            _G._notify_level = level
        end
        require('mkdnflow.links').followLink()
        vim.notify = orig
    ]])
    local msg = child.lua_get('_G._notify_msg')
    eq(msg, "Couldn't find footnote reference!")
end

T['follow']['multiple footnotes jump to their own definitions'] = function()
    set_lines({
        'Text[^1] and[^2] here.',
        '',
        '[^1]: First footnote',
        '[^2]: Second footnote',
    })
    -- Follow [^2]
    set_cursor(1, 13)
    child.lua([[require('mkdnflow.links').followLink()]])
    local cursor = get_cursor()
    eq(cursor[1], 4) -- jumped to second definition
end

-- =============================================================================
-- E2E keypress tests
-- =============================================================================
T['keypress'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                vim.cmd('runtime plugin/mkdnflow.lua')
                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
                require('mkdnflow').setup({
                    links = {
                        transform_on_create = false,
                    }
                })
                vim.cmd('doautocmd BufEnter')
            ]])
        end,
    },
})

T['keypress']['<CR> on [^1] jumps to definition'] = function()
    set_lines({ 'Text[^1] here.', '', '[^1]: Footnote text' })
    set_cursor(1, 5)
    child.type_keys('<CR>')
    local cursor = get_cursor()
    eq(cursor[1], 3)
end

T['keypress']['<CR> on definition jumps to reference'] = function()
    set_lines({ 'Text[^1] here.', '', '[^1]: Footnote text' })
    set_cursor(3, 3)
    child.type_keys('<CR>')
    local cursor = get_cursor()
    eq(cursor[1], 1)
end

-- =============================================================================
-- Hints (virtual text)
-- =============================================================================
T['hints'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
                require('mkdnflow').setup({
                    links = {
                        ref_hint = true,
                        transform_on_create = false,
                    }
                })
                vim.cmd('doautocmd FileType')
            ]])
        end,
    },
})

T['hints']['footnote_ref shows footnote text as hint'] = function()
    set_lines({ 'Text[^1] here.', '', '[^1]: Footnote text' })
    set_cursor(1, 5)
    wait_for_hint()
    local marks = get_hint_extmarks()
    eq(#marks, 1)
    eq(marks[1].row, 1)
    eq(marks[1].text, '→ Footnote text')
end

T['hints']['footnote_definition shows reference count'] = function()
    set_lines({ 'Text[^1] here.', 'Also[^1].', '', '[^1]: Footnote text' })
    set_cursor(4, 3)
    wait_for_hint()
    local marks = get_hint_extmarks()
    eq(#marks, 1)
    eq(marks[1].row, 4)
    eq(marks[1].text, '(2 references)')
end

T['hints']['footnote_definition singular reference'] = function()
    set_lines({ 'Text[^1] here.', '', '[^1]: Footnote text' })
    set_cursor(3, 3)
    wait_for_hint()
    local marks = get_hint_extmarks()
    eq(#marks, 1)
    eq(marks[1].text, '(1 reference)')
end

T['hints']['orphan footnote_ref no hint'] = function()
    set_lines({ 'Text[^orphan] here.' })
    set_cursor(1, 5)
    wait_for_hint()
    local marks = get_hint_extmarks()
    eq(#marks, 0)
end

T['hints']['orphan footnote_definition zero references'] = function()
    set_lines({ '[^orphan]: Unused footnote.' })
    set_cursor(1, 5)
    wait_for_hint()
    local marks = get_hint_extmarks()
    eq(#marks, 1)
    eq(marks[1].text, '(0 references)')
end

T['hints']['long footnote text truncated'] = function()
    local long_text = string.rep('a', 100)
    set_lines({ 'Text[^1] here.', '', '[^1]: ' .. long_text })
    set_cursor(1, 5)
    wait_for_hint()
    local marks = get_hint_extmarks()
    eq(#marks, 1)
    -- Should end with '...' when truncated
    eq(string.sub(marks[1].text, -3), '...')
end

return T
