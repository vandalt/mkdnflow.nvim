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
                -- Trigger autocmd to set up buffer-local mappings
                vim.cmd('doautocmd BufEnter')
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
    local register = child.lua_get("vim.fn.getreg('\"')")
    eq(register, '[My Heading](#my-heading)')
end

T['yankAsAnchorLink']['yanks H2 heading'] = function()
    set_lines({ '## Sub Heading' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.cursor').yankAsAnchorLink()]])
    local register = child.lua_get("vim.fn.getreg('\"')")
    eq(register, '[Sub Heading](#sub-heading)')
end

T['yankAsAnchorLink']['includes full path when requested'] = function()
    set_lines({ '# Heading' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.cursor').yankAsAnchorLink(true)]])
    local register = child.lua_get("vim.fn.getreg('\"')")
    -- Should contain the buffer path and anchor
    local has_path = register:match('test%.md#heading') ~= nil
    eq(has_path, true)
end

T['yankAsAnchorLink']['yanks bracketed span as anchor'] = function()
    set_lines({ '[Span Text]{#span-id}' })
    set_cursor(1, 5) -- cursor on the span
    child.lua([[require('mkdnflow.cursor').yankAsAnchorLink()]])
    local register = child.lua_get("vim.fn.getreg('\"')")
    eq(register, '[Span Text](#span-id)')
end

T['yankAsAnchorLink']['does nothing on non-heading line'] = function()
    -- Set a known value first
    child.lua([[vim.fn.setreg('"', 'original')]])
    set_lines({ 'Regular text' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.cursor').yankAsAnchorLink()]])
    local register = child.lua_get("vim.fn.getreg('\"')")
    eq(register, 'original') -- Should be unchanged
end

-- =============================================================================
-- Configurable yank register
-- =============================================================================
T['yank_register'] = new_set()

T['yank_register']['uses configured register'] = function()
    -- Configure to use register 'a'
    child.lua(
        [[require('mkdnflow').setup({ cursor = { yank_register = 'a' }, links = { transform_explicit = false }, silent = true })]]
    )
    -- Clear the registers
    child.lua([[vim.fn.setreg('a', '')]])
    child.lua([[vim.fn.setreg('"', 'should_stay')]])
    set_lines({ '# Test Heading' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.cursor').yankAsAnchorLink()]])

    -- Should be in register 'a', not unnamed
    local reg_a = child.lua_get([[vim.fn.getreg('a')]])
    local reg_unnamed = child.lua_get([[vim.fn.getreg('"')]])
    eq(reg_a, '[Test Heading](#test-heading)')
    eq(reg_unnamed, 'should_stay') -- Unnamed should be unchanged
end

T['yank_register']['defaults to unnamed register'] = function()
    child.lua(
        [[require('mkdnflow').setup({ links = { transform_explicit = false }, silent = true })]]
    )
    child.lua([[vim.fn.setreg('"', '')]])
    set_lines({ '# Test Heading' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.cursor').yankAsAnchorLink()]])

    local reg = child.lua_get([[vim.fn.getreg('"')]])
    eq(reg, '[Test Heading](#test-heading)')
end

T['yank_register']['works with system clipboard register'] = function()
    -- Set up a mock clipboard provider for CI environments without xclip/xsel
    child.lua([[
        _G._mock_clipboard = { ['+'] = '', ['*'] = '' }
        vim.g.clipboard = {
            name = 'mock_lua',
            copy = {
                ['+'] = function(lines, _) _G._mock_clipboard['+'] = table.concat(lines, '\n') end,
                ['*'] = function(lines, _) _G._mock_clipboard['*'] = table.concat(lines, '\n') end,
            },
            paste = {
                ['+'] = function() return { _G._mock_clipboard['+'] }, 'c' end,
                ['*'] = function() return { _G._mock_clipboard['*'] }, 'c' end,
            },
        }
    ]])
    child.lua(
        [[require('mkdnflow').setup({ cursor = { yank_register = '+' }, links = { transform_explicit = false }, silent = true })]]
    )
    child.lua([[vim.fn.setreg('+', '')]])
    set_lines({ '# Clipboard Test' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.cursor').yankAsAnchorLink()]])

    local reg = child.lua_get([[vim.fn.getreg('+')]])
    eq(reg, '[Clipboard Test](#clipboard-test)')
end

T['yank_register']['works with full path'] = function()
    child.lua(
        [[require('mkdnflow').setup({ cursor = { yank_register = 'b' }, links = { transform_explicit = false }, silent = true })]]
    )
    child.lua([[vim.fn.setreg('b', '')]])
    set_lines({ '# Heading' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.cursor').yankAsAnchorLink(true)]])

    local reg = child.lua_get([[vim.fn.getreg('b')]])
    -- Should contain the buffer path and anchor
    local has_path = reg:match('test%.md#heading') ~= nil
    eq(has_path, true)
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

-- =============================================================================
-- changeHeadingLevel() with range - Issue #256
-- =============================================================================
T['changeHeadingLevel_range'] = new_set()

T['changeHeadingLevel_range']['decreases multiple headings in range'] = function()
    set_lines({ '# First', 'text', '## Second', '### Third' })
    child.lua([[require('mkdnflow.cursor').changeHeadingLevel('decrease', { line1 = 1, line2 = 4 })]])
    eq(get_line(1), '## First')
    eq(get_line(2), 'text')
    eq(get_line(3), '### Second')
    eq(get_line(4), '#### Third')
end

T['changeHeadingLevel_range']['increases multiple headings in range'] = function()
    set_lines({ '## First', 'text', '### Second', '#### Third' })
    child.lua([[require('mkdnflow.cursor').changeHeadingLevel('increase', { line1 = 1, line2 = 4 })]])
    eq(get_line(1), '# First')
    eq(get_line(2), 'text')
    eq(get_line(3), '## Second')
    eq(get_line(4), '### Third')
end

T['changeHeadingLevel_range']['skips non-heading lines'] = function()
    set_lines({ '# Heading', 'plain text', '- list item' })
    child.lua([[require('mkdnflow.cursor').changeHeadingLevel('decrease', { line1 = 1, line2 = 3 })]])
    eq(get_line(1), '## Heading')
    eq(get_line(2), 'plain text')
    eq(get_line(3), '- list item')
end

T['changeHeadingLevel_range']['does not increase H1 beyond limit'] = function()
    set_lines({ '# Already H1', '## Can increase' })
    child.lua([[require('mkdnflow.cursor').changeHeadingLevel('increase', { line1 = 1, line2 = 2 })]])
    eq(get_line(1), '# Already H1')
    eq(get_line(2), '# Can increase')
end

T['changeHeadingLevel_range']['works with single line range'] = function()
    set_lines({ '# First', '## Second', '### Third' })
    child.lua([[require('mkdnflow.cursor').changeHeadingLevel('decrease', { line1 = 2, line2 = 2 })]])
    eq(get_line(1), '# First')
    eq(get_line(2), '### Second')
    eq(get_line(3), '### Third')
end

T['changeHeadingLevel_range']['handles empty range gracefully'] = function()
    set_lines({ '# First', '## Second' })
    -- No-op if line1 > line2 (shouldn't happen in practice, but handle gracefully)
    child.lua([[require('mkdnflow.cursor').changeHeadingLevel('decrease', { line1 = 2, line2 = 1 })]])
    eq(get_line(1), '# First')
    eq(get_line(2), '## Second')
end

-- =============================================================================
-- changeHeadingLevel() command integration - Issue #256
-- =============================================================================
T['changeHeadingLevel_command'] = new_set()

T['changeHeadingLevel_command']['command with range decreases headings'] = function()
    set_lines({ '# First', '## Second', '### Third' })
    child.lua([[vim.cmd('1,3MkdnDecreaseHeading')]])
    eq(get_line(1), '## First')
    eq(get_line(2), '### Second')
    eq(get_line(3), '#### Third')
end

T['changeHeadingLevel_command']['command with range increases headings'] = function()
    set_lines({ '## First', '### Second', '#### Third' })
    child.lua([[vim.cmd('1,3MkdnIncreaseHeading')]])
    eq(get_line(1), '# First')
    eq(get_line(2), '## Second')
    eq(get_line(3), '### Third')
end

T['changeHeadingLevel_command']['command without range uses current line'] = function()
    set_lines({ '## First', '## Second', '## Third' })
    set_cursor(2, 0)
    child.lua([[vim.cmd('MkdnDecreaseHeading')]])
    eq(get_line(1), '## First')
    eq(get_line(2), '### Second')
    eq(get_line(3), '## Third')
end

T['changeHeadingLevel_command']['visual mode keymap increases headings'] = function()
    set_lines({ '## First', '### Second', '#### Third' })
    set_cursor(1, 0)
    -- Simulate visual line mode, select lines 1-3, then press +
    child.type_keys('V', '2j', '+')
    eq(get_line(1), '# First')
    eq(get_line(2), '## Second')
    eq(get_line(3), '### Third')
end

T['changeHeadingLevel_command']['visual mode keymap decreases headings'] = function()
    set_lines({ '# First', '## Second', '### Third' })
    set_cursor(1, 0)
    -- Simulate visual line mode, select lines 1-3, then press -
    child.type_keys('V', '2j', '-')
    eq(get_line(1), '## First')
    eq(get_line(2), '### Second')
    eq(get_line(3), '#### Third')
end

T['changeHeadingLevel_command']['visual mode skips H1 when increasing'] = function()
    set_lines({ '# Already H1', '## Can increase', '### Third' })
    set_cursor(1, 0)
    child.type_keys('V', '2j', '+')
    eq(get_line(1), '# Already H1') -- Cannot increase beyond H1
    eq(get_line(2), '# Can increase')
    eq(get_line(3), '## Third')
end

-- =============================================================================
-- Heading operator (g+/g-) with dot-repeat - Issue #256 enhancement
-- =============================================================================
T['heading_operator'] = new_set()

T['heading_operator']['setupHeadingOperator returns g@'] = function()
    local result = child.lua_get([[require('mkdnflow.cursor').setupHeadingOperator('increase')]])
    eq(result, 'g@')
end

T['heading_operator']['_headingOperator works with normal mode marks'] = function()
    set_lines({ '## First', '### Second', '#### Third', 'text' })
    -- Manually set the '[ and '] marks to simulate a motion
    child.lua([[
        vim.api.nvim_buf_set_mark(0, '[', 1, 0, {})
        vim.api.nvim_buf_set_mark(0, ']', 3, 0, {})
        require('mkdnflow.cursor')._pending_direction = 'increase'
        require('mkdnflow.cursor')._headingOperator('line')
    ]])
    eq(get_line(1), '# First')
    eq(get_line(2), '## Second')
    eq(get_line(3), '### Third')
    eq(get_line(4), 'text') -- Not affected
end

T['heading_operator']['_headingOperator works with visual mode marks'] = function()
    set_lines({ '## First', '### Second', '#### Third', 'text' })
    -- Manually set the '< and '> marks to simulate visual selection
    child.lua([[
        vim.api.nvim_buf_set_mark(0, '<', 1, 0, {})
        vim.api.nvim_buf_set_mark(0, '>', 3, 0, {})
        require('mkdnflow.cursor')._pending_direction = 'decrease'
        require('mkdnflow.cursor')._headingOperator('V')
    ]])
    eq(get_line(1), '### First')
    eq(get_line(2), '#### Second')
    eq(get_line(3), '##### Third')
    eq(get_line(4), 'text') -- Not affected
end

T['heading_operator']['headingOperatorVisual sets operatorfunc and applies change'] = function()
    set_lines({ '## First', '### Second' })
    -- Set visual marks as if lines 1-2 were selected in visual line mode
    child.lua([[
        vim.api.nvim_buf_set_mark(0, '<', 1, 0, {})
        vim.api.nvim_buf_set_mark(0, '>', 2, 0, {})
        -- Simulate that visual mode was 'V' (line mode)
        vim.fn.setreg('v', 'V')
    ]])
    -- Call the visual handler - it will use visualmode() which we can't easily mock,
    -- but it should fall back to the marks
    child.lua([[require('mkdnflow.cursor').headingOperatorVisual('increase')]])

    -- Check that operatorfunc was set for dot-repeat
    local opfunc = child.lua_get('vim.o.operatorfunc')
    eq(opfunc, "v:lua.require'mkdnflow.cursor'._headingOperator")

    -- Check that the headings were increased
    eq(get_line(1), '# First')
    eq(get_line(2), '## Second')
end

-- Helper to execute keys properly for expression mappings
-- child.type_keys doesn't work well with expression mappings
local function feedkeys(keys)
    child.lua('vim.fn.feedkeys(' .. vim.inspect(keys) .. ', "tx")')
end

T['heading_operator']['g+ keymap with motion increases headings'] = function()
    set_lines({ '## First', '### Second', '#### Third', 'text', '## Another' })
    set_cursor(1, 0)
    -- g+ followed by 2j motion (current line + 2 lines down = 3 lines)
    feedkeys('g+2j')
    eq(get_line(1), '# First')
    eq(get_line(2), '## Second')
    eq(get_line(3), '### Third')
    eq(get_line(4), 'text')
    eq(get_line(5), '## Another') -- Not affected
end

T['heading_operator']['g- keymap with motion decreases headings'] = function()
    set_lines({ '# First', '## Second', '### Third', 'text', '# Another' })
    set_cursor(1, 0)
    -- g- followed by 2j motion
    feedkeys('g-2j')
    eq(get_line(1), '## First')
    eq(get_line(2), '### Second')
    eq(get_line(3), '#### Third')
    eq(get_line(4), 'text')
    eq(get_line(5), '# Another') -- Not affected
end

T['heading_operator']['g+ in visual mode works'] = function()
    set_lines({ '## First', '### Second', '#### Third' })
    set_cursor(1, 0)
    feedkeys('V2jg+')
    eq(get_line(1), '# First')
    eq(get_line(2), '## Second')
    eq(get_line(3), '### Third')
end

T['heading_operator']['g- in visual mode works'] = function()
    set_lines({ '# First', '## Second', '### Third' })
    set_cursor(1, 0)
    feedkeys('V2jg-')
    eq(get_line(1), '## First')
    eq(get_line(2), '### Second')
    eq(get_line(3), '#### Third')
end

T['heading_operator']['dot repeat works after g+ with motion'] = function()
    set_lines({ '## First', '### Second', '', '## Third', '### Fourth' })
    set_cursor(1, 0)
    -- First operation: g+ with j motion (2 lines)
    feedkeys('g+j')
    eq(get_line(1), '# First')
    eq(get_line(2), '## Second')

    -- Move to line 4 and dot-repeat
    set_cursor(4, 0)
    feedkeys('.')
    eq(get_line(4), '# Third')
    eq(get_line(5), '## Fourth')
end

T['heading_operator']['dot repeat works after g- with motion'] = function()
    set_lines({ '# First', '## Second', '', '# Third', '## Fourth' })
    set_cursor(1, 0)
    -- First operation: g- with j motion (2 lines)
    feedkeys('g-j')
    eq(get_line(1), '## First')
    eq(get_line(2), '### Second')

    -- Move to line 4 and dot-repeat
    set_cursor(4, 0)
    feedkeys('.')
    eq(get_line(4), '## Third')
    eq(get_line(5), '### Fourth')
end

T['heading_operator']['dot repeat works after visual mode g+'] = function()
    -- Visual mode operations now support dot-repeat (like > and < do)
    set_lines({ '## First', '### Second', '', '## Third', '### Fourth' })
    set_cursor(1, 0)
    -- First operation: visual select 2 lines, then g+
    feedkeys('Vjg+')
    eq(get_line(1), '# First')
    eq(get_line(2), '## Second')

    -- Move to line 4 and dot-repeat - affects same number of lines (2)
    set_cursor(4, 0)
    feedkeys('.')
    eq(get_line(4), '# Third')
    eq(get_line(5), '## Fourth')
end

T['heading_operator']['g+ with paragraph motion'] = function()
    set_lines({ '## First', '### Second', '', '## Third' })
    set_cursor(1, 0)
    -- g+ with } motion (to next blank line/paragraph)
    feedkeys('g+}')
    eq(get_line(1), '# First')
    eq(get_line(2), '## Second')
    eq(get_line(3), '')
    eq(get_line(4), '## Third') -- Not affected (after paragraph)
end

T['heading_operator']['g- skips non-heading lines'] = function()
    set_lines({ '# Heading', 'plain text', '- list item', '## Another' })
    set_cursor(1, 0)
    feedkeys('g-3j')
    eq(get_line(1), '## Heading')
    eq(get_line(2), 'plain text') -- Unchanged
    eq(get_line(3), '- list item') -- Unchanged
    eq(get_line(4), '### Another')
end

T['heading_operator']['g+ does not increase H1 beyond limit'] = function()
    set_lines({ '# Already H1', '## Can increase' })
    set_cursor(1, 0)
    feedkeys('g+j')
    eq(get_line(1), '# Already H1') -- Cannot increase beyond H1
    eq(get_line(2), '# Can increase')
end

-- =============================================================================
-- E2E tests: Keymap behavior for heading operators (g+/g-)
-- These test through the actual mapping system, not just feedkeys
-- =============================================================================
T['heading_operator_e2e'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                -- Source the plugin to register commands
                vim.cmd('runtime plugin/mkdnflow.lua')

                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
                require('mkdnflow').setup({
                    links = { transform_explicit = false },
                    silent = true
                })

                -- Trigger the autocmd to set up mappings
                vim.cmd('doautocmd BufEnter')
            ]])
        end,
    },
})

T['heading_operator_e2e']['g+ mapping exists and uses expr'] = function()
    child.lua([[
        _G.test_map = nil
        local maps = vim.api.nvim_buf_get_keymap(0, 'n')
        for _, m in ipairs(maps) do
            if m.lhs == 'g+' then
                _G.test_map = { lhs = m.lhs, expr = m.expr }
            end
        end
    ]])
    local map = child.lua_get('_G.test_map')
    eq(map ~= nil, true)
    eq(map.lhs, 'g+')
    eq(map.expr, 1) -- expr mapping for dot-repeat
end

T['heading_operator_e2e']['g+ visual mode mapping exists'] = function()
    child.lua([[
        _G.test_map = nil
        local maps = vim.api.nvim_buf_get_keymap(0, 'v')
        for _, m in ipairs(maps) do
            if m.lhs == 'g+' then
                _G.test_map = { lhs = m.lhs, callback = m.callback ~= nil }
            end
        end
    ]])
    local map = child.lua_get('_G.test_map')
    eq(map ~= nil, true)
    eq(map.lhs, 'g+')
    eq(map.callback, true) -- callback for visual mode
end

T['heading_operator_e2e']['visual g+ followed by dot repeat'] = function()
    set_lines({ '## First', '### Second', '', '## Third', '### Fourth' })
    set_cursor(1, 0)
    -- Visual select 2 lines, then g+
    child.type_keys('V', 'j', 'g', '+')
    eq(get_line(1), '# First')
    eq(get_line(2), '## Second')

    -- Move to line 4 and dot-repeat
    set_cursor(4, 0)
    child.type_keys('.')
    eq(get_line(4), '# Third')
    eq(get_line(5), '## Fourth')
end

T['heading_operator_e2e']['visual g- followed by dot repeat'] = function()
    set_lines({ '# First', '## Second', '', '# Third', '## Fourth' })
    set_cursor(1, 0)
    -- Visual select 2 lines, then g-
    child.type_keys('V', 'j', 'g', '-')
    eq(get_line(1), '## First')
    eq(get_line(2), '### Second')

    -- Move to line 4 and dot-repeat
    set_cursor(4, 0)
    child.type_keys('.')
    eq(get_line(4), '## Third')
    eq(get_line(5), '### Fourth')
end

-- Visual mode +/- now support dot-repeat (like Vim's built-in < and > operators)
T['heading_operator_e2e']['visual + followed by dot repeat'] = function()
    set_lines({ '## First', '### Second', '', '## Third', '### Fourth' })
    set_cursor(1, 0)
    -- Visual select 2 lines, then +
    child.type_keys('V', 'j', '+')
    eq(get_line(1), '# First')
    eq(get_line(2), '## Second')

    -- Move to line 4 and dot-repeat - affects same number of lines (2)
    set_cursor(4, 0)
    child.type_keys('.')
    eq(get_line(4), '# Third')
    eq(get_line(5), '## Fourth')
end

T['heading_operator_e2e']['visual - followed by dot repeat'] = function()
    set_lines({ '# First', '## Second', '', '# Third', '## Fourth' })
    set_cursor(1, 0)
    -- Visual select 2 lines, then -
    child.type_keys('V', 'j', '-')
    eq(get_line(1), '## First')
    eq(get_line(2), '### Second')

    -- Move to line 4 and dot-repeat
    set_cursor(4, 0)
    child.type_keys('.')
    eq(get_line(4), '## Third')
    eq(get_line(5), '### Fourth')
end

return T
