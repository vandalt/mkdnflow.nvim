-- tests/test_foldtext.lua
-- Tests for custom foldtext display functionality

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

local T = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
                vim.opt.foldmethod = 'manual'
                require('mkdnflow').setup({
                    modules = { folds = true, foldtext = true },
                    silent = true
                })
            ]])
        end,
        post_once = child.stop,
    },
})

-- =============================================================================
-- default_title_transformer() - Transform heading text for fold display
-- =============================================================================
T['default_title_transformer'] = new_set()

T['default_title_transformer']['transforms H1 heading'] = function()
    local result =
        child.lua_get([[require('mkdnflow.foldtext').default_title_transformer('# Heading')]])
    -- Should have one filled circle and 5 empty, plus the text
    eq(result:match('^●○○○○○ Heading$') ~= nil, true)
end

T['default_title_transformer']['transforms H2 heading'] = function()
    local result =
        child.lua_get([[require('mkdnflow.foldtext').default_title_transformer('## Heading')]])
    eq(result:match('^●●○○○○ Heading$') ~= nil, true)
end

T['default_title_transformer']['transforms H3 heading'] = function()
    local result =
        child.lua_get([[require('mkdnflow.foldtext').default_title_transformer('### Heading')]])
    eq(result:match('^●●●○○○ Heading$') ~= nil, true)
end

T['default_title_transformer']['transforms H6 heading'] = function()
    local result =
        child.lua_get([[require('mkdnflow.foldtext').default_title_transformer('###### Heading')]])
    eq(result:match('^●●●●●● Heading$') ~= nil, true)
end

T['default_title_transformer']['removes trailing whitespace'] = function()
    local result =
        child.lua_get([[require('mkdnflow.foldtext').default_title_transformer('# Heading   ')]])
    eq(result:match('Heading$') ~= nil, true)
end

T['default_title_transformer']['removes leading whitespace'] = function()
    local result =
        child.lua_get([[require('mkdnflow.foldtext').default_title_transformer('  # Heading')]])
    eq(result:match('Heading$') ~= nil, true)
end

T['default_title_transformer']['removes attributes'] = function()
    local result = child.lua_get(
        [[require('mkdnflow.foldtext').default_title_transformer('# Heading {#custom-id .class}')]]
    )
    eq(result:match('Heading$') ~= nil, true)
    eq(result:match('{') == nil, true)
end

T['default_title_transformer']['handles heading with special characters'] = function()
    local result =
        child.lua_get([[require('mkdnflow.foldtext').default_title_transformer("# It's a Test!")]])
    eq(result:match("It's a Test!$") ~= nil, true)
end

-- =============================================================================
-- object_icons - Icon sets for object counts
-- =============================================================================
T['object_icons'] = new_set()

T['object_icons']['has nerdfont icons'] = function()
    local icons = child.lua_get('require("mkdnflow.foldtext").object_icons.nerdfont')
    eq(type(icons), 'table')
    eq(icons.tbl ~= nil, true)
    eq(icons.ul ~= nil, true)
    eq(icons.ol ~= nil, true)
    eq(icons.todo ~= nil, true)
end

T['object_icons']['has plain icons'] = function()
    local icons = child.lua_get('require("mkdnflow.foldtext").object_icons.plain')
    eq(type(icons), 'table')
    eq(icons.tbl ~= nil, true)
    eq(icons.ul ~= nil, true)
end

T['object_icons']['has emoji icons'] = function()
    local icons = child.lua_get('require("mkdnflow.foldtext").object_icons.emoji')
    eq(type(icons), 'table')
    eq(icons.tbl ~= nil, true)
    eq(icons.ul ~= nil, true)
end

T['object_icons']['all icon sets have same keys'] = function()
    local nerdfont = child.lua_get('require("mkdnflow.foldtext").object_icons.nerdfont')
    local plain = child.lua_get('require("mkdnflow.foldtext").object_icons.plain')
    local emoji = child.lua_get('require("mkdnflow.foldtext").object_icons.emoji')

    -- Check that all sets have the same keys
    for key, _ in pairs(nerdfont) do
        eq(plain[key] ~= nil, true)
        eq(emoji[key] ~= nil, true)
    end
end

-- =============================================================================
-- default_count_opts - Object count configuration
-- =============================================================================
T['default_count_opts'] = new_set()

T['default_count_opts']['has table counting'] = function()
    -- Can't serialize functions, so just check structure
    local has_tbl = child.lua_get('require("mkdnflow.foldtext").default_count_opts().tbl ~= nil')
    local has_icon =
        child.lua_get('require("mkdnflow.foldtext").default_count_opts().tbl.icon ~= nil')
    local has_method =
        child.lua_get('require("mkdnflow.foldtext").default_count_opts().tbl.count_method ~= nil')
    eq(has_tbl, true)
    eq(has_icon, true)
    eq(has_method, true)
end

T['default_count_opts']['has unordered list counting'] = function()
    local opts = child.lua_get('require("mkdnflow.foldtext").default_count_opts().ul')
    eq(type(opts), 'table')
    eq(opts.count_method.tally, 'blocks')
end

T['default_count_opts']['has ordered list counting'] = function()
    local opts = child.lua_get('require("mkdnflow.foldtext").default_count_opts().ol')
    eq(type(opts), 'table')
    eq(opts.count_method.tally, 'blocks')
end

T['default_count_opts']['has todo counting'] = function()
    local opts = child.lua_get('require("mkdnflow.foldtext").default_count_opts().todo')
    eq(type(opts), 'table')
end

T['default_count_opts']['has image counting'] = function()
    local opts = child.lua_get('require("mkdnflow.foldtext").default_count_opts().img')
    eq(type(opts), 'table')
    eq(opts.count_method.tally, 'global_matches')
end

T['default_count_opts']['has fenced block counting'] = function()
    -- Can't serialize functions, so just check structure
    local has_fncblk =
        child.lua_get('require("mkdnflow.foldtext").default_count_opts().fncblk ~= nil')
    local has_icon =
        child.lua_get('require("mkdnflow.foldtext").default_count_opts().fncblk.icon ~= nil')
    eq(has_fncblk, true)
    eq(has_icon, true)
end

T['default_count_opts']['has section counting'] = function()
    local opts = child.lua_get('require("mkdnflow.foldtext").default_count_opts().sec')
    eq(type(opts), 'table')
    eq(opts.count_method.tally, 'line_matches')
end

T['default_count_opts']['has paragraph counting'] = function()
    local opts = child.lua_get('require("mkdnflow.foldtext").default_count_opts().par')
    eq(type(opts), 'table')
end

T['default_count_opts']['has link counting'] = function()
    local opts = child.lua_get('require("mkdnflow.foldtext").default_count_opts().link')
    eq(type(opts), 'table')
    -- Should match multiple link types
    eq(type(opts.count_method.pattern), 'table')
end

-- =============================================================================
-- Integration with fold_text() - Full foldtext generation
-- =============================================================================
T['fold_text'] = new_set()

T['fold_text']['generates foldtext for H1'] = function()
    set_lines({ '# Main Heading', 'Content line 1', 'Content line 2' })
    set_cursor(1, 0)
    -- Create a fold
    child.lua([[require('mkdnflow.folds').foldSection()]])
    -- Get the foldtext
    child.lua('vim.v.foldstart = 1; vim.v.foldend = 3')
    local foldtext = child.lua_get([[require('mkdnflow.foldtext').fold_text()]])
    eq(type(foldtext), 'string')
    -- Should contain the heading text
    eq(foldtext:match('Main Heading') ~= nil, true)
end

T['fold_text']['includes line count when enabled'] = function()
    set_lines({ '# Heading', 'Line 1', 'Line 2', 'Line 3' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.folds').foldSection()]])
    child.lua('vim.v.foldstart = 1; vim.v.foldend = 4')
    local foldtext = child.lua_get([[require('mkdnflow.foldtext').fold_text()]])
    -- Default config has line_count = true
    eq(foldtext:match('%d+ lines?') ~= nil, true)
end

-- =============================================================================
-- Edge cases
-- =============================================================================
T['edge_cases'] = new_set()

T['edge_cases']['title_transformer handles empty string'] = function()
    -- While this shouldn't happen in practice, test robustness
    local result = child.lua_get([[require('mkdnflow.foldtext').default_title_transformer('')]])
    eq(type(result), 'string')
end

T['edge_cases']['title_transformer handles no hashes'] = function()
    local result =
        child.lua_get([[require('mkdnflow.foldtext').default_title_transformer('No heading')]])
    -- When no hashes, level is 0, so 6 empty circles
    eq(result:match('^○○○○○○ No heading$') ~= nil, true)
end

T['edge_cases']['handles very deep headings'] = function()
    local result = child.lua_get(
        [[require('mkdnflow.foldtext').default_title_transformer('####### Seven Hashes')]]
    )
    -- Level 7 would overflow the 6 circles - all filled
    eq(type(result), 'string')
end

T['edge_cases']['handles heading with only hashes'] = function()
    local result = child.lua_get([[require('mkdnflow.foldtext').default_title_transformer('###')]])
    eq(type(result), 'string')
end

return T
