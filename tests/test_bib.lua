-- tests/test_bib.lua
-- Tests for bibliography/citation handling functionality

local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

-- Get the absolute path to the test bib file
local test_bib_path = vim.fn.fnamemodify('tests/fixtures/test.bib', ':p')

local T = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
                require('mkdnflow').setup({
                    modules = { bib = true },
                    bib = {
                        default_path = ']] .. test_bib_path .. [[',
                        find_in_root = false
                    },
                    silent = true
                })
            ]])
        end,
        post_once = child.stop,
    },
})

-- =============================================================================
-- BibEntry:new - Constructor tests
-- =============================================================================
T['BibEntry:new'] = new_set()

T['BibEntry:new']['creates empty instance with defaults'] = function()
    child.lua([[_G.e = require('mkdnflow.bib').BibEntry:new()]])
    local key = child.lua_get('_G.e.key')
    local valid = child.lua_get('_G.e.valid')
    local entry_type = child.lua_get('_G.e.entry_type')
    eq(key, '')
    eq(valid, false)
    eq(entry_type, '')
end

T['BibEntry:new']['creates instance with provided options'] = function()
    child.lua(
        [[_G.e = require('mkdnflow.bib').BibEntry:new({ key = 'test2020', valid = true, entry_type = 'article' })]]
    )
    local key = child.lua_get('_G.e.key')
    local valid = child.lua_get('_G.e.valid')
    local entry_type = child.lua_get('_G.e.entry_type')
    eq(key, 'test2020')
    eq(valid, true)
    eq(entry_type, 'article')
end

T['BibEntry:new']['sets __className correctly'] = function()
    child.lua([[_G.e = require('mkdnflow.bib').BibEntry:new()]])
    local className = child.lua_get('_G.e.__className')
    eq(className, 'BibEntry')
end

-- =============================================================================
-- BibEntry:read - Factory method tests
-- =============================================================================
T['BibEntry:read'] = new_set()

T['BibEntry:read']['parses citation key from entry'] = function()
    child.lua([[
        local BibEntry = require('mkdnflow.bib').BibEntry
        local text = "{testkey2020,\n  author = {Test Author},\n  title = {Test Title},\n}"
        _G.e = BibEntry:read(text)
    ]])
    local key = child.lua_get('_G.e:get_citation_key()')
    eq(key, 'testkey2020')
end

T['BibEntry:read']['parses standard fields'] = function()
    child.lua([[
        local BibEntry = require('mkdnflow.bib').BibEntry
        local text = "{testkey2020,\n  author = {Test Author},\n  title = {Test Title},\n  year = {2020},\n  url = {https://example.com},\n}"
        _G.e = BibEntry:read(text)
    ]])
    eq(child.lua_get([[_G.e:get_field('author')]]), 'Test Author')
    eq(child.lua_get('_G.e:get_title()'), 'Test Title')
    eq(child.lua_get('_G.e:get_year()'), '2020')
    eq(child.lua_get([[_G.e:get_field('url')]]), 'https://example.com')
end

T['BibEntry:read']['handles braces in field values'] = function()
    child.lua([[
        local BibEntry = require('mkdnflow.bib').BibEntry
        local text = "{braces2020,\n  title = {Title with {Special} Words},\n}"
        _G.e = BibEntry:read(text)
    ]])
    local title = child.lua_get('_G.e:get_title()')
    eq(title, 'Title with {Special} Words')
end

T['BibEntry:read']['returns entry with valid=false for empty input'] = function()
    child.lua([[_G.e = require('mkdnflow.bib').BibEntry:read('')]])
    local valid = child.lua_get('_G.e:is_valid()')
    eq(valid, false)
end

T['BibEntry:read']['returns entry with valid=false for nil input'] = function()
    child.lua([[_G.e = require('mkdnflow.bib').BibEntry:read(nil)]])
    local valid = child.lua_get('_G.e:is_valid()')
    eq(valid, false)
end

-- =============================================================================
-- BibEntry accessors
-- =============================================================================
T['BibEntry_accessors'] = new_set()

T['BibEntry_accessors']['get_citation_key returns key'] = function()
    child.lua([[_G.e = require('mkdnflow.bib').BibEntry:new({ key = 'mykey2020', valid = true })]])
    local key = child.lua_get('_G.e:get_citation_key()')
    eq(key, 'mykey2020')
end

T['BibEntry_accessors']['get_authors parses single author'] = function()
    child.lua(
        [[_G.e = require('mkdnflow.bib').BibEntry:new({ fields = { author = 'John Smith' }, valid = true })]]
    )
    local authors = child.lua_get('_G.e:get_authors()')
    eq(#authors, 1)
    eq(authors[1], 'John Smith')
end

T['BibEntry_accessors']['get_authors parses multiple authors'] = function()
    child.lua(
        [[_G.e = require('mkdnflow.bib').BibEntry:new({ fields = { author = 'John Smith and Jane Doe' }, valid = true })]]
    )
    local authors = child.lua_get('_G.e:get_authors()')
    eq(#authors, 2)
    eq(authors[1], 'John Smith')
    eq(authors[2], 'Jane Doe')
end

T['BibEntry_accessors']['get_title returns title'] = function()
    child.lua(
        [[_G.e = require('mkdnflow.bib').BibEntry:new({ fields = { title = 'My Great Paper' }, valid = true })]]
    )
    local title = child.lua_get('_G.e:get_title()')
    eq(title, 'My Great Paper')
end

T['BibEntry_accessors']['get_year returns year'] = function()
    child.lua(
        [[_G.e = require('mkdnflow.bib').BibEntry:new({ fields = { year = '2023' }, valid = true })]]
    )
    local year = child.lua_get('_G.e:get_year()')
    eq(year, '2023')
end

T['BibEntry_accessors']['get_field returns any field by name'] = function()
    child.lua(
        [[_G.e = require('mkdnflow.bib').BibEntry:new({ fields = { journal = 'Test Journal' }, valid = true })]]
    )
    local journal = child.lua_get([[_G.e:get_field('journal')]])
    eq(journal, 'Test Journal')
end

T['BibEntry_accessors']['get_field returns nil for missing field'] = function()
    child.lua([[_G.e = require('mkdnflow.bib').BibEntry:new({ fields = {}, valid = true })]])
    local result = child.lua_get([[_G.e:get_field('nonexistent')]])
    eq(result, vim.NIL)
end

T['BibEntry_accessors']['has_field returns true for existing field'] = function()
    child.lua(
        [[_G.e = require('mkdnflow.bib').BibEntry:new({ fields = { title = 'Test' }, valid = true })]]
    )
    local result = child.lua_get([[_G.e:has_field('title')]])
    eq(result, true)
end

T['BibEntry_accessors']['has_field returns false for missing field'] = function()
    child.lua([[_G.e = require('mkdnflow.bib').BibEntry:new({ fields = {}, valid = true })]])
    local result = child.lua_get([[_G.e:has_field('nonexistent')]])
    eq(result, false)
end

T['BibEntry_accessors']['is_valid returns true for entry with key'] = function()
    child.lua([[_G.e = require('mkdnflow.bib').BibEntry:new({ key = 'test', valid = true })]])
    local result = child.lua_get('_G.e:is_valid()')
    eq(result, true)
end

-- =============================================================================
-- BibEntry:get_link - Link resolution tests
-- =============================================================================
T['BibEntry:get_link'] = new_set()

T['BibEntry:get_link']['returns file path when file field exists'] = function()
    child.lua(
        [[_G.e = require('mkdnflow.bib').BibEntry:new({ fields = { file = '/path/to/paper.pdf' }, valid = true })]]
    )
    local link = child.lua_get('_G.e:get_link()')
    eq(link, 'file:/path/to/paper.pdf')
end

T['BibEntry:get_link']['returns url when url field exists'] = function()
    child.lua(
        [[_G.e = require('mkdnflow.bib').BibEntry:new({ fields = { url = 'https://example.com' }, valid = true })]]
    )
    local link = child.lua_get('_G.e:get_link()')
    eq(link, 'https://example.com')
end

T['BibEntry:get_link']['returns DOI url when doi field exists'] = function()
    child.lua(
        [[_G.e = require('mkdnflow.bib').BibEntry:new({ fields = { doi = '10.1234/test.2020' }, valid = true })]]
    )
    local link = child.lua_get('_G.e:get_link()')
    eq(link, 'https://doi.org/10.1234/test.2020')
end

T['BibEntry:get_link']['returns howpublished when that field exists'] = function()
    child.lua(
        [[_G.e = require('mkdnflow.bib').BibEntry:new({ fields = { howpublished = 'https://website.org' }, valid = true })]]
    )
    local link = child.lua_get('_G.e:get_link()')
    eq(link, 'https://website.org')
end

T['BibEntry:get_link']['returns nil when no link fields exist'] = function()
    child.lua(
        [[_G.e = require('mkdnflow.bib').BibEntry:new({ fields = { title = 'No Links' }, valid = true })]]
    )
    local link = child.lua_get('_G.e:get_link()')
    eq(link, vim.NIL)
end

T['BibEntry:get_link']['follows priority file > url'] = function()
    child.lua(
        [[_G.e = require('mkdnflow.bib').BibEntry:new({ fields = { file = '/path/to/paper.pdf', url = 'https://example.com' }, valid = true })]]
    )
    local link = child.lua_get('_G.e:get_link()')
    eq(link, 'file:/path/to/paper.pdf')
end

T['BibEntry:get_link']['follows priority url > doi'] = function()
    child.lua(
        [[_G.e = require('mkdnflow.bib').BibEntry:new({ fields = { url = 'https://example.com', doi = '10.1234/test' }, valid = true })]]
    )
    local link = child.lua_get('_G.e:get_link()')
    eq(link, 'https://example.com')
end

-- =============================================================================
-- BibEntry:format_citation - Citation formatting tests
-- =============================================================================
T['BibEntry:format_citation'] = new_set()

T['BibEntry:format_citation']['formats single author with year'] = function()
    child.lua(
        [[_G.e = require('mkdnflow.bib').BibEntry:new({ key = 'test2020', fields = { author = 'John Smith', year = '2020' }, valid = true })]]
    )
    local citation = child.lua_get('_G.e:format_citation()')
    eq(citation, 'John Smith (2020)')
end

T['BibEntry:format_citation']['formats multiple authors with et al'] = function()
    child.lua(
        [[_G.e = require('mkdnflow.bib').BibEntry:new({ key = 'test2020', fields = { author = 'Smith, John and Doe, Jane and Williams, Bob', year = '2020' }, valid = true })]]
    )
    local citation = child.lua_get('_G.e:format_citation()')
    eq(citation:match('et al') ~= nil, true)
end

T['BibEntry:format_citation']['handles missing fields gracefully'] = function()
    child.lua(
        [[_G.e = require('mkdnflow.bib').BibEntry:new({ key = 'test2020', fields = {}, valid = true })]]
    )
    local citation = child.lua_get('_G.e:format_citation()')
    eq(citation, '@test2020')
end

-- =============================================================================
-- bib_paths - Bibliography path storage
-- =============================================================================
T['bib_paths'] = new_set()

T['bib_paths']['has default paths table'] = function()
    local has_default = child.lua_get('require("mkdnflow.bib").bib_paths.default ~= nil')
    eq(has_default, true)
end

T['bib_paths']['has root paths table'] = function()
    local has_root = child.lua_get('require("mkdnflow.bib").bib_paths.root ~= nil')
    eq(has_root, true)
end

T['bib_paths']['has yaml paths table'] = function()
    local has_yaml = child.lua_get('require("mkdnflow.bib").bib_paths.yaml ~= nil')
    eq(has_yaml, true)
end

T['bib_paths']['default contains configured path'] = function()
    local default_paths = child.lua_get('require("mkdnflow.bib").bib_paths.default')
    eq(type(default_paths), 'table')
    eq(#default_paths >= 1, true)
end

-- =============================================================================
-- handleCitation() - Look up citation and return link (backward compatibility)
-- =============================================================================
T['handleCitation'] = new_set()

T['handleCitation']['returns URL for entry with url field'] = function()
    local result = child.lua_get([[require('mkdnflow.bib').handleCitation('@smith2020')]])
    eq(result, 'https://example.com/smith2020')
end

T['handleCitation']['returns file path for entry with file field'] = function()
    local result = child.lua_get([[require('mkdnflow.bib').handleCitation('@jones2021')]])
    eq(result, 'file:/path/to/jones2021.pdf')
end

T['handleCitation']['returns DOI URL for entry with doi field'] = function()
    local result = child.lua_get([[require('mkdnflow.bib').handleCitation('@doe2022')]])
    eq(result, 'https://doi.org/10.1234/test.2022')
end

T['handleCitation']['returns howpublished for entry with that field'] = function()
    local result = child.lua_get([[require('mkdnflow.bib').handleCitation('@web2023')]])
    eq(result, 'https://example.org/web')
end

T['handleCitation']['returns nil for entry with no relevant fields'] = function()
    local result = child.lua_get([[require('mkdnflow.bib').handleCitation('@empty2024')]])
    eq(result, vim.NIL)
end

T['handleCitation']['returns nil for nonexistent citation'] = function()
    local result = child.lua_get([[require('mkdnflow.bib').handleCitation('@nonexistent')]])
    eq(result, vim.NIL)
end

T['handleCitation']['handles citation with @ prefix'] = function()
    local result = child.lua_get([[require('mkdnflow.bib').handleCitation('@smith2020')]])
    eq(result ~= nil, true)
end

-- =============================================================================
-- findEntry() - New class-based API
-- =============================================================================
T['findEntry'] = new_set()

T['findEntry']['returns BibEntry instance for valid citation'] = function()
    child.lua([[_G.entry = require('mkdnflow.bib').findEntry('@smith2020')]])
    local className = child.lua_get('_G.entry.__className')
    eq(className, 'BibEntry')
end

T['findEntry']['returns nil for nonexistent citation'] = function()
    local result = child.lua_get([[require('mkdnflow.bib').findEntry('@nonexistent')]])
    eq(result, vim.NIL)
end

T['findEntry']['returned entry has all fields accessible'] = function()
    child.lua([[_G.entry = require('mkdnflow.bib').findEntry('@smith2020')]])
    eq(child.lua_get('_G.entry:get_citation_key()'), 'smith2020')
    eq(child.lua_get('_G.entry:get_title()'), 'A Test Article')
    eq(child.lua_get('_G.entry:get_year()'), '2020')
    eq(child.lua_get('_G.entry:is_valid()'), true)
end

T['findEntry']['get_link matches handleCitation result'] = function()
    child.lua([[
        local bib = require('mkdnflow.bib')
        _G.entry = bib.findEntry('@smith2020')
        _G.handle_result = bib.handleCitation('@smith2020')
    ]])
    local get_link = child.lua_get('_G.entry:get_link()')
    local handle_result = child.lua_get('_G.handle_result')
    eq(get_link, handle_result)
end

-- =============================================================================
-- field_priority - Priority of fields
-- =============================================================================
T['field_priority'] = new_set()

T['field_priority']['file takes precedence over url'] = function()
    -- jones2021 has a file field, which should be returned even if url existed
    local result = child.lua_get([[require('mkdnflow.bib').handleCitation('@jones2021')]])
    eq(result:match('^file:') ~= nil, true)
end

-- =============================================================================
-- edge_cases - Edge cases
-- =============================================================================
T['edge_cases'] = new_set()

T['edge_cases']['empty citation returns nil'] = function()
    local result = child.lua_get([[require('mkdnflow.bib').handleCitation('@')]])
    -- Empty citekey should not match any entry
    eq(result, vim.NIL)
end

T['edge_cases']['handles citation without @ prefix via findEntry'] = function()
    -- findEntry without @ prefix should still work (it strips the @ if present)
    local result = child.lua_get([[require('mkdnflow.bib').findEntry('smith2020')]])
    eq(result ~= vim.NIL, true)
end

T['edge_cases']['handles citation with special characters'] = function()
    -- Citation key with underscore and hyphen
    local result = child.lua_get([[require('mkdnflow.bib').handleCitation('@special_key-2024')]])
    eq(result, 'https://example.com/special')
end

T['edge_cases']['case sensitivity in citation lookup'] = function()
    -- BibTeX is case-sensitive for citation keys
    local result = child.lua_get([[require('mkdnflow.bib').handleCitation('@SMITH2020')]])
    eq(result, vim.NIL) -- Should not find uppercase version
end

T['edge_cases']['handles multi-author entries'] = function()
    child.lua([[_G.entry = require('mkdnflow.bib').findEntry('@multiauthor2023')]])
    local valid = child.lua_get('_G.entry:is_valid()')
    local authors = child.lua_get('_G.entry:get_authors()')
    eq(valid, true)
    eq(#authors > 1, true)
end

T['edge_cases']['handles entries with braces in title'] = function()
    child.lua([[_G.entry = require('mkdnflow.bib').findEntry('@braces2023')]])
    local valid = child.lua_get('_G.entry:is_valid()')
    local title = child.lua_get('_G.entry:get_title()')
    eq(valid, true)
    eq(title:match('{Special}') ~= nil, true)
end

return T
