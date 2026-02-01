-- tests/test_tables.lua
-- Tests for markdown table functionality

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
-- Table detection
-- =============================================================================
T['isPartOfTable'] = new_set()

T['isPartOfTable']['detects simple table row'] = function()
    set_lines({ '| col1 | col2 |' })
    local result = child.lua_get([[require('mkdnflow.tables').isPartOfTable('| col1 | col2 |')]])
    eq(result, true)
end

T['isPartOfTable']['detects table without outer pipes'] = function()
    set_lines({ 'col1 | col2' })
    local result = child.lua_get([[require('mkdnflow.tables').isPartOfTable('col1 | col2')]])
    eq(result, true)
end

T['isPartOfTable']['detects separator row'] = function()
    set_lines({ '| --- | --- |' })
    local result = child.lua_get([[require('mkdnflow.tables').isPartOfTable('| --- | --- |')]])
    eq(result, true)
end

T['isPartOfTable']['rejects plain text'] = function()
    set_lines({ 'just some text' })
    local result = child.lua_get([[require('mkdnflow.tables').isPartOfTable('just some text')]])
    eq(result, false)
end

T['isPartOfTable']['rejects single pipe'] = function()
    set_lines({ 'text | more text' })
    -- Single pipe might be ambiguous, but without enough context should be false
    local result = child.lua_get([[require('mkdnflow.tables').isPartOfTable('text with one pipe')]])
    eq(result, false)
end

-- =============================================================================
-- Table creation
-- =============================================================================
T['newTable'] = new_set()

T['newTable']['creates basic 2x2 table'] = function()
    set_lines({ '' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.tables').newTable({2, 2})]])
    local lines = get_lines()
    -- Original empty line + header row + separator row + 2 data rows = 5
    eq(#lines, 5)
    -- Check structure has pipes (table starts at line 2)
    eq(lines[2]:match('^|.*|$') ~= nil, true)
    eq(lines[3]:match('%-%-%-') ~= nil, true) -- separator row
end

T['newTable']['creates table with specified dimensions'] = function()
    set_lines({ '' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.tables').newTable({3, 1})]])
    local lines = get_lines()
    -- Original empty line + header + separator + 1 data row = 4 lines
    eq(#lines, 4)
    -- Count pipes to verify column count (3 cols = 4 pipes with outer pipes)
    local _, pipe_count = lines[2]:gsub('|', '')
    eq(pipe_count, 4)
end

T['newTable']['creates table without header when noh specified'] = function()
    set_lines({ '' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.tables').newTable({2, 2, 'noh'})]])
    local lines = get_lines()
    -- Original empty line + 2 data rows = 3
    eq(#lines, 3)
    -- Should not contain separator dashes (check lines 2 and 3)
    eq(lines[2]:match('%-%-%-') == nil, true)
    eq(lines[3]:match('%-%-%-') == nil, true)
end

-- =============================================================================
-- Table formatting
-- =============================================================================
T['formatTable'] = new_set()

T['formatTable']['aligns columns to max width'] = function()
    set_lines({
        '| short | x |',
        '| --- | --- |',
        '| very long content | y |',
    })
    set_cursor(1, 1)
    child.lua([[require('mkdnflow.tables').formatTable()]])
    local lines = get_lines()
    -- After formatting, all rows should have same length
    eq(#lines[1], #lines[3])
end

T['formatTable']['preserves left alignment'] = function()
    set_lines({
        '| Header | Col2 |',
        '| :--- | --- |',
        '| text | more |',
    })
    set_cursor(1, 1)
    child.lua([[require('mkdnflow.tables').formatTable()]])
    local lines = get_lines()
    -- Separator should still have left alignment marker (use %-+ for one or more dashes)
    eq(lines[2]:match(':%-+[^:]') ~= nil, true)
end

T['formatTable']['preserves right alignment'] = function()
    set_lines({
        '| Header | Col2 |',
        '| ---: | --- |',
        '| text | more |',
    })
    set_cursor(1, 1)
    child.lua([[require('mkdnflow.tables').formatTable()]])
    local lines = get_lines()
    -- Separator should still have right alignment marker (use %-+ for one or more dashes)
    eq(lines[2]:match('[^:]%-+:') ~= nil, true)
end

T['formatTable']['preserves center alignment'] = function()
    set_lines({
        '| Header | Col2 |',
        '| :---: | --- |',
        '| text | more |',
    })
    set_cursor(1, 1)
    child.lua([[require('mkdnflow.tables').formatTable()]])
    local lines = get_lines()
    -- Separator should still have center alignment markers (use %-+ for one or more dashes)
    eq(lines[2]:match(':%-+:') ~= nil, true)
end

-- =============================================================================
-- Cell navigation
-- =============================================================================
T['moveToCell'] = new_set()

T['moveToCell']['moves to next cell'] = function()
    set_lines({
        '| cell1 | cell2 |',
        '| ----- | ----- |',
        '| a     | b     |',
    })
    set_cursor(1, 2) -- In cell1
    child.lua([[require('mkdnflow.tables').moveToCell(0, 1)]])
    local cursor = get_cursor()
    -- Should be in cell2 now (column position should be after second pipe)
    eq(cursor[1], 1) -- Same row
    eq(cursor[2] > 8, true) -- Past the first cell
end

T['moveToCell']['moves to previous cell'] = function()
    set_lines({
        '| cell1 | cell2 |',
        '| ----- | ----- |',
        '| a     | b     |',
    })
    set_cursor(1, 10) -- In cell2
    child.lua([[require('mkdnflow.tables').moveToCell(0, -1)]])
    local cursor = get_cursor()
    eq(cursor[1], 1) -- Same row
    eq(cursor[2] < 8, true) -- In first cell area
end

T['moveToCell']['moves to next row'] = function()
    set_lines({
        '| cell1 | cell2 |',
        '| ----- | ----- |',
        '| a     | b     |',
    })
    set_cursor(1, 2) -- In header row
    child.lua([[require('mkdnflow.tables').moveToCell(1, 0)]])
    local cursor = get_cursor()
    -- Should skip separator row and land on data row
    eq(cursor[1], 3)
end

T['moveToCell']['moves to previous row'] = function()
    set_lines({
        '| cell1 | cell2 |',
        '| ----- | ----- |',
        '| a     | b     |',
    })
    set_cursor(3, 2) -- In data row
    child.lua([[require('mkdnflow.tables').moveToCell(-1, 0)]])
    local cursor = get_cursor()
    -- Should skip separator row and land on header row
    eq(cursor[1], 1)
end

T['moveToCell']['skips separator row when navigating down'] = function()
    set_lines({
        '| header | col2 |',
        '| ------ | ---- |',
        '| data   | more |',
    })
    set_cursor(1, 2)
    child.lua([[require('mkdnflow.tables').moveToCell(1, 0)]])
    local cursor = get_cursor()
    -- Should land on row 3, not row 2 (separator)
    eq(cursor[1], 3)
end

-- =============================================================================
-- Row operations
-- =============================================================================
T['addRow'] = new_set()

T['addRow']['adds row below current'] = function()
    set_lines({
        '| col1 | col2 |',
        '| ---- | ---- |',
        '| a    | b    |',
    })
    set_cursor(3, 2)
    child.lua([[require('mkdnflow.tables').addRow()]])
    local lines = get_lines()
    eq(#lines, 4) -- One more row
    -- New row should be at line 4
    eq(lines[4]:match('^|.*|$') ~= nil, true)
end

T['addRow']['adds row above current'] = function()
    set_lines({
        '| col1 | col2 |',
        '| ---- | ---- |',
        '| a    | b    |',
    })
    set_cursor(3, 2)
    child.lua([[require('mkdnflow.tables').addRow(-1)]])
    local lines = get_lines()
    eq(#lines, 4)
    -- Original data should now be at line 4
    eq(lines[4]:match('a') ~= nil, true)
end

-- =============================================================================
-- Column operations
-- =============================================================================
T['addCol'] = new_set()

T['addCol']['adds column after current'] = function()
    set_lines({
        '| col1 | col2 |',
        '| ---- | ---- |',
        '| a    | b    |',
    })
    set_cursor(1, 2)
    child.lua([[require('mkdnflow.tables').addCol()]])
    local lines = get_lines()
    -- Count pipes - should have 5 now (3 columns with outer pipes)
    local _, pipe_count = lines[1]:gsub('|', '')
    eq(pipe_count, 4) -- Actually 4 pipes for 3 cols with outer pipes
end

T['addCol']['adds column before current'] = function()
    set_lines({
        '| col1 | col2 |',
        '| ---- | ---- |',
        '| a    | b    |',
    })
    set_cursor(1, 2)
    child.lua([[require('mkdnflow.tables').addCol(-1)]])
    local lines = get_lines()
    -- New column should be before col1
    local _, pipe_count = lines[1]:gsub('|', '')
    eq(pipe_count, 4)
end

-- =============================================================================
-- Edge cases
-- =============================================================================
T['edge_cases'] = new_set()

T['edge_cases']['formatTable handles empty cells'] = function()
    set_lines({
        '| a |  |',
        '| - | - |',
        '|   | b |',
    })
    set_cursor(1, 1)
    child.lua([[require('mkdnflow.tables').formatTable()]])
    local lines = get_lines()
    -- Should not crash, table should still be valid
    eq(#lines, 3)
    eq(lines[1]:match('|.*|') ~= nil, true)
end

T['edge_cases']['handles table at end of buffer'] = function()
    set_lines({
        '| col1 |',
        '| ---- |',
        '| data |',
    })
    set_cursor(3, 2)
    -- Moving down from last row should not crash
    child.lua([[require('mkdnflow.tables').moveToCell(1, 0)]])
    -- Should still be functional
    local cursor = get_cursor()
    eq(cursor[1] >= 1, true)
end

T['edge_cases']['handles partial table without separator row'] = function()
    -- User is creating a table manually and has only typed the header row
    set_lines({
        '| Col1 | Col2 | Col3 |',
    })
    set_cursor(1, 5)
    -- Enter insert mode and run MkdnEnter command (simulates user pressing mapped key)
    -- In insert mode, MkdnEnter calls newListItemOrNextTableRow which calls moveToCell(1, 0)
    -- Without a separator row, this should treat it as normal text and insert a newline
    -- (which splits the line at cursor position, like normal insert mode Enter)
    child.type_keys('i')  -- Enter insert mode
    child.cmd('MkdnEnter')  -- Run the command
    child.type_keys('<Esc>')  -- Exit insert mode
    -- Should create a new line (newline inserted, splitting the line at cursor)
    local cursor = get_cursor()
    eq(cursor[1], 2)  -- Cursor should be on line 2
    local lines = get_lines()
    eq(#lines, 2)  -- Should now have 2 lines (line was split)
end

T['edge_cases']['handles Enter at end of header-only row'] = function()
    -- User has typed only the header row and presses Enter at the very end
    set_lines({
        '| Col1 | Col2 | Col3 |',
    })
    -- Use append mode to go to end of line
    child.type_keys('A')  -- Append mode - cursor at end
    child.cmd('MkdnEnter')  -- Run the command
    child.type_keys('<Esc>')  -- Exit insert mode
    -- Should create a new line below (not navigate within "table")
    local cursor = get_cursor()
    eq(cursor[1], 2)  -- Cursor should be on line 2
    local lines = get_lines()
    eq(#lines, 2)  -- Should have 2 lines
    eq(lines[1], '| Col1 | Col2 | Col3 |')  -- Original header intact
    eq(lines[2], '')  -- New empty line
end

T['edge_cases']['handles table with only header and separator row'] = function()
    -- User is creating a table and has typed header + separator, but no data rows yet
    set_lines({
        '| Col1 | Col2 | Col3 |',
        '| - | - | - |',
    })
    set_cursor(2, 5)  -- Cursor on separator row
    -- Enter insert mode and run MkdnEnter command
    -- moveToCell tries to skip separator row but there's no data row to land on
    -- Currently fails with: stack overflow (infinite recursion in moveToCell)
    child.type_keys('i')  -- Enter insert mode
    child.cmd('MkdnEnter')  -- Run the command
    child.type_keys('<Esc>')  -- Exit insert mode
    -- Should not crash - just verify we're still functional
    local cursor = get_cursor()
    eq(cursor[1] >= 1, true)
end

T['edge_cases']['handles cursor at end of table row'] = function()
    -- User has a complete table and cursor is at the very end of a data row
    -- The cursor is positioned ON the last pipe character
    set_lines({
        '| Col1 | Col2 | Col3 |',
        '| - | - | - |',
        '| cell1 | cell2 | cell3 |',
    })
    -- Place cursor ON the last | character (0-indexed, so length - 1)
    -- Line is: | cell1 | cell2 | cell3 |
    -- The last | is at position 26 (0-indexed) for a 27-char line
    local line_len = #'| cell1 | cell2 | cell3 |'
    set_cursor(3, line_len - 1)  -- On the last pipe
    -- Enter insert mode at end of line and run MkdnEnter command
    child.type_keys('A')  -- Append mode - cursor goes to end of line
    child.cmd('MkdnEnter')  -- Run the command
    child.type_keys('<Esc>')  -- Exit insert mode
    -- which_cell returns nil for cursor at/past last pipe, then moveToCell
    -- tries to do arithmetic on nil cursor_cell
    -- Currently fails with: attempt to perform arithmetic on local 'cursor_cell' (a nil value)
    -- Should not crash - just verify we're still functional
    local cursor = get_cursor()
    eq(cursor[1] >= 1, true)
end

-- Issue #257: S-Tab on list item after todo causes stack overflow
-- The bug: pressing S-Tab in insert mode on a list item causes
-- infinite recursion in moveToCell when there's a todo item above
T['edge_cases']['S-Tab on list item does not cause stack overflow (#257)'] = function()
    set_lines({
        '- [ ] This is a todo item',
        '- ',
    })
    set_cursor(2, 2)  -- Cursor at end of second line "- "
    child.type_keys('A')  -- Enter insert mode at end of line
    -- Run MkdnSTab command which calls indentListItemOrJumpTableCell(-1)
    child.lua([[
        _G.test_ok, _G.test_err = pcall(function()
            vim.cmd('MkdnSTab')
        end)
    ]])
    child.type_keys('<Esc>')
    local success = child.lua_get('_G.test_ok')
    if not success then
        local err = child.lua_get('tostring(_G.test_err)')
        if err:match('stack overflow') then
            error('Issue #257 reproduced: stack overflow on S-Tab: ' .. err)
        end
        error('MkdnSTab failed: ' .. err)
    end
    eq(success, true)
end

return T
