-- tests/test_cursor.lua
-- Tests for cursor movement functionality

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
                require('mkdnflow').setup({
                    links = { transform_explicit = false },
                    silent = true
                })
            ]])
        end,
        post_once = child.stop,
    },
})

-- =============================================================================
-- goTo() - Pattern-based cursor movement
-- =============================================================================
T['goTo'] = new_set()

T['goTo']['moves to next pattern match'] = function()
    set_lines({ 'hello world hello' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.cursor').goTo('world')]])
    local cursor = get_cursor()
    eq(cursor[1], 1)
    eq(cursor[2], 6) -- 'world' starts at column 6
end

T['goTo']['moves to next match on subsequent lines'] = function()
    set_lines({ 'first line', 'second world line' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.cursor').goTo('world')]])
    local cursor = get_cursor()
    eq(cursor[1], 2)
    eq(cursor[2], 7)
end

T['goTo']['skips match before cursor'] = function()
    set_lines({ 'hello world hello' })
    set_cursor(1, 10) -- cursor after 'world'
    child.lua([[require('mkdnflow.cursor').goTo('hello')]])
    local cursor = get_cursor()
    eq(cursor[1], 1)
    eq(cursor[2], 12) -- second 'hello'
end

T['goTo']['moves to previous match when reverse=true'] = function()
    set_lines({ 'hello world hello' })
    set_cursor(1, 12) -- cursor on second 'hello'
    child.lua([[require('mkdnflow.cursor').goTo('hello', true)]])
    local cursor = get_cursor()
    eq(cursor[1], 1)
    eq(cursor[2], 0) -- first 'hello'
end

T['goTo']['handles multiple patterns'] = function()
    set_lines({ 'find apple or banana here' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.cursor').goTo({'apple', 'banana'})]])
    local cursor = get_cursor()
    eq(cursor[1], 1)
    eq(cursor[2], 5) -- 'apple' is first match
end

-- Note: wrap config is cached at module load time.
-- This test verifies behavior when wrap=false (the default).
T['goTo']['stays on last line when no match and wrap=false'] = function()
    set_lines({ 'no match', 'still no match' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.cursor').goTo('target')]])
    -- Cursor should not move when pattern not found
    local cursor = get_cursor()
    eq(cursor[1], 1)
end

-- =============================================================================
-- changeHeadingLevel() - Modify heading importance
-- =============================================================================
T['changeHeadingLevel'] = new_set()

T['changeHeadingLevel']['decreases heading level (adds hash)'] = function()
    set_lines({ '# Heading' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.cursor').changeHeadingLevel('decrease')]])
    local line = get_line(1)
    eq(line, '## Heading')
end

T['changeHeadingLevel']['increases heading level (removes hash)'] = function()
    set_lines({ '## Heading' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.cursor').changeHeadingLevel('increase')]])
    local line = get_line(1)
    eq(line, '# Heading')
end

T['changeHeadingLevel']['does not increase beyond H1'] = function()
    set_lines({ '# Heading' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.cursor').changeHeadingLevel('increase')]])
    local line = get_line(1)
    -- Should remain unchanged
    eq(line, '# Heading')
end

T['changeHeadingLevel']['can decrease to H6 and beyond'] = function()
    set_lines({ '###### Heading' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.cursor').changeHeadingLevel('decrease')]])
    local line = get_line(1)
    eq(line, '####### Heading')
end

T['changeHeadingLevel']['does nothing on non-heading'] = function()
    set_lines({ 'Regular text' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.cursor').changeHeadingLevel('decrease')]])
    local line = get_line(1)
    eq(line, 'Regular text')
end

T['changeHeadingLevel']['works with cursor anywhere on line'] = function()
    set_lines({ '## Heading text here' })
    set_cursor(1, 15) -- cursor in middle of text
    child.lua([[require('mkdnflow.cursor').changeHeadingLevel('increase')]])
    local line = get_line(1)
    eq(line, '# Heading text here')
end

-- =============================================================================
-- toNextLink() / toPrevLink() - Link navigation
-- =============================================================================
T['toNextLink'] = new_set()

T['toNextLink']['moves to markdown link'] = function()
    set_lines({ 'Text [link](url) more' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.cursor').toNextLink()]])
    local cursor = get_cursor()
    eq(cursor[1], 1)
    eq(cursor[2], 5) -- '[' of link
end

T['toNextLink']['moves to next link on subsequent line'] = function()
    set_lines({ 'no link here', '[link](url)' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.cursor').toNextLink()]])
    local cursor = get_cursor()
    eq(cursor[1], 2)
    eq(cursor[2], 0)
end

-- Note: Default jump_patterns (markdown style) don't include wiki links.
-- Wiki links are only in jump_patterns when links.style = 'wiki'.
T['toNextLink']['moves to auto link'] = function()
    set_lines({ 'Text <https://example.com> more' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.cursor').toNextLink()]])
    local cursor = get_cursor()
    eq(cursor[1], 1)
    eq(cursor[2], 5) -- '<' of auto link
end

T['toPrevLink'] = new_set()

T['toPrevLink']['moves to previous link'] = function()
    -- Put two complete links, cursor after the first one
    set_lines({ '[first](a.md)', '[second](b.md)' })
    set_cursor(2, 10) -- on second line
    child.lua([[require('mkdnflow.cursor').toPrevLink()]])
    local cursor = get_cursor()
    eq(cursor[1], 1) -- Should find link on line 1
    eq(cursor[2], 0)
end

T['toPrevLink']['moves to link on previous line'] = function()
    set_lines({ '[link](url)', 'no link here' })
    set_cursor(2, 5)
    child.lua([[require('mkdnflow.cursor').toPrevLink()]])
    local cursor = get_cursor()
    eq(cursor[1], 1)
    eq(cursor[2], 0)
end

-- =============================================================================
-- toHeading() - Jump to headings
-- =============================================================================
T['toHeading'] = new_set()

T['toHeading']['moves to next heading when no anchor'] = function()
    set_lines({ 'Text', '# First Heading', 'More text' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.cursor').toHeading()]])
    local cursor = get_cursor()
    eq(cursor[1], 2)
end

T['toHeading']['moves to specific heading by anchor'] = function()
    set_lines({ '# First', '# Second', '# Target Heading' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.cursor').toHeading('#target-heading')]])
    local cursor = get_cursor()
    eq(cursor[1], 3)
end

T['toHeading']['moves to previous heading when reverse=true'] = function()
    set_lines({ '# First', 'text', '# Second' })
    set_cursor(3, 0)
    child.lua([[require('mkdnflow.cursor').toHeading(nil, true)]])
    local cursor = get_cursor()
    eq(cursor[1], 1)
end

T['toHeading']['skips headings in code blocks'] = function()
    set_lines({ '```', '# Not a heading', '```', '# Real heading' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.cursor').toHeading()]])
    local cursor = get_cursor()
    eq(cursor[1], 4) -- Should skip the one in code block
end

T['toHeading']['handles heading with special characters'] = function()
    set_lines({ "# Heading with 'quotes' and (parens)" })
    set_cursor(1, 0)
    -- The anchor would be #heading-with-quotes-and-parens
    child.lua([[require('mkdnflow.cursor').toHeading("#heading-with-quotes-and-parens")]])
    local cursor = get_cursor()
    eq(cursor[1], 1)
end

-- =============================================================================
-- toId() - Jump to ID attributes
-- =============================================================================
T['toId'] = new_set()

T['toId']['finds bracketed span with ID'] = function()
    set_lines({ 'Text', '[span]{#my-id}', 'More text' })
    set_cursor(1, 0)
    local found = child.lua_get([[require('mkdnflow.cursor').toId('#my-id')]])
    eq(found, true)
    local cursor = get_cursor()
    eq(cursor[1], 2)
end

T['toId']['finds Pandoc-style heading ID'] = function()
    set_lines({ '# Heading {#custom-id}' })
    set_cursor(1, 0)
    local found = child.lua_get([[require('mkdnflow.cursor').toId('#custom-id', 1)]])
    eq(found, true)
end

T['toId']['returns false when ID not found'] = function()
    set_lines({ 'No IDs here', 'Just text' })
    set_cursor(1, 0)
    local found = child.lua_get([[require('mkdnflow.cursor').toId('#nonexistent')]])
    eq(found, false)
end

T['toId']['finds ID with class attributes'] = function()
    set_lines({ '[span]{.class #my-id .other}' })
    set_cursor(1, 0)
    local found = child.lua_get([[require('mkdnflow.cursor').toId('#my-id', 1)]])
    eq(found, true)
end

T['toId']['finds correct ID among multiple spans'] = function()
    set_lines({ '[first]{#id1} [second]{#id2}' })
    set_cursor(1, 0)
    local found = child.lua_get([[require('mkdnflow.cursor').toId('#id2', 1)]])
    eq(found, true)
    local cursor = get_cursor()
    eq(cursor[2], 14) -- Should be at second span
end

-- =============================================================================
-- yankAsAnchorLink() - Copy heading as anchor link
-- =============================================================================
T['yankAsAnchorLink'] = new_set()

T['yankAsAnchorLink']['yanks heading as anchor link'] = function()
    set_lines({ '# My Heading' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.cursor').yankAsAnchorLink()]])
    local register = child.lua_get('vim.fn.getreg(\'"\')')
    eq(register, '[My Heading](#my-heading)')
end

T['yankAsAnchorLink']['yanks H2 heading'] = function()
    set_lines({ '## Sub Heading' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.cursor').yankAsAnchorLink()]])
    local register = child.lua_get('vim.fn.getreg(\'"\')')
    eq(register, '[Sub Heading](#sub-heading)')
end

T['yankAsAnchorLink']['includes full path when requested'] = function()
    set_lines({ '# Heading' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.cursor').yankAsAnchorLink(true)]])
    local register = child.lua_get('vim.fn.getreg(\'"\')')
    -- Should contain the buffer path and anchor
    local has_path = register:match('test%.md#heading') ~= nil
    eq(has_path, true)
end

T['yankAsAnchorLink']['yanks bracketed span as anchor'] = function()
    set_lines({ '[Span Text]{#span-id}' })
    set_cursor(1, 5) -- cursor on the span
    child.lua([[require('mkdnflow.cursor').yankAsAnchorLink()]])
    local register = child.lua_get('vim.fn.getreg(\'"\')')
    eq(register, '[Span Text](#span-id)')
end

T['yankAsAnchorLink']['does nothing on non-heading line'] = function()
    -- Set a known value first
    child.lua([[vim.fn.setreg('"', 'original')]])
    set_lines({ 'Regular text' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.cursor').yankAsAnchorLink()]])
    local register = child.lua_get('vim.fn.getreg(\'"\')')
    eq(register, 'original') -- Should be unchanged
end

-- =============================================================================
-- Edge cases
-- =============================================================================
T['edge_cases'] = new_set()

T['edge_cases']['goTo handles empty buffer'] = function()
    set_lines({ '' })
    set_cursor(1, 0)
    -- Should not error
    child.lua([[require('mkdnflow.cursor').goTo('pattern')]])
    local cursor = get_cursor()
    eq(cursor[1], 1)
end

T['edge_cases']['changeHeadingLevel handles empty line'] = function()
    set_lines({ '' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.cursor').changeHeadingLevel('decrease')]])
    local line = get_line(1)
    eq(line, '')
end

-- Note: wrap config is cached at module load time, so we test without wrap
T['edge_cases']['toHeading stays at end when no more headings'] = function()
    set_lines({ '# First', 'text', '# Second' })
    set_cursor(3, 0) -- on last heading
    child.lua([[require('mkdnflow.cursor').toHeading()]])
    -- With wrap=false (default), cursor stays when no more headings
    local cursor = get_cursor()
    eq(cursor[1], 3)
end

T['edge_cases']['toId starts from specified row'] = function()
    set_lines({ '[first]{#id1}', '[second]{#id2}' })
    -- Start from row 2 - should find id2
    local found = child.lua_get([[require('mkdnflow.cursor').toId('#id2', 2)]])
    eq(found, true)
    local cursor = get_cursor()
    eq(cursor[1], 2)
end

T['edge_cases']['goTo with regex special chars'] = function()
    set_lines({ 'find [brackets] here' })
    set_cursor(1, 0)
    -- Need to escape the pattern for Lua regex
    child.lua([[require('mkdnflow.cursor').goTo('%[brackets%]')]])
    local cursor = get_cursor()
    eq(cursor[1], 1)
    eq(cursor[2], 5)
end

return T
