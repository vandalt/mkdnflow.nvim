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
    local result = child.lua_get([[string.match('- item', require('mkdnflow.lists').patterns.ul.main) ~= nil]])
    eq(result, true)
end

T['patterns']['ol.main matches ordered list'] = function()
    local result = child.lua_get([[string.match('1. item', require('mkdnflow.lists').patterns.ol.main) ~= nil]])
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

return T
