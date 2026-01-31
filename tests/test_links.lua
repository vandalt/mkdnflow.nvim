-- tests/test_links.lua
-- Tests for link handling functionality

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

local T = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
                require('mkdnflow').setup({
                    links = {
                        -- Disable path transformation for predictable test output
                        transform_explicit = false
                    }
                })
            ]])
        end,
        post_once = child.stop,
    },
})

-- =============================================================================
-- hasUrl() - URL detection
-- =============================================================================
T['hasUrl'] = new_set()

-- Basic URL detection
T['hasUrl']['detects simple http URL'] = function()
    local result = child.lua_get([[require('mkdnflow.links').hasUrl('http://example.com')]])
    eq(result, true)
end

T['hasUrl']['detects https URL'] = function()
    local result = child.lua_get([[require('mkdnflow.links').hasUrl('https://example.com')]])
    eq(result, true)
end

T['hasUrl']['detects URL with path'] = function()
    local result = child.lua_get([[require('mkdnflow.links').hasUrl('https://example.com/path/to/page')]])
    eq(result, true)
end

T['hasUrl']['detects URL with query string'] = function()
    local result = child.lua_get([[require('mkdnflow.links').hasUrl('https://example.com/search?q=test')]])
    eq(result, true)
end

T['hasUrl']['detects URL with fragment'] = function()
    local result = child.lua_get([[require('mkdnflow.links').hasUrl('https://example.com/page#section')]])
    eq(result, true)
end

T['hasUrl']['detects URL with port'] = function()
    local result = child.lua_get([[require('mkdnflow.links').hasUrl('http://localhost:8080')]])
    eq(result, true)
end

T['hasUrl']['detects ftp URL'] = function()
    local result = child.lua_get([[require('mkdnflow.links').hasUrl('ftp://files.example.com')]])
    eq(result, true)
end

-- Domain-only URLs (no protocol)
T['hasUrl']['detects domain without protocol'] = function()
    local result = child.lua_get([[require('mkdnflow.links').hasUrl('example.com')]])
    eq(result, true)
end

T['hasUrl']['detects www subdomain'] = function()
    local result = child.lua_get([[require('mkdnflow.links').hasUrl('www.example.com')]])
    eq(result, true)
end

-- Various TLDs
T['hasUrl']['detects .org TLD'] = function()
    local result = child.lua_get([[require('mkdnflow.links').hasUrl('https://wikipedia.org')]])
    eq(result, true)
end

T['hasUrl']['detects .io TLD'] = function()
    local result = child.lua_get([[require('mkdnflow.links').hasUrl('https://github.io')]])
    eq(result, true)
end

T['hasUrl']['detects .edu TLD'] = function()
    local result = child.lua_get([[require('mkdnflow.links').hasUrl('https://mit.edu')]])
    eq(result, true)
end

-- Note: .md is explicitly set to false in the TLD table to avoid matching markdown files
T['hasUrl']['rejects .md as TLD'] = function()
    local result = child.lua_get([[require('mkdnflow.links').hasUrl('file.md')]])
    eq(result, false)
end

-- IP addresses
T['hasUrl']['detects IP address URL'] = function()
    local result = child.lua_get([[require('mkdnflow.links').hasUrl('http://192.168.1.1')]])
    eq(result, true)
end

T['hasUrl']['detects IP with port'] = function()
    local result = child.lua_get([[require('mkdnflow.links').hasUrl('http://127.0.0.1:3000')]])
    eq(result, true)
end

-- Non-URLs
T['hasUrl']['rejects plain text'] = function()
    local result = child.lua_get([[require('mkdnflow.links').hasUrl('just some text')]])
    eq(result, false)
end

T['hasUrl']['rejects file paths'] = function()
    local result = child.lua_get([[require('mkdnflow.links').hasUrl('/path/to/file.txt')]])
    eq(result, false)
end

T['hasUrl']['rejects relative paths'] = function()
    local result = child.lua_get([[require('mkdnflow.links').hasUrl('./relative/path')]])
    eq(result, false)
end

T['hasUrl']['rejects email addresses'] = function()
    -- Email addresses look similar but shouldn't be detected as URLs
    local result = child.lua_get([[require('mkdnflow.links').hasUrl('user@example')]])
    eq(result, false)
end

-- URL in context
T['hasUrl']['detects URL within text'] = function()
    local result = child.lua_get([[require('mkdnflow.links').hasUrl('Check out https://example.com for more')]])
    eq(result, true)
end

-- Position detection
T['hasUrl']['returns positions when requested'] = function()
    child.lua([[_G.test_first, _G.test_last = require('mkdnflow.links').hasUrl('Visit https://example.com today', 'positions', 10)]])
    local first = child.lua_get('_G.test_first')
    local last = child.lua_get('_G.test_last')
    -- URL starts at position 7 ("https://example.com")
    eq(first, 7)
    eq(last, 26)
end

T['hasUrl']['returns nil positions when cursor not on URL'] = function()
    child.lua([[_G.test_first, _G.test_last = require('mkdnflow.links').hasUrl('Visit https://example.com today', 'positions', 0)]])
    local result = child.lua_get('_G.test_first')
    eq(result, vim.NIL)
end

-- =============================================================================
-- formatLink() - Link formatting
-- =============================================================================
T['formatLink'] = new_set()

-- Markdown style links
T['formatLink']['creates markdown link from text'] = function()
    local result = child.lua_get([[require('mkdnflow.links').formatLink('my page')]])
    eq(result[1], '[my page](my page.md)')
end

T['formatLink']['creates markdown link with source'] = function()
    local result = child.lua_get([[require('mkdnflow.links').formatLink('display text', 'path/to/file.md')]])
    eq(result[1], '[display text](path/to/file.md)')
end

-- Anchor links
T['formatLink']['creates anchor link from hash text'] = function()
    local result = child.lua_get([[require('mkdnflow.links').formatLink('#My Heading')]])
    eq(result[1], '[My Heading](#my-heading)')
end

T['formatLink']['normalizes anchor link text'] = function()
    -- Should lowercase, replace spaces with dashes, remove special chars
    local result = child.lua_get([[require('mkdnflow.links').formatLink('# Complex Heading! With @Special# Chars')]])
    eq(result[1], '[Complex Heading! With @Special# Chars](#complex-heading-with-special-chars)')
end

T['formatLink']['handles anchor with multiple spaces'] = function()
    local result = child.lua_get([[require('mkdnflow.links').formatLink('#Multiple   Spaces')]])
    -- Note: The gsub('%-%-', '-') only runs once, so 3 spaces → 3 dashes → 2 dashes
    -- This means multiple consecutive spaces leave double-dashes in the anchor
    eq(result[1], '[Multiple   Spaces](#multiple--spaces)')
end

-- Part extraction
T['formatLink']['returns only text when part=1'] = function()
    local result = child.lua_get([[require('mkdnflow.links').formatLink('my page', nil, 1)]])
    eq(result, 'my page')
end

T['formatLink']['returns only path when part=2'] = function()
    local result = child.lua_get([[require('mkdnflow.links').formatLink('my page', nil, 2)]])
    eq(result, 'my page.md')
end

-- Wiki style links
T['formatLink']['creates wiki link when configured'] = function()
    child.lua([[require('mkdnflow').setup({ links = { style = 'wiki' } })]])
    local result = child.lua_get([[require('mkdnflow.links').formatLink('my page')]])
    eq(result[1], '[[my page.md|my page]]')
end

T['formatLink']['creates wiki link with name_is_source'] = function()
    child.lua([[require('mkdnflow').setup({ links = { style = 'wiki', name_is_source = true } })]])
    local result = child.lua_get([[require('mkdnflow.links').formatLink('my page')]])
    eq(result[1], '[[my page]]')
end

-- =============================================================================
-- getLinkUnderCursor() - Link detection
-- =============================================================================
T['getLinkUnderCursor'] = new_set()

-- Markdown links
T['getLinkUnderCursor']['detects markdown link'] = function()
    set_lines({ '[link text](path/to/file.md)' })
    set_cursor(1, 5) -- cursor on "text"
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'md_link')
end

T['getLinkUnderCursor']['detects markdown link on opening bracket'] = function()
    set_lines({ '[link](file.md)' })
    set_cursor(1, 0) -- cursor on "["
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'md_link')
end

T['getLinkUnderCursor']['detects markdown link on closing paren'] = function()
    set_lines({ '[link](file.md)' })
    set_cursor(1, 14) -- cursor on ")"
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'md_link')
end

T['getLinkUnderCursor']['returns nil when not on link'] = function()
    set_lines({ 'plain text here' })
    set_cursor(1, 5)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link')
    eq(result, vim.NIL)
end

-- Wiki links
T['getLinkUnderCursor']['detects wiki link'] = function()
    set_lines({ '[[page name]]' })
    set_cursor(1, 5)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'wiki_link')
end

T['getLinkUnderCursor']['detects wiki link with alias'] = function()
    set_lines({ '[[path/to/page|display text]]' })
    set_cursor(1, 10)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'wiki_link')
end

-- Reference-style links
T['getLinkUnderCursor']['detects reference-style link'] = function()
    set_lines({ '[link text][ref]', '', '[ref]: https://example.com' })
    set_cursor(1, 5)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'ref_style_link')
end

T['getLinkUnderCursor']['detects reference-style link with space'] = function()
    set_lines({ '[link text] [ref]', '', '[ref]: https://example.com' })
    set_cursor(1, 5)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'ref_style_link')
end

-- Auto links
T['getLinkUnderCursor']['detects auto link'] = function()
    set_lines({ '<https://example.com>' })
    set_cursor(1, 10)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'auto_link')
end

-- Citations
T['getLinkUnderCursor']['detects citation'] = function()
    set_lines({ 'As noted by @smith2020, this is true.' })
    set_cursor(1, 15) -- cursor on citation
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'citation')
end

T['getLinkUnderCursor']['detects citation at start of line'] = function()
    set_lines({ '@smith2020 says this.' })
    set_cursor(1, 5)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'citation')
end

T['getLinkUnderCursor']['handles possessive citation'] = function()
    -- @smith2020's should match as @smith2020 (without 's)
    set_lines({ "@smith2020's work is important." })
    set_cursor(1, 5)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[1] or nil')
    eq(result, '@smith2020')
end

-- Edge cases
T['getLinkUnderCursor']['handles link at end of line'] = function()
    set_lines({ 'See [this](file.md)' })
    set_cursor(1, 10)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'md_link')
end

T['getLinkUnderCursor']['handles multiple links on line'] = function()
    set_lines({ '[first](a.md) and [second](b.md)' })
    set_cursor(1, 22) -- cursor on "second"
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[1] or nil')
    eq(result, '[second](b.md)')
end

T['getLinkUnderCursor']['returns correct positions'] = function()
    set_lines({ '[link](file.md)' })
    set_cursor(1, 5)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('{ _G.test_link[4], _G.test_link[5], _G.test_link[6], _G.test_link[7] }')
    -- start_row, start_col, end_row, end_col
    eq(result[1], 1) -- start_row
    eq(result[2], 1) -- start_col
    eq(result[3], 1) -- end_row
    eq(result[4], 15) -- end_col
end

-- =============================================================================
-- getLinkPart() - Extract link components
-- =============================================================================
T['getLinkPart'] = new_set()

-- Markdown links - source extraction
T['getLinkPart']['extracts source from markdown link'] = function()
    set_lines({ '[text](path/to/file.md)' })
    set_cursor(1, 5)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.test_source = require("mkdnflow.links").getLinkPart(_G.test_link, "source")')
    local result = child.lua_get('_G.test_source')
    eq(result, 'path/to/file.md')
end

T['getLinkPart']['extracts source with anchor from markdown link'] = function()
    set_lines({ '[text](file.md#section)' })
    set_cursor(1, 5)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.test_source, _G.test_anchor = require("mkdnflow.links").getLinkPart(_G.test_link, "source")')
    local source = child.lua_get('_G.test_source')
    local anchor = child.lua_get('_G.test_anchor')
    eq(source, 'file.md')
    eq(anchor, '#section')
end

T['getLinkPart']['extracts source from angle bracket markdown link'] = function()
    set_lines({ '[text](<path with spaces.md>)' })
    set_cursor(1, 5)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.test_source = require("mkdnflow.links").getLinkPart(_G.test_link, "source")')
    local result = child.lua_get('_G.test_source')
    eq(result, 'path with spaces.md')
end

-- Markdown links - name extraction
T['getLinkPart']['extracts name from markdown link'] = function()
    set_lines({ '[display text](file.md)' })
    set_cursor(1, 5)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.test_name = require("mkdnflow.links").getLinkPart(_G.test_link, "name")')
    local result = child.lua_get('_G.test_name')
    eq(result, 'display text')
end

-- Wiki links - source extraction
T['getLinkPart']['extracts source from wiki link with bar'] = function()
    set_lines({ '[[path/to/page|display]]' })
    set_cursor(1, 5)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.test_source = require("mkdnflow.links").getLinkPart(_G.test_link, "source")')
    local result = child.lua_get('_G.test_source')
    eq(result, 'path/to/page')
end

T['getLinkPart']['extracts source from wiki link without bar'] = function()
    set_lines({ '[[simple page]]' })
    set_cursor(1, 5)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.test_source = require("mkdnflow.links").getLinkPart(_G.test_link, "source")')
    local result = child.lua_get('_G.test_source')
    eq(result, 'simple page')
end

T['getLinkPart']['extracts source with anchor from wiki link'] = function()
    set_lines({ '[[page#section]]' })
    set_cursor(1, 5)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.test_source, _G.test_anchor = require("mkdnflow.links").getLinkPart(_G.test_link, "source")')
    local source = child.lua_get('_G.test_source')
    local anchor = child.lua_get('_G.test_anchor')
    eq(source, 'page')
    eq(anchor, '#section')
end

-- Wiki links - name extraction
T['getLinkPart']['extracts name from wiki link with bar'] = function()
    set_lines({ '[[page|display name]]' })
    set_cursor(1, 5)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.test_name = require("mkdnflow.links").getLinkPart(_G.test_link, "name")')
    local result = child.lua_get('_G.test_name')
    eq(result, 'display name')
end

T['getLinkPart']['extracts name from wiki link without bar'] = function()
    set_lines({ '[[page name]]' })
    set_cursor(1, 5)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.test_name = require("mkdnflow.links").getLinkPart(_G.test_link, "name")')
    local result = child.lua_get('_G.test_name')
    eq(result, 'page name')
end

-- Reference-style links
T['getLinkPart']['extracts source from reference-style link'] = function()
    set_lines({ '[text][ref]', '', '[ref]: https://example.com' })
    set_cursor(1, 5)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.test_source = require("mkdnflow.links").getLinkPart(_G.test_link, "source")')
    local result = child.lua_get('_G.test_source')
    eq(result, 'https://example.com')
end

T['getLinkPart']['extracts source from ref link with title'] = function()
    set_lines({ '[text][ref]', '', '[ref]: https://example.com "Title"' })
    set_cursor(1, 5)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.test_source = require("mkdnflow.links").getLinkPart(_G.test_link, "source")')
    local result = child.lua_get('_G.test_source')
    eq(result, 'https://example.com')
end

T['getLinkPart']['extracts source from ref link with angle brackets'] = function()
    set_lines({ '[text][ref]', '', '[ref]: <https://example.com>' })
    set_cursor(1, 5)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.test_source = require("mkdnflow.links").getLinkPart(_G.test_link, "source")')
    local result = child.lua_get('_G.test_source')
    eq(result, 'https://example.com')
end

T['getLinkPart']['extracts name from reference-style link'] = function()
    set_lines({ '[display text][ref]', '', '[ref]: https://example.com' })
    set_cursor(1, 5)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.test_name = require("mkdnflow.links").getLinkPart(_G.test_link, "name")')
    local result = child.lua_get('_G.test_name')
    eq(result, 'display text')
end

-- Auto links
T['getLinkPart']['extracts source from auto link'] = function()
    set_lines({ '<https://example.com>' })
    set_cursor(1, 10)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.test_source = require("mkdnflow.links").getLinkPart(_G.test_link, "source")')
    local result = child.lua_get('_G.test_source')
    eq(result, 'https://example.com')
end

T['getLinkPart']['extracts source with anchor from auto link'] = function()
    set_lines({ '<https://example.com#section>' })
    set_cursor(1, 10)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.test_source, _G.test_anchor = require("mkdnflow.links").getLinkPart(_G.test_link, "source")')
    local source = child.lua_get('_G.test_source')
    local anchor = child.lua_get('_G.test_anchor')
    eq(source, 'https://example.com')
    eq(anchor, '#section')
end

-- Citations
T['getLinkPart']['extracts source from citation'] = function()
    set_lines({ 'See @smith2020 for details.' })
    set_cursor(1, 7)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.test_source = require("mkdnflow.links").getLinkPart(_G.test_link, "source")')
    local result = child.lua_get('_G.test_source')
    eq(result, '@smith2020')
end

-- =============================================================================
-- destroyLink() - Remove link syntax
-- =============================================================================
T['destroyLink'] = new_set()

T['destroyLink']['removes markdown link syntax'] = function()
    set_lines({ '[link text](file.md)' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.links').destroyLink()]])
    local result = get_line(1)
    eq(result, 'link text')
end

T['destroyLink']['removes wiki link syntax'] = function()
    set_lines({ '[[page|display text]]' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.links').destroyLink()]])
    local result = get_line(1)
    eq(result, 'display text')
end

T['destroyLink']['removes wiki link syntax without bar'] = function()
    set_lines({ '[[page name]]' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.links').destroyLink()]])
    local result = get_line(1)
    eq(result, 'page name')
end

T['destroyLink']['preserves surrounding text'] = function()
    set_lines({ 'Before [link](file.md) after' })
    set_cursor(1, 10)
    child.lua([[require('mkdnflow.links').destroyLink()]])
    local result = get_line(1)
    eq(result, 'Before link after')
end

T['destroyLink']['handles link at start of line'] = function()
    set_lines({ '[link](file.md) continues here' })
    set_cursor(1, 3)
    child.lua([[require('mkdnflow.links').destroyLink()]])
    local result = get_line(1)
    eq(result, 'link continues here')
end

T['destroyLink']['handles link at end of line'] = function()
    set_lines({ 'Text before [link](file.md)' })
    set_cursor(1, 15)
    child.lua([[require('mkdnflow.links').destroyLink()]])
    local result = get_line(1)
    eq(result, 'Text before link')
end

-- =============================================================================
-- createLink() - Create links from text
-- =============================================================================
T['createLink'] = new_set()

T['createLink']['creates link from word under cursor'] = function()
    set_lines({ 'Create a link from word' })
    -- 'Create a link from word'
    --  0     6     12   17   22
    set_cursor(1, 19) -- cursor on "word" (positions 19-22)
    child.lua([[require('mkdnflow.links').createLink()]])
    local result = get_line(1)
    eq(result, 'Create a link from [word](word.md)')
end

T['createLink']['creates link from first word'] = function()
    set_lines({ 'word at start' })
    set_cursor(1, 2) -- cursor on "word"
    child.lua([[require('mkdnflow.links').createLink()]])
    local result = get_line(1)
    eq(result, '[word](word.md) at start')
end

T['createLink']['wraps URL under cursor'] = function()
    set_lines({ 'Visit https://example.com today' })
    set_cursor(1, 10) -- cursor on URL
    child.lua([[require('mkdnflow.links').createLink()]])
    local result = get_line(1)
    eq(result, 'Visit [](https://example.com) today')
end

T['createLink']['on whitespace creates link from adjacent word'] = function()
    -- When cursor is on whitespace, vim's <cword> typically returns adjacent word
    set_lines({ 'word  other' })
    set_cursor(1, 5) -- cursor on space between words
    child.lua([[require('mkdnflow.links').createLink()]])
    local result = get_line(1)
    -- The second word gets linked because <cword> finds it
    eq(result, 'word  [other](other.md)')
end

-- =============================================================================
-- getBracketedSpanPart() - Extract bracketed span components
-- =============================================================================
T['getBracketedSpanPart'] = new_set()

T['getBracketedSpanPart']['extracts text from bracketed span'] = function()
    set_lines({ '[span text]{#my-id}' })
    set_cursor(1, 5)
    local result = child.lua_get('require("mkdnflow.links").getBracketedSpanPart("text")')
    eq(result, 'span text')
end

T['getBracketedSpanPart']['extracts attr from bracketed span'] = function()
    set_lines({ '[span text]{#my-id}' })
    set_cursor(1, 5)
    local result = child.lua_get('require("mkdnflow.links").getBracketedSpanPart("attr")')
    eq(result, '#my-id')
end

T['getBracketedSpanPart']['returns nil when not on span'] = function()
    set_lines({ 'plain text here' })
    set_cursor(1, 5)
    local result = child.lua_get('require("mkdnflow.links").getBracketedSpanPart("text")')
    eq(result, vim.NIL)
end

T['getBracketedSpanPart']['handles span with class attribute'] = function()
    set_lines({ '[text]{.highlight}' })
    set_cursor(1, 3)
    local result = child.lua_get('require("mkdnflow.links").getBracketedSpanPart("attr")')
    eq(result, '.highlight')
end

T['getBracketedSpanPart']['handles multiple spans on line'] = function()
    set_lines({ '[first]{#one} and [second]{#two}' })
    set_cursor(1, 22) -- cursor on "second"
    local result = child.lua_get('require("mkdnflow.links").getBracketedSpanPart("text")')
    eq(result, 'second')
end

return T
