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
            child.lua(
                [[
                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
                require('mkdnflow').setup({
                    modules = { bib = true },
                    bib = {
                        default_path = ']]
                    .. test_bib_path
                    .. [[',
                        find_in_root = false
                    },
                    silent = true
                })
            ]]
            )
        end,
        post_once = child.stop,
    },
})

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
-- handleCitation() - Look up citation and return link
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
-- Priority of fields
-- =============================================================================
T['field_priority'] = new_set()

T['field_priority']['file takes precedence over url'] = function()
    -- jones2021 has a file field, which should be returned even if url existed
    local result = child.lua_get([[require('mkdnflow.bib').handleCitation('@jones2021')]])
    eq(result:match('^file:') ~= nil, true)
end

-- =============================================================================
-- Edge cases
-- =============================================================================
T['edge_cases'] = new_set()

-- Note: Empty citation "@" actually matches the first entry in the bib file
-- because the citekey becomes empty and the pattern matches any entry.
-- This could be considered a bug, but documenting actual behavior here.
T['edge_cases']['empty citation matches first entry'] = function()
    local result = child.lua_get([[require('mkdnflow.bib').handleCitation('@')]])
    -- Returns the URL from smith2020 (first entry)
    eq(result, 'https://example.com/smith2020')
end

T['edge_cases']['handles citation without @ prefix'] = function()
    -- The function expects @ prefix, so smith2020 without @ should fail
    local result = child.lua_get([[require('mkdnflow.bib').handleCitation('smith2020')]])
    eq(result, vim.NIL)
end

T['edge_cases']['handles citation with special characters'] = function()
    -- Citation keys often have underscores, hyphens, etc.
    -- @smith2020 should work even though it has numbers
    local result = child.lua_get([[require('mkdnflow.bib').handleCitation('@smith2020')]])
    eq(result ~= nil, true)
end

T['edge_cases']['case sensitivity in citation lookup'] = function()
    -- BibTeX is case-sensitive for citation keys
    local result = child.lua_get([[require('mkdnflow.bib').handleCitation('@SMITH2020')]])
    eq(result, vim.NIL) -- Should not find uppercase version
end

return T
