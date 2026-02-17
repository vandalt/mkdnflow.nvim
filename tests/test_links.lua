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
                        transform_on_create = false
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
    local result =
        child.lua_get([[require('mkdnflow.links').hasUrl('https://example.com/path/to/page')]])
    eq(result, true)
end

T['hasUrl']['detects URL with query string'] = function()
    local result =
        child.lua_get([[require('mkdnflow.links').hasUrl('https://example.com/search?q=test')]])
    eq(result, true)
end

T['hasUrl']['detects URL with fragment'] = function()
    local result =
        child.lua_get([[require('mkdnflow.links').hasUrl('https://example.com/page#section')]])
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
    local result = child.lua_get(
        [[require('mkdnflow.links').hasUrl('Check out https://example.com for more')]]
    )
    eq(result, true)
end

-- Position detection
T['hasUrl']['returns positions when requested'] = function()
    child.lua(
        [[_G.test_first, _G.test_last = require('mkdnflow.links').hasUrl('Visit https://example.com today', 'positions', 10)]]
    )
    local first = child.lua_get('_G.test_first')
    local last = child.lua_get('_G.test_last')
    -- URL starts at position 7 ("https://example.com")
    eq(first, 7)
    eq(last, 26)
end

T['hasUrl']['returns nil positions when cursor not on URL'] = function()
    child.lua(
        [[_G.test_first, _G.test_last = require('mkdnflow.links').hasUrl('Visit https://example.com today', 'positions', 0)]]
    )
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
    local result =
        child.lua_get([[require('mkdnflow.links').formatLink('display text', 'path/to/file.md')]])
    eq(result[1], '[display text](path/to/file.md)')
end

-- Anchor links
T['formatLink']['creates anchor link from hash text'] = function()
    local result = child.lua_get([[require('mkdnflow.links').formatLink('#My Heading')]])
    eq(result[1], '[My Heading](#my-heading)')
end

T['formatLink']['normalizes anchor link text'] = function()
    -- Should lowercase, replace spaces with dashes, remove special chars
    local result = child.lua_get(
        [[require('mkdnflow.links').formatLink('# Complex Heading! With @Special# Chars')]]
    )
    eq(result[1], '[Complex Heading! With @Special# Chars](#complex-heading-with-special-chars)')
end

T['formatLink']['handles anchor with multiple spaces'] = function()
    local result = child.lua_get([[require('mkdnflow.links').formatLink('#Multiple   Spaces')]])
    -- Each space becomes a hyphen (matches GitHub behavior - no collapsing)
    eq(result[1], '[Multiple   Spaces](#multiple---spaces)')
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

T['formatLink']['creates wiki link with compact'] = function()
    child.lua([[require('mkdnflow').setup({ links = { style = 'wiki', compact = true } })]])
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

T['getLinkUnderCursor']['does not detect email as citation'] = function()
    set_lines({ 'Contact me at jakewvincent@gmail.com please.' })
    set_cursor(1, 30) -- cursor on 'g' of 'gmail'
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link')
    eq(result, vim.NIL)
end

T['getLinkUnderCursor']['does not detect email as citation on @'] = function()
    set_lines({ 'Contact me at jakewvincent@gmail.com please.' })
    set_cursor(1, 26) -- cursor on '@'
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link')
    eq(result, vim.NIL)
end

-- =============================================================================
-- Pandoc-style bracketed citations (Issue #285)
-- =============================================================================
T['pandoc_citation'] = new_set()

T['pandoc_citation']['detects on opening bracket'] = function()
    set_lines({ 'See [@smith2020] for details.' })
    set_cursor(1, 4) -- cursor on '['
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'pandoc_citation')
end

T['pandoc_citation']['detects on @ symbol'] = function()
    set_lines({ 'See [@smith2020] for details.' })
    set_cursor(1, 5) -- cursor on '@'
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'pandoc_citation')
end

T['pandoc_citation']['detects on citekey'] = function()
    set_lines({ 'See [@smith2020] for details.' })
    set_cursor(1, 8) -- cursor in middle of citekey
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'pandoc_citation')
end

T['pandoc_citation']['detects on closing bracket'] = function()
    set_lines({ 'See [@smith2020] for details.' })
    set_cursor(1, 15) -- cursor on ']'
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'pandoc_citation')
end

T['pandoc_citation']['extracts source with @ prefix'] = function()
    set_lines({ 'See [@smith2020] for details.' })
    set_cursor(1, 5)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.test_source = require("mkdnflow.links").getLinkPart(_G.test_link, "source")')
    local result = child.lua_get('_G.test_source')
    eq(result, '@smith2020')
end

T['pandoc_citation']['extracts name without @ prefix'] = function()
    set_lines({ 'See [@smith2020] for details.' })
    set_cursor(1, 5)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.test_name = require("mkdnflow.links").getLinkPart(_G.test_link, "name")')
    local result = child.lua_get('_G.test_name')
    eq(result, 'smith2020')
end

T['pandoc_citation']['returns correct boundaries including brackets'] = function()
    set_lines({ 'See [@smith2020] for details.' })
    set_cursor(1, 8)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local start_col = child.lua_get('_G.test_link[5]')
    local end_col = child.lua_get('_G.test_link[7]')
    eq(start_col, 5) -- '[' at position 5
    eq(end_col, 16) -- ']' at position 16
end

T['pandoc_citation']['destroyLink removes brackets'] = function()
    set_lines({ 'See [@smith2020] for details.' })
    set_cursor(1, 8)
    child.lua([[require('mkdnflow.links').destroyLink()]])
    local result = get_line(1)
    eq(result, 'See smith2020 for details.')
end

T['pandoc_citation']['standalone @citekey still detected as citation'] = function()
    set_lines({ 'As noted by @smith2020, this is true.' })
    set_cursor(1, 15)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'citation') -- Regular citation, not pandoc_citation
end

T['pandoc_citation']['handles special chars in citekey'] = function()
    set_lines({ 'See [@smith_2020-a.b] for details.' })
    set_cursor(1, 8)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.test_source = require("mkdnflow.links").getLinkPart(_G.test_link, "source")')
    local result = child.lua_get('_G.test_source')
    eq(result, '@smith_2020-a.b')
end

T['pandoc_citation']['handles multiple on same line'] = function()
    set_lines({ 'See [@smith2020] and [@jones2021].' })
    set_cursor(1, 22) -- cursor on second citation
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local match = child.lua_get('_G.test_link and _G.test_link[1] or nil')
    eq(match, '[@jones2021]')
end

T['pandoc_citation']['at start of line'] = function()
    set_lines({ '[@smith2020] says this.' })
    set_cursor(1, 0)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'pandoc_citation')
end

T['pandoc_citation']['at end of line'] = function()
    set_lines({ 'See [@smith2020]' })
    set_cursor(1, 15)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'pandoc_citation')
end

-- =============================================================================
-- Pandoc citation integration with bib module
-- =============================================================================
T['pandoc_citation_bib'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            -- Get the absolute path to the test bib file
            local test_bib_path = vim.fn.fnamemodify('tests/fixtures/test.bib', ':p')
            child.lua([[
                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
                require('mkdnflow').setup({
                    modules = { bib = true },
                    bib = {
                        default_path = ']] .. test_bib_path .. [[',
                        find_in_root = false
                    },
                    links = { transform_on_create = false },
                    silent = true
                })
            ]])
        end,
    },
})

T['pandoc_citation_bib']['source works with handleCitation'] = function()
    -- Verify that the source extracted from [@citekey] works with bib.handleCitation()
    set_lines({ 'See [@smith2020] for details.' })
    set_cursor(1, 5) -- on '['
    child.lua([[
        _G.link = require('mkdnflow.links').getLinkUnderCursor()
        _G.source = require('mkdnflow.links').getLinkPart(_G.link, 'source')
        _G.bib_result = require('mkdnflow.bib').handleCitation(_G.source)
    ]])
    local source = child.lua_get('_G.source')
    local bib_result = child.lua_get('_G.bib_result')
    eq(source, '@smith2020')
    eq(bib_result, 'https://example.com/smith2020')
end

T['pandoc_citation_bib']['cursor on bracket still resolves bib entry'] = function()
    -- The key test: cursor on '[' bracket should still find the citation
    set_lines({ 'Reference: [@jones2021]' })
    set_cursor(1, 11) -- on '[' bracket
    child.lua([[
        _G.link = require('mkdnflow.links').getLinkUnderCursor()
        _G.source = require('mkdnflow.links').getLinkPart(_G.link, 'source')
        _G.bib_result = require('mkdnflow.bib').handleCitation(_G.source)
    ]])
    local link_type = child.lua_get('_G.link and _G.link.type or nil')
    local source = child.lua_get('_G.source')
    local bib_result = child.lua_get('_G.bib_result')
    eq(link_type, 'pandoc_citation')
    eq(source, '@jones2021')
    eq(bib_result, 'file:/path/to/jones2021.pdf')
end

T['pandoc_citation_bib']['pathType identifies citation correctly'] = function()
    -- Verify that paths.pathType() correctly identifies the extracted source as a citation
    set_lines({ 'See [@doe2022] here.' })
    set_cursor(1, 5)
    child.lua([[
        _G.link = require('mkdnflow.links').getLinkUnderCursor()
        _G.source = require('mkdnflow.links').getLinkPart(_G.link, 'source')
        _G.path_type = require('mkdnflow.paths').pathType(_G.source, nil, _G.link.type)
    ]])
    local path_type = child.lua_get('_G.path_type')
    eq(path_type, 'citation')
end

T['pandoc_citation_bib']['nonexistent citekey returns nil'] = function()
    set_lines({ 'See [@nonexistent2099] here.' })
    set_cursor(1, 5)
    child.lua([[
        _G.link = require('mkdnflow.links').getLinkUnderCursor()
        _G.source = require('mkdnflow.links').getLinkPart(_G.link, 'source')
        _G.bib_result = require('mkdnflow.bib').handleCitation(_G.source)
    ]])
    local link_type = child.lua_get('_G.link and _G.link.type or nil')
    local bib_result = child.lua_get('_G.bib_result')
    eq(link_type, 'pandoc_citation')
    eq(bib_result, vim.NIL)
end

T['pandoc_citation_bib']['special chars in citekey works with bib'] = function()
    set_lines({ 'See [@special_key-2024] here.' })
    set_cursor(1, 5)
    child.lua([[
        _G.link = require('mkdnflow.links').getLinkUnderCursor()
        _G.source = require('mkdnflow.links').getLinkPart(_G.link, 'source')
        _G.bib_result = require('mkdnflow.bib').handleCitation(_G.source)
    ]])
    local source = child.lua_get('_G.source')
    local bib_result = child.lua_get('_G.bib_result')
    eq(source, '@special_key-2024')
    eq(bib_result, 'https://example.com/special')
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
    local result =
        child.lua_get('{ _G.test_link[4], _G.test_link[5], _G.test_link[6], _G.test_link[7] }')
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
    child.lua(
        '_G.test_source, _G.test_anchor = require("mkdnflow.links").getLinkPart(_G.test_link, "source")'
    )
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

-- Markdown links with parentheses in path (#316)
T['getLinkPart']['extracts source with parens in directory name'] = function()
    set_lines({ '[Notes](Projects/Solar Array (Phase 2)/notes.md)' })
    set_cursor(1, 5)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.test_source = require("mkdnflow.links").getLinkPart(_G.test_link, "source")')
    local result = child.lua_get('_G.test_source')
    eq(result, 'Projects/Solar Array (Phase 2)/notes.md')
end

T['getLinkPart']['extracts source with parens in filename'] = function()
    set_lines({ '[Doc](file (copy).pdf)' })
    set_cursor(1, 5)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.test_source = require("mkdnflow.links").getLinkPart(_G.test_link, "source")')
    local result = child.lua_get('_G.test_source')
    eq(result, 'file (copy).pdf')
end

T['getLinkPart']['extracts source with multiple paren groups in path'] = function()
    set_lines({ '[Doc](path (a) and (b)/file.md)' })
    set_cursor(1, 5)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.test_source = require("mkdnflow.links").getLinkPart(_G.test_link, "source")')
    local result = child.lua_get('_G.test_source')
    eq(result, 'path (a) and (b)/file.md')
end

T['getLinkPart']['extracts source with parens and anchor'] = function()
    set_lines({ '[Doc](file (1).pdf#page=2)' })
    set_cursor(1, 5)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua(
        '_G.test_source, _G.test_anchor = require("mkdnflow.links").getLinkPart(_G.test_link, "source")'
    )
    local source = child.lua_get('_G.test_source')
    local anchor = child.lua_get('_G.test_anchor')
    eq(source, 'file (1).pdf')
    eq(anchor, '#page=2')
end

T['getLinkPart']['extracts source with parens when multiple links on line'] = function()
    set_lines({ '[a](dir (x)/a.md) and [b](other.md)' })
    set_cursor(1, 5)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.test_source = require("mkdnflow.links").getLinkPart(_G.test_link, "source")')
    local result = child.lua_get('_G.test_source')
    eq(result, 'dir (x)/a.md')
end

T['getLinkPart']['extracts source from image link with parens in path'] = function()
    set_lines({ '![Image](photos (vacation)/beach.png)' })
    set_cursor(1, 5)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.test_source = require("mkdnflow.links").getLinkPart(_G.test_link, "source")')
    local result = child.lua_get('_G.test_source')
    eq(result, 'photos (vacation)/beach.png')
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
    child.lua(
        '_G.test_source, _G.test_anchor = require("mkdnflow.links").getLinkPart(_G.test_link, "source")'
    )
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
    child.lua(
        '_G.test_source, _G.test_anchor = require("mkdnflow.links").getLinkPart(_G.test_link, "source")'
    )
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

-- Issue #252: Link destruction doesn't work properly if multiple links on a line
T['destroyLink']['destroys first of multiple links on line (#252)'] = function()
    set_lines({ '[first](a.md) and [second](b.md)' })
    set_cursor(1, 3) -- Cursor on "first"
    child.lua([[require('mkdnflow.links').destroyLink()]])
    local result = get_line(1)
    eq(result, 'first and [second](b.md)')
end

T['destroyLink']['destroys second of multiple links on line'] = function()
    set_lines({ '[first](a.md) and [second](b.md)' })
    set_cursor(1, 22) -- Cursor on "second"
    child.lua([[require('mkdnflow.links').destroyLink()]])
    local result = get_line(1)
    eq(result, '[first](a.md) and second')
end

T['destroyLink']['destroys middle link of three'] = function()
    set_lines({ '[one](1.md) [two](2.md) [three](3.md)' })
    set_cursor(1, 14) -- Cursor on "two"
    child.lua([[require('mkdnflow.links').destroyLink()]])
    local result = get_line(1)
    eq(result, '[one](1.md) two [three](3.md)')
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
    -- When cursor is on whitespace, vim's <cWORD> typically returns adjacent word
    set_lines({ 'word  other' })
    set_cursor(1, 5) -- cursor on space between words
    child.lua([[require('mkdnflow.links').createLink()]])
    local result = get_line(1)
    -- The second word gets linked because <cWORD> finds it
    eq(result, 'word  [other](other.md)')
end

-- Issue #258: Visual selection with range should use full selection, not just first char
T['createLink']['creates link from visual selection with range'] = function()
    set_lines({ 'ABC-123' })
    -- Simulate visual selection of entire text, then run with range=true
    child.lua([[
        -- Set the visual selection marks
        vim.api.nvim_buf_set_mark(0, '<', 1, 0, {})
        vim.api.nvim_buf_set_mark(0, '>', 1, 6, {})
        require('mkdnflow.links').createLink({range = true})
    ]])
    local result = get_line(1)
    eq(result, '[ABC-123](ABC-123.md)')
end

T['createLink']['creates link from partial visual selection with range'] = function()
    set_lines({ 'prefix ABC-123 suffix' })
    -- Select just "ABC-123" in the middle
    child.lua([[
        vim.api.nvim_buf_set_mark(0, '<', 1, 7, {})
        vim.api.nvim_buf_set_mark(0, '>', 1, 13, {})
        require('mkdnflow.links').createLink({range = true})
    ]])
    local result = get_line(1)
    eq(result, 'prefix [ABC-123](ABC-123.md) suffix')
end

-- Issue #206: <cWORD> captures contiguous non-whitespace, including path separators
T['createLink']['creates link from path with slashes'] = function()
    set_lines({ 'See foo/bar for details' })
    set_cursor(1, 6) -- cursor on 'b' in 'bar' part of 'foo/bar'
    child.lua([[require('mkdnflow.links').createLink()]])
    local result = get_line(1)
    eq(result, 'See [foo/bar](foo/bar.md) for details')
end

T['createLink']['strips trailing period'] = function()
    set_lines({ 'See word.' })
    set_cursor(1, 4) -- cursor on 'word'
    child.lua([[require('mkdnflow.links').createLink()]])
    local result = get_line(1)
    eq(result, 'See [word](word.md).')
end

T['createLink']['strips trailing comma'] = function()
    set_lines({ 'word, rest' })
    set_cursor(1, 0) -- cursor on 'word'
    child.lua([[require('mkdnflow.links').createLink()]])
    local result = get_line(1)
    eq(result, '[word](word.md), rest')
end

T['createLink']['strips surrounding parens'] = function()
    set_lines({ '(word) rest' })
    set_cursor(1, 1) -- cursor on 'w' in 'word'
    child.lua([[require('mkdnflow.links').createLink()]])
    local result = get_line(1)
    eq(result, '([word](word.md)) rest')
end

T['createLink']['preserves leading dot for dotfiles'] = function()
    set_lines({ '.gitignore rest' })
    set_cursor(1, 3) -- cursor on 'i' in 'gitignore'
    child.lua([[require('mkdnflow.links').createLink()]])
    local result = get_line(1)
    eq(result, '[.gitignore](.gitignore.md) rest')
end

T['createLink']['creates link from path with trailing period'] = function()
    set_lines({ 'See path/to/file.' })
    set_cursor(1, 6) -- cursor on 't' in 'to'
    child.lua([[require('mkdnflow.links').createLink()]])
    local result = get_line(1)
    eq(result, 'See [path/to/file](path/to/file.md).')
end

T['createLink']['creates link from file with extension'] = function()
    set_lines({ 'See file.txt here' })
    set_cursor(1, 4) -- cursor on 'file'
    child.lua([[require('mkdnflow.links').createLink()]])
    local result = get_line(1)
    eq(result, 'See [file.txt](file.txt.md) here')
end

T['createLink']['creates link from hyphenated word'] = function()
    set_lines({ 'See some-slug here' })
    set_cursor(1, 8) -- cursor on 'slug' part of 'some-slug'
    child.lua([[require('mkdnflow.links').createLink()]])
    local result = get_line(1)
    eq(result, 'See [some-slug](some-slug.md) here')
end

T['createLink']['pattern escaping selects correct match'] = function()
    -- Without vim.pesc(), the pattern 'file.txt' would match 'file_txt' first
    set_lines({ 'file_txt file.txt rest' })
    set_cursor(1, 12) -- cursor on 'file.txt'
    child.lua([[require('mkdnflow.links').createLink()]])
    local result = get_line(1)
    eq(result, 'file_txt [file.txt](file.txt.md) rest')
end

T['createLink']['strips surrounding quotes'] = function()
    set_lines({ 'the "word" here' })
    set_cursor(1, 5) -- cursor on 'word'
    child.lua([[require('mkdnflow.links').createLink()]])
    local result = get_line(1)
    eq(result, 'the "[word](word.md)" here')
end

T['createLink']['strips multiple trailing punctuation'] = function()
    set_lines({ '(word!)' })
    set_cursor(1, 1) -- cursor on 'word'
    child.lua([[require('mkdnflow.links').createLink()]])
    local result = get_line(1)
    eq(result, '([word](word.md)!)')
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

-- =============================================================================
-- Task list edge cases (Issue #269)
-- =============================================================================
T['task_list_edge_cases'] = new_set()

-- Issue #269: Error following link in a task list
-- When cursor is on checkbox [ ], it gets matched as ref_style_link pattern
-- and causes crash in get_ref() when trying to concatenate nil refnr
T['task_list_edge_cases']['does not crash when cursor on checkbox before link'] = function()
    set_lines({ '- [ ] [Foo](bar.md)' })
    set_cursor(1, 3) -- cursor on the checkbox '['
    -- This should not crash - getLinkPart with nil should be handled gracefully
    child.lua([[
        _G.test_ok, _G.test_err = pcall(function()
            local link = require('mkdnflow.links').getLinkUnderCursor()
            if link then
                require('mkdnflow.links').getLinkPart(link, 'source')
            end
        end)
    ]])
    local success = child.lua_get('_G.test_ok')
    -- If it failed, show the error message for debugging
    if not success then
        local err = child.lua_get('tostring(_G.test_err)')
        error('getLinkPart crashed: ' .. err)
    end
    eq(success, true)
end

-- This test verifies that following a link in a task list doesn't crash
-- Reproduces the exact scenario from issue #269
T['task_list_edge_cases']['followLink does not crash on task list with link'] = function()
    set_lines({ '- [ ] [Foo](bar.md)', '', '[ref]: http://example.com' })
    set_cursor(1, 3) -- cursor on the checkbox '['
    -- followLink should not crash even if cursor is on checkbox
    child.lua([[
        _G.test_ok, _G.test_err = pcall(function()
            require('mkdnflow.links').followLink()
        end)
    ]])
    local success = child.lua_get('_G.test_ok')
    if not success then
        local err = child.lua_get('tostring(_G.test_err)')
        -- The bug causes: "attempt to concatenate local 'refnr' (a nil value)"
        if err:match('concatenate') and err:match('nil') then
            error('Issue #269 bug reproduced: ' .. err)
        end
        error('followLink crashed: ' .. err)
    end
    eq(success, true)
end

-- Pattern priority: md_link should be detected before ref_style_link
-- even when checkbox "[ ]" precedes the link (which could match ref_style_link pattern)
T['task_list_edge_cases']['detects md_link when cursor on link text in task list'] = function()
    set_lines({ '- [ ] [Foo](bar.md)' })
    set_cursor(1, 8) -- cursor on 'Foo' inside the link
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local link_type = child.lua_get('_G.test_link and _G.test_link[3]')
    eq(link_type, 'md_link')
end

T['task_list_edge_cases']['extracts source from link in task list'] = function()
    set_lines({ '- [ ] [Foo](bar.md)' })
    set_cursor(1, 8) -- cursor on 'Foo' inside the link
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.test_source = require("mkdnflow.links").getLinkPart(_G.test_link, "source")')
    local source = child.lua_get('_G.test_source')
    eq(source, 'bar.md')
end

T['task_list_edge_cases']['handles checked task with link'] = function()
    set_lines({ '- [x] [Link](page.md)' })
    set_cursor(1, 3) -- cursor on the checkbox 'x'
    child.lua([[
        _G.test_ok, _G.test_err = pcall(function()
            local link = require('mkdnflow.links').getLinkUnderCursor()
            if link then
                require('mkdnflow.links').getLinkPart(link, 'source')
            end
        end)
    ]])
    local success = child.lua_get('_G.test_ok')
    eq(success, true)
end

T['task_list_edge_cases']['handles in-progress task with link'] = function()
    set_lines({ '- [-] [Link](page.md)' })
    set_cursor(1, 3) -- cursor on the checkbox '-'
    child.lua([[
        _G.test_ok, _G.test_err = pcall(function()
            local link = require('mkdnflow.links').getLinkUnderCursor()
            if link then
                require('mkdnflow.links').getLinkPart(link, 'source')
            end
        end)
    ]])
    local success = child.lua_get('_G.test_ok')
    eq(success, true)
end

T['task_list_edge_cases']['handles nested task list with link'] = function()
    set_lines({ '  - [ ] [Nested](nested.md)' })
    set_cursor(1, 5) -- cursor on the checkbox '['
    child.lua([[
        _G.test_ok, _G.test_err = pcall(function()
            local link = require('mkdnflow.links').getLinkUnderCursor()
            if link then
                require('mkdnflow.links').getLinkPart(link, 'source')
            end
        end)
    ]])
    local success = child.lua_get('_G.test_ok')
    eq(success, true)
end

T['task_list_edge_cases']['handles task list item without link'] = function()
    set_lines({ '- [ ] Just a task' })
    set_cursor(1, 3) -- cursor on the checkbox '['
    -- The checkbox might be detected as something, but getLinkPart should not crash
    child.lua([[
        _G.test_ok, _G.test_err = pcall(function()
            local link = require('mkdnflow.links').getLinkUnderCursor()
            if link then
                require('mkdnflow.links').getLinkPart(link, 'source')
            end
        end)
    ]])
    local success = child.lua_get('_G.test_ok')
    eq(success, true)
end

T['task_list_edge_cases']['handles wiki link in task list'] = function()
    set_lines({ '- [ ] [[WikiPage]]' })
    set_cursor(1, 3) -- cursor on the checkbox '['
    child.lua([[
        _G.test_ok, _G.test_err = pcall(function()
            local link = require('mkdnflow.links').getLinkUnderCursor()
            if link then
                require('mkdnflow.links').getLinkPart(link, 'source')
            end
        end)
    ]])
    local success = child.lua_get('_G.test_ok')
    eq(success, true)
end

-- =============================================================================
-- createLink with from_clipboard (Issue #258 related)
-- =============================================================================
T['createLink_from_clipboard'] = new_set({
    hooks = {
        pre_case = function()
            -- Configure a mock clipboard provider for headless CI environments
            child.lua([[
                vim.g.clipboard = {
                    name = 'test_clipboard',
                    copy = { ['+'] = 'true', ['*'] = 'true' },
                    paste = {
                        ['+'] = function() return {vim.g._test_clipboard_content or ''} end,
                        ['*'] = function() return {vim.g._test_clipboard_content or ''} end,
                    },
                }
            ]])
        end,
    },
})

T['createLink_from_clipboard']['creates link using clipboard URL with range'] = function()
    set_lines({ 'Link Text' })
    child.lua([[
        -- Set clipboard content via our mock
        vim.g._test_clipboard_content = 'https://example.com'
        vim.fn.setreg('+', 'https://example.com')
        -- Set visual selection marks for full text
        vim.api.nvim_buf_set_mark(0, '<', 1, 0, {})
        vim.api.nvim_buf_set_mark(0, '>', 1, 8, {})
        require('mkdnflow.links').createLink({from_clipboard = true, range = true})
    ]])
    local result = get_line(1)
    eq(result, '[Link Text](https://example.com)')
end

T['createLink_from_clipboard']['creates link from partial selection with clipboard URL'] = function()
    set_lines({ 'prefix Click Here suffix' })
    child.lua([[
        -- Set clipboard content via our mock
        vim.g._test_clipboard_content = 'https://example.com/page'
        vim.fn.setreg('+', 'https://example.com/page')
        vim.api.nvim_buf_set_mark(0, '<', 1, 7, {})
        vim.api.nvim_buf_set_mark(0, '>', 1, 16, {})
        require('mkdnflow.links').createLink({from_clipboard = true, range = true})
    ]])
    local result = get_line(1)
    eq(result, 'prefix [Click Here](https://example.com/page) suffix')
end

-- =============================================================================
-- tagSpan() - Bracketed span creation from visual selection
-- =============================================================================
T['tagSpan'] = new_set()

T['tagSpan']['creates bracketed span from visual selection'] = function()
    set_lines({ 'some text here' })
    -- Enter visual mode, select "text", then call tagSpan
    child.type_keys('0') -- go to start of line
    child.type_keys('w') -- move to "text"
    child.type_keys('v') -- enter visual mode
    child.type_keys('e') -- select to end of word "text"
    child.lua([[require('mkdnflow.links').tagSpan()]])
    local result = get_line(1)
    eq(result, 'some [text]{#text} here')
end

T['tagSpan']['creates span with spaces converted to dashes in id'] = function()
    set_lines({ 'hello world text' })
    child.type_keys('0') -- go to start
    child.type_keys('v') -- enter visual mode
    child.type_keys('e') -- select "hello"
    child.type_keys('e') -- extend to "world"
    child.lua([[require('mkdnflow.links').tagSpan()]])
    local result = get_line(1)
    -- The ID should have spaces converted to dashes
    eq(result, '[hello world]{#hello-world} text')
end

T['tagSpan']['creates span for single word'] = function()
    set_lines({ 'word' })
    child.type_keys('0')
    child.type_keys('v')
    child.type_keys('e')
    child.lua([[require('mkdnflow.links').tagSpan()]])
    local result = get_line(1)
    eq(result, '[word]{#word}')
end

T['tagSpan']['does nothing in normal mode'] = function()
    set_lines({ 'unchanged text' })
    set_cursor(1, 5)
    -- Call tagSpan without being in visual mode
    child.lua([[require('mkdnflow.links').tagSpan()]])
    local result = get_line(1)
    eq(result, 'unchanged text')
end

T['tagSpan']['handles inverted selection (right to left)'] = function()
    set_lines({ 'select this word' })
    child.type_keys('0')
    child.type_keys('2w') -- move to "word"
    child.type_keys('v') -- enter visual mode
    child.type_keys('b') -- select backwards to "this"
    child.lua([[require('mkdnflow.links').tagSpan()]])
    local result = get_line(1)
    -- Should create span for "this word" (or "this wor" depending on exact selection)
    eq(result, 'select [this w]{#this-w}ord')
end

-- =============================================================================
-- Position accuracy tests - getLinkPart returns correct positions
-- =============================================================================
T['positions'] = new_set()

T['positions']['getLinkPart returns correct source positions for md_link'] = function()
    set_lines({ '[text](path/to/file.md)' })
    set_cursor(1, 5)
    child.lua([[
        _G.link = require('mkdnflow.links').getLinkUnderCursor()
        _G.source, _G.anchor, _G.link_type, _G.start_row, _G.start_col, _G.end_row, _G.end_col =
            require('mkdnflow.links').getLinkPart(_G.link, 'source')
    ]])
    local start_row = child.lua_get('_G.start_row')
    local start_col = child.lua_get('_G.start_col')
    local end_row = child.lua_get('_G.end_row')
    local end_col = child.lua_get('_G.end_col')
    eq(start_row, 1)
    -- Source starts after "](" which is at position 7 (1-indexed)
    eq(start_col, 8)
    eq(end_row, 1)
    -- Source ends before ")" which is at position 22
    eq(end_col, 22)
end

T['positions']['getLinkPart returns correct name positions for md_link'] = function()
    set_lines({ '[display text](file.md)' })
    set_cursor(1, 5)
    child.lua([[
        _G.link = require('mkdnflow.links').getLinkUnderCursor()
        _G.name, _G.anchor, _G.link_type, _G.start_row, _G.start_col, _G.end_row, _G.end_col =
            require('mkdnflow.links').getLinkPart(_G.link, 'name')
    ]])
    local start_row = child.lua_get('_G.start_row')
    local start_col = child.lua_get('_G.start_col')
    local end_row = child.lua_get('_G.end_row')
    local end_col = child.lua_get('_G.end_col')
    eq(start_row, 1)
    -- Name starts after "[" at position 2
    eq(start_col, 2)
    eq(end_row, 1)
end

T['positions']['getLinkPart returns correct positions for wiki_link with bar'] = function()
    set_lines({ '[[path/to/page|display]]' })
    set_cursor(1, 5)
    child.lua([[
        _G.link = require('mkdnflow.links').getLinkUnderCursor()
        _G.source, _G.anchor, _G.link_type, _G.start_row, _G.start_col, _G.end_row, _G.end_col =
            require('mkdnflow.links').getLinkPart(_G.link, 'source')
    ]])
    local start_row = child.lua_get('_G.start_row')
    local start_col = child.lua_get('_G.start_col')
    eq(start_row, 1)
    -- Source starts after "[[" at position 3
    eq(start_col, 3)
end

T['positions']['getLinkPart returns correct positions for ref_style_link'] = function()
    set_lines({ '[text][ref]', '', '[ref]: https://example.com' })
    set_cursor(1, 5)
    child.lua([[
        _G.link = require('mkdnflow.links').getLinkUnderCursor()
        _G.source, _G.anchor, _G.link_type, _G.start_row, _G.start_col, _G.end_row, _G.end_col =
            require('mkdnflow.links').getLinkPart(_G.link, 'source')
    ]])
    local start_row = child.lua_get('_G.start_row')
    local source = child.lua_get('_G.source')
    eq(source, 'https://example.com')
    -- Source is on line 3 (the reference definition line)
    eq(start_row, 3)
end

T['positions']['getLinkPart returns correct positions for auto_link'] = function()
    set_lines({ '<https://example.com>' })
    set_cursor(1, 10)
    child.lua([[
        _G.link = require('mkdnflow.links').getLinkUnderCursor()
        _G.source, _G.anchor, _G.link_type, _G.start_row, _G.start_col, _G.end_row, _G.end_col =
            require('mkdnflow.links').getLinkPart(_G.link, 'source')
    ]])
    local start_row = child.lua_get('_G.start_row')
    local start_col = child.lua_get('_G.start_col')
    eq(start_row, 1)
    -- Source starts after "<" at position 2
    eq(start_col, 2)
end

T['positions']['getLinkPart returns correct positions for citation'] = function()
    set_lines({ 'See @smith2020 for details.' })
    set_cursor(1, 7)
    child.lua([[
        _G.link = require('mkdnflow.links').getLinkUnderCursor()
        _G.source, _G.anchor, _G.link_type, _G.start_row, _G.start_col, _G.end_row, _G.end_col =
            require('mkdnflow.links').getLinkPart(_G.link, 'source')
    ]])
    local start_row = child.lua_get('_G.start_row')
    local source = child.lua_get('_G.source')
    eq(start_row, 1)
    -- Citation source is the full @citekey
    eq(source, '@smith2020')
end

T['positions']['getLinkUnderCursor returns correct bounds for link in middle of line'] = function()
    set_lines({ 'prefix [link](file.md) suffix' })
    set_cursor(1, 12) -- on "link"
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    local start_row = child.lua_get('_G.link[4]')
    local start_col = child.lua_get('_G.link[5]')
    local end_row = child.lua_get('_G.link[6]')
    local end_col = child.lua_get('_G.link[7]')
    eq(start_row, 1)
    eq(start_col, 8) -- "[" is at position 8
    eq(end_row, 1)
    eq(end_col, 22) -- ")" is at position 22
end

-- =============================================================================
-- Buffer boundary tests
-- =============================================================================
T['boundaries'] = new_set()

T['boundaries']['link at very start of buffer'] = function()
    set_lines({ '[link](file.md)' })
    set_cursor(1, 0) -- cursor at very start
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    local link_type = child.lua_get('_G.link and _G.link[3]')
    eq(link_type, 'md_link')
end

T['boundaries']['link at very end of buffer'] = function()
    set_lines({ '[link](file.md)' })
    set_cursor(1, 14) -- cursor at end
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    local link_type = child.lua_get('_G.link and _G.link[3]')
    eq(link_type, 'md_link')
end

T['boundaries']['link on first line of file'] = function()
    set_lines({ '[first](first.md)', 'second line' })
    set_cursor(1, 5)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    local link_type = child.lua_get('_G.link and _G.link[3]')
    eq(link_type, 'md_link')
end

T['boundaries']['link on last line of file'] = function()
    set_lines({ 'first line', '[last](last.md)' })
    set_cursor(2, 5)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    local link_type = child.lua_get('_G.link and _G.link[3]')
    eq(link_type, 'md_link')
end

T['boundaries']['single-line buffer with link'] = function()
    set_lines({ '[only](only.md)' })
    set_cursor(1, 5)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    local link_type = child.lua_get('_G.link and _G.link[3]')
    eq(link_type, 'md_link')
end

T['boundaries']['empty buffer does not crash'] = function()
    set_lines({ '' })
    set_cursor(1, 0)
    child.lua([[
        _G.ok, _G.err = pcall(function()
            _G.link = require('mkdnflow.links').getLinkUnderCursor()
        end)
    ]])
    local success = child.lua_get('_G.ok')
    eq(success, true)
    local link = child.lua_get('_G.link')
    eq(link, vim.NIL)
end

T['boundaries']['destroyLink on only line in buffer'] = function()
    set_lines({ '[only](only.md)' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.links').destroyLink()]])
    local result = get_line(1)
    eq(result, 'only')
end

-- =============================================================================
-- Unicode/multibyte character tests
-- =============================================================================
T['unicode'] = new_set()

T['unicode']['link with CJK text in name'] = function()
    set_lines({ '[中文文本](file.md)' })
    set_cursor(1, 3)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.name = require("mkdnflow.links").getLinkPart(_G.link, "name")')
    local link_type = child.lua_get('_G.link and _G.link[3]')
    local name = child.lua_get('_G.name')
    eq(link_type, 'md_link')
    eq(name, '中文文本')
end

T['unicode']['link with CJK text in source'] = function()
    set_lines({ '[text](路径/文件.md)' })
    set_cursor(1, 3)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.source = require("mkdnflow.links").getLinkPart(_G.link, "source")')
    local source = child.lua_get('_G.source')
    eq(source, '路径/文件.md')
end

T['unicode']['wiki link with unicode content'] = function()
    set_lines({ '[[日本語ページ|表示テキスト]]' })
    set_cursor(1, 5)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    local link_type = child.lua_get('_G.link and _G.link[3]')
    eq(link_type, 'wiki_link')
end

T['unicode']['destroyLink preserves surrounding unicode'] = function()
    set_lines({ '前置 [link](file.md) 後置' })
    set_cursor(1, 10)
    child.lua([[require('mkdnflow.links').destroyLink()]])
    local result = get_line(1)
    eq(result, '前置 link 後置')
end

T['unicode']['createLink with unicode word'] = function()
    set_lines({ '中文' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.links').createLink()]])
    local result = get_line(1)
    eq(result, '[中文](中文.md)')
end

T['unicode']['link with emoji in name'] = function()
    set_lines({ '[🚀 Launch](rocket.md)' })
    set_cursor(1, 5)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.name = require("mkdnflow.links").getLinkPart(_G.link, "name")')
    local name = child.lua_get('_G.name')
    eq(name, '🚀 Launch')
end

T['unicode']['anchor with unicode heading'] = function()
    local result = child.lua_get([[require('mkdnflow.links').formatLink('#日本語見出し')]])
    -- Should lowercase and convert spaces to dashes, preserve unicode
    eq(result[1], '[日本語見出し](#日本語見出し)')
end

-- =============================================================================
-- Configuration option tests
-- =============================================================================
T['config'] = new_set()

T['config']['links.style=wiki creates wiki links'] = function()
    child.lua([[require('mkdnflow').setup({ links = { style = 'wiki' } })]])
    local result = child.lua_get([[require('mkdnflow.links').formatLink('my page')]])
    eq(result[1], '[[my page.md|my page]]')
end

T['config']['links.style=markdown creates markdown links'] = function()
    child.lua([[require('mkdnflow').setup({ links = { style = 'markdown' } })]])
    local result = child.lua_get([[require('mkdnflow.links').formatLink('my page')]])
    eq(result[1], '[my page](my page.md)')
end

T['config']['formatLink style param overrides config (wiki)'] = function()
    child.lua([[require('mkdnflow').setup({ links = { style = 'markdown' } })]])
    local result =
        child.lua_get([[require('mkdnflow.links').formatLink('my page', nil, nil, 'wiki')]])
    eq(result[1], '[[my page.md|my page]]')
end

T['config']['formatLink style param overrides config (markdown)'] = function()
    child.lua([[require('mkdnflow').setup({ links = { style = 'wiki' } })]])
    local result =
        child.lua_get([[require('mkdnflow.links').formatLink('my page', nil, nil, 'markdown')]])
    eq(result[1], '[my page](my page.md)')
end

T['config']['formatLink without style param uses config'] = function()
    child.lua([[require('mkdnflow').setup({ links = { style = 'wiki' } })]])
    local result = child.lua_get([[require('mkdnflow.links').formatLink('my page')]])
    eq(result[1], '[[my page.md|my page]]')
end

T['config']['createLink style param overrides config'] = function()
    child.lua([[require('mkdnflow').setup({ links = { style = 'markdown' } })]])
    set_lines({ 'myword' })
    set_cursor(1, 2)
    child.lua([[require('mkdnflow.links').createLink({ style = 'wiki' })]])
    local line = get_lines()[1]
    -- Should be wiki style despite config being markdown
    eq(line:match('%[%[') ~= nil, true)
end

T['config']['createLink without style param uses config'] = function()
    child.lua([[require('mkdnflow').setup({ links = { style = 'markdown' } })]])
    set_lines({ 'myword' })
    set_cursor(1, 2)
    child.lua([[require('mkdnflow.links').createLink()]])
    local line = get_lines()[1]
    -- Should be markdown style
    eq(line:match('%[.*%]%(.*%)') ~= nil, true)
end

T['config']['MkdnCreateLink command accepts style arg'] = function()
    child.lua([[
        vim.cmd('runtime plugin/mkdnflow.lua')
        require('mkdnflow').setup({ links = { style = 'markdown' }, silent = true })
        vim.api.nvim_buf_set_name(0, 'test.md')
        vim.bo.filetype = 'markdown'
    ]])
    set_lines({ 'myword' })
    set_cursor(1, 2)
    child.cmd('MkdnCreateLink wiki')
    local line = get_lines()[1]
    eq(line:match('%[%[') ~= nil, true)
end

T['config']['MkdnCreateLink command accepts abbreviated style'] = function()
    child.lua([[
        vim.cmd('runtime plugin/mkdnflow.lua')
        require('mkdnflow').setup({ links = { style = 'markdown' }, silent = true })
        vim.api.nvim_buf_set_name(0, 'test.md')
        vim.bo.filetype = 'markdown'
    ]])
    set_lines({ 'testword' })
    set_cursor(1, 2)
    child.cmd('MkdnCreateLink w')
    local line = get_lines()[1]
    eq(line:match('%[%[') ~= nil, true)
end

T['config']['MkdnCreateLink command without arg uses config'] = function()
    child.lua([[
        vim.cmd('runtime plugin/mkdnflow.lua')
        require('mkdnflow').setup({ links = { style = 'wiki' }, silent = true })
        vim.api.nvim_buf_set_name(0, 'test.md')
        vim.bo.filetype = 'markdown'
    ]])
    set_lines({ 'aword' })
    set_cursor(1, 2)
    child.cmd('MkdnCreateLink')
    local line = get_lines()[1]
    eq(line:match('%[%[') ~= nil, true)
end

T['config']['links.compact omits bar in wiki link'] = function()
    child.lua([[require('mkdnflow').setup({ links = { style = 'wiki', compact = true } })]])
    local result = child.lua_get([[require('mkdnflow.links').formatLink('my page')]])
    eq(result[1], '[[my page]]')
end

T['config']['links.implicit_extension omits .md'] = function()
    child.lua([[require('mkdnflow').setup({ links = { implicit_extension = '.md' } })]])
    local result = child.lua_get([[require('mkdnflow.links').formatLink('my page')]])
    eq(result[1], '[my page](my page)')
end

T['config']['links.transform_on_create applies custom function'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = {
                transform_on_create = function(text)
                    return string.lower(text):gsub(' ', '_')
                end
            }
        })
    ]])
    local result = child.lua_get([[require('mkdnflow.links').formatLink('My Page')]])
    eq(result[1], '[My Page](my_page.md)')
end

T['config']['links.transform_on_create=false returns text unchanged'] = function()
    child.lua([[require('mkdnflow').setup({ links = { transform_on_create = false } })]])
    local result = child.lua_get([[require('mkdnflow.links').formatLink('My Page')]])
    eq(result[1], '[My Page](My Page.md)')
end

T['config']['links.transform_scope=path passes full text to transform'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = {
                transform_on_create = function(text)
                    return string.lower(text):gsub('[ /]', '-')
                end,
                transform_scope = 'path',
            }
        })
    ]])
    local result = child.lua_get([[require('mkdnflow.links').formatLink('work/with/dirs')]])
    eq(result[1], '[work/with/dirs](work-with-dirs.md)')
end

T['config']['links.transform_scope=filename transforms only filename'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = {
                transform_on_create = function(text)
                    return string.lower(text):gsub(' ', '-')
                end,
                transform_scope = 'filename',
            }
        })
    ]])
    local result = child.lua_get([[require('mkdnflow.links').formatLink('work/with/My Page')]])
    eq(result[1], '[work/with/My Page](work/with/my-page.md)')
end

T['config']['links.transform_scope=filename without slash behaves like path'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = {
                transform_on_create = function(text)
                    return string.lower(text):gsub(' ', '_')
                end,
                transform_scope = 'filename',
            }
        })
    ]])
    local result = child.lua_get([[require('mkdnflow.links').formatLink('My Page')]])
    eq(result[1], '[My Page](my_page.md)')
end

T['config']['links.transform_scope per-call override in formatLink'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = {
                transform_on_create = function(text)
                    return string.lower(text):gsub(' ', '-')
                end,
                transform_scope = 'path',
            }
        })
    ]])
    -- Override to 'filename' at call time
    local result = child.lua_get(
        [[require('mkdnflow.links').formatLink('work/with/My Page', nil, nil, nil, 'filename')]]
    )
    eq(result[1], '[work/with/My Page](work/with/my-page.md)')
end

T['config']['links.transform_scope per-call override in createLink'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = {
                transform_on_create = function(text)
                    return string.lower(text):gsub(' ', '-')
                end,
                transform_scope = 'path',
            }
        })
    ]])
    set_lines({ 'work/with/dirs' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.links').createLink({ transform_scope = 'filename' })]])
    local result = get_line(1)
    eq(result, '[work/with/dirs](work/with/dirs.md)')
end

T['config']['links.transform_scope=filename with default transform'] = function()
    -- This test verifies the exact scenario from issue #223
    -- Must explicitly provide transform_on_create since pre_case sets it to false
    child.lua([[
        require('mkdnflow').setup({
            links = {
                transform_on_create = function(text)
                    text = text:gsub('[ /]', '-')
                    text = text:lower()
                    text = os.date('%Y-%m-%d_') .. text
                    return text
                end,
                transform_scope = 'filename',
            }
        })
    ]])
    -- Use formatLink with part=2 to get just the path portion
    local path_part =
        child.lua_get([[require('mkdnflow.links').formatLink('work/with/dirs', nil, 2)]])
    -- With default transform: only 'dirs' gets the date prefix and lowercasing
    -- Directory prefix 'work/with/' is preserved
    local today = os.date('%Y-%m-%d')
    eq(path_part, 'work/with/' .. today .. '_dirs.md')
end

T['config']['MkdnCreateLink command accepts scope argument'] = function()
    child.lua([[
        vim.cmd('runtime plugin/mkdnflow.lua')
        require('mkdnflow').setup({
            links = {
                transform_on_create = function(text)
                    return string.lower(text):gsub(' ', '-')
                end,
            },
            silent = true,
        })
        vim.api.nvim_buf_set_name(0, 'test.md')
        vim.bo.filetype = 'markdown'
    ]])
    set_lines({ 'work/with/dirs' })
    set_cursor(1, 5)
    child.cmd('MkdnCreateLink filename')
    local result = get_line(1)
    eq(result, '[work/with/dirs](work/with/dirs.md)')
end

T['config']['MkdnCreateLink command accepts both style and scope'] = function()
    child.lua([[
        vim.cmd('runtime plugin/mkdnflow.lua')
        require('mkdnflow').setup({
            links = {
                transform_on_create = function(text)
                    return string.lower(text):gsub(' ', '-')
                end,
            },
            silent = true,
        })
        vim.api.nvim_buf_set_name(0, 'test.md')
        vim.bo.filetype = 'markdown'
    ]])
    set_lines({ 'work/with/dirs' })
    set_cursor(1, 5)
    child.cmd('MkdnCreateLink wiki filename')
    local result = get_line(1)
    eq(result, '[[work/with/dirs.md|work/with/dirs]]')
end

T['config']['links.auto_create creates link from word'] = function()
    child.lua([[require('mkdnflow').setup({ links = { auto_create = true } })]])
    set_lines({ 'word here' })
    set_cursor(1, 2)
    -- followLink with no link under cursor should create one
    child.lua([[require('mkdnflow.links').followLink()]])
    local result = get_line(1)
    eq(result, '[word](word.md) here')
end

T['config']['links.auto_create=false does not create link'] = function()
    child.lua([[require('mkdnflow').setup({ links = { auto_create = false } })]])
    set_lines({ 'word here' })
    set_cursor(1, 2)
    child.lua([[require('mkdnflow.links').followLink()]])
    local result = get_line(1)
    eq(result, 'word here') -- unchanged
end

-- =============================================================================
-- Image link specific tests
-- =============================================================================
T['image_links'] = new_set()

T['image_links']['getLinkUnderCursor detects image link'] = function()
    set_lines({ '![alt text](image.png)' })
    set_cursor(1, 5)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    local link_type = child.lua_get('_G.link and _G.link[3]')
    eq(link_type, 'image_link')
end

T['image_links']['getLinkPart extracts source from image link'] = function()
    set_lines({ '![alt](path/to/image.png)' })
    set_cursor(1, 5)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.source = require("mkdnflow.links").getLinkPart(_G.link, "source")')
    local source = child.lua_get('_G.source')
    eq(source, 'path/to/image.png')
end

T['image_links']['getLinkPart extracts alt text from image link'] = function()
    set_lines({ '![my alt text](image.png)' })
    set_cursor(1, 5)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.name = require("mkdnflow.links").getLinkPart(_G.link, "name")')
    local name = child.lua_get('_G.name')
    eq(name, 'my alt text')
end

T['image_links']['getLinkPart extracts anchor from image link'] = function()
    set_lines({ '![alt](image.png#section)' })
    set_cursor(1, 5)
    child.lua([[
        _G.link = require('mkdnflow.links').getLinkUnderCursor()
        _G.source, _G.anchor = require('mkdnflow.links').getLinkPart(_G.link, 'source')
    ]])
    local source = child.lua_get('_G.source')
    local anchor = child.lua_get('_G.anchor')
    eq(source, 'image.png')
    eq(anchor, '#section')
end

T['image_links']['destroyLink on image link keeps alt text'] = function()
    set_lines({ '![alt text](image.png)' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.links').destroyLink()]])
    local result = get_line(1)
    eq(result, 'alt text')
end

T['image_links']['image link with angle bracket source'] = function()
    set_lines({ '![alt](<path with spaces.png>)' })
    set_cursor(1, 5)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.source = require("mkdnflow.links").getLinkPart(_G.link, "source")')
    local source = child.lua_get('_G.source')
    eq(source, 'path with spaces.png')
end

T['image_links']['image link in middle of text'] = function()
    set_lines({ 'See ![diagram](fig.png) for details.' })
    set_cursor(1, 8)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    local link_type = child.lua_get('_G.link and _G.link[3]')
    eq(link_type, 'image_link')
end

-- =============================================================================
-- Anchor-only link tests
-- =============================================================================
T['anchor_links'] = new_set()

T['anchor_links']['formatLink creates anchor from heading'] = function()
    local result = child.lua_get([[require('mkdnflow.links').formatLink('#My Heading')]])
    eq(result[1], '[My Heading](#my-heading)')
end

T['anchor_links']['formatLink handles heading with punctuation'] = function()
    local result = child.lua_get([[require('mkdnflow.links').formatLink('#What is this?')]])
    eq(result[1], '[What is this?](#what-is-this)')
end

T['anchor_links']['formatLink preserves unicode in anchor'] = function()
    local result = child.lua_get([[require('mkdnflow.links').formatLink('#日本語')]])
    eq(result[1], '[日本語](#日本語)')
end

T['anchor_links']['formatAnchorLegacy produces ASCII-only anchor'] = function()
    local result = child.lua_get([[require('mkdnflow.links').formatAnchorLegacy('日本語 Text')]])
    -- Legacy strips non-ASCII chars but leaves spaces, then removes leading space
    -- "日本語 Text" -> " Text" -> "Text" -> "#text"
    eq(result, '#text')
end

T['anchor_links']['formatLink removes multiple hash prefixes'] = function()
    local result = child.lua_get([[require('mkdnflow.links').formatLink('### Third Level')]])
    eq(result[1], '[Third Level](#third-level)')
end

T['anchor_links']['anchor-only link detected correctly'] = function()
    set_lines({ '[Section](#my-section)' })
    set_cursor(1, 5)
    child.lua([[
        _G.link = require('mkdnflow.links').getLinkUnderCursor()
        _G.source, _G.anchor = require('mkdnflow.links').getLinkPart(_G.link, 'source')
    ]])
    local source = child.lua_get('_G.source')
    local anchor = child.lua_get('_G.anchor')
    eq(source, '')
    eq(anchor, '#my-section')
end

-- =============================================================================
-- Special character handling tests
-- =============================================================================
T['special_chars'] = new_set()

T['special_chars']['link with parentheses in URL'] = function()
    set_lines({ '[wiki](https://en.wikipedia.org/wiki/Lua_(programming_language))' })
    set_cursor(1, 5)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    local link_type = child.lua_get('_G.link and _G.link[3]')
    eq(link_type, 'md_link')
end

T['special_chars']['link with query string'] = function()
    set_lines({ '[search](https://google.com/search?q=test&lang=en)' })
    set_cursor(1, 5)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.source = require("mkdnflow.links").getLinkPart(_G.link, "source")')
    local source = child.lua_get('_G.source')
    eq(source, 'https://google.com/search?q=test&lang=en')
end

T['special_chars']['link with percent encoding'] = function()
    set_lines({ '[file](path%20with%20spaces.md)' })
    set_cursor(1, 5)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.source = require("mkdnflow.links").getLinkPart(_G.link, "source")')
    local source = child.lua_get('_G.source')
    eq(source, 'path%20with%20spaces.md')
end

T['special_chars']['wiki link without pipe has same source and name'] = function()
    set_lines({ '[[simple page]]' })
    set_cursor(1, 5)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.source = require("mkdnflow.links").getLinkPart(_G.link, "source")')
    child.lua('_G.name = require("mkdnflow.links").getLinkPart(_G.link, "name")')
    local source = child.lua_get('_G.source')
    local name = child.lua_get('_G.name')
    eq(source, 'simple page')
    eq(name, 'simple page')
end

T['special_chars']['auto_link with complex URL'] = function()
    set_lines({ '<https://example.com/path?query=1&other=2#anchor>' })
    set_cursor(1, 15)
    child.lua([[
        _G.link = require('mkdnflow.links').getLinkUnderCursor()
        _G.source, _G.anchor = require('mkdnflow.links').getLinkPart(_G.link, 'source')
    ]])
    local source = child.lua_get('_G.source')
    local anchor = child.lua_get('_G.anchor')
    eq(source, 'https://example.com/path?query=1&other=2')
    eq(anchor, '#anchor')
end

T['special_chars']['ref_style_link with angle brackets in definition'] = function()
    set_lines({ '[text][ref]', '', '[ref]: <https://example.com/path with spaces>' })
    set_cursor(1, 3)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.source = require("mkdnflow.links").getLinkPart(_G.link, "source")')
    local source = child.lua_get('_G.source')
    eq(source, 'https://example.com/path with spaces')
end

-- =============================================================================
-- Multiline link tests
-- =============================================================================
T['multiline'] = new_set()

T['multiline']['getLinkUnderCursor returns nil for partial link on single line'] = function()
    -- A link that starts on one line but doesn't complete should not match
    set_lines({ '[incomplete link', 'second line' })
    set_cursor(1, 5)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    local link = child.lua_get('_G.link')
    eq(link, vim.NIL)
end

T['multiline']['citation at line boundary'] = function()
    set_lines({ 'End of line @smith2020', 'next line' })
    set_cursor(1, 15)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    local link_type = child.lua_get('_G.link and _G.link[3]')
    eq(link_type, 'citation')
end

T['multiline']['ref_style_link with definition on later line'] = function()
    set_lines({ 'Paragraph with [text][ref].', '', '', '[ref]: https://example.com' })
    set_cursor(1, 18)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.source = require("mkdnflow.links").getLinkPart(_G.link, "source")')
    local source = child.lua_get('_G.source')
    eq(source, 'https://example.com')
end

T['multiline']['destroyLink works correctly on single-line link'] = function()
    set_lines({ 'Line one', '[link](file.md)', 'Line three' })
    set_cursor(2, 5)
    child.lua([[require('mkdnflow.links').destroyLink()]])
    local result = get_line(2)
    eq(result, 'link')
end

-- Multi-line link detection with search_range > 0
-- These tests verify the feature from issue #85: following links split across
-- lines (e.g. by hard-wrapping with `gq`).
T['multiline']['search_range'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
                require('mkdnflow').setup({
                    links = {
                        search_range = 1,
                        transform_on_create = false,
                    },
                })
            ]])
        end,
    },
})

T['multiline']['search_range']['detects md_link split after link text'] = function()
    -- [some link
    -- text](https://example.com)
    set_lines({ '[some link', 'text](https://example.com)' })
    set_cursor(1, 3)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    local link_type = child.lua_get('_G.link and _G.link[3]')
    eq(link_type, 'md_link')
    child.lua('_G.source = require("mkdnflow.links").getLinkPart(_G.link, "source")')
    local source = child.lua_get('_G.source')
    eq(source, 'https://example.com')
end

T['multiline']['search_range']['detects md_link with cursor on second line'] = function()
    -- [long link text on first
    -- line](file.md)
    set_lines({ '[long link text on first', 'line](file.md)' })
    set_cursor(2, 0)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    local link_type = child.lua_get('_G.link and _G.link[3]')
    eq(link_type, 'md_link')
    child.lua('_G.source = require("mkdnflow.links").getLinkPart(_G.link, "source")')
    local source = child.lua_get('_G.source')
    eq(source, 'file.md')
end

T['multiline']['search_range']['detects md_link with inline text before link'] = function()
    -- Words before the link [here it
    -- is](short-url.md)
    set_lines({ 'Words before the link [here it', 'is](short-url.md)' })
    set_cursor(1, 25)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    local link_type = child.lua_get('_G.link and _G.link[3]')
    eq(link_type, 'md_link')
    child.lua('_G.source = require("mkdnflow.links").getLinkPart(_G.link, "source")')
    local source = child.lua_get('_G.source')
    eq(source, 'short-url.md')
end

T['multiline']['search_range']['reports correct start/end rows for split link'] = function()
    set_lines({ '[split', 'link](url.md)' })
    set_cursor(1, 2)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    local start_row = child.lua_get('_G.link and _G.link[4]')
    local end_row = child.lua_get('_G.link and _G.link[6]')
    eq(start_row, 1)
    eq(end_row, 2)
end

T['multiline']['search_range']['does not detect link beyond search_range'] = function()
    -- With search_range = 1, a link that spans 3 lines should not be found
    -- when cursor is on the first line
    set_lines({ '[link text', 'that spans', 'many lines](url.md)' })
    set_cursor(1, 3)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    local link = child.lua_get('_G.link')
    eq(link, vim.NIL)
end

T['multiline']['search_range']['detects wiki_link split across lines'] = function()
    set_lines({ '[[some long', 'page name]]' })
    set_cursor(1, 4)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    local link_type = child.lua_get('_G.link and _G.link[3]')
    eq(link_type, 'wiki_link')
end

T['multiline']['search_range']['detects image_link split across lines'] = function()
    set_lines({ '![alt', 'text](image.png)' })
    set_cursor(1, 2)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    local link_type = child.lua_get('_G.link and _G.link[3]')
    eq(link_type, 'image_link')
    child.lua('_G.source = require("mkdnflow.links").getLinkPart(_G.link, "source")')
    local source = child.lua_get('_G.source')
    eq(source, 'image.png')
end

T['multiline']['search_range']['adjacent brackets and parens form link across lines'] = function()
    -- With search_range > 0, adjacent [text] and (url) on separate lines
    -- are concatenated and matched as a link. This is a known trade-off of
    -- multi-line detection (and why search_range defaults to 0).
    set_lines({ '[link text]', '(url.md)' })
    set_cursor(1, 3)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    local link_type = child.lua_get('_G.link and _G.link[3]')
    eq(link_type, 'md_link')
end

-- destroyLink tests for multi-line links (issue #85 comments)
T['multiline']['search_range']['destroyLink joins multi-line name with space'] = function()
    -- [some
    -- text](destination) → "some text"
    set_lines({ '[some', 'text](destination.md)' })
    set_cursor(1, 2)
    child.lua([[require('mkdnflow.links').destroyLink()]])
    local lines = get_lines()
    eq(lines, { 'some text' })
end

T['multiline']['search_range']['destroyLink preserves surrounding text'] = function()
    -- Before [some
    -- text](dest) after → "Before some text after"
    set_lines({ 'Before [some', 'text](dest.md) after' })
    set_cursor(1, 9)
    child.lua([[require('mkdnflow.links').destroyLink()]])
    local lines = get_lines()
    eq(lines, { 'Before some text after' })
end

T['multiline']['search_range']['destroyLink works when only URL wraps'] = function()
    -- [link text](really/long/
    -- url/path.md) → "link text"
    set_lines({ '[link text](really/long/', 'url/path.md)' })
    set_cursor(1, 3)
    child.lua([[require('mkdnflow.links').destroyLink()]])
    local lines = get_lines()
    eq(lines, { 'link text' })
end

T['multiline']['search_range']['destroyLink on single-line link with preceding lines'] = function()
    -- Regression test: should not get end_col out of bounds error
    set_lines({ 'Some text', 'and now the next line. [link text](link-text.md)' })
    set_cursor(2, 25)
    child.lua([[require('mkdnflow.links').destroyLink()]])
    eq(get_line(1), 'Some text')
    eq(get_line(2), 'and now the next line. link text')
end

T['multiline']['search_range']['destroyLink on multi-line wiki_link joins with space'] = function()
    set_lines({ '[[some long', 'page name]]' })
    set_cursor(1, 4)
    child.lua([[require('mkdnflow.links').destroyLink()]])
    local lines = get_lines()
    eq(lines, { 'some long page name' })
end

-- =============================================================================
-- Pattern export tests (for advanced users)
-- =============================================================================
T['patterns'] = new_set()

-- Note: The current links.lua doesn't export patterns publicly.
-- These tests verify the internal patterns work correctly.
-- After refactoring, patterns may be exported for advanced use.

T['patterns']['md_link pattern matches standard link'] = function()
    local result = child.lua_get([[string.match('[text](url)', '(%b[]%b())') ~= nil]])
    eq(result, true)
end

T['patterns']['wiki_link pattern matches double brackets'] = function()
    local result = child.lua_get("string.match('[[page]]', '(%[%b[]%])') ~= nil")
    eq(result, true)
end

T['patterns']['image_link pattern matches exclamation mark'] = function()
    local result = child.lua_get([[string.match('![alt](img)', '(!%b[]%b())') ~= nil]])
    eq(result, true)
end

T['patterns']['citation pattern matches at-sign'] = function()
    local result = child.lua_get(
        [[string.match(' @smith2020 ', "[^%a%d]-(@[%a%d_%.%-']*[%a%d]+)[%s%p%c]?") ~= nil]]
    )
    eq(result, true)
end

T['patterns']['ref_style_link pattern matches bracket-bracket'] = function()
    local result = child.lua_get([[string.match('[text][ref]', '(%b[]%s?%b[])') ~= nil]])
    eq(result, true)
end

T['patterns']['auto_link pattern matches angle brackets'] = function()
    local result = child.lua_get([[string.match('<https://url>', '(%b<>)') ~= nil]])
    eq(result, true)
end

-- =============================================================================
-- Link Class Tests
-- =============================================================================
T['Link'] = new_set()

T['Link']['new() creates valid instance'] = function()
    child.lua([[
        local core = require('mkdnflow.links.core')
        _G.link = core.Link:new({
            match = '[text](url)',
            match_lines = { '[text](url)' },
            type = 'md_link',
            start_row = 1,
            start_col = 1,
            end_row = 1,
            end_col = 12,
        })
    ]])
    eq(child.lua_get('_G.link.match'), '[text](url)')
    eq(child.lua_get('_G.link.type'), 'md_link')
    eq(child.lua_get('_G.link.start_row'), 1)
    eq(child.lua_get('_G.link.end_col'), 12)
end

T['Link']['__className is Link'] = function()
    child.lua([[
        local core = require('mkdnflow.links.core')
        _G.link = core.Link:new({ match = 'test', type = 'md_link' })
    ]])
    eq(child.lua_get('_G.link.__className'), 'Link')
end

T['Link']['backwards compatible numeric indexing'] = function()
    child.lua([[
        local core = require('mkdnflow.links.core')
        _G.link = core.Link:new({
            match = '[text](url)',
            match_lines = { '[text](url)' },
            type = 'md_link',
            start_row = 5,
            start_col = 10,
            end_row = 5,
            end_col = 21,
        })
    ]])
    -- link[1] = match, link[2] = match_lines, link[3] = type, etc.
    eq(child.lua_get('_G.link[1]'), '[text](url)')
    eq(child.lua_get('_G.link[3]'), 'md_link')
    eq(child.lua_get('_G.link[4]'), 5) -- start_row
    eq(child.lua_get('_G.link[5]'), 10) -- start_col
    eq(child.lua_get('_G.link[6]'), 5) -- end_row
    eq(child.lua_get('_G.link[7]'), 21) -- end_col
end

T['Link']['read() detects md_link under cursor'] = function()
    set_lines({ 'Check [this link](https://example.com) out' })
    child.api.nvim_win_set_cursor(0, { 1, 10 })
    child.lua([[
        local core = require('mkdnflow.links.core')
        _G.link = core.Link:read(nil, 0)
    ]])
    eq(child.lua_get('_G.link.type'), 'md_link')
    eq(child.lua_get('_G.link.match'), '[this link](https://example.com)')
end

T['Link']['read() detects wiki_link under cursor'] = function()
    set_lines({ 'See [[wiki page]] for details' })
    child.api.nvim_win_set_cursor(0, { 1, 8 })
    child.lua([[
        local core = require('mkdnflow.links.core')
        _G.link = core.Link:read(nil, 0)
    ]])
    eq(child.lua_get('_G.link.type'), 'wiki_link')
    eq(child.lua_get('_G.link.match'), '[[wiki page]]')
end

T['Link']['read() detects image_link under cursor'] = function()
    set_lines({ 'Image: ![alt text](image.png)' })
    child.api.nvim_win_set_cursor(0, { 1, 12 })
    child.lua([[
        local core = require('mkdnflow.links.core')
        _G.link = core.Link:read(nil, 0)
    ]])
    eq(child.lua_get('_G.link.type'), 'image_link')
end

T['Link']['read() returns nil when no link under cursor'] = function()
    set_lines({ 'Just plain text here' })
    child.api.nvim_win_set_cursor(0, { 1, 5 })
    child.lua([[
        local core = require('mkdnflow.links.core')
        _G.link = core.Link:read(nil, 0)
    ]])
    eq(child.lua_get('_G.link'), vim.NIL)
end

T['Link']['is_image() returns true for image links'] = function()
    child.lua([[
        local core = require('mkdnflow.links.core')
        _G.link = core.Link:new({ match = '![alt](img.png)', type = 'image_link' })
    ]])
    eq(child.lua_get('_G.link:is_image()'), true)
    eq(child.lua_get('_G.link:is_wiki()'), false)
end

T['Link']['is_wiki() returns true for wiki links'] = function()
    child.lua(
        "local core = require('mkdnflow.links.core'); _G.link = core.Link:new({ match = '[[page]]', type = 'wiki_link' })"
    )
    eq(child.lua_get('_G.link:is_wiki()'), true)
    eq(child.lua_get('_G.link:is_image()'), false)
end

T['Link']['is_citation() returns true for citations'] = function()
    child.lua([[
        local core = require('mkdnflow.links.core')
        _G.link = core.Link:new({ match = '@smith2020', type = 'citation' })
    ]])
    eq(child.lua_get('_G.link:is_citation()'), true)
end

T['Link']['is_pandoc_citation() returns true for pandoc citations'] = function()
    child.lua([[
        local core = require('mkdnflow.links.core')
        _G.link = core.Link:new({ match = '[@smith2020]', type = 'pandoc_citation' })
    ]])
    eq(child.lua_get('_G.link:is_pandoc_citation()'), true)
    eq(child.lua_get('_G.link:is_citation()'), false)
end

T['Link']['get_type() returns type string'] = function()
    child.lua([[
        local core = require('mkdnflow.links.core')
        _G.link = core.Link:new({ match = '[text](url)', type = 'md_link' })
    ]])
    eq(child.lua_get('_G.link:get_type()'), 'md_link')
end

T['Link']['has_anchor() returns true when anchor present'] = function()
    set_lines({ '[text](page.md#section)' })
    child.api.nvim_win_set_cursor(0, { 1, 5 })
    child.lua([[
        local core = require('mkdnflow.links.core')
        _G.link = core.Link:read(nil, 0)
    ]])
    eq(child.lua_get('_G.link:has_anchor()'), true)
end

T['Link']['has_anchor() returns false when no anchor'] = function()
    set_lines({ '[text](page.md)' })
    child.api.nvim_win_set_cursor(0, { 1, 5 })
    child.lua([[
        local core = require('mkdnflow.links.core')
        _G.link = core.Link:read(nil, 0)
    ]])
    eq(child.lua_get('_G.link:has_anchor()'), false)
end

T['Link']['get_source() returns LinkPart with source text'] = function()
    set_lines({ '[link text](https://example.com)' })
    child.api.nvim_win_set_cursor(0, { 1, 5 })
    child.lua([[
        local core = require('mkdnflow.links.core')
        _G.link = core.Link:read(nil, 0)
        _G.source = _G.link:get_source()
    ]])
    eq(child.lua_get('_G.source.text'), 'https://example.com')
    eq(child.lua_get('_G.source.__className'), 'LinkPart')
end

T['Link']['get_name() returns LinkPart with name text'] = function()
    set_lines({ '[link text](https://example.com)' })
    child.api.nvim_win_set_cursor(0, { 1, 5 })
    child.lua([[
        local core = require('mkdnflow.links.core')
        _G.link = core.Link:read(nil, 0)
        _G.name = _G.link:get_name()
    ]])
    eq(child.lua_get('_G.name.text'), 'link text')
end

T['Link']['get_anchor() returns LinkPart with anchor'] = function()
    set_lines({ '[text](page.md#heading)' })
    child.api.nvim_win_set_cursor(0, { 1, 5 })
    child.lua([[
        local core = require('mkdnflow.links.core')
        _G.link = core.Link:read(nil, 0)
        _G.anchor = _G.link:get_anchor()
    ]])
    eq(child.lua_get('_G.anchor.text'), '#heading')
end

T['Link']['get_anchor() returns empty LinkPart when no anchor'] = function()
    set_lines({ '[text](page.md)' })
    child.api.nvim_win_set_cursor(0, { 1, 5 })
    child.lua([[
        local core = require('mkdnflow.links.core')
        _G.link = core.Link:read(nil, 0)
        _G.anchor = _G.link:get_anchor()
    ]])
    eq(child.lua_get('_G.anchor.text'), '')
    eq(child.lua_get('_G.anchor.anchor'), '')
end

-- =============================================================================
-- LinkPart Class Tests
-- =============================================================================
T['LinkPart'] = new_set()

T['LinkPart']['new() creates valid instance'] = function()
    child.lua([[
        local core = require('mkdnflow.links.core')
        _G.part = core.LinkPart:new({
            text = 'https://example.com',
            anchor = '#section',
            start_row = 1,
            start_col = 12,
            end_row = 1,
            end_col = 31,
        })
    ]])
    eq(child.lua_get('_G.part.text'), 'https://example.com')
    eq(child.lua_get('_G.part.anchor'), '#section')
    eq(child.lua_get('_G.part.start_col'), 12)
end

T['LinkPart']['__className is LinkPart'] = function()
    child.lua([[
        local core = require('mkdnflow.links.core')
        _G.part = core.LinkPart:new({ text = 'test' })
    ]])
    eq(child.lua_get('_G.part.__className'), 'LinkPart')
end

T['LinkPart']['has_anchor() returns true when anchor present'] = function()
    child.lua([[
        local core = require('mkdnflow.links.core')
        _G.part = core.LinkPart:new({ text = 'page.md', anchor = '#section' })
    ]])
    eq(child.lua_get('_G.part:has_anchor()'), true)
end

T['LinkPart']['has_anchor() returns false when no anchor'] = function()
    child.lua([[
        local core = require('mkdnflow.links.core')
        _G.part = core.LinkPart:new({ text = 'page.md', anchor = '' })
    ]])
    eq(child.lua_get('_G.part:has_anchor()'), false)
end

T['LinkPart']['get_text() returns text without anchor'] = function()
    child.lua([[
        local core = require('mkdnflow.links.core')
        _G.part = core.LinkPart:new({ text = 'page.md', anchor = '#section' })
    ]])
    eq(child.lua_get('_G.part:get_text()'), 'page.md')
end

T['LinkPart']['get_anchor() returns anchor string'] = function()
    child.lua([[
        local core = require('mkdnflow.links.core')
        _G.part = core.LinkPart:new({ text = 'page.md', anchor = '#section' })
    ]])
    eq(child.lua_get('_G.part:get_anchor()'), '#section')
end

T['LinkPart']['get_full_text() returns text with anchor'] = function()
    child.lua([[
        local core = require('mkdnflow.links.core')
        _G.part = core.LinkPart:new({ text = 'page.md', anchor = '#section' })
    ]])
    eq(child.lua_get('_G.part:get_full_text()'), 'page.md#section')
end

-- =============================================================================
-- cleanCitationText() - Strip citation syntax
-- =============================================================================
T['cleanCitationText'] = new_set()

T['cleanCitationText']['strips brackets from full pandoc syntax'] = function()
    local result = child.lua_get([[require('mkdnflow.links').cleanCitationText('[@smith2020]')]])
    eq(result, '@smith2020')
end

T['cleanCitationText']['preserves @ without brackets'] = function()
    local result = child.lua_get([[require('mkdnflow.links').cleanCitationText('@smith2020')]])
    eq(result, '@smith2020')
end

T['cleanCitationText']['strips trailing ] preserves @'] = function()
    local result = child.lua_get([[require('mkdnflow.links').cleanCitationText('@smith2020]')]])
    eq(result, '@smith2020')
end

T['cleanCitationText']['strips leading [ preserves @'] = function()
    local result = child.lua_get([[require('mkdnflow.links').cleanCitationText('[@smith2020')]])
    eq(result, '@smith2020')
end

T['cleanCitationText']['leaves plain text unchanged'] = function()
    local result = child.lua_get([[require('mkdnflow.links').cleanCitationText('smith2020')]])
    eq(result, 'smith2020')
end

T['cleanCitationText']['handles special chars in citekey'] = function()
    local result =
        child.lua_get([[require('mkdnflow.links').cleanCitationText('[@smith_2020-a.b]')]])
    eq(result, '@smith_2020-a.b')
end

T['cleanCitationText']['returns nil for nil input'] = function()
    local result = child.lua_get([[require('mkdnflow.links').cleanCitationText(nil)]])
    eq(result, vim.NIL)
end

T['cleanCitationText']['returns empty string for empty input'] = function()
    local result = child.lua_get([[require('mkdnflow.links').cleanCitationText('')]])
    eq(result, '')
end

T['cleanCitationText']['does not strip internal @'] = function()
    local result = child.lua_get([[require('mkdnflow.links').cleanCitationText('user@host')]])
    eq(result, 'user@host')
end

-- =============================================================================
-- followLink() with range + citation (integration tests)
-- =============================================================================
T['citation_link_creation'] = new_set()

T['citation_link_creation']['plain citation with range creates link'] = function()
    set_lines({ 'See @smith2020 for details.' })
    set_cursor(1, 7) -- cursor on the citation so getLinkUnderCursor detects it
    child.lua([[
        vim.api.nvim_buf_set_mark(0, '<', 1, 4, {})
        vim.api.nvim_buf_set_mark(0, '>', 1, 13, {})
        require('mkdnflow.links').followLink({ range = true })
    ]])
    local result = get_line(1)
    eq(result, 'See [@smith2020](smith2020.md) for details.')
end

T['citation_link_creation']['pandoc citation with range creates link'] = function()
    set_lines({ 'See [@smith2020] for details.' })
    set_cursor(1, 7) -- cursor on the citation so getLinkUnderCursor detects it
    child.lua([[
        vim.api.nvim_buf_set_mark(0, '<', 1, 4, {})
        vim.api.nvim_buf_set_mark(0, '>', 1, 15, {})
        require('mkdnflow.links').followLink({ range = true })
    ]])
    local result = get_line(1)
    eq(result, 'See [@smith2020](smith2020.md) for details.')
end

T['citation_link_creation']['partial marks on plain citation expand to full bounds'] = function()
    -- Marks cover only 'smith2020' (without @), but citation bounds should expand
    set_lines({ 'See @smith2020 for details.' })
    set_cursor(1, 7) -- cursor on the citation
    child.lua([[
        vim.api.nvim_buf_set_mark(0, '<', 1, 5, {})  -- 's' of smith2020
        vim.api.nvim_buf_set_mark(0, '>', 1, 13, {})  -- '0' of smith2020
        require('mkdnflow.links').followLink({ range = true })
    ]])
    local result = get_line(1)
    -- Full @smith2020 is replaced, not just the partial selection
    eq(result, 'See [@smith2020](smith2020.md) for details.')
end

T['citation_link_creation']['partial marks on pandoc citation expand to full bounds'] = function()
    -- Marks cover only '@smith2020' (without brackets), but citation bounds should expand
    set_lines({ 'See [@smith2020] for details.' })
    set_cursor(1, 7) -- cursor on the citation
    child.lua([[
        vim.api.nvim_buf_set_mark(0, '<', 1, 5, {})  -- '@' of @smith2020
        vim.api.nvim_buf_set_mark(0, '>', 1, 14, {})  -- '0' of smith2020
        require('mkdnflow.links').followLink({ range = true })
    ]])
    local result = get_line(1)
    -- Full [@smith2020] is replaced, not just the partial selection
    eq(result, 'See [@smith2020](smith2020.md) for details.')
end

T['citation_link_creation']['normal mode on citation does not create link'] = function()
    set_lines({ 'See @smith2020 for details.' })
    set_cursor(1, 7)
    -- followLink without range should NOT create a link (it would try to follow the citation)
    -- We just verify the line is unchanged (bib lookup will fail silently without a bib file)
    child.lua([[
        pcall(function()
            require('mkdnflow.links').followLink()
        end)
    ]])
    local result = get_line(1)
    eq(result, 'See @smith2020 for details.')
end

-- =============================================================================
-- E2E tests: Visual selection of citation + <CR> creates link
-- =============================================================================
T['citation_e2e'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                vim.cmd('runtime plugin/mkdnflow.lua')
                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
                require('mkdnflow').setup({
                    links = {
                        transform_on_create = false,
                    },
                })
                vim.cmd('doautocmd BufEnter')
            ]])
        end,
    },
})

T['citation_e2e']['visual select plain citation + <CR> creates link'] = function()
    set_lines({ 'See @smith2020 for details.' })
    set_cursor(1, 4)
    child.type_keys('v')
    child.type_keys('e')
    child.type_keys('<CR>')
    local result = get_line(1)
    eq(result, 'See [@smith2020](smith2020.md) for details.')
end

T['citation_e2e']['visual select full pandoc citation + <CR> creates link'] = function()
    set_lines({ 'See [@smith2020] for details.' })
    set_cursor(1, 4)
    child.type_keys('v')
    -- Select to the closing ]
    child.type_keys('f]')
    child.type_keys('<CR>')
    local result = get_line(1)
    eq(result, 'See [@smith2020](smith2020.md) for details.')
end

T['citation_e2e']['visual select bare citekey + <CR> creates link'] = function()
    set_lines({ 'See smith2020 for details.' })
    set_cursor(1, 4)
    child.type_keys('v')
    child.type_keys('e')
    child.type_keys('<CR>')
    local result = get_line(1)
    eq(result, 'See [smith2020](smith2020.md) for details.')
end

T['citation_e2e']['partial select @smith2020] expands to full citation'] = function()
    set_lines({ 'See [@smith2020] for details.' })
    set_cursor(1, 5)
    child.type_keys('v')
    child.type_keys('f]')
    child.type_keys('<CR>')
    local result = get_line(1)
    -- With bounds expansion, the full [@smith2020] is replaced even though [ was not selected
    eq(result, 'See [@smith2020](smith2020.md) for details.')
end

T['citation_e2e']['partial select [@smith2020 expands to full citation'] = function()
    set_lines({ 'See [@smith2020] for details.' })
    set_cursor(1, 4)
    child.type_keys('v')
    child.type_keys('t', ']') -- select up to but not including ']'
    child.type_keys('<CR>')
    local result = get_line(1)
    -- With bounds expansion, the full [@smith2020] is replaced even though ] was not selected
    eq(result, 'See [@smith2020](smith2020.md) for details.')
end

T['citation_e2e']['partial select bare citekey from plain citation expands'] = function()
    -- Select just 'smith2020' (without @) from '@smith2020'
    set_lines({ 'See @smith2020 for details.' })
    set_cursor(1, 5) -- on 's' of 'smith2020'
    child.type_keys('v')
    child.type_keys('e')
    child.type_keys('<CR>')
    local result = get_line(1)
    -- Bounds expansion replaces the full @smith2020
    eq(result, 'See [@smith2020](smith2020.md) for details.')
end

T['citation_e2e']['partial select bare citekey from pandoc citation expands'] = function()
    -- Select just 'smith2020' (without @ or brackets) from '[@smith2020]'
    set_lines({ 'See [@smith2020] for details.' })
    set_cursor(1, 6) -- on 's' of 'smith2020'
    child.type_keys('v')
    child.type_keys('e')
    child.type_keys('<CR>')
    local result = get_line(1)
    -- Bounds expansion replaces the full [@smith2020]
    eq(result, 'See [@smith2020](smith2020.md) for details.')
end

T['citation_e2e']['inverted selection on citation + <CR> creates link'] = function()
    set_lines({ 'See @smith2020 for details.' })
    -- Start at the end of the citation and select backward
    set_cursor(1, 13)
    child.type_keys('v')
    child.type_keys('F@')
    child.type_keys('<CR>')
    local result = get_line(1)
    eq(result, 'See [@smith2020](smith2020.md) for details.')
end

T['citation_e2e']['normal mode <CR> on citation does not create link'] = function()
    set_lines({ 'See @smith2020 for details.' })
    set_cursor(1, 7)
    -- In normal mode, <CR> should try to follow the citation (which will fail without bib),
    -- but should NOT create a link. Suppress the expected error notification.
    child.lua([[vim.notify = function() end]])
    child.type_keys('<CR>')
    local result = get_line(1)
    eq(result, 'See @smith2020 for details.')
end

T['citation_e2e']['visual select citation with wiki style creates wiki link'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = {
                style = 'wiki',
                transform_on_create = false,
            },
        })
    ]])
    set_lines({ 'See @smith2020 for details.' })
    set_cursor(1, 4)
    child.type_keys('v')
    child.type_keys('e')
    child.type_keys('<CR>')
    local result = get_line(1)
    eq(result, 'See [[smith2020.md|@smith2020]] for details.')
end

T['citation_e2e']['visual select on email creates plain link not citation link'] = function()
    set_lines({ 'Contact me at jakewvincent@gmail.com please.' })
    set_cursor(1, 14) -- on 'j' of 'jakewvincent'
    child.type_keys('v')
    child.type_keys('E') -- select the whole email (word + punctuation)
    child.type_keys('<CR>')
    local result = get_line(1)
    -- Should create a regular link from the selection, not treat @gmail.com as a citation
    eq(result, 'Contact me at [jakewvincent@gmail.com](jakewvincent@gmail.com.md) please.')
end

-- =============================================================================
-- Shortcut reference links [label] (Issue #208)
-- =============================================================================
T['shortcut_ref'] = new_set()

T['shortcut_ref']['detects shortcut reference link'] = function()
    set_lines({ 'See [gh] for details.', '', '[gh]: https://github.com/' })
    set_cursor(1, 5) -- on 'g' inside [gh]
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'shortcut_ref_link')
end

T['shortcut_ref']['resolves source from definition below'] = function()
    set_lines({ 'See [gh] for details.', '', '[gh]: https://github.com/' })
    set_cursor(1, 5)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    local path = child.lua_get([[require('mkdnflow.links').getLinkPart(_G.link, 'source')]])
    eq(path, 'https://github.com/')
end

T['shortcut_ref']['resolves source from definition above'] = function()
    set_lines({ '[gh]: https://github.com/', '', 'See [gh] for details.' })
    set_cursor(3, 5) -- on 'g' inside [gh] on line 3
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    local path = child.lua_get([[require('mkdnflow.links').getLinkPart(_G.link, 'source')]])
    eq(path, 'https://github.com/')
end

T['shortcut_ref']['returns empty source when no definition exists'] = function()
    set_lines({ 'See [orphan] for details.' })
    set_cursor(1, 6)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    local path = child.lua_get([[require('mkdnflow.links').getLinkPart(_G.link, 'source')]])
    eq(path, '')
end

T['shortcut_ref']['extracts name'] = function()
    set_lines({ 'See [gh] for details.', '', '[gh]: https://github.com/' })
    set_cursor(1, 5)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    local name = child.lua_get([[require('mkdnflow.links').getLinkPart(_G.link, 'name')]])
    eq(name, 'gh')
end

T['shortcut_ref']['not detected when cursor is on md_link'] = function()
    set_lines({ '[text](https://example.com)' })
    set_cursor(1, 3) -- on 'x' in 'text'
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'md_link')
end

T['shortcut_ref']['not detected when cursor is on ref_style_link'] = function()
    set_lines({ '[text][ref]', '', '[ref]: https://example.com' })
    set_cursor(1, 3) -- on 'x' in 'text'
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'ref_style_link')
end

T['shortcut_ref']['resolves definition with angle brackets'] = function()
    set_lines({ 'See [gh].', '', '[gh]: <https://github.com/path with spaces>' })
    set_cursor(1, 5)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    local path = child.lua_get([[require('mkdnflow.links').getLinkPart(_G.link, 'source')]])
    eq(path, 'https://github.com/path with spaces')
end

T['shortcut_ref']['resolves definition with title'] = function()
    set_lines({ 'See [gh].', '', '[gh]: https://github.com/ "GitHub"' })
    set_cursor(1, 5)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    local path = child.lua_get([[require('mkdnflow.links').getLinkPart(_G.link, 'source')]])
    eq(path, 'https://github.com/')
end

-- =============================================================================
-- Reference definition lines [label]: url
-- =============================================================================
T['ref_definition'] = new_set()

T['ref_definition']['detects reference definition line'] = function()
    set_lines({ '[ref]: https://example.com' })
    set_cursor(1, 3)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'ref_definition')
end

T['ref_definition']['extracts source URL'] = function()
    set_lines({ '[ref]: https://example.com' })
    set_cursor(1, 3)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    local path = child.lua_get([[require('mkdnflow.links').getLinkPart(_G.link, 'source')]])
    eq(path, 'https://example.com')
end

T['ref_definition']['extracts source with angle brackets'] = function()
    set_lines({ '[ref]: <https://example.com/path with spaces>' })
    set_cursor(1, 3)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    local path = child.lua_get([[require('mkdnflow.links').getLinkPart(_G.link, 'source')]])
    eq(path, 'https://example.com/path with spaces')
end

T['ref_definition']['extracts source with title'] = function()
    set_lines({ '[ref]: https://example.com "Example Site"' })
    set_cursor(1, 3)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    local path = child.lua_get([[require('mkdnflow.links').getLinkPart(_G.link, 'source')]])
    eq(path, 'https://example.com')
end

T['ref_definition']['extracts name (label)'] = function()
    set_lines({ '[my-ref]: https://example.com' })
    set_cursor(1, 3)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    local name = child.lua_get([[require('mkdnflow.links').getLinkPart(_G.link, 'name')]])
    eq(name, 'my-ref')
end

T['ref_definition']['detects with leading whitespace (up to 3 spaces)'] = function()
    set_lines({ '   [ref]: https://example.com' })
    set_cursor(1, 5)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'ref_definition')
end

T['ref_definition']['not detected with 4+ spaces indent'] = function()
    set_lines({ '    [ref]: https://example.com' })
    set_cursor(1, 6)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    -- Should NOT be detected as ref_definition (4 spaces = code block in GFM)
    eq(result ~= 'ref_definition', true)
end

T['ref_definition']['extracts source with anchor'] = function()
    set_lines({ '[ref]: https://example.com#section' })
    set_cursor(1, 3)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua([[
        _G.path, _G.anchor = require('mkdnflow.links').getLinkPart(_G.link, 'source')
    ]])
    eq(child.lua_get('_G.path'), 'https://example.com')
    eq(child.lua_get('_G.anchor'), '#section')
end

-- =============================================================================
-- Collapsed reference links [label][]
-- =============================================================================
T['collapsed_ref'] = new_set()

T['collapsed_ref']['detected as ref_style_link'] = function()
    set_lines({ '[label][]', '', '[label]: https://example.com' })
    set_cursor(1, 3)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'ref_style_link')
end

T['collapsed_ref']['resolves source using label as reference'] = function()
    set_lines({ '[label][]', '', '[label]: https://example.com' })
    set_cursor(1, 3)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    local path = child.lua_get([[require('mkdnflow.links').getLinkPart(_G.link, 'source')]])
    eq(path, 'https://example.com')
end

T['collapsed_ref']['resolves with definition above'] = function()
    set_lines({ '[label]: https://example.com', '', 'See [label][].' })
    set_cursor(3, 6)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    local path = child.lua_get([[require('mkdnflow.links').getLinkPart(_G.link, 'source')]])
    eq(path, 'https://example.com')
end

-- =============================================================================
-- get_ref() whole-buffer search
-- =============================================================================
T['get_ref_whole_buffer'] = new_set()

T['get_ref_whole_buffer']['full ref_style_link resolves definition above'] = function()
    set_lines({ '[ref]: https://example.com', '', '[text][ref]' })
    set_cursor(3, 3) -- on 'x' in 'text'
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    local path = child.lua_get([[require('mkdnflow.links').getLinkPart(_G.link, 'source')]])
    eq(path, 'https://example.com')
end

T['get_ref_whole_buffer']['full ref_style_link resolves definition below'] = function()
    set_lines({ '[text][ref]', '', '[ref]: https://example.com' })
    set_cursor(1, 3)
    child.lua('_G.link = require("mkdnflow.links").getLinkUnderCursor()')
    local path = child.lua_get([[require('mkdnflow.links').getLinkPart(_G.link, 'source')]])
    eq(path, 'https://example.com')
end

return T
