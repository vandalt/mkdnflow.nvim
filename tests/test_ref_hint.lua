-- tests/test_ref_hint.lua
-- Tests for reference link virtual text hints

local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

-- Helper to set buffer content
local function set_lines(lines)
    child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, ' .. vim.inspect(lines) .. ')')
end

-- Helper to set cursor position (1-indexed row, 0-indexed col)
local function set_cursor(row, col)
    child.lua('vim.api.nvim_win_set_cursor(0, {' .. row .. ', ' .. col .. '})')
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
    -- Trigger CursorMoved and wait for debounce (50ms) + processing
    child.lua('vim.cmd("doautocmd CursorMoved")')
    vim.loop.sleep(100)
    -- Process pending scheduled callbacks
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
                        ref_hint = true,
                        transform_on_create = false,
                    }
                })
                -- Trigger FileType to set up autocmds
                vim.cmd('doautocmd FileType')
            ]])
        end,
        post_once = child.stop,
    },
})

-- =============================================================================
-- Virtual text on reference-style links
-- =============================================================================
T['ref_hint'] = new_set()

T['ref_hint']['shows URL for ref_style_link'] = function()
    set_lines({ '[text][ref]', '', '[ref]: https://example.com' })
    set_cursor(1, 3)
    wait_for_hint()
    local marks = get_hint_extmarks()
    eq(#marks, 1)
    eq(marks[1].row, 1)
    eq(marks[1].text, '→ https://example.com')
end

T['ref_hint']['shows URL for shortcut_ref_link'] = function()
    set_lines({ 'See [gh] for details.', '', '[gh]: https://github.com/' })
    set_cursor(1, 5)
    wait_for_hint()
    local marks = get_hint_extmarks()
    eq(#marks, 1)
    eq(marks[1].row, 1)
    eq(marks[1].text, '→ https://github.com/')
end

T['ref_hint']['shows usage count on definition line'] = function()
    set_lines({
        '[text][ref]',
        'Also see [ref].',
        '',
        '[ref]: https://example.com',
    })
    set_cursor(4, 3)
    wait_for_hint()
    local marks = get_hint_extmarks()
    eq(#marks, 1)
    eq(marks[1].row, 4)
    eq(marks[1].text, '(2 references)')
end

T['ref_hint']['shows singular reference count'] = function()
    set_lines({ '[text][ref]', '', '[ref]: https://example.com' })
    set_cursor(3, 3)
    wait_for_hint()
    local marks = get_hint_extmarks()
    eq(#marks, 1)
    eq(marks[1].text, '(1 reference)')
end

T['ref_hint']['shows zero references'] = function()
    set_lines({ '[orphan]: https://example.com' })
    set_cursor(1, 3)
    wait_for_hint()
    local marks = get_hint_extmarks()
    eq(#marks, 1)
    eq(marks[1].text, '(0 references)')
end

T['ref_hint']['clears hint when cursor moves to non-link line'] = function()
    set_lines({ '[text][ref]', 'plain text', '', '[ref]: https://example.com' })
    set_cursor(1, 3)
    wait_for_hint()
    local marks = get_hint_extmarks()
    eq(#marks, 1)

    -- Move to plain text line
    set_cursor(2, 3)
    wait_for_hint()
    marks = get_hint_extmarks()
    eq(#marks, 0)
end

T['ref_hint']['no hint for shortcut_ref_link without definition'] = function()
    set_lines({ 'See [orphan] for details.' })
    set_cursor(1, 6)
    wait_for_hint()
    local marks = get_hint_extmarks()
    eq(#marks, 0)
end

T['ref_hint']['no hint for non-ref link types'] = function()
    set_lines({ '[text](https://example.com)' })
    set_cursor(1, 3)
    wait_for_hint()
    local marks = get_hint_extmarks()
    eq(#marks, 0)
end

T['ref_hint']['counts collapsed reference links'] = function()
    set_lines({ '[ref][]', '[text][ref]', '', '[ref]: https://example.com' })
    set_cursor(4, 3)
    wait_for_hint()
    local marks = get_hint_extmarks()
    eq(#marks, 1)
    eq(marks[1].text, '(2 references)')
end

-- =============================================================================
-- Module disabled
-- =============================================================================
T['ref_hint_disabled'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
                require('mkdnflow').setup({
                    links = {
                        ref_hint = false,
                    }
                })
                vim.cmd('doautocmd FileType')
            ]])
        end,
    },
})

T['ref_hint_disabled']['no hints when disabled'] = function()
    set_lines({ '[text][ref]', '', '[ref]: https://example.com' })
    set_cursor(1, 3)
    wait_for_hint()
    local marks = get_hint_extmarks()
    eq(#marks, 0)
end

return T
