-- tests/test_compat.lua
-- Tests for backwards compatibility layer

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

local T = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            -- Give buffer a .md filename so mkdnflow recognizes it
            child.lua([[
                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
            ]])
        end,
        post_once = child.stop,
    },
})

-- =============================================================================
-- Backwards compatibility for to_do.statuses config keys
-- =============================================================================
T['compat'] = new_set()

T['compat']['migrates symbol to marker'] = function()
    -- Setup with old config format using 'symbol' instead of 'marker'
    child.lua([[
        require('mkdnflow').setup({
            to_do = {
                statuses = {
                    { name = 'not_started', symbol = ' ' },
                    { name = 'in_progress', symbol = '-' },
                    { name = 'complete', symbol = 'x' },
                }
            }
        })
    ]])
    -- Set buffer with to-do item
    set_lines({ '- [ ] Test item' })
    set_cursor(1, 0)
    -- Toggle to-do - this should work if symbol was migrated to marker
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    -- Verify it toggled to in_progress
    local line = get_line(1)
    eq(line, '- [-] Test item')
end

T['compat']['migrates colors to highlight'] = function()
    -- Setup with old config format using 'colors' instead of 'highlight'
    child.lua([[
        require('mkdnflow').setup({
            to_do = {
                statuses = {
                    { name = 'not_started', marker = ' ', colors = { 'Comment' } },
                    { name = 'in_progress', marker = '-', colors = { 'DiagnosticWarn' } },
                    { name = 'complete', marker = 'x', colors = { 'DiagnosticOk' } },
                }
            }
        })
    ]])
    -- Verify the config was migrated - check that highlight is set
    local highlight_first = child.lua_get(
        "require('mkdnflow').config.to_do.statuses[1].highlight[1]"
    )
    eq(highlight_first, 'Comment')
end

T['compat']['handles mixed old and new config'] = function()
    -- Config with some statuses using old keys, some using new
    child.lua([[
        require('mkdnflow').setup({
            to_do = {
                statuses = {
                    { name = 'not_started', symbol = ' ' },           -- old key
                    { name = 'in_progress', marker = '-' },           -- new key
                    { name = 'complete', marker = 'x', colors = { 'DiagnosticOk' } },  -- mixed
                }
            }
        })
    ]])
    -- Set buffer with to-do item
    set_lines({ '- [ ] Test item' })
    set_cursor(1, 0)
    -- Toggle through all states to verify all statuses work
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    eq(get_line(1), '- [-] Test item')
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    eq(get_line(1), '- [x] Test item')
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    eq(get_line(1), '- [ ] Test item')
end

T['compat']['new config format works unchanged'] = function()
    -- Config using marker and highlight (new format)
    child.lua([[
        require('mkdnflow').setup({
            to_do = {
                statuses = {
                    { name = 'not_started', marker = ' ', highlight = { 'Comment' } },
                    { name = 'in_progress', marker = '-', highlight = { 'DiagnosticWarn' } },
                    { name = 'complete', marker = 'X', highlight = { 'DiagnosticOk' } },
                }
            }
        })
    ]])
    -- Set buffer with to-do item
    set_lines({ '- [ ] Test item' })
    set_cursor(1, 0)
    -- Toggle to-do
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    eq(get_line(1), '- [-] Test item')
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    eq(get_line(1), '- [X] Test item')
end

T['compat']['does not overwrite new key with old key'] = function()
    -- If both old and new keys are present, new key should take precedence
    child.lua([[
        require('mkdnflow').setup({
            to_do = {
                statuses = {
                    { name = 'not_started', symbol = '?', marker = ' ' },  -- marker should win
                    { name = 'complete', symbol = '!', marker = 'x' },
                }
            }
        })
    ]])
    -- Set buffer with to-do item
    set_lines({ '- [ ] Test item' })
    set_cursor(1, 0)
    -- Toggle to-do
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    -- Should use 'x' from marker, not '!' from symbol
    eq(get_line(1), '- [x] Test item')
end

return T
