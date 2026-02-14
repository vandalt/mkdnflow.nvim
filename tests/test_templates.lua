-- tests/test_templates.lua
-- Tests for template formatting and injection

local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

-- Helper to set buffer content
local function set_lines(lines)
    child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, ' .. vim.inspect(lines) .. ')')
end

-- Helper to get buffer content
local function get_lines()
    return child.lua_get('vim.api.nvim_buf_get_lines(0, 0, -1, false)')
end

-- Helper to set cursor position (1-indexed row, 0-indexed col)
local function set_cursor(row, col)
    child.lua('vim.api.nvim_win_set_cursor(0, {' .. row .. ', ' .. col .. '})')
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
                        transform_on_follow = false
                    }
                })
            ]])
        end,
        post_once = child.stop,
    },
})

-- =============================================================================
-- formatTemplate() - Template placeholder substitution
-- =============================================================================
T['formatTemplate'] = new_set()

T['formatTemplate']['replaces link_title when cursor on link'] = function()
    set_lines({ '[My Page Title](my-page.md)' })
    set_cursor(1, 5)
    local result = child.lua_get([[require('mkdnflow.templates').formatTemplate('before')]])
    eq(result, '# My Page Title')
end

T['formatTemplate']['replaces link_title from wiki link'] = function()
    set_lines({ '[[my-page|Display Name]]' })
    set_cursor(1, 5)
    local result = child.lua_get([[require('mkdnflow.templates').formatTemplate('before')]])
    eq(result, '# Display Name')
end

T['formatTemplate']['uses custom template parameter'] = function()
    set_lines({ '[Note Title](note.md)' })
    set_cursor(1, 5)
    local result =
        child.lua_get([[require('mkdnflow.templates').formatTemplate('before', 'Created: {{date}}')]])
    local matches_date = result:match('^Created: %d%d%d%d%-%d%d%-%d%d$') ~= nil
    eq(matches_date, true)
end

T['formatTemplate']['handles template with both placeholders'] = function()
    set_lines({ '[My Note](note.md)' })
    set_cursor(1, 5)
    local result = child.lua_get(
        [[require('mkdnflow.templates').formatTemplate('before', '# {{title}}\nDate: {{date}}')]]
    )
    local has_title = result:match('^# My Note\n') ~= nil
    eq(has_title, true)
    local has_date = result:match('Date: %d%d%d%d%-%d%d%-%d%d$') ~= nil
    eq(has_date, true)
end

T['formatTemplate']['after timing uses after placeholders'] = function()
    set_lines({ '[Title](note.md)' })
    set_cursor(1, 5)
    local result =
        child.lua_get([[require('mkdnflow.templates').formatTemplate('after', 'Static text')]])
    eq(result, 'Static text')
end

T['formatTemplate']['handles no link under cursor gracefully'] = function()
    set_lines({ 'No link here' })
    set_cursor(1, 5)
    local result = child.lua_get([[require('mkdnflow.templates').formatTemplate('before')]])
    eq(result, '# ')
end

T['formatTemplate']['handles empty buffer'] = function()
    set_lines({ '' })
    set_cursor(1, 0)
    local result = child.lua_get([[require('mkdnflow.templates').formatTemplate('before')]])
    eq(result, '# ')
end

T['formatTemplate']['handles cursor at end of line with no link'] = function()
    set_lines({ 'Some text without links' })
    set_cursor(1, 20)
    local result = child.lua_get([[require('mkdnflow.templates').formatTemplate('before')]])
    eq(result, '# ')
end

T['formatTemplate']['os_date still works when no link'] = function()
    set_lines({ 'No link here' })
    set_cursor(1, 5)
    local result =
        child.lua_get([[require('mkdnflow.templates').formatTemplate('before', 'Date: {{date}}')]])
    local matches_date = result:match('^Date: %d%d%d%d%-%d%d%-%d%d$') ~= nil
    eq(matches_date, true)
end

-- =============================================================================
-- apply() - Template injection into buffer
-- =============================================================================
T['apply'] = new_set()

T['apply']['injects single-line template into empty buffer'] = function()
    set_lines({ '' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.templates').apply('# Test Title')]])
    local lines = get_lines()
    eq(lines[1], '# Test Title')
end

T['apply']['injects multi-line template into empty buffer'] = function()
    set_lines({ '' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.templates').apply('# Title\n\nContent here')]])
    local lines = get_lines()
    eq(lines[1], '# Title')
    eq(lines[2], '')
    eq(lines[3], 'Content here')
end

-- =============================================================================
-- Backward compat: paths.formatTemplate delegates to templates module
-- =============================================================================
T['compat'] = new_set()

T['compat']['paths.formatTemplate delegates to templates module'] = function()
    set_lines({ '[My Page](my-page.md)' })
    set_cursor(1, 5)
    local via_paths = child.lua_get([[require('mkdnflow.paths').formatTemplate('before')]])
    set_cursor(1, 5)
    local via_templates = child.lua_get([[require('mkdnflow.templates').formatTemplate('before')]])
    eq(via_paths, via_templates)
end

-- =============================================================================
-- modules.templates = false: template injection gracefully skipped
-- =============================================================================
T['module_disabled'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
                require('mkdnflow').setup({
                    modules = { templates = false },
                    links = {
                        transform_on_create = false,
                        transform_on_follow = false,
                    },
                    new_file_template = {
                        enabled = true,
                        placeholders = {
                            before = { title = 'link_title' },
                            after = {},
                        },
                        template = '# {{ title }}',
                    },
                })
            ]])
        end,
    },
})

T['module_disabled']['paths.formatTemplate returns raw template when module disabled'] = function()
    set_lines({ '[My Page](my-page.md)' })
    set_cursor(1, 5)
    local result = child.lua_get([[require('mkdnflow.paths').formatTemplate('before')]])
    -- Shim falls back to raw template string (no substitution)
    eq(result, '# {{ title }}')
end

return T
