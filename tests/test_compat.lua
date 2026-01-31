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

-- =============================================================================
-- Backwards compatibility for individual keys → statuses array
-- =============================================================================
T['compat']['migrates individual keys to statuses array'] = function()
    -- Setup with old config format using individual keys
    child.lua([[
        require('mkdnflow').setup({
            to_do = {
                not_started = ' ',
                in_progress = '-',
                complete = 'X',
            }
        })
    ]])
    -- Set buffer with to-do item
    set_lines({ '- [ ] Test item' })
    set_cursor(1, 0)
    -- Toggle to-do - this should work if individual keys were migrated to statuses
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    eq(get_line(1), '- [-] Test item')
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    eq(get_line(1), '- [X] Test item')
end

T['compat']['does not create statuses from nil individual keys'] = function()
    -- Setup with empty to_do config - should use defaults, not create nil statuses
    child.lua([[
        require('mkdnflow').setup({
            to_do = {}
        })
    ]])
    -- Set buffer with to-do item
    set_lines({ '- [ ] Test item' })
    set_cursor(1, 0)
    -- Toggle should work with default statuses
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    eq(get_line(1), '- [-] Test item')
end

-- =============================================================================
-- Backwards compatibility for update_parents → status_propagation.up
-- =============================================================================
T['compat']['migrates update_parents to status_propagation'] = function()
    -- Setup with old config format using update_parents
    child.lua([[
        require('mkdnflow').setup({
            to_do = {
                update_parents = true,
            }
        })
    ]])
    -- Verify the config was migrated
    local up = child.lua_get("require('mkdnflow').config.to_do.status_propagation.up")
    eq(up, true)
end

T['compat']['migrates update_parents false value'] = function()
    -- Setup with update_parents = false
    child.lua([[
        require('mkdnflow').setup({
            to_do = {
                update_parents = false,
            }
        })
    ]])
    -- Verify the config was migrated (false should be preserved)
    local up = child.lua_get("require('mkdnflow').config.to_do.status_propagation.up")
    eq(up, false)
end

return T
