-- tests/test_todo.lua
-- Tests for to-do list functionality

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

-- Helper to setup mkdnflow with fresh module state
-- The to_do module caches statuses at load time, so we need to clear the cache
local function setup_fresh(config_str)
    child.lua([[
        -- Clear cached modules to force fresh load with new config
        for name, _ in pairs(package.loaded) do
            if name:match('^mkdnflow') then
                package.loaded[name] = nil
            end
        end
        vim.api.nvim_buf_set_name(0, 'test.md')
        vim.bo.filetype = 'markdown'
    ]] .. config_str)
end

local T = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            -- Give buffer a .md filename so mkdnflow recognizes it and loads modules
            -- Then set filetype and initialize mkdnflow
            child.lua([[
                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
                require('mkdnflow').setup({})
            ]])
        end,
        post_once = child.stop,
    },
})

-- =============================================================================
-- To-do item detection
-- =============================================================================
T['get_to_do_item'] = new_set()

T['get_to_do_item']['detects basic to-do item'] = function()
    set_lines({ '- [ ] task' })
    set_cursor(1, 0)
    local valid = child.lua_get([[require('mkdnflow.to_do').get_to_do_item().valid]])
    eq(valid, true)
end

T['get_to_do_item']['detects in-progress to-do'] = function()
    set_lines({ '- [-] task' })
    set_cursor(1, 0)
    local valid = child.lua_get([[require('mkdnflow.to_do').get_to_do_item().valid]])
    local status_name = child.lua_get([[require('mkdnflow.to_do').get_to_do_item().status.name]])
    eq(valid, true)
    eq(status_name, 'in_progress')
end

T['get_to_do_item']['detects complete to-do'] = function()
    set_lines({ '- [X] task' })
    set_cursor(1, 0)
    local valid = child.lua_get([[require('mkdnflow.to_do').get_to_do_item().valid]])
    local status_name = child.lua_get([[require('mkdnflow.to_do').get_to_do_item().status.name]])
    eq(valid, true)
    eq(status_name, 'complete')
end

T['get_to_do_item']['rejects plain list item'] = function()
    set_lines({ '- plain item' })
    set_cursor(1, 0)
    local valid = child.lua_get([[require('mkdnflow.to_do').get_to_do_item().valid]])
    eq(valid, false)
end

T['get_to_do_item']['rejects regular text'] = function()
    set_lines({ 'just some text' })
    set_cursor(1, 0)
    local valid = child.lua_get([[require('mkdnflow.to_do').get_to_do_item().valid]])
    eq(valid, false)
end

T['get_to_do_item']['handles asterisk bullet'] = function()
    set_lines({ '* [ ] task' })
    set_cursor(1, 0)
    local valid = child.lua_get([[require('mkdnflow.to_do').get_to_do_item().valid]])
    eq(valid, true)
end

T['get_to_do_item']['handles plus bullet'] = function()
    set_lines({ '+ [ ] task' })
    set_cursor(1, 0)
    local valid = child.lua_get([[require('mkdnflow.to_do').get_to_do_item().valid]])
    eq(valid, true)
end

T['get_to_do_item']['handles ordered list'] = function()
    set_lines({ '1. [ ] task' })
    set_cursor(1, 0)
    local valid = child.lua_get([[require('mkdnflow.to_do').get_to_do_item().valid]])
    eq(valid, true)
end

T['get_to_do_item']['handles indented to-do'] = function()
    set_lines({ '    - [ ] indented task' })
    set_cursor(1, 0)
    local valid = child.lua_get([[require('mkdnflow.to_do').get_to_do_item().valid]])
    eq(valid, true)
end

-- =============================================================================
-- Status rotation (toggle_to_do)
-- =============================================================================
T['toggle_to_do'] = new_set()

T['toggle_to_do']['cycles from not_started to in_progress'] = function()
    set_lines({ '- [ ] task' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    eq(get_line(1), '- [-] task')
end

T['toggle_to_do']['cycles from in_progress to complete'] = function()
    set_lines({ '- [-] task' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    eq(get_line(1), '- [X] task')
end

T['toggle_to_do']['cycles from complete to not_started'] = function()
    set_lines({ '- [X] task' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    eq(get_line(1), '- [ ] task')
end

T['toggle_to_do']['full cycle returns to original'] = function()
    set_lines({ '- [ ] task' })
    set_cursor(1, 0)
    -- Toggle three times to complete a full cycle
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    eq(get_line(1), '- [ ] task')
end

T['toggle_to_do']['preserves task text'] = function()
    set_lines({ '- [ ] my important task with details' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    eq(get_line(1), '- [-] my important task with details')
end

T['toggle_to_do']['works on second line'] = function()
    set_lines({ '# Header', '- [ ] task' })
    set_cursor(2, 0)
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    eq(get_line(2), '- [-] task')
end

T['toggle_to_do']['handles lowercase x'] = function()
    set_lines({ '- [x] task' })
    set_cursor(1, 0)
    -- lowercase x should be recognized as complete
    local status_name = child.lua_get([[require('mkdnflow.to_do').get_to_do_item().status.name]])
    eq(status_name, 'complete')
end

-- =============================================================================
-- Cursor position after toggle
-- =============================================================================
T['cursor_position'] = new_set()

T['cursor_position']['stays at start of line'] = function()
    set_lines({ '- [ ] task' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    local cursor = get_cursor()
    eq(cursor[1], 1) -- row
    eq(cursor[2], 0) -- col
end

T['cursor_position']['stays on task text after toggle'] = function()
    set_lines({ '- [ ] task' })
    -- Position cursor on 't' of 'task' (index 6)
    set_cursor(1, 6)
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    local line = get_line(1)
    local cursor = get_cursor()
    eq(line, '- [-] task')
    eq(cursor[1], 1)
    -- Cursor should still be on 't' of 'task'
    eq(cursor[2], 6)
end

T['cursor_position']['adjusts when marker changes size'] = function()
    -- When going from [ ] to [-], both are same size, so position shouldn't change
    set_lines({ '- [ ] task' })
    set_cursor(1, 6) -- on 't'
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    local cursor = get_cursor()
    eq(cursor[2], 6)
end

T['cursor_position']['stays on correct row'] = function()
    set_lines({ '- [ ] first', '- [ ] second', '- [ ] third' })
    set_cursor(2, 0)
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    local cursor = get_cursor()
    eq(cursor[1], 2)
    eq(get_line(2), '- [-] second')
end

-- =============================================================================
-- Multiple to-do items
-- =============================================================================
T['multiple_items'] = new_set()

T['multiple_items']['toggle only affects current line'] = function()
    set_lines({ '- [ ] first', '- [ ] second', '- [ ] third' })
    set_cursor(2, 0)
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    eq(get_line(1), '- [ ] first')
    eq(get_line(2), '- [-] second')
    eq(get_line(3), '- [ ] third')
end

T['multiple_items']['can toggle each independently'] = function()
    set_lines({ '- [ ] first', '- [ ] second', '- [ ] third' })

    set_cursor(1, 0)
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])

    set_cursor(3, 0)
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])

    eq(get_line(1), '- [-] first')
    eq(get_line(2), '- [ ] second')
    eq(get_line(3), '- [X] third')
end

-- =============================================================================
-- Edge cases
-- =============================================================================
T['edge_cases'] = new_set()

T['edge_cases']['handles empty buffer gracefully'] = function()
    set_lines({ '' })
    set_cursor(1, 0)
    local valid = child.lua_get([[require('mkdnflow.to_do').get_to_do_item().valid]])
    eq(valid, false)
end

T['edge_cases']['handles to-do at end of buffer'] = function()
    set_lines({ '# Header', '', '- [ ] last item' })
    set_cursor(3, 0)
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    eq(get_line(3), '- [-] last item')
end

T['edge_cases']['handles to-do with special characters'] = function()
    set_lines({ '- [ ] task with `code` and *emphasis*' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    eq(get_line(1), '- [-] task with `code` and *emphasis*')
end

T['edge_cases']['toggle_to_do does nothing on plain text'] = function()
    set_lines({ 'just plain text' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    eq(get_line(1), 'just plain text') -- unchanged
end

T['edge_cases']['toggle_to_do does nothing on empty buffer'] = function()
    set_lines({ '' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    eq(get_line(1), '') -- unchanged
end

-- =============================================================================
-- List item to to-do conversion (#292)
-- =============================================================================
T['list_to_todo'] = new_set()

T['list_to_todo']['converts unordered list item with dash'] = function()
    set_lines({ '- plain list item' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    eq(get_line(1), '- [ ] plain list item')
end

T['list_to_todo']['converts unordered list item with asterisk'] = function()
    set_lines({ '* plain list item' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    eq(get_line(1), '* [ ] plain list item')
end

T['list_to_todo']['converts unordered list item with plus'] = function()
    set_lines({ '+ plain list item' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    eq(get_line(1), '+ [ ] plain list item')
end

T['list_to_todo']['converts ordered list item'] = function()
    set_lines({ '1. plain list item' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    eq(get_line(1), '1. [ ] plain list item')
end

T['list_to_todo']['converts indented list item'] = function()
    set_lines({ '    - indented list item' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    eq(get_line(1), '    - [ ] indented list item')
end

T['list_to_todo']['does not affect plain text'] = function()
    set_lines({ 'just plain text' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    eq(get_line(1), 'just plain text') -- unchanged
end

T['list_to_todo']['subsequent toggle cycles status after conversion'] = function()
    set_lines({ '- plain list item' })
    set_cursor(1, 0)
    -- First toggle: convert to to-do
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    eq(get_line(1), '- [ ] plain list item')
    -- Second toggle: cycle status
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    eq(get_line(1), '- [-] plain list item')
end

-- =============================================================================
-- sort_to_do_list() - Manual sorting command
-- =============================================================================
T['sort_to_do_list'] = new_set()

T['sort_to_do_list']['sorts items by section'] = function()
    set_lines({
        '- [X] complete task', -- section 3
        '- [ ] not started task', -- section 2
        '- [-] in progress task', -- section 1
    })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.to_do').sort_to_do_list()]])
    -- Expected order: in_progress (1), not_started (2), complete (3)
    eq(get_line(1), '- [-] in progress task')
    eq(get_line(2), '- [ ] not started task')
    eq(get_line(3), '- [X] complete task')
end

T['sort_to_do_list']['cursor tracks sorted item'] = function()
    set_lines({
        '- [X] complete task',
        '- [-] in progress task',
    })
    set_cursor(2, 0) -- On in_progress item
    child.lua([[require('mkdnflow.to_do').sort_to_do_list()]])
    -- in_progress moves to line 1, cursor should follow
    local cursor = get_cursor()
    eq(cursor[1], 1)
end

T['sort_to_do_list']['handles multiple items same status'] = function()
    set_lines({
        '- [X] complete 1',
        '- [ ] not started 1',
        '- [X] complete 2',
        '- [ ] not started 2',
    })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.to_do').sort_to_do_list()]])
    -- not_started (section 2) before complete (section 3)
    eq(get_line(1), '- [ ] not started 1')
    eq(get_line(2), '- [ ] not started 2')
    eq(get_line(3), '- [X] complete 1')
    eq(get_line(4), '- [X] complete 2')
end

T['sort_to_do_list']['preserves nested items'] = function()
    set_lines({
        '- [X] parent complete',
        '    - [ ] child task',
        '- [-] parent in progress',
    })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.to_do').sort_to_do_list()]])
    -- in_progress parent moves up, complete parent (with child) moves down
    eq(get_line(1), '- [-] parent in progress')
    eq(get_line(2), '- [X] parent complete')
    eq(get_line(3), '    - [ ] child task')
end

T['sort_to_do_list']['no-op on non-todo line'] = function()
    set_lines({
        '# Header',
        '- [X] task',
    })
    set_cursor(1, 0) -- On header, not to-do
    child.lua([[require('mkdnflow.to_do').sort_to_do_list()]])
    -- Lines unchanged
    eq(get_line(1), '# Header')
    eq(get_line(2), '- [X] task')
end

T['sort_to_do_list']['respects custom sort config'] = function()
    -- Reconfigure with custom sort order (not_started first)
    -- Must use setup_fresh to reload the to_do module with new config
    setup_fresh([[
        require('mkdnflow').setup({
            to_do = {
                statuses = {
                    { name = 'not_started', marker = ' ', sort = { section = 1, position = 'top' } },
                    { name = 'in_progress', marker = '-', sort = { section = 2, position = 'top' } },
                    { name = 'complete', marker = 'X', sort = { section = 3, position = 'top' } },
                },
            },
        })
    ]])
    set_lines({
        '- [-] in progress', -- section 2
        '- [ ] not started', -- section 1
    })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.to_do').sort_to_do_list()]])
    -- With custom config: not_started (1) before in_progress (2)
    eq(get_line(1), '- [ ] not started')
    eq(get_line(2), '- [-] in progress')
end

-- =============================================================================
-- Custom status count (#268) -- users can configure fewer or more statuses
-- =============================================================================
T['custom_status_count'] = new_set()

T['custom_status_count']['two statuses: cycles directly from not_started to complete'] = function()
    -- Configure with only 2 statuses (no in_progress)
    -- Array replacement in mergeTables allows this to work correctly
    setup_fresh([[
        require('mkdnflow').setup({
            to_do = {
                statuses = {
                    { name = 'not_started', marker = ' ' },
                    { name = 'complete', marker = 'X' },
                },
            },
        })
    ]])

    -- Verify we have exactly 2 statuses
    local num_statuses = child.lua_get('#require("mkdnflow").config.to_do.statuses')
    eq(num_statuses, 2)

    set_lines({ '- [ ] task' })
    set_cursor(1, 0)

    -- First toggle: not_started -> complete
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    eq(get_line(1), '- [X] task')

    -- Second toggle: complete -> not_started
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    eq(get_line(1), '- [ ] task')
end

T['custom_status_count']['two statuses: full cycle with two toggles'] = function()
    -- Configure with only 2 statuses
    setup_fresh([[
        require('mkdnflow').setup({
            to_do = {
                statuses = {
                    { name = 'not_started', marker = ' ' },
                    { name = 'complete', marker = 'X' },
                },
            },
        })
    ]])
    set_lines({ '- [ ] task' })
    set_cursor(1, 0)

    -- Two toggles should complete a full cycle
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    eq(get_line(1), '- [ ] task')
end

T['custom_status_count']['four statuses: cycles through all four'] = function()
    -- Configure with 4 statuses
    setup_fresh([[
        require('mkdnflow').setup({
            to_do = {
                statuses = {
                    { name = 'not_started', marker = ' ' },
                    { name = 'in_progress', marker = '-' },
                    { name = 'blocked', marker = '!' },
                    { name = 'complete', marker = 'X' },
                },
            },
        })
    ]])
    set_lines({ '- [ ] task' })
    set_cursor(1, 0)

    -- First toggle: not_started -> in_progress
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    eq(get_line(1), '- [-] task')

    -- Second toggle: in_progress -> blocked
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    eq(get_line(1), '- [!] task')

    -- Third toggle: blocked -> complete
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    eq(get_line(1), '- [X] task')

    -- Fourth toggle: complete -> not_started
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    eq(get_line(1), '- [ ] task')
end

T['custom_status_count']['four statuses: full cycle with four toggles'] = function()
    -- Configure with 4 statuses
    setup_fresh([[
        require('mkdnflow').setup({
            to_do = {
                statuses = {
                    { name = 'not_started', marker = ' ' },
                    { name = 'in_progress', marker = '-' },
                    { name = 'blocked', marker = '!' },
                    { name = 'complete', marker = 'X' },
                },
            },
        })
    ]])
    set_lines({ '- [ ] task' })
    set_cursor(1, 0)

    -- Four toggles should complete a full cycle
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    child.lua([[require('mkdnflow.to_do').toggle_to_do()]])
    eq(get_line(1), '- [ ] task')
end

-- =============================================================================
-- Visual mode toggle (E2E via keymap) — tests that <C-Space> in visual mode
-- toggles all selected to-do items through the full command/mapping pipeline
-- =============================================================================
T['visual_toggle_e2e'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                -- Source the plugin to register commands
                vim.cmd('runtime plugin/mkdnflow.lua')

                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
                require('mkdnflow').setup({
                    modules = { to_do = true, lists = true, maps = true },
                    silent = true,
                })

                -- Trigger autocmd to set up buffer-local mappings
                vim.cmd('doautocmd FileType')
            ]])
        end,
    },
})

T['visual_toggle_e2e']['<C-Space> toggles all visually selected to-do items'] = function()
    set_lines({
        '- [ ] first',
        '- [ ] second',
        '- [ ] third',
    })
    set_cursor(1, 0)
    -- Enter visual mode and select all three lines, then toggle
    child.type_keys('v', '2j', '<C-Space>')
    eq(get_line(1), '- [-] first')
    eq(get_line(2), '- [-] second')
    eq(get_line(3), '- [-] third')
end

T['visual_toggle_e2e']['<C-Space> toggles subset of visually selected to-do items'] = function()
    set_lines({
        '- [ ] first',
        '- [ ] second',
        '- [ ] third',
        '- [ ] fourth',
    })
    set_cursor(2, 0)
    -- Select lines 2-3 only
    child.type_keys('v', 'j', '<C-Space>')
    eq(get_line(1), '- [ ] first') -- untouched
    eq(get_line(2), '- [-] second')
    eq(get_line(3), '- [-] third')
    eq(get_line(4), '- [ ] fourth') -- untouched
end

T['visual_toggle_e2e']['<C-Space> toggles selection made from bottom to top'] = function()
    set_lines({
        '- [ ] first',
        '- [ ] second',
        '- [ ] third',
    })
    set_cursor(3, 0)
    -- Select upward from line 3 to line 1
    child.type_keys('v', '2k', '<C-Space>')
    eq(get_line(1), '- [-] first')
    eq(get_line(2), '- [-] second')
    eq(get_line(3), '- [-] third')
end

T['visual_toggle_e2e']['<C-Space> in visual mode only toggles single line when no motion'] = function()
    set_lines({
        '- [ ] first',
        '- [ ] second',
    })
    set_cursor(1, 0)
    -- Enter visual mode on line 1 only (no motion), then toggle
    child.type_keys('v', '<C-Space>')
    eq(get_line(1), '- [-] first')
    eq(get_line(2), '- [ ] second') -- untouched
end

T['visual_toggle_e2e']['V (line visual) toggles all selected to-do items'] = function()
    set_lines({
        '- [ ] first',
        '- [ ] second',
        '- [ ] third',
    })
    set_cursor(1, 0)
    -- Line visual mode: select all three lines, then toggle
    child.type_keys('V', '2j', '<C-Space>')
    eq(get_line(1), '- [-] first')
    eq(get_line(2), '- [-] second')
    eq(get_line(3), '- [-] third')
end

T['visual_toggle_e2e']['V (line visual) toggles subset'] = function()
    set_lines({
        '- [ ] first',
        '- [ ] second',
        '- [ ] third',
        '- [ ] fourth',
    })
    set_cursor(2, 0)
    -- Select lines 2-3 only
    child.type_keys('V', 'j', '<C-Space>')
    eq(get_line(1), '- [ ] first') -- untouched
    eq(get_line(2), '- [-] second')
    eq(get_line(3), '- [-] third')
    eq(get_line(4), '- [ ] fourth') -- untouched
end

T['visual_toggle_e2e']['V (line visual) single line'] = function()
    set_lines({
        '- [ ] first',
        '- [ ] second',
    })
    set_cursor(1, 0)
    -- Line visual on just one line
    child.type_keys('V', '<C-Space>')
    eq(get_line(1), '- [-] first')
    eq(get_line(2), '- [ ] second') -- untouched
end

-- =============================================================================
-- Visual mode toggle (direct Lua call path) — tests the fallback code path
-- where toggle_to_do() is called without range opts while in visual mode.
-- Uses <Cmd> mapping to preserve visual mode during execution.
-- =============================================================================
T['visual_toggle_direct'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
                require('mkdnflow').setup({
                    modules = { to_do = true, lists = true },
                    silent = true,
                })

                -- Set up a direct-call mapping using <Cmd> to preserve visual mode.
                -- This bypasses the command pipeline entirely, exercising the
                -- mode-detection fallback in toggle_to_do().
                vim.g.mapleader = ','
                vim.api.nvim_buf_set_keymap(0, 'x', ',t',
                    '<Cmd>lua require("mkdnflow.to_do").toggle_to_do()<CR>',
                    { noremap = true })
            ]])
        end,
    },
})

T['visual_toggle_direct']['v (characterwise) toggles multiple items'] = function()
    set_lines({
        '- [ ] first',
        '- [ ] second',
        '- [ ] third',
    })
    set_cursor(1, 0)
    -- <Cmd> preserves visual mode, so <Esc> afterwards to unblock child
    child.type_keys('v', '2j', ',t', '<Esc>')
    eq(get_line(1), '- [-] first')
    eq(get_line(2), '- [-] second')
    eq(get_line(3), '- [-] third')
end

T['visual_toggle_direct']['V (linewise) toggles multiple items'] = function()
    set_lines({
        '- [ ] first',
        '- [ ] second',
        '- [ ] third',
    })
    set_cursor(1, 0)
    child.type_keys('V', '2j', ',t', '<Esc>')
    eq(get_line(1), '- [-] first')
    eq(get_line(2), '- [-] second')
    eq(get_line(3), '- [-] third')
end

T['visual_toggle_direct']['<C-V> (blockwise) toggles multiple items'] = function()
    set_lines({
        '- [ ] first',
        '- [ ] second',
        '- [ ] third',
    })
    set_cursor(1, 0)
    child.type_keys('<C-V>', '2j', ',t', '<Esc>')
    eq(get_line(1), '- [-] first')
    eq(get_line(2), '- [-] second')
    eq(get_line(3), '- [-] third')
end

-- =============================================================================
-- Visual mode: plain list item conversion and mixed selections
-- =============================================================================
T['visual_toggle_conversion'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                vim.cmd('runtime plugin/mkdnflow.lua')

                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
                require('mkdnflow').setup({
                    modules = { to_do = true, lists = true, maps = true },
                    silent = true,
                })

                vim.cmd('doautocmd FileType')
            ]])
        end,
    },
})

T['visual_toggle_conversion']['converts plain list items to to-dos'] = function()
    set_lines({
        '- Task 1',
        '- Task 2',
        '- Task 3',
    })
    set_cursor(1, 0)
    child.type_keys('v', '2j', '<C-Space>')
    eq(get_line(1), '- [ ] Task 1')
    eq(get_line(2), '- [ ] Task 2')
    eq(get_line(3), '- [ ] Task 3')
end

T['visual_toggle_conversion']['converts ordered list items to to-dos'] = function()
    set_lines({
        '1. Task 1',
        '2. Task 2',
    })
    set_cursor(1, 0)
    child.type_keys('v', 'j', '<C-Space>')
    eq(get_line(1), '1. [ ] Task 1')
    eq(get_line(2), '2. [ ] Task 2')
end

T['visual_toggle_conversion']['handles mixed plain and existing to-dos'] = function()
    set_lines({
        '- Task 1',
        '- [ ] Task 2',
        '- Task 3',
    })
    set_cursor(1, 0)
    child.type_keys('v', '2j', '<C-Space>')
    eq(get_line(1), '- [ ] Task 1') -- converted
    eq(get_line(2), '- [-] Task 2') -- rotated
    eq(get_line(3), '- [ ] Task 3') -- converted
end

T['visual_toggle_conversion']['skips non-list lines'] = function()
    set_lines({
        '- Task 1',
        'Just some text',
        '- Task 3',
    })
    set_cursor(1, 0)
    child.type_keys('v', '2j', '<C-Space>')
    eq(get_line(1), '- [ ] Task 1') -- converted
    eq(get_line(2), 'Just some text') -- unchanged
    eq(get_line(3), '- [ ] Task 3') -- converted
end

T['visual_toggle_conversion']['converts subset of plain items'] = function()
    set_lines({
        '- Task 1',
        '- Task 2',
        '- Task 3',
        '- Task 4',
    })
    set_cursor(2, 0)
    child.type_keys('v', 'j', '<C-Space>')
    eq(get_line(1), '- Task 1') -- untouched
    eq(get_line(2), '- [ ] Task 2') -- converted
    eq(get_line(3), '- [ ] Task 3') -- converted
    eq(get_line(4), '- Task 4') -- untouched
end

T['visual_toggle_conversion']['works with V (line visual) for plain items'] = function()
    set_lines({
        '- Task 1',
        '- Task 2',
    })
    set_cursor(1, 0)
    child.type_keys('V', 'j', '<C-Space>')
    eq(get_line(1), '- [ ] Task 1')
    eq(get_line(2), '- [ ] Task 2')
end

-- =============================================================================
-- Visual mode toggle with nested to-do items and propagation
-- Tests that selecting a parent + children doesn't double-toggle children
-- =============================================================================
T['visual_toggle_nested'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                vim.cmd('runtime plugin/mkdnflow.lua')

                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
                require('mkdnflow').setup({
                    modules = { to_do = true, lists = true, maps = true },
                    to_do = {
                        status_propagation = { up = true, down = true },
                    },
                    silent = true,
                })

                vim.cmd('doautocmd FileType')
            ]])
        end,
    },
})

T['visual_toggle_nested']['parent+children: not_started to in_progress'] = function()
    set_lines({
        '- [ ] Parent',
        '    - [ ] Child 1',
        '    - [ ] Child 2',
    })
    set_cursor(1, 0)
    child.type_keys('V', '2j', '<C-Space>')
    -- Parent toggled to in_progress; children left to propagation
    -- (in_progress.propagate.down is a no-op, so children stay as-is)
    eq(get_line(1), '- [-] Parent')
    eq(get_line(2), '    - [ ] Child 1')
    eq(get_line(3), '    - [ ] Child 2')
end

T['visual_toggle_nested']['parent+children: in_progress to complete propagates down'] = function()
    set_lines({
        '- [-] Parent',
        '    - [-] Child 1',
        '    - [-] Child 2',
    })
    set_cursor(1, 0)
    child.type_keys('V', '2j', '<C-Space>')
    -- Parent toggled to complete; complete.propagate.down pushes to children
    eq(get_line(1), '- [X] Parent')
    eq(get_line(2), '    - [X] Child 1')
    eq(get_line(3), '    - [X] Child 2')
end

T['visual_toggle_nested']['parent+children: complete to not_started propagates down'] = function()
    set_lines({
        '- [X] Parent',
        '    - [X] Child 1',
        '    - [X] Child 2',
    })
    set_cursor(1, 0)
    child.type_keys('V', '2j', '<C-Space>')
    -- Parent toggled to not_started; not_started.propagate.down resets children
    eq(get_line(1), '- [ ] Parent')
    eq(get_line(2), '    - [ ] Child 1')
    eq(get_line(3), '    - [ ] Child 2')
end

T['visual_toggle_nested']['only children selected toggles independently'] = function()
    set_lines({
        '- [ ] Parent',
        '    - [ ] Child 1',
        '    - [ ] Child 2',
    })
    set_cursor(2, 0)
    -- Select only the children (lines 2-3), parent is outside range
    child.type_keys('V', 'j', '<C-Space>')
    -- Children toggle independently; upward propagation updates parent
    eq(get_line(2), '    - [-] Child 1')
    eq(get_line(3), '    - [-] Child 2')
    -- Parent should be in_progress via upward propagation
    eq(get_line(1), '- [-] Parent')
end

T['visual_toggle_nested']['deeply nested: grandparent selected skips all descendants'] = function()
    set_lines({
        '- [-] Grandparent',
        '    - [-] Parent',
        '        - [-] Child',
    })
    set_cursor(1, 0)
    child.type_keys('V', '2j', '<C-Space>')
    -- Only grandparent toggled; complete propagates down through the tree
    eq(get_line(1), '- [X] Grandparent')
    eq(get_line(2), '    - [X] Parent')
    eq(get_line(3), '        - [X] Child')
end

T['visual_toggle_nested']['siblings at same level all toggle'] = function()
    set_lines({
        '- [ ] Sibling 1',
        '- [ ] Sibling 2',
        '- [ ] Sibling 3',
    })
    set_cursor(1, 0)
    child.type_keys('V', '2j', '<C-Space>')
    -- Same-level items have no parent relationship; all toggle
    eq(get_line(1), '- [-] Sibling 1')
    eq(get_line(2), '- [-] Sibling 2')
    eq(get_line(3), '- [-] Sibling 3')
end

T['visual_toggle_nested']['two parent-child groups in one selection'] = function()
    set_lines({
        '- [ ] Parent A',
        '    - [ ] Child A1',
        '- [ ] Parent B',
        '    - [ ] Child B1',
    })
    set_cursor(1, 0)
    child.type_keys('V', '3j', '<C-Space>')
    -- Both parents toggle; children are skipped (handled by propagation)
    eq(get_line(1), '- [-] Parent A')
    eq(get_line(2), '    - [ ] Child A1')
    eq(get_line(3), '- [-] Parent B')
    eq(get_line(4), '    - [ ] Child B1')
end

T['visual_toggle_nested']['mixed plain items and nested to-dos'] = function()
    set_lines({
        '- Plain item',
        '- [ ] Parent',
        '    - [ ] Child',
    })
    set_cursor(1, 0)
    child.type_keys('V', '2j', '<C-Space>')
    -- Plain item converted; parent toggled; child skipped
    eq(get_line(1), '- [ ] Plain item')
    eq(get_line(2), '- [-] Parent')
    eq(get_line(3), '    - [ ] Child')
end

return T
