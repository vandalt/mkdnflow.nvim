-- tests/test_lists.lua
-- Tests for list management functionality

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
                vim.bo.expandtab = true
                vim.bo.shiftwidth = 4
                require('mkdnflow').setup({})
            ]])
        end,
        post_once = child.stop,
    },
})

-- =============================================================================
-- hasListType() - Detect list type from line
-- =============================================================================
T['hasListType'] = new_set()

-- Unordered lists (ul)
T['hasListType']['detects dash unordered list'] = function()
    local result = child.lua_get([[require('mkdnflow.lists').hasListType('- item')]])
    eq(result, 'ul')
end

T['hasListType']['detects asterisk unordered list'] = function()
    local result = child.lua_get([[require('mkdnflow.lists').hasListType('* item')]])
    eq(result, 'ul')
end

T['hasListType']['detects plus unordered list'] = function()
    local result = child.lua_get([[require('mkdnflow.lists').hasListType('+ item')]])
    eq(result, 'ul')
end

T['hasListType']['detects indented unordered list'] = function()
    local result = child.lua_get([[require('mkdnflow.lists').hasListType('    - nested item')]])
    eq(result, 'ul')
end

-- Ordered lists (ol)
T['hasListType']['detects ordered list'] = function()
    local result = child.lua_get([[require('mkdnflow.lists').hasListType('1. first item')]])
    eq(result, 'ol')
end

T['hasListType']['detects ordered list with higher number'] = function()
    local result = child.lua_get([[require('mkdnflow.lists').hasListType('42. item forty-two')]])
    eq(result, 'ol')
end

T['hasListType']['detects indented ordered list'] = function()
    local result = child.lua_get([[require('mkdnflow.lists').hasListType('    1. nested item')]])
    eq(result, 'ol')
end

-- Unordered to-do lists (ultd)
T['hasListType']['detects unordered to-do not started'] = function()
    local result = child.lua_get([[require('mkdnflow.lists').hasListType('- [ ] task')]])
    eq(result, 'ultd')
end

T['hasListType']['detects unordered to-do in progress'] = function()
    local result = child.lua_get([[require('mkdnflow.lists').hasListType('- [-] task')]])
    eq(result, 'ultd')
end

T['hasListType']['detects unordered to-do complete'] = function()
    local result = child.lua_get([[require('mkdnflow.lists').hasListType('- [x] task')]])
    eq(result, 'ultd')
end

T['hasListType']['detects unordered to-do with asterisk'] = function()
    local result = child.lua_get([[require('mkdnflow.lists').hasListType('* [ ] task')]])
    eq(result, 'ultd')
end

-- Ordered to-do lists (oltd)
T['hasListType']['detects ordered to-do'] = function()
    local result = child.lua_get([[require('mkdnflow.lists').hasListType('1. [ ] task')]])
    eq(result, 'oltd')
end

T['hasListType']['detects ordered to-do complete'] = function()
    local result = child.lua_get([[require('mkdnflow.lists').hasListType('1. [x] task')]])
    eq(result, 'oltd')
end

T['hasListType']['detects ordered to-do with higher number'] = function()
    local result = child.lua_get([[require('mkdnflow.lists').hasListType('5. [ ] fifth task')]])
    eq(result, 'oltd')
end

-- Non-list lines
T['hasListType']['returns nil for plain text'] = function()
    local result = child.lua_get([[require('mkdnflow.lists').hasListType('just some text')]])
    eq(result, vim.NIL)
end

T['hasListType']['returns nil for heading'] = function()
    local result = child.lua_get([[require('mkdnflow.lists').hasListType('# Heading')]])
    eq(result, vim.NIL)
end

T['hasListType']['returns nil for empty line'] = function()
    local result = child.lua_get([[require('mkdnflow.lists').hasListType('')]])
    eq(result, vim.NIL)
end

T['hasListType']['returns nil for dash without space'] = function()
    -- '-item' is not a list item (no space after dash)
    local result = child.lua_get([[require('mkdnflow.lists').hasListType('-item')]])
    eq(result, vim.NIL)
end

-- Indentation detection
T['hasListType']['returns indentation for unordered list'] = function()
    child.lua([[_G.li_type, _G.indent = require('mkdnflow.lists').hasListType('    - item')]])
    local indent = child.lua_get('_G.indent')
    eq(indent, '    ')
end

T['hasListType']['returns empty indentation for non-indented list'] = function()
    child.lua([[_G.li_type, _G.indent = require('mkdnflow.lists').hasListType('- item')]])
    local indent = child.lua_get('_G.indent')
    eq(indent, '')
end

-- Uses current line when no argument
T['hasListType']['uses current line when nil passed'] = function()
    set_lines({ '- list item here' })
    set_cursor(1, 0)
    local result = child.lua_get([[require('mkdnflow.lists').hasListType(nil)]])
    eq(result, 'ul')
end

-- =============================================================================
-- newListItem() - Create new list items
-- =============================================================================
T['newListItem'] = new_set()

-- Basic list item creation
-- Note: With carry=true, text after cursor is moved to new line.
-- Use carry=false to create empty new item regardless of cursor position.
T['newListItem']['creates new unordered item below'] = function()
    set_lines({ '- first item' })
    set_cursor(1, 5)
    -- carry=false means don't carry text after cursor
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[1], '- first item')
    eq(lines[2], '- ')
end

T['newListItem']['creates new ordered item below'] = function()
    set_lines({ '1. first item' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[1], '1. first item')
    eq(lines[2], '2. ')
end

T['newListItem']['creates new item above'] = function()
    set_lines({ '- first item' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.lists').newListItem(false, true, true, 'n')]])
    local lines = get_lines()
    eq(lines[1], '- ')
    eq(lines[2], '- first item')
end

-- Preserves indentation
T['newListItem']['preserves indentation for nested list'] = function()
    set_lines({ '    - nested item' })
    set_cursor(1, 10)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[2], '    - ')
end

-- Ordered list numbering
T['newListItem']['increments number for ordered list'] = function()
    set_lines({ '5. fifth item' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[2], '6. ')
end

-- To-do items
T['newListItem']['creates to-do with not_started status'] = function()
    set_lines({ '- [ ] first task' })
    set_cursor(1, 10)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[2], '- [ ] ')
end

T['newListItem']['creates ordered to-do with correct number'] = function()
    set_lines({ '1. [ ] first task' })
    set_cursor(1, 10)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[2], '2. [ ] ')
end

-- Carry text behavior
T['newListItem']['carries text after cursor to new line'] = function()
    set_lines({ '- first second' })
    set_cursor(1, 7) -- cursor after "first"
    child.lua([[require('mkdnflow.lists').newListItem(true, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[1], '- first')
    eq(lines[2], '-  second')
end

T['newListItem']['does not carry when carry=false'] = function()
    set_lines({ '- first second' })
    set_cursor(1, 7) -- cursor after "first"
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[1], '- first second')
    eq(lines[2], '- ')
end

-- Empty item demotion
T['newListItem']['demotes empty indented item'] = function()
    set_lines({ '    - ' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.lists').newListItem(true, false, true, 'n')]])
    local line = get_line(1)
    eq(line, '- ')
end

T['newListItem']['removes marker from empty non-indented item'] = function()
    set_lines({ '- ' })
    set_cursor(1, 1)
    child.lua([[require('mkdnflow.lists').newListItem(true, false, true, 'n')]])
    local line = get_line(1)
    eq(line, '')
end

T['newListItem']['demotes tab-indented empty item when expandtab is false'] = function()
    child.lua('vim.bo.expandtab = false')
    set_lines({ '\t- ' })
    set_cursor(1, 2)
    child.lua([[require('mkdnflow.lists').newListItem(true, false, true, 'n')]])
    local line = get_line(1)
    eq(line, '- ')
end

-- Colon at end creates indented child
T['newListItem']['indents after line ending with colon'] = function()
    set_lines({ '- parent item:' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[2], '    - ')
end

T['newListItem']['indents ordered list after colon with number 1'] = function()
    set_lines({ '1. parent item:' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[2], '    1. ')
end

T['newListItem']['uses tabs when expandtab is false'] = function()
    child.lua('vim.bo.expandtab = false')
    set_lines({ '- parent item:' })
    set_cursor(1, 14) -- end of line
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[2], '\t- ')
end

T['newListItem']['respects shiftwidth for indent size'] = function()
    child.lua('vim.bo.expandtab = true')
    child.lua('vim.bo.shiftwidth = 2')
    set_lines({ '- parent item:' })
    set_cursor(1, 14)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[2], '  - ') -- 2 spaces, not 4
end

-- Non-list lines
T['newListItem']['does nothing on non-list line without alt'] = function()
    set_lines({ 'plain text' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.lists').newListItem(true, false, true, 'n')]])
    local lines = get_lines()
    eq(#lines, 1)
    eq(lines[1], 'plain text')
end

-- =============================================================================
-- updateNumbering() - Fix ordered list numbering
-- =============================================================================
T['updateNumbering'] = new_set()

T['updateNumbering']['fixes broken sequence'] = function()
    set_lines({ '1. first', '1. second', '1. third' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.lists').updateNumbering()]])
    local lines = get_lines()
    eq(lines[1], '1. first')
    eq(lines[2], '2. second')
    eq(lines[3], '3. third')
end

T['updateNumbering']['starts from specified number'] = function()
    set_lines({ '1. first', '1. second', '1. third' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.lists').updateNumbering({5})]])
    local lines = get_lines()
    eq(lines[1], '5. first')
    eq(lines[2], '6. second')
    eq(lines[3], '7. third')
end

T['updateNumbering']['respects offset parameter'] = function()
    set_lines({ 'text', '1. first', '1. second' })
    set_cursor(1, 0) -- on 'text' line
    child.lua([[require('mkdnflow.lists').updateNumbering({}, 1)]])
    local lines = get_lines()
    eq(lines[2], '1. first')
    eq(lines[3], '2. second')
end

T['updateNumbering']['preserves correct numbering'] = function()
    set_lines({ '1. first', '2. second', '3. third' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.lists').updateNumbering()]])
    local lines = get_lines()
    eq(lines[1], '1. first')
    eq(lines[2], '2. second')
    eq(lines[3], '3. third')
end

T['updateNumbering']['renumbers single item to 1 by default'] = function()
    -- updateNumbering() defaults to starting from 1
    set_lines({ '5. only item' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.lists').updateNumbering()]])
    local line = get_line(1)
    eq(line, '1. only item')
end

T['updateNumbering']['preserves number when start matches'] = function()
    -- Pass {5} to start numbering from 5
    set_lines({ '5. only item' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.lists').updateNumbering({5})]])
    local line = get_line(1)
    eq(line, '5. only item')
end

T['updateNumbering']['does nothing on unordered list'] = function()
    set_lines({ '- first', '- second' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.lists').updateNumbering()]])
    local lines = get_lines()
    eq(lines[1], '- first')
    eq(lines[2], '- second')
end

-- =============================================================================
-- patterns table - Exported patterns
-- =============================================================================
T['patterns'] = new_set()

T['patterns']['exports ul patterns'] = function()
    local result = child.lua_get([[require('mkdnflow.lists').patterns.ul ~= nil]])
    eq(result, true)
end

T['patterns']['exports ol patterns'] = function()
    local result = child.lua_get([[require('mkdnflow.lists').patterns.ol ~= nil]])
    eq(result, true)
end

T['patterns']['exports ultd patterns'] = function()
    local result = child.lua_get([[require('mkdnflow.lists').patterns.ultd ~= nil]])
    eq(result, true)
end

T['patterns']['exports oltd patterns'] = function()
    local result = child.lua_get([[require('mkdnflow.lists').patterns.oltd ~= nil]])
    eq(result, true)
end

T['patterns']['ul.main matches unordered list'] = function()
    local result =
        child.lua_get([[string.match('- item', require('mkdnflow.lists').patterns.ul.main) ~= nil]])
    eq(result, true)
end

T['patterns']['ol.main matches ordered list'] = function()
    local result = child.lua_get(
        [[string.match('1. item', require('mkdnflow.lists').patterns.ol.main) ~= nil]]
    )
    eq(result, true)
end

-- =============================================================================
-- Edge cases
-- =============================================================================
T['edge_cases'] = new_set()

T['edge_cases']['handles tab-indented lists'] = function()
    child.lua('vim.bo.expandtab = false')
    set_lines({ '\t- item' })
    local result = child.lua_get([[require('mkdnflow.lists').hasListType('\t- item')]])
    eq(result, 'ul')
end

T['edge_cases']['handles deeply nested list'] = function()
    local result = child.lua_get([[require('mkdnflow.lists').hasListType('        - deep item')]])
    eq(result, 'ul')
end

T['edge_cases']['handles list with special characters'] = function()
    set_lines({ '- item with *bold* and _italic_' })
    set_cursor(1, 10)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[2], '- ')
end

T['edge_cases']['handles to-do with unicode marker'] = function()
    -- Some users might use unicode checkmarks
    local result = child.lua_get([[require('mkdnflow.lists').hasListType('- [✓] task')]])
    eq(result, 'ultd')
end

T['edge_cases']['preserves to-do marker style on new item'] = function()
    -- Regardless of what marker the current item has, new items get not_started
    set_lines({ '- [x] completed task' })
    set_cursor(1, 10)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[2], '- [ ] ')
end

-- =============================================================================
-- Sibling detection tests (get_siblings behavior)
-- =============================================================================
T['siblings'] = new_set()

T['siblings']['finds all siblings at same level'] = function()
    set_lines({ '1. one', '1. two', '1. three' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.lists').updateNumbering()]])
    local lines = get_lines()
    -- All three should be renumbered (proving siblings were found)
    eq(lines[1], '1. one')
    eq(lines[2], '2. two')
    eq(lines[3], '3. three')
end

T['siblings']['stops at different list type'] = function()
    set_lines({ '1. ol item', '- ul item', '1. another ol' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.lists').updateNumbering()]])
    local lines = get_lines()
    -- ul and ol are separate lists - only first item should stay as 1
    eq(lines[1], '1. ol item')
    eq(lines[2], '- ul item')
    eq(lines[3], '1. another ol') -- Separate list, not renumbered
end

T['siblings']['skips children when finding siblings'] = function()
    set_lines({ '1. parent', '    1. child', '1. sibling' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.lists').updateNumbering()]])
    local lines = get_lines()
    -- parent and sibling are siblings (should become 1, 2)
    eq(lines[1], '1. parent')
    eq(lines[2], '    1. child')
    eq(lines[3], '2. sibling')
end

T['siblings']['handles deeply nested lists'] = function()
    set_lines({ '- L0', '    - L1', '        - L2', '            - L3' })
    set_cursor(1, 0)
    local result = child.lua_get([[require('mkdnflow.lists').hasListType('- L0')]])
    eq(result, 'ul')
    -- Creating new item at L0 should not affect nested items
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[2], '- ')
    eq(lines[3], '    - L1')
end

T['siblings']['stops at lesser indentation'] = function()
    set_lines({ '- parent', '    1. nested1', '    1. nested2', '- another parent' })
    set_cursor(2, 4)
    child.lua([[require('mkdnflow.lists').updateNumbering()]])
    local lines = get_lines()
    -- nested1 and nested2 are siblings
    eq(lines[2], '    1. nested1')
    eq(lines[3], '    2. nested2')
end

-- =============================================================================
-- Parent/Child relationship tests
-- =============================================================================
T['hierarchy'] = new_set()

T['hierarchy']['detects parent item via indentation'] = function()
    -- When creating a new item after colon, we get indented child
    set_lines({ '- parent:' })
    set_cursor(1, 8)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[1], '- parent:')
    eq(lines[2], '    - ')
end

T['hierarchy']['handles multi-level nesting'] = function()
    set_lines({ '- grandparent:', '    - parent:', '        - child' })
    set_cursor(2, 12)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    -- New child at third level
    eq(lines[3], '        - ')
    eq(lines[4], '        - child')
end

T['hierarchy']['sibling numbering after demotion'] = function()
    -- When demoted, the item becomes a sibling at a lesser level
    set_lines({ '    1. item1', '    1. item2', '    1. item3' })
    set_cursor(2, 4)
    child.lua([[require('mkdnflow.lists').updateNumbering()]])
    local lines = get_lines()
    eq(lines[1], '    1. item1')
    eq(lines[2], '    2. item2')
    eq(lines[3], '    3. item3')
end

T['hierarchy']['mixed nesting levels preserved'] = function()
    -- updateNumbering only operates on siblings at the same level
    -- It does NOT recursively update nested lists
    set_lines({
        '1. first',
        '    1. nested a',
        '    1. nested b',
        '1. second',
    })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.lists').updateNumbering()]])
    local lines = get_lines()
    eq(lines[1], '1. first')
    eq(lines[2], '    1. nested a')
    eq(lines[3], '    1. nested b') -- Nested items not updated by parent's updateNumbering
    eq(lines[4], '2. second')
end

-- =============================================================================
-- Issue regression tests
-- =============================================================================
T['regressions'] = new_set()

-- Issue #199: newListItem Fails for Ordered List on First Line of File
T['regressions']['ordered list on first line of file (#199)'] = function()
    set_lines({ '1. first item' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[1], '1. first item')
    eq(lines[2], '2. ')
end

-- Issue #112: Plus characters not recognized
T['regressions']['plus character in unordered list (#112)'] = function()
    local result = child.lua_get([[require('mkdnflow.lists').hasListType('+ item')]])
    eq(result, 'ul')
end

-- Issue #79: MkdnExtendList splitting line when not on a list
T['regressions']['extend list on non-list line (#79)'] = function()
    set_lines({ 'plain text' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.lists').newListItem(true, false, true, 'n')]])
    local lines = get_lines()
    eq(#lines, 1) -- Should not modify
    eq(lines[1], 'plain text')
end

T['regressions']['ul with asterisk marker'] = function()
    set_lines({ '* asterisk item' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[2], '* ')
end

T['regressions']['ul with plus marker'] = function()
    set_lines({ '+ plus item' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[2], '+ ')
end

T['regressions']['empty to-do item demotion'] = function()
    set_lines({ '    - [ ] ' })
    set_cursor(1, 9)
    child.lua([[require('mkdnflow.lists').newListItem(true, false, true, 'n')]])
    local line = get_line(1)
    eq(line, '- [ ] ')
end

T['regressions']['empty ordered to-do item demotion'] = function()
    set_lines({ '    1. [ ] ' })
    set_cursor(1, 10)
    child.lua([[require('mkdnflow.lists').newListItem(true, false, true, 'n')]])
    local line = get_line(1)
    eq(line, '1. [ ] ')
end

-- =============================================================================
-- Cursor position tests
-- =============================================================================
T['cursor'] = new_set()

T['cursor']['lands at end of marker after newListItem ul'] = function()
    set_lines({ '- item' })
    set_cursor(1, 6)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local cursor = get_cursor()
    eq(cursor[1], 2) -- On new line
    -- Cursor is 0-indexed, "- " has length 2, so cursor at position 1 means after "-" but before space ends
    -- Actual behavior: cursor lands at column 1 (after the dash, on the space)
    eq(cursor[2], 1) -- At position 1 (0-indexed)
end

T['cursor']['lands at end of marker after newListItem ol'] = function()
    set_lines({ '1. item' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local cursor = get_cursor()
    eq(cursor[1], 2) -- On new line
    -- "2. " has length 3, cursor lands at position 2 (0-indexed)
    eq(cursor[2], 2) -- At position 2 (0-indexed)
end

T['cursor']['lands at end of marker after newListItem ultd'] = function()
    set_lines({ '- [ ] item' })
    set_cursor(1, 10)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local cursor = get_cursor()
    eq(cursor[1], 2) -- On new line
    -- "- [ ] " has length 6, cursor lands at position 5 (0-indexed)
    eq(cursor[2], 5) -- At position 5 (0-indexed)
end

T['cursor']['lands at end of marker after newListItem oltd'] = function()
    set_lines({ '1. [ ] item' })
    set_cursor(1, 10)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local cursor = get_cursor()
    eq(cursor[1], 2) -- On new line
    -- "2. [ ] " has length 7, cursor lands at position 6 (0-indexed)
    eq(cursor[2], 6) -- At position 6 (0-indexed)
end

T['cursor']['correct after demotion from indented'] = function()
    set_lines({ '    - ' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.lists').newListItem(true, false, true, 'n')]])
    local cursor = get_cursor()
    -- After demotion, "- " has length 2, cursor at position 1 (0-indexed)
    eq(cursor[2], 1) -- At position 1 (0-indexed)
end

T['cursor']['correct after full demotion'] = function()
    set_lines({ '- ' })
    set_cursor(1, 1)
    child.lua([[require('mkdnflow.lists').newListItem(true, false, true, 'n')]])
    local cursor = get_cursor()
    eq(cursor[2], 0) -- At start of empty line
end

T['cursor']['does not move when cursor_moves is false'] = function()
    set_lines({ '- item' })
    set_cursor(1, 3)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, false, 'n')]])
    local cursor = get_cursor()
    eq(cursor[1], 1) -- Still on original line
    eq(cursor[2], 3) -- Same column
end

-- =============================================================================
-- Buffer boundary tests
-- =============================================================================
T['boundaries'] = new_set()

T['boundaries']['first line of buffer'] = function()
    set_lines({ '- only item' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    eq(#get_lines(), 2)
end

T['boundaries']['last line of buffer'] = function()
    set_lines({ '- item' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(#lines, 2)
    eq(lines[2], '- ')
end

T['boundaries']['empty buffer'] = function()
    set_lines({ '' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.lists').newListItem(true, false, true, 'n')]])
    -- Should not crash, buffer stays as is (not a list line)
    local lines = get_lines()
    eq(#lines, 1)
    eq(lines[1], '')
end

T['boundaries']['single line buffer with ordered list'] = function()
    set_lines({ '1. only' })
    set_cursor(1, 3)
    child.lua([[require('mkdnflow.lists').updateNumbering()]])
    -- Should handle single item without error
    local line = get_line(1)
    eq(line, '1. only')
end

T['boundaries']['newListItem above on first line'] = function()
    set_lines({ '- item' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.lists').newListItem(false, true, true, 'n')]])
    local lines = get_lines()
    eq(lines[1], '- ')
    eq(lines[2], '- item')
end

T['boundaries']['newListItem below on last line'] = function()
    set_lines({ 'text', '- item' })
    set_cursor(2, 5)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(#lines, 3)
    eq(lines[3], '- ')
end

T['boundaries']['updateNumbering at end of buffer'] = function()
    set_lines({ '1. first', '1. last' })
    set_cursor(2, 0)
    child.lua([[require('mkdnflow.lists').updateNumbering()]])
    local lines = get_lines()
    eq(lines[2], '2. last')
end

-- =============================================================================
-- Multi-digit number tests
-- =============================================================================
T['multi_digit'] = new_set()

T['multi_digit']['detects 2-digit numbers'] = function()
    local result = child.lua_get([[require('mkdnflow.lists').hasListType('10. tenth item')]])
    eq(result, 'ol')
end

T['multi_digit']['detects 3-digit numbers'] = function()
    local result = child.lua_get([[require('mkdnflow.lists').hasListType('100. hundredth')]])
    eq(result, 'ol')
end

T['multi_digit']['increments correctly past 9'] = function()
    set_lines({ '9. ninth' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[2], '10. ')
end

T['multi_digit']['renumbers multi-digit sequence'] = function()
    set_lines({ '10. tenth', '10. eleventh', '10. twelfth' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.lists').updateNumbering({10})]])
    local lines = get_lines()
    eq(lines[1], '10. tenth')
    eq(lines[2], '11. eleventh')
    eq(lines[3], '12. twelfth')
end

T['multi_digit']['handles 99 to 100 transition'] = function()
    set_lines({ '99. item' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[2], '100. ')
end

T['multi_digit']['preserves indentation with multi-digit'] = function()
    set_lines({ '    10. nested' })
    set_cursor(1, 8)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[2], '    11. ')
end

-- =============================================================================
-- Unicode tests
-- =============================================================================
T['unicode'] = new_set()

T['unicode']['list with CJK content'] = function()
    set_lines({ '- 你好世界' })
    set_cursor(1, 2)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(#lines, 2)
    eq(lines[2], '- ')
end

T['unicode']['to-do with unicode checkmark'] = function()
    local result = child.lua_get([[require('mkdnflow.lists').hasListType('- [✓] done')]])
    eq(result, 'ultd')
end

T['unicode']['to-do with emoji marker'] = function()
    -- Emoji markers should be detected within the 4-byte allowance
    local result = child.lua_get([[require('mkdnflow.lists').hasListType('- [🔥] hot')]])
    eq(result, 'ultd')
end

T['unicode']['ordered to-do with unicode marker'] = function()
    local result = child.lua_get([[require('mkdnflow.lists').hasListType('1. [✓] done')]])
    eq(result, 'oltd')
end

T['unicode']['preserves unicode content after newListItem'] = function()
    set_lines({ '- emoji 😀 here' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[1], '- emoji 😀 here')
    eq(lines[2], '- ')
end

-- =============================================================================
-- Numbering correction tests
-- =============================================================================
T['numbering'] = new_set()

T['numbering']['corrects from middle of list'] = function()
    set_lines({ '1. first', '5. second', '3. third' })
    set_cursor(2, 0)
    child.lua([[require('mkdnflow.lists').updateNumbering()]])
    local lines = get_lines()
    -- Starting from middle, should correct all siblings
    eq(lines[1], '1. first')
    eq(lines[2], '2. second')
    eq(lines[3], '3. third')
end

T['numbering']['handles gaps in sequence'] = function()
    set_lines({ '1. a', '10. b', '100. c' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.lists').updateNumbering()]])
    local lines = get_lines()
    eq(lines[1], '1. a')
    eq(lines[2], '2. b')
    eq(lines[3], '3. c')
end

T['numbering']['preserves content with numbers'] = function()
    set_lines({ '1. item with 42 in it' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.lists').updateNumbering()]])
    local line = get_line(1)
    eq(line, '1. item with 42 in it')
end

T['numbering']['handles indented ordered lists'] = function()
    set_lines({ '    1. nested', '    1. items' })
    set_cursor(1, 4)
    child.lua([[require('mkdnflow.lists').updateNumbering()]])
    local lines = get_lines()
    eq(lines[1], '    1. nested')
    eq(lines[2], '    2. items')
end

T['numbering']['starts from custom number'] = function()
    set_lines({ '1. a', '1. b', '1. c' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.lists').updateNumbering({5})]])
    local lines = get_lines()
    eq(lines[1], '5. a')
    eq(lines[2], '6. b')
    eq(lines[3], '7. c')
end

T['numbering']['does not affect unordered lists'] = function()
    set_lines({ '- a', '- b', '- c' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.lists').updateNumbering()]])
    local lines = get_lines()
    eq(lines[1], '- a')
    eq(lines[2], '- b')
    eq(lines[3], '- c')
end

T['numbering']['renumbers to-do ordered list'] = function()
    set_lines({ '1. [ ] first', '1. [ ] second' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.lists').updateNumbering()]])
    local lines = get_lines()
    eq(lines[1], '1. [ ] first')
    eq(lines[2], '2. [ ] second')
end

T['numbering']['preserves to-do status during renumbering'] = function()
    set_lines({ '1. [x] done', '1. [ ] pending' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.lists').updateNumbering()]])
    local lines = get_lines()
    eq(lines[1], '1. [x] done')
    eq(lines[2], '2. [ ] pending')
end

-- =============================================================================
-- Mixed list types tests
-- =============================================================================
T['mixed_types'] = new_set()

T['mixed_types']['ul followed by ol are separate'] = function()
    set_lines({ '- ul item', '1. ol item' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[1], '- ul item')
    eq(lines[2], '- ')
    eq(lines[3], '1. ol item')
end

T['mixed_types']['to-do and regular ul are separate'] = function()
    set_lines({ '- [ ] to-do', '- regular' })
    local result1 = child.lua_get([[require('mkdnflow.lists').hasListType('- [ ] to-do')]])
    local result2 = child.lua_get([[require('mkdnflow.lists').hasListType('- regular')]])
    eq(result1, 'ultd')
    eq(result2, 'ul')
end

T['mixed_types']['nested mixed types'] = function()
    set_lines({ '1. ordered', '    - unordered child' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[1], '1. ordered')
    eq(lines[2], '2. ')
    eq(lines[3], '    - unordered child')
end

T['mixed_types']['ol sibling detection stops at ul'] = function()
    set_lines({ '1. first ol', '- ul item', '1. second ol' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.lists').updateNumbering()]])
    local lines = get_lines()
    -- First ol is isolated, should stay 1
    eq(lines[1], '1. first ol')
    eq(lines[2], '- ul item')
    eq(lines[3], '1. second ol')
end

T['mixed_types']['oltd and ul are separate'] = function()
    set_lines({ '1. [ ] ordered to-do', '- ul item' })
    local result1 = child.lua_get([[require('mkdnflow.lists').hasListType('1. [ ] ordered to-do')]])
    local result2 = child.lua_get([[require('mkdnflow.lists').hasListType('- ul item')]])
    eq(result1, 'oltd')
    eq(result2, 'ul')
end

-- =============================================================================
-- Config option tests
-- =============================================================================
T['config'] = new_set()

T['config']['respects shiftwidth=2'] = function()
    child.lua('vim.bo.shiftwidth = 2')
    set_lines({ '- parent:' })
    set_cursor(1, 8)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[2], '  - ') -- 2 spaces
end

T['config']['respects shiftwidth=8'] = function()
    child.lua('vim.bo.shiftwidth = 8')
    set_lines({ '- parent:' })
    set_cursor(1, 8)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[2], '        - ') -- 8 spaces
end

T['config']['respects expandtab=false'] = function()
    child.lua('vim.bo.expandtab = false')
    set_lines({ '- parent:' })
    set_cursor(1, 8)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[2], '\t- ')
end

T['config']['demotion with shiftwidth=2'] = function()
    child.lua('vim.bo.shiftwidth = 2')
    set_lines({ '  - ' })
    set_cursor(1, 3)
    child.lua([[require('mkdnflow.lists').newListItem(true, false, true, 'n')]])
    local line = get_line(1)
    eq(line, '- ')
end

T['config']['demotion with tabs'] = function()
    child.lua('vim.bo.expandtab = false')
    set_lines({ '\t- ' })
    set_cursor(1, 2)
    child.lua([[require('mkdnflow.lists').newListItem(true, false, true, 'n')]])
    local line = get_line(1)
    eq(line, '- ')
end

-- =============================================================================
-- newListItem above tests
-- =============================================================================
T['newListItem_above'] = new_set()

T['newListItem_above']['creates item above unordered'] = function()
    set_lines({ '- existing' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.lists').newListItem(false, true, true, 'n')]])
    local lines = get_lines()
    eq(lines[1], '- ')
    eq(lines[2], '- existing')
end

T['newListItem_above']['creates item above ordered'] = function()
    set_lines({ '5. existing' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.lists').newListItem(false, true, true, 'n')]])
    local lines = get_lines()
    eq(lines[1], '5. ')
    eq(lines[2], '6. existing')
end

T['newListItem_above']['creates item above to-do'] = function()
    set_lines({ '- [ ] existing' })
    set_cursor(1, 10)
    child.lua([[require('mkdnflow.lists').newListItem(false, true, true, 'n')]])
    local lines = get_lines()
    eq(lines[1], '- [ ] ')
    eq(lines[2], '- [ ] existing')
end

T['newListItem_above']['renumbers ordered list after above'] = function()
    set_lines({ '1. first', '2. second' })
    set_cursor(2, 3)
    child.lua([[require('mkdnflow.lists').newListItem(false, true, true, 'n')]])
    local lines = get_lines()
    eq(lines[1], '1. first')
    eq(lines[2], '2. ')
    eq(lines[3], '3. second')
end

-- =============================================================================
-- Carry text tests
-- =============================================================================
T['carry'] = new_set()

T['carry']['carries text to new ul item'] = function()
    set_lines({ '- before after' })
    set_cursor(1, 8) -- After "before" (0-indexed: "- before" = 8 chars)
    child.lua([[require('mkdnflow.lists').newListItem(true, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[1], '- before')
    -- The implementation carries text starting from cursor position, including leading space
    eq(lines[2], '-  after')
end

T['carry']['carries text to new ol item'] = function()
    set_lines({ '1. before after' })
    set_cursor(1, 9) -- After "before" (0-indexed: "1. before" = 9 chars)
    child.lua([[require('mkdnflow.lists').newListItem(true, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[1], '1. before')
    -- The implementation carries text starting from cursor position, including leading space
    eq(lines[2], '2.  after')
end

T['carry']['cursor on last char still carries that char'] = function()
    set_lines({ '- item' })
    -- "- item" has length 6
    -- Cursor can't be placed past position 5 (the last char 'm')
    -- The implementation checks: col ~= #line, where col is 0-indexed cursor position
    -- With cursor at 5 and #line = 6, 5 ~= 6 is true, so carry happens
    set_cursor(1, 5) -- 0-indexed, position 5 is on the last char 'm'
    child.lua([[require('mkdnflow.lists').newListItem(true, false, true, 'n')]])
    local lines = get_lines()
    -- The last character is carried to the new line
    eq(lines[1], '- ite')
    eq(lines[2], '- m')
end

T['carry']['no carry with carry=false'] = function()
    set_lines({ '- before after' })
    set_cursor(1, 8) -- After "before "
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[1], '- before after')
    eq(lines[2], '- ')
end

-- =============================================================================
-- Special marker tests
-- =============================================================================
T['markers'] = new_set()

T['markers']['dash marker'] = function()
    set_lines({ '- dash' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[2], '- ')
end

T['markers']['asterisk marker'] = function()
    set_lines({ '* asterisk' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[2], '* ')
end

T['markers']['plus marker'] = function()
    set_lines({ '+ plus' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[2], '+ ')
end

T['markers']['period after number'] = function()
    set_lines({ '1. period' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[2], '2. ')
end

-- =============================================================================
-- Mode tests
-- =============================================================================
T['modes'] = new_set()

T['modes']['ends in normal mode when specified'] = function()
    set_lines({ '- item' })
    set_cursor(1, 5)
    child.type_keys('i') -- Enter insert mode first
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local mode = child.lua_get('vim.api.nvim_get_mode().mode')
    eq(mode, 'n')
end

T['modes']['ends in insert mode when specified'] = function()
    set_lines({ '- item' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'i')]])
    local mode = child.lua_get('vim.api.nvim_get_mode().mode')
    eq(mode, 'i')
    child.type_keys('<Esc>') -- Clean up
end

-- =============================================================================
-- Colon behavior tests
-- =============================================================================
T['colon'] = new_set()

T['colon']['indents unordered list after colon'] = function()
    set_lines({ '- parent:' })
    set_cursor(1, 9)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[2], '    - ')
end

T['colon']['indents ordered list after colon with number 1'] = function()
    set_lines({ '1. parent:' })
    set_cursor(1, 10)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[2], '    1. ')
end

T['colon']['indents to-do after colon'] = function()
    set_lines({ '- [ ] parent:' })
    set_cursor(1, 13)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[2], '    - [ ] ')
end

T['colon']['does not indent when above=true'] = function()
    set_lines({ '- parent:' })
    set_cursor(1, 9)
    child.lua([[require('mkdnflow.lists').newListItem(false, true, true, 'n')]])
    local lines = get_lines()
    -- Above should not check colon
    eq(lines[1], '- ')
    eq(lines[2], '- parent:')
end

T['colon']['colon in middle does not indent'] = function()
    set_lines({ '- has: colon' })
    set_cursor(1, 12)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[2], '- ')
end

-- =============================================================================
-- alt parameter tests
-- =============================================================================
T['alt'] = new_set()

T['alt']['feeds keys on non-list line when alt provided'] = function()
    set_lines({ 'plain text' })
    set_cursor(1, 5)
    -- alt='o' would normally open a new line below in vim
    child.lua([[require('mkdnflow.lists').newListItem(true, false, true, 'n', 'o')]])
    -- After 'o' is fed, we should be in insert mode on a new line
    local mode = child.lua_get('vim.api.nvim_get_mode().mode')
    eq(mode, 'i')
    local lines = get_lines()
    eq(#lines, 2)
    child.type_keys('<Esc>') -- Clean up
end

T['alt']['does nothing on non-list line without alt'] = function()
    set_lines({ 'plain text' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.lists').newListItem(true, false, true, 'n')]])
    local lines = get_lines()
    eq(#lines, 1)
    eq(lines[1], 'plain text')
end

-- =============================================================================
-- Pattern exposure tests
-- =============================================================================
T['patterns_exposed'] = new_set()

T['patterns_exposed']['ul patterns work'] = function()
    local result =
        child.lua_get([[string.match('- test', require('mkdnflow.lists').patterns.ul.main)]])
    eq(result ~= vim.NIL, true)
end

T['patterns_exposed']['ol patterns work'] = function()
    local result =
        child.lua_get([[string.match('1. test', require('mkdnflow.lists').patterns.ol.main)]])
    eq(result ~= vim.NIL, true)
end

T['patterns_exposed']['ultd patterns work'] = function()
    local result =
        child.lua_get([[string.match('- [ ] test', require('mkdnflow.lists').patterns.ultd.main)]])
    eq(result ~= vim.NIL, true)
end

T['patterns_exposed']['oltd patterns work'] = function()
    local result =
        child.lua_get([[string.match('1. [ ] test', require('mkdnflow.lists').patterns.oltd.main)]])
    eq(result ~= vim.NIL, true)
end

T['patterns_exposed']['indentation pattern extracts correctly'] = function()
    local result = child.lua_get(
        [[string.match('    - test', require('mkdnflow.lists').patterns.ul.indentation)]]
    )
    eq(result, '    ')
end

T['patterns_exposed']['marker pattern extracts correctly'] = function()
    local result =
        child.lua_get([[string.match('- test', require('mkdnflow.lists').patterns.ul.marker)]])
    eq(result, '- ')
end

T['patterns_exposed']['number pattern extracts correctly'] = function()
    local result =
        child.lua_get([[string.match('42. test', require('mkdnflow.lists').patterns.ol.number)]])
    eq(result, '42')
end

T['patterns_exposed']['content pattern extracts correctly'] = function()
    local result = child.lua_get(
        [[string.match('- the content', require('mkdnflow.lists').patterns.ul.content)]]
    )
    eq(result, 'the content')
end

T['patterns_exposed']['empty pattern matches empty item'] = function()
    local result =
        child.lua_get([[string.match('- ', require('mkdnflow.lists').patterns.ul.empty)]])
    eq(result ~= vim.NIL, true)
end

-- =============================================================================
-- Long lists tests
-- =============================================================================
T['long_lists'] = new_set()

T['long_lists']['handles 20 item list'] = function()
    local items = {}
    for i = 1, 20 do
        table.insert(items, '1. item ' .. i)
    end
    set_lines(items)
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.lists').updateNumbering()]])
    local lines = get_lines()
    eq(lines[1], '1. item 1')
    eq(lines[10], '10. item 10')
    eq(lines[20], '20. item 20')
end

T['long_lists']['inserts at middle of long list'] = function()
    local items = {}
    for i = 1, 10 do
        table.insert(items, i .. '. item ' .. i)
    end
    set_lines(items)
    set_cursor(5, 5)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(#lines, 11)
    eq(lines[5], '5. item 5')
    eq(lines[6], '6. ')
    eq(lines[7], '7. item 6')
end

-- =============================================================================
-- ListItem class tests
-- =============================================================================
T['ListItem'] = new_set()

T['ListItem']['read parses unordered list item'] = function()
    set_lines({ '- test item' })
    child.lua('_G.item = require("mkdnflow.lists").ListItem:read(1)')
    eq(child.lua_get('_G.item.valid'), true)
    eq(child.lua_get('_G.item.li_type'), 'ul')
    eq(child.lua_get('_G.item.indentation'), '')
end

T['ListItem']['read parses ordered list item'] = function()
    set_lines({ '1. test item' })
    child.lua('_G.item = require("mkdnflow.lists").ListItem:read(1)')
    eq(child.lua_get('_G.item.valid'), true)
    eq(child.lua_get('_G.item.li_type'), 'ol')
    eq(child.lua_get('_G.item.number'), 1)
end

T['ListItem']['read parses to-do item'] = function()
    set_lines({ '- [ ] todo item' })
    child.lua('_G.item = require("mkdnflow.lists").ListItem:read(1)')
    eq(child.lua_get('_G.item.valid'), true)
    eq(child.lua_get('_G.item.li_type'), 'ultd')
end

T['ListItem']['read returns invalid for non-list'] = function()
    set_lines({ 'plain text' })
    child.lua('_G.item = require("mkdnflow.lists").ListItem:read(1)')
    eq(child.lua_get('_G.item.valid'), false)
end

T['ListItem']['read detects indentation level'] = function()
    set_lines({ '    - nested item' })
    child.lua('_G.item = require("mkdnflow.lists").ListItem:read(1)')
    eq(child.lua_get('_G.item.level'), 1)
    eq(child.lua_get('_G.item.indentation'), '    ')
end

T['ListItem']['is_ordered returns true for ol'] = function()
    set_lines({ '1. ordered' })
    child.lua('_G.item = require("mkdnflow.lists").ListItem:read(1)')
    eq(child.lua_get('_G.item:is_ordered()'), true)
end

T['ListItem']['is_ordered returns false for ul'] = function()
    set_lines({ '- unordered' })
    child.lua('_G.item = require("mkdnflow.lists").ListItem:read(1)')
    eq(child.lua_get('_G.item:is_ordered()'), false)
end

T['ListItem']['is_todo returns true for ultd'] = function()
    set_lines({ '- [ ] todo' })
    child.lua('_G.item = require("mkdnflow.lists").ListItem:read(1)')
    eq(child.lua_get('_G.item:is_todo()'), true)
end

T['ListItem']['is_empty returns true for empty item'] = function()
    set_lines({ '- ' })
    child.lua('_G.item = require("mkdnflow.lists").ListItem:read(1)')
    eq(child.lua_get('_G.item:is_empty()'), true)
end

T['ListItem']['is_empty returns false for item with content'] = function()
    set_lines({ '- has content' })
    child.lua('_G.item = require("mkdnflow.lists").ListItem:read(1)')
    eq(child.lua_get('_G.item:is_empty()'), false)
end

-- =============================================================================
-- List class tests
-- =============================================================================
T['List'] = new_set()

T['List']['read finds all siblings'] = function()
    set_lines({ '- one', '- two', '- three' })
    child.lua('_G.list = require("mkdnflow.lists").List:new():read(1)')
    eq(child.lua_get('#_G.list.items'), 3)
end

T['List']['read stops at different list type'] = function()
    set_lines({ '- ul item', '1. ol item', '- another ul' })
    child.lua('_G.list = require("mkdnflow.lists").List:new():read(1)')
    eq(child.lua_get('#_G.list.items'), 1) -- Only the first ul item
end

T['List']['read skips children'] = function()
    set_lines({ '- parent', '    - child', '- sibling' })
    child.lua('_G.list = require("mkdnflow.lists").List:new():read(1)')
    eq(child.lua_get('#_G.list.items'), 2) -- parent and sibling
end

T['List']['read sets requester_idx correctly'] = function()
    set_lines({ '- one', '- two', '- three' })
    child.lua('_G.list = require("mkdnflow.lists").List:new():read(2)')
    eq(child.lua_get('_G.list.requester_idx'), 2) -- Requested from middle item
end

T['List']['add_relatives finds children'] = function()
    set_lines({ '- parent', '    - child1', '    - child2' })
    child.lua('_G.list = require("mkdnflow.lists").List:new():read(1)')
    child.lua('_G.parent = _G.list.items[1]')
    eq(child.lua_get('_G.parent:has_children()'), true)
end

T['List']['terminus finds deepest item'] = function()
    set_lines({ '- L0', '    - L1', '        - L2' })
    child.lua('_G.list = require("mkdnflow.lists").List:new():read(1)')
    child.lua('_G.terminus = _G.list:terminus()')
    eq(child.lua_get('_G.terminus.line_nr'), 3) -- The deepest item is on line 3
end

T['List']['flatten returns all items'] = function()
    set_lines({ '- parent', '    - child' })
    child.lua('_G.list = require("mkdnflow.lists").List:new():read(1)')
    child.lua('_G.flattened = _G.list:flatten(false)')
    eq(child.lua_get('#_G.flattened'), 2)
end

T['List']['update_numbering fixes sequence'] = function()
    set_lines({ '1. first', '1. second', '1. third' })
    child.lua('_G.list = require("mkdnflow.lists").List:new():read(1)')
    child.lua('_G.list:update_numbering(1)')
    local lines = get_lines()
    eq(lines[1], '1. first')
    eq(lines[2], '2. second')
    eq(lines[3], '3. third')
end

T['List']['line_range is set correctly'] = function()
    set_lines({ 'text', '- one', '- two', '- three', 'more text' })
    child.lua('_G.list = require("mkdnflow.lists").List:new():read(2)')
    eq(child.lua_get('_G.list.line_range.start'), 2)
    eq(child.lua_get('_G.list.line_range.finish'), 4)
end

-- =============================================================================
-- Promotion renumbering (enter on empty nested item promotes + renumbers)
-- =============================================================================
T['promotion_renumbering'] = new_set()

-- The user's exact scenario: nested ordered list, enter on last sub-item
-- creates empty sub-item, enter again promotes it to parent level.
-- The promoted item should be renumbered as the next parent item.
T['promotion_renumbering']['promoted item renumbers to continue parent sequence'] = function()
    set_lines({
        '1. An item',
        '2. A second item:',
        '    1. A sub-item',
        '    2. A sub-item again',
        '    3. A sub-item AGAIN again',
    })
    -- First enter: creates empty sub-item "    4. "
    set_cursor(5, 29)
    child.lua([[require('mkdnflow.lists').newListItem(false, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[6], '    4. ')

    -- Second enter on the empty sub-item: promotes to parent level
    set_cursor(6, 6)
    child.lua([[require('mkdnflow.lists').newListItem(true, false, true, 'n')]])
    lines = get_lines()
    -- Should be promoted to "3. " (continuing the parent 1., 2. sequence)
    eq(lines[6], '3. ')
end

T['promotion_renumbering']['promoted ordered item keeps type with unordered parent'] = function()
    -- When parent list is unordered but sub-list is ordered, promotion
    -- strips indentation but keeps the ordered marker type (the demotion
    -- logic doesn't change marker types, only indentation)
    set_lines({
        '- An item',
        '- A second item:',
        '    1. A sub-item',
        '    2. Another sub-item',
        '    3. ',
    })
    set_cursor(5, 6)
    child.lua([[require('mkdnflow.lists').newListItem(true, false, true, 'n')]])
    local lines = get_lines()
    -- Promoted but keeps ordered type; renumbers as 1 since it has no ol siblings
    eq(lines[5], '3. ')
end

T['promotion_renumbering']['promoted ordered item renumbers among existing siblings'] = function()
    -- Parent list has items after the nested list; promoted item should
    -- renumber correctly and subsequent siblings should update too
    set_lines({
        '1. First',
        '2. Second:',
        '    1. Sub A',
        '    2. Sub B',
        '    3. ',
        '3. Third',
    })
    set_cursor(5, 6)
    child.lua([[require('mkdnflow.lists').newListItem(true, false, true, 'n')]])
    local lines = get_lines()
    -- The empty sub-item should be promoted to "3. " between "2. Second:" and old "3. Third"
    eq(lines[5], '3. ')
    -- The old "3. Third" should renumber to "4. Third"
    eq(lines[6], '4. Third')
end

T['promotion_renumbering']['double promotion renumbers correctly'] = function()
    -- Two levels of nesting: promote once from level 3 to level 2,
    -- then promote again from level 2 to level 1
    set_lines({
        '1. Top',
        '    1. Mid:',
        '        1. Deep',
        '        2. ',
    })
    -- First promotion: level 3 → level 2
    set_cursor(4, 10)
    child.lua([[require('mkdnflow.lists').newListItem(true, false, true, 'n')]])
    local lines = get_lines()
    eq(lines[4], '    2. ')

    -- Second promotion: level 2 → level 1
    set_cursor(4, 6)
    child.lua([[require('mkdnflow.lists').newListItem(true, false, true, 'n')]])
    lines = get_lines()
    eq(lines[4], '2. ')
end

-- E2E test: full keypress flow through MkdnEnter mapping
T['promotion_renumbering_e2e'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                vim.cmd('runtime plugin/mkdnflow.lua')
                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
                vim.bo.expandtab = true
                vim.bo.shiftwidth = 4
                require('mkdnflow').setup({})
                vim.cmd('doautocmd BufEnter')
            ]])
        end,
    },
})

T['promotion_renumbering_e2e']['<CR> in insert mode promotes and renumbers'] = function()
    -- Reconfigure with <CR> mapped in insert mode too
    child.restart({ '-u', 'scripts/minimal_init.lua' })
    child.lua([[
        vim.cmd('runtime plugin/mkdnflow.lua')
        vim.api.nvim_buf_set_name(0, 'test.md')
        vim.bo.filetype = 'markdown'
        vim.bo.expandtab = true
        vim.bo.shiftwidth = 4
        require('mkdnflow').setup({
            mappings = {
                MkdnEnter = { { 'n', 'v', 'i' }, '<CR>' },
            },
        })
        vim.cmd('doautocmd BufEnter')
    ]])
    set_lines({
        '1. An item',
        '2. A second item:',
        '    1. A sub-item',
        '    2. A sub-item again',
        '    3. A sub-item AGAIN again',
    })
    -- Position at end of last sub-item, enter insert mode, press CR
    set_cursor(5, 29)
    child.type_keys('A')
    child.type_keys('<CR>')
    child.type_keys('<Esc>')
    local lines = get_lines()
    eq(lines[6], '    4. ')

    -- CR again on the empty sub-item: promote to parent level
    set_cursor(6, 6)
    child.type_keys('A')
    child.type_keys('<CR>')
    child.type_keys('<Esc>')
    lines = get_lines()
    -- Should be "3. " (continuing parent sequence), not "4. "
    eq(lines[6], '3. ')
end

return T
