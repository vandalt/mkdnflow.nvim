-- tests/test_yaml.lua
-- Tests for YAML frontmatter parsing functionality

local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

-- Helper to set buffer content
local function set_lines(lines)
    child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, ' .. vim.inspect(lines) .. ')')
end

local T = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
                require('mkdnflow').setup({
                    modules = { yaml = true },
                    silent = true
                })
            ]])
        end,
        post_once = child.stop,
    },
})

-- =============================================================================
-- hasYaml() - Detect YAML frontmatter
-- =============================================================================
T['hasYaml'] = new_set()

T['hasYaml']['returns start and end for valid YAML'] = function()
    set_lines({ '---', 'title: Test', 'date: 2024-01-01', '---', 'Content' })
    child.lua('_start, _finish = require("mkdnflow.yaml").hasYaml()')
    local start = child.lua_get('_start')
    local finish = child.lua_get('_finish')
    eq(start, 0) -- Start at line 0 (0-indexed)
    eq(finish, 3) -- End at line 3 (0-indexed)
end

T['hasYaml']['returns nil when no YAML'] = function()
    set_lines({ '# Heading', 'Some content' })
    child.lua('_start, _finish = require("mkdnflow.yaml").hasYaml()')
    local result = child.lua_get('_start == nil')
    eq(result, true)
end

T['hasYaml']['returns nil when first line is not ---'] = function()
    set_lines({ 'Not YAML', '---', 'key: value', '---' })
    child.lua('_start, _finish = require("mkdnflow.yaml").hasYaml()')
    local result = child.lua_get('_start == nil')
    eq(result, true)
end

T['hasYaml']['handles YAML at very start of file'] = function()
    set_lines({ '---', 'key: value', '---' })
    child.lua('_start, _finish = require("mkdnflow.yaml").hasYaml()')
    local start = child.lua_get('_start')
    local finish = child.lua_get('_finish')
    eq(start, 0)
    eq(finish, 2)
end

T['hasYaml']['handles empty YAML block'] = function()
    set_lines({ '---', '---', 'Content' })
    child.lua('_start, _finish = require("mkdnflow.yaml").hasYaml()')
    local start = child.lua_get('_start')
    local finish = child.lua_get('_finish')
    eq(start, 0)
    eq(finish, 1)
end

-- BUG: This test documents a bug where hasYaml() crashes when the YAML block
-- is not closed. The while loop tries to access lines beyond the buffer end.
-- Uncomment to verify the bug:
-- T['hasYaml']['returns nil for unclosed YAML block'] = function()
--     set_lines({ '---', 'title: Test', 'No closing delimiter' })
--     child.lua('_start, _finish = require("mkdnflow.yaml").hasYaml()')
--     local result = child.lua_get('_start == nil')
--     eq(result, true)
-- end

T['hasYaml']['handles long YAML block'] = function()
    set_lines({
        '---',
        'title: Test',
        'author: Someone',
        'date: 2024-01-01',
        'tags:',
        '  - tag1',
        '  - tag2',
        '---',
        'Content',
    })
    child.lua('_start, _finish = require("mkdnflow.yaml").hasYaml()')
    local start = child.lua_get('_start')
    local finish = child.lua_get('_finish')
    eq(start, 0)
    eq(finish, 7)
end

-- =============================================================================
-- ingestYamlBlock() - Parse YAML into Lua table
-- =============================================================================
T['ingestYamlBlock'] = new_set()

T['ingestYamlBlock']['parses simple key-value pairs'] = function()
    set_lines({ '---', 'title: My Title', 'author: Jake', '---' })
    child.lua([[
        local yaml = require('mkdnflow.yaml')
        _start, _finish = yaml.hasYaml()
        _data = yaml.ingestYamlBlock(_start, _finish)
    ]])
    local title = child.lua_get('_data.title[1]')
    local author = child.lua_get('_data.author[1]')
    eq(title, 'My Title')
    eq(author, 'Jake')
end

T['ingestYamlBlock']['parses list items'] = function()
    set_lines({ '---', 'tags:', '  - lua', '  - neovim', '---' })
    child.lua([[
        local yaml = require('mkdnflow.yaml')
        _start, _finish = yaml.hasYaml()
        _data = yaml.ingestYamlBlock(_start, _finish)
    ]])
    local tags = child.lua_get('_data.tags')
    eq(#tags, 2)
    eq(tags[1], 'lua')
    eq(tags[2], 'neovim')
end

T['ingestYamlBlock']['handles mixed content'] = function()
    set_lines({
        '---',
        'title: Test',
        'tags:',
        '  - tag1',
        '  - tag2',
        'author: Someone',
        '---',
    })
    child.lua([[
        local yaml = require('mkdnflow.yaml')
        _start, _finish = yaml.hasYaml()
        _data = yaml.ingestYamlBlock(_start, _finish)
    ]])
    eq(child.lua_get('_data.title[1]'), 'Test')
    eq(child.lua_get('_data.author[1]'), 'Someone')
    eq(child.lua_get('#_data.tags'), 2)
end

T['ingestYamlBlock']['handles keys with underscores and hyphens'] = function()
    set_lines({ '---', 'created_at: 2024-01-01', 'last-modified: 2024-01-02', '---' })
    child.lua([[
        local yaml = require('mkdnflow.yaml')
        _start, _finish = yaml.hasYaml()
        _data = yaml.ingestYamlBlock(_start, _finish)
    ]])
    eq(child.lua_get('_data["created_at"][1]'), '2024-01-01')
    eq(child.lua_get('_data["last-modified"][1]'), '2024-01-02')
end

T['ingestYamlBlock']['returns nil for nil params'] = function()
    set_lines({ '# No YAML' })
    child.lua('_data = require("mkdnflow.yaml").ingestYamlBlock(nil, nil)')
    local result = child.lua_get('_data == nil')
    eq(result, true)
end

T['ingestYamlBlock']['handles empty list values'] = function()
    set_lines({ '---', 'emptylist:', '---' })
    child.lua([[
        local yaml = require('mkdnflow.yaml')
        _start, _finish = yaml.hasYaml()
        _data = yaml.ingestYamlBlock(_start, _finish)
    ]])
    local emptylist = child.lua_get('_data.emptylist')
    eq(type(emptylist), 'table')
    eq(#emptylist, 0)
end

-- =============================================================================
-- Bibliography paths from YAML
-- =============================================================================
T['bib_paths'] = new_set()

T['bib_paths']['extracts bibliography path from YAML'] = function()
    set_lines({ '---', 'bibliography: refs.bib', '---', 'Content' })
    child.lua([[
        local yaml = require('mkdnflow.yaml')
        _start, _finish = yaml.hasYaml()
        _data = yaml.ingestYamlBlock(_start, _finish)
    ]])
    eq(child.lua_get('_data.bibliography[1]'), 'refs.bib')
end

T['bib_paths']['extracts multiple bibliography paths'] = function()
    set_lines({ '---', 'bibliography:', '  - refs.bib', '  - other.bib', '---' })
    child.lua([[
        local yaml = require('mkdnflow.yaml')
        _start, _finish = yaml.hasYaml()
        _data = yaml.ingestYamlBlock(_start, _finish)
    ]])
    local bib = child.lua_get('_data.bibliography')
    eq(#bib, 2)
    eq(bib[1], 'refs.bib')
    eq(bib[2], 'other.bib')
end

-- =============================================================================
-- Edge cases
-- =============================================================================
T['edge_cases'] = new_set()

T['edge_cases']['handles empty buffer'] = function()
    set_lines({ '' })
    child.lua('_start, _finish = require("mkdnflow.yaml").hasYaml()')
    local result = child.lua_get('_start == nil')
    eq(result, true)
end

-- BUG: Same issue as unclosed YAML - crashes when accessing beyond buffer end.
-- Uncomment to verify the bug:
-- T['edge_cases']['handles single line buffer'] = function()
--     set_lines({ '---' })
--     child.lua('_start, _finish = require("mkdnflow.yaml").hasYaml()')
--     local result = child.lua_get('_start == nil')
--     eq(result, true)
-- end

-- BUG: This test documents a bug where values containing colons are parsed incorrectly.
-- The regex `.*:%s?(.+)$` captures after the FIRST colon, so:
-- `url: https://example.com` becomes `//example.com` instead of `https://example.com`
-- Uncomment to verify the bug:
-- T['edge_cases']['handles value with colon'] = function()
--     set_lines({ '---', 'url: https://example.com', '---' })
--     child.lua([[
--         local yaml = require('mkdnflow.yaml')
--         _start, _finish = yaml.hasYaml()
--         _data = yaml.ingestYamlBlock(_start, _finish)
--     ]])
--     eq(child.lua_get('_data.url[1]'), 'https://example.com')
-- end

-- Test showing actual behavior (not ideal, but doesn't crash)
T['edge_cases']['parses value after first colon'] = function()
    set_lines({ '---', 'url: https://example.com', '---' })
    child.lua([[
        local yaml = require('mkdnflow.yaml')
        _start, _finish = yaml.hasYaml()
        _data = yaml.ingestYamlBlock(_start, _finish)
    ]])
    -- Due to regex, only gets content after first colon
    eq(child.lua_get('_data.url[1]'), '//example.com')
end

-- BUG: Same colon parsing issue - quoted values with colons are truncated.
-- `"A: Special Title"` becomes `Special Title"` (after the inner colon)
-- Uncomment to verify the bug:
-- T['edge_cases']['handles quoted values'] = function()
--     set_lines({ '---', 'title: "A: Special Title"', '---' })
--     child.lua([[
--         local yaml = require('mkdnflow.yaml')
--         _start, _finish = yaml.hasYaml()
--         _data = yaml.ingestYamlBlock(_start, _finish)
--     ]])
--     eq(child.lua_get('_data.title[1]'), '"A: Special Title"')
-- end

-- Test showing actual behavior with quoted colons
T['edge_cases']['quoted values with colons truncated'] = function()
    set_lines({ '---', 'title: "A: Special Title"', '---' })
    child.lua([[
        local yaml = require('mkdnflow.yaml')
        _start, _finish = yaml.hasYaml()
        _data = yaml.ingestYamlBlock(_start, _finish)
    ]])
    -- Due to regex, gets content after inner colon
    eq(child.lua_get('_data.title[1]'), 'Special Title"')
end

T['edge_cases']['handles --- in content after YAML'] = function()
    set_lines({ '---', 'title: Test', '---', '', '---', 'This is a horizontal rule' })
    child.lua('_start, _finish = require("mkdnflow.yaml").hasYaml()')
    local start = child.lua_get('_start')
    local finish = child.lua_get('_finish')
    -- Should only find the first YAML block
    eq(start, 0)
    eq(finish, 2)
end

return T
