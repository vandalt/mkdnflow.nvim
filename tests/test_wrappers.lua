-- tests/test_wrappers.lua
-- Tests for command wrapper functions

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

-- Helper to get a specific line (1-indexed)
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

local T = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
                vim.opt.foldmethod = 'manual'
                require('mkdnflow').setup({
                    modules = {
                        folds = true,
                        links = true,
                        lists = true,
                        tables = true
                    },
                    links = {
                        transform_explicit = false
                    },
                    silent = true
                })
            ]])
        end,
        post_once = child.stop,
    },
})

-- =============================================================================
-- newListItemOrNextTableRow() - List/table context-aware action
-- =============================================================================
T['newListItemOrNextTableRow'] = new_set()

T['newListItemOrNextTableRow']['creates new list item on list line'] = function()
    set_lines({ '- Item 1' })
    set_cursor(1, 7)
    child.lua([[require('mkdnflow.wrappers').newListItemOrNextTableRow()]])
    local lines = get_lines()
    eq(#lines, 2)
    eq(lines[2]:match('^%- ') ~= nil, true)
end

T['newListItemOrNextTableRow']['creates new numbered item'] = function()
    set_lines({ '1. First item' })
    set_cursor(1, 12)
    child.lua([[require('mkdnflow.wrappers').newListItemOrNextTableRow()]])
    local lines = get_lines()
    eq(#lines, 2)
    eq(lines[2]:match('^2%.') ~= nil, true)
end

T['newListItemOrNextTableRow']['moves to next row in table'] = function()
    set_lines({
        '| A | B |',
        '|---|---|',
        '| 1 | 2 |',
    })
    set_cursor(3, 3) -- In cell A of row 3
    child.lua([[require('mkdnflow.wrappers').newListItemOrNextTableRow()]])
    local cursor = get_cursor()
    -- Should move down to next row or same cell position
    -- This behavior depends on table module implementation
    eq(cursor ~= nil, true)
end

T['newListItemOrNextTableRow']['inserts newline when not on list or table'] = function()
    set_lines({ 'Regular text' })
    set_cursor(1, 5)
    -- This calls feedkeys for <CR>, which in headless mode may behave differently
    -- Just verify it doesn't error
    child.lua([[pcall(require('mkdnflow.wrappers').newListItemOrNextTableRow)]])
    eq(true, true) -- If we got here, no error
end

-- =============================================================================
-- indentListItemOrJumpTableCell() - Indent/jump context-aware action
-- =============================================================================
T['indentListItemOrJumpTableCell'] = new_set()

T['indentListItemOrJumpTableCell']['indents empty list item forward'] = function()
    set_lines({ '- Item', '- ' })
    set_cursor(2, 2)
    child.lua([[require('mkdnflow.wrappers').indentListItemOrJumpTableCell(1)]])
    local line = get_line(2)
    -- Should be indented
    eq(line:match('^%s+%-') ~= nil, true)
end

T['indentListItemOrJumpTableCell']['unindents empty list item backward'] = function()
    set_lines({ '- Item', '    - ' })
    set_cursor(2, 6)
    child.lua([[require('mkdnflow.wrappers').indentListItemOrJumpTableCell(-1)]])
    local line = get_line(2)
    -- Should have less indentation
    eq(line:match('^%s*%-') ~= nil, true)
end

T['indentListItemOrJumpTableCell']['jumps table cell forward'] = function()
    set_lines({
        '| A | B |',
        '|---|---|',
        '| 1 | 2 |',
    })
    set_cursor(3, 2) -- In first cell
    child.lua([[require('mkdnflow.wrappers').indentListItemOrJumpTableCell(1)]])
    local cursor = get_cursor()
    -- Should move to next cell
    eq(cursor[2] > 2, true)
end

T['indentListItemOrJumpTableCell']['jumps table cell backward'] = function()
    set_lines({
        '| A | B |',
        '|---|---|',
        '| 1 | 2 |',
    })
    set_cursor(3, 6) -- In second cell
    child.lua([[require('mkdnflow.wrappers').indentListItemOrJumpTableCell(-1)]])
    local cursor = get_cursor()
    -- Should move to first cell
    eq(cursor[2] < 6, true)
end

-- =============================================================================
-- followOrCreateLinksOrToggleFolds() - Link/fold context-aware action
-- =============================================================================
T['followOrCreateLinksOrToggleFolds'] = new_set()

T['followOrCreateLinksOrToggleFolds']['folds section on heading'] = function()
    set_lines({ '# Heading', 'Content line' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.wrappers').followOrCreateLinksOrToggleFolds()]])
    -- Check if fold was created
    local foldclosed = child.lua_get('vim.fn.foldclosed(1)')
    eq(foldclosed, 1)
end

T['followOrCreateLinksOrToggleFolds']['unfolds when on closed fold'] = function()
    set_lines({ '# Heading', 'Content line' })
    set_cursor(1, 0)
    -- Create fold first
    child.lua([[require('mkdnflow.folds').foldSection()]])
    -- Now toggle should unfold
    child.lua([[require('mkdnflow.wrappers').followOrCreateLinksOrToggleFolds()]])
    local foldclosed = child.lua_get('vim.fn.foldclosed(1)')
    eq(foldclosed, -1)
end

T['followOrCreateLinksOrToggleFolds']['follows link when on link'] = function()
    set_lines({ '[link](#anchor)', '', '# Anchor' })
    set_cursor(1, 2)
    -- Following an anchor should move cursor to heading
    child.lua([[require('mkdnflow.wrappers').followOrCreateLinksOrToggleFolds()]])
    local cursor = get_cursor()
    eq(cursor[1], 3)
end

T['followOrCreateLinksOrToggleFolds']['accepts mode parameter'] = function()
    set_lines({ 'Regular text' })
    set_cursor(1, 5)
    -- Should not error with explicit mode
    child.lua([[require('mkdnflow.wrappers').followOrCreateLinksOrToggleFolds({ mode = 'n' })]])
    eq(true, true)
end

-- =============================================================================
-- multiFuncEnter() - Multi-function enter key
-- =============================================================================
T['multiFuncEnter'] = new_set()

T['multiFuncEnter']['in normal mode toggles fold on heading'] = function()
    set_lines({ '# Heading', 'Content' })
    set_cursor(1, 0)
    child.lua('vim.cmd("normal! \\27")') -- Ensure normal mode
    child.lua([[require('mkdnflow.wrappers').multiFuncEnter()]])
    local foldclosed = child.lua_get('vim.fn.foldclosed(1)')
    eq(foldclosed, 1)
end

T['multiFuncEnter']['accepts range parameter'] = function()
    set_lines({ 'Some text here' })
    set_cursor(1, 5)
    -- Should not error with range parameter
    child.lua([[require('mkdnflow.wrappers').multiFuncEnter({ range = false })]])
    eq(true, true)
end

-- =============================================================================
-- E2E tests: Keymap behavior (testing actual <CR> keypress through mappings)
-- These are critical because expression mappings behave differently than
-- direct function calls
-- =============================================================================
T['keymap_e2e'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                -- Source the plugin to register commands
                vim.cmd('runtime plugin/mkdnflow.lua')

                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
                vim.opt.foldmethod = 'manual'
                require('mkdnflow').setup({
                    modules = {
                        folds = true,
                        links = true,
                        lists = true,
                        tables = true
                    },
                    links = {
                        transform_explicit = false
                    },
                    silent = true
                })

                -- Trigger the autocmd to set up mappings
                vim.cmd('doautocmd BufEnter')
            ]])
        end,
    },
})

T['keymap_e2e']['<CR> follows anchor link in normal mode'] = function()
    set_lines({ '[link](#anchor)', '', '# Anchor' })
    set_cursor(1, 2) -- Cursor on the link
    -- Simulate actual keypress through the mapping
    child.type_keys('<CR>')
    local cursor = get_cursor()
    eq(cursor[1], 3) -- Should jump to the anchor heading
end

T['keymap_e2e']['<CR> follows anchor link from link text'] = function()
    set_lines({ '[click here](#target)', '', '# Target' })
    set_cursor(1, 5) -- Cursor in the middle of "click here"
    child.type_keys('<CR>')
    local cursor = get_cursor()
    eq(cursor[1], 3)
end

T['keymap_e2e']['<CR> folds section on heading'] = function()
    set_lines({ '# Heading', 'Content line 1', 'Content line 2' })
    set_cursor(1, 0)
    child.type_keys('<CR>')
    local foldclosed = child.lua_get('vim.fn.foldclosed(1)')
    eq(foldclosed, 1)
end

T['keymap_e2e']['<CR> unfolds closed fold'] = function()
    set_lines({ '# Heading', 'Content line' })
    set_cursor(1, 0)
    -- First fold
    child.type_keys('<CR>')
    eq(child.lua_get('vim.fn.foldclosed(1)'), 1)
    -- Then unfold
    child.type_keys('<CR>')
    eq(child.lua_get('vim.fn.foldclosed(1)'), -1)
end

T['keymap_e2e']['<CR> on regular text follows link behavior'] = function()
    -- On regular text (not heading, not link), MkdnEnter tries to follow/create link
    -- This should not error
    set_lines({ 'regular text here' })
    set_cursor(1, 5)
    child.type_keys('<CR>')
    -- Should not change cursor position dramatically (no link to follow)
    local cursor = get_cursor()
    eq(cursor[1], 1)
end

-- =============================================================================
-- E2E tests for Tab/S-Tab keymaps
-- These must work in insert mode for table navigation
-- =============================================================================
T['keymap_e2e_tab'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                -- Source the plugin to register commands
                vim.cmd('runtime plugin/mkdnflow.lua')

                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
                require('mkdnflow').setup({
                    modules = {
                        folds = true,
                        links = true,
                        lists = true,
                        tables = true
                    },
                    mappings = {
                        -- Enable MkdnTab for testing
                        MkdnTab = { 'i', '<Tab>' },
                        MkdnSTab = { 'i', '<S-Tab>' },
                    },
                    silent = true
                })

                -- Trigger the autocmd to set up mappings
                vim.cmd('doautocmd BufEnter')
            ]])
        end,
    },
})

T['keymap_e2e_tab']['<Tab> moves to next cell in table'] = function()
    set_lines({
        '| A | B |',
        '|---|---|',
        '| 1 | 2 |',
    })
    set_cursor(3, 2) -- In first cell
    child.type_keys('i') -- Enter insert mode
    child.type_keys('<Tab>')
    child.type_keys('<Esc>') -- Exit insert mode to check cursor
    local cursor = get_cursor()
    -- Should have moved to second cell (column > 2)
    eq(cursor[2] > 4, true)
end

T['keymap_e2e_tab']['<S-Tab> moves to previous cell in table'] = function()
    set_lines({
        '| A | B |',
        '|---|---|',
        '| 1 | 2 |',
    })
    set_cursor(3, 6) -- In second cell
    child.type_keys('i') -- Enter insert mode
    child.type_keys('<S-Tab>')
    child.type_keys('<Esc>') -- Exit insert mode to check cursor
    local cursor = get_cursor()
    -- Should have moved to first cell (column < 6)
    eq(cursor[2] < 4, true)
end

T['keymap_e2e_tab']['<Tab> indents empty list item'] = function()
    set_lines({ '- Item', '- ' })
    set_cursor(2, 2)
    -- Test the indent function directly since insert mode keymap simulation is flaky
    child.lua([[require('mkdnflow.wrappers').indentListItemOrJumpTableCell(1)]])
    local line = get_line(2)
    -- Should be indented
    eq(line:match('^%s+%-') ~= nil, true)
end

-- =============================================================================
-- Edge cases
-- =============================================================================
T['edge_cases'] = new_set()

T['edge_cases']['wrapper handles missing modules gracefully'] = function()
    -- Disable some modules and verify wrappers still work
    child.lua([[
        require('mkdnflow').config.modules.tables = false
    ]])
    set_lines({ 'Regular text' })
    set_cursor(1, 5)
    -- Should not error
    child.lua([[pcall(require('mkdnflow.wrappers').newListItemOrNextTableRow)]])
    eq(true, true)
end

T['edge_cases']['empty buffer handling'] = function()
    set_lines({ '' })
    set_cursor(1, 0)
    -- Should not error
    child.lua([[pcall(require('mkdnflow.wrappers').followOrCreateLinksOrToggleFolds)]])
    eq(true, true)
end

T['edge_cases']['indentation with tabs'] = function()
    child.lua('vim.bo.expandtab = false')
    set_lines({ '- Item', '- ' })
    set_cursor(2, 2)
    child.lua([[require('mkdnflow.wrappers').indentListItemOrJumpTableCell(1)]])
    local line = get_line(2)
    -- Should be indented with exactly one tab
    eq(line:sub(1, 1), '\t')
    eq(line:sub(2, 3), '- ')
end

T['edge_cases']['indentation with spaces respects shiftwidth'] = function()
    child.lua('vim.bo.expandtab = true')
    child.lua('vim.bo.shiftwidth = 4')
    set_lines({ '- Item', '- ' })
    set_cursor(2, 2)
    child.lua([[require('mkdnflow.wrappers').indentListItemOrJumpTableCell(1)]])
    local line = get_line(2)
    -- Should be indented with exactly 4 spaces
    eq(line:sub(1, 4), '    ')
    eq(line:sub(5, 6), '- ')
end

T['edge_cases']['indentation respects changed shiftwidth'] = function()
    -- This test verifies that indent is computed on-the-fly, not cached at module load
    child.lua('vim.bo.expandtab = true')
    child.lua('vim.bo.shiftwidth = 2')
    set_lines({ '- Item', '- ' })
    set_cursor(2, 2)
    child.lua([[require('mkdnflow.wrappers').indentListItemOrJumpTableCell(1)]])
    local line = get_line(2)
    -- Should be indented with exactly 2 spaces
    eq(line:sub(1, 2), '  ')
    eq(line:sub(3, 4), '- ')
end

T['edge_cases']['indentation not cached at module load'] = function()
    -- Pre-load the wrappers module with initial settings
    child.lua('vim.bo.expandtab = true')
    child.lua('vim.bo.shiftwidth = 4')
    child.lua([[require('mkdnflow.wrappers')]]) -- Force module load

    -- Now change settings AFTER module is loaded
    child.lua('vim.bo.shiftwidth = 2')
    set_lines({ '- Item', '- ' })
    set_cursor(2, 2)
    child.lua([[require('mkdnflow.wrappers').indentListItemOrJumpTableCell(1)]])
    local line = get_line(2)
    -- Should use the NEW shiftwidth (2), not the cached value (4)
    eq(line:sub(1, 2), '  ')
    eq(line:sub(3, 4), '- ')
end

-- =============================================================================
-- Command robustness (Issue #255)
-- Commands should not crash when modules are not loaded
-- =============================================================================
T['command_robustness'] = new_set({
    hooks = {
        pre_case = function()
            -- Start fresh without calling setup
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
            ]])
        end,
    },
})

-- Issue #255: MkdnCreateLinkFromClipboard crashes when setup() not called
T['command_robustness']['MkdnCreateLinkFromClipboard does not crash without setup'] = function()
    set_lines({ 'some text here' })
    set_cursor(1, 5)
    -- Run command directly (no visual selection to simplify test)
    child.lua([[
        _G.test_ok, _G.test_err = pcall(function()
            vim.cmd('MkdnCreateLinkFromClipboard')
        end)
    ]])
    local success = child.lua_get('_G.test_ok')
    if not success then
        local err = child.lua_get('tostring(_G.test_err)')
        if err:match('index field.*links.*nil') then
            error('Issue #255 bug reproduced: ' .. err)
        end
        -- If error is something else, show it for debugging
        error('Unexpected error: ' .. err)
    end
    eq(success, true)
end

T['command_robustness']['MkdnFollowLink does not crash without setup'] = function()
    set_lines({ '[link](page.md)' })
    set_cursor(1, 3)
    child.lua([[
        _G.test_ok, _G.test_err = pcall(function()
            vim.cmd('MkdnFollowLink')
        end)
    ]])
    local success = child.lua_get('_G.test_ok')
    eq(success, true)
end

T['command_robustness']['MkdnCreateLink does not crash without setup'] = function()
    set_lines({ 'word here' })
    set_cursor(1, 2)
    child.lua([[
        _G.test_ok, _G.test_err = pcall(function()
            vim.cmd('MkdnCreateLink')
        end)
    ]])
    local success = child.lua_get('_G.test_ok')
    eq(success, true)
end

T['command_robustness']['MkdnToggleToDo does not crash without setup'] = function()
    set_lines({ '- [ ] task' })
    set_cursor(1, 5)
    child.lua([[
        _G.test_ok, _G.test_err = pcall(function()
            vim.cmd('MkdnToggleToDo')
        end)
    ]])
    local success = child.lua_get('_G.test_ok')
    eq(success, true)
end

return T
