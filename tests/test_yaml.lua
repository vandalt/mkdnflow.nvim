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

T['hasYaml']['returns nil for unclosed YAML block'] = function()
    set_lines({ '---', 'title: Test', 'No closing delimiter' })
    child.lua('_start, _finish = require("mkdnflow.yaml").hasYaml()')
    local result = child.lua_get('_start == nil')
    eq(result, true)
end

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

T['hasYaml']['handles single line buffer with just ---'] = function()
    set_lines({ '---' })
    child.lua('_start, _finish = require("mkdnflow.yaml").hasYaml()')
    local result = child.lua_get('_start == nil')
    eq(result, true)
end

T['hasYaml']['handles YAML with empty lines inside'] = function()
    set_lines({ '---', 'title: Test', '', 'author: Someone', '---' })
    child.lua('_start, _finish = require("mkdnflow.yaml").hasYaml()')
    local start = child.lua_get('_start')
    local finish = child.lua_get('_finish')
    eq(start, 0)
    eq(finish, 4)
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

T['ingestYamlBlock']['handles URL with colons'] = function()
    set_lines({ '---', 'url: https://example.com', '---' })
    child.lua([[
        local yaml = require('mkdnflow.yaml')
        _start, _finish = yaml.hasYaml()
        _data = yaml.ingestYamlBlock(_start, _finish)
    ]])
    eq(child.lua_get('_data.url[1]'), 'https://example.com')
end

T['ingestYamlBlock']['handles quoted values with colons'] = function()
    set_lines({ '---', 'title: "A: Special Title"', '---' })
    child.lua([[
        local yaml = require('mkdnflow.yaml')
        _start, _finish = yaml.hasYaml()
        _data = yaml.ingestYamlBlock(_start, _finish)
    ]])
    eq(child.lua_get('_data.title[1]'), '"A: Special Title"')
end

T['ingestYamlBlock']['handles time values with multiple colons'] = function()
    set_lines({ '---', 'time: 10:30:45', '---' })
    child.lua([[
        local yaml = require('mkdnflow.yaml')
        _start, _finish = yaml.hasYaml()
        _data = yaml.ingestYamlBlock(_start, _finish)
    ]])
    eq(child.lua_get('_data.time[1]'), '10:30:45')
end

T['ingestYamlBlock']['handles value with leading spaces'] = function()
    set_lines({ '---', 'title:   Spaced Title', '---' })
    child.lua([[
        local yaml = require('mkdnflow.yaml')
        _start, _finish = yaml.hasYaml()
        _data = yaml.ingestYamlBlock(_start, _finish)
    ]])
    -- Should trim the leading space after colon
    local title = child.lua_get('_data.title[1]')
    eq(title:match('^%s'), nil) -- No leading whitespace
end

T['ingestYamlBlock']['handles empty value'] = function()
    set_lines({ '---', 'empty:', '---' })
    child.lua([[
        local yaml = require('mkdnflow.yaml')
        _start, _finish = yaml.hasYaml()
        _data = yaml.ingestYamlBlock(_start, _finish)
    ]])
    local empty = child.lua_get('_data.empty')
    eq(type(empty), 'table')
    eq(#empty, 0)
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
-- bibliography/bib normalization in yaml init
-- =============================================================================
T['bib_paths']['bibliography key populates bib_paths.yaml'] = function()
    child.restart({ '-u', 'scripts/minimal_init.lua' })
    child.lua([[
        vim.cmd('runtime plugin/mkdnflow.lua')
        vim.api.nvim_buf_set_name(0, 'test_bib_norm.md')
        vim.bo.filetype = 'markdown'
        require('mkdnflow').setup({
            modules = { yaml = true, bib = true },
            silent = true,
        })
    ]])
    set_lines({ '---', 'bibliography: refs.bib', '---', 'Content' })
    child.lua('vim.cmd("doautocmd FileType")')
    local paths = child.lua_get('require("mkdnflow").bib.bib_paths.yaml')
    eq(#paths, 1)
    eq(paths[1], 'refs.bib')
end

T['bib_paths']['bib key populates bib_paths.yaml'] = function()
    child.restart({ '-u', 'scripts/minimal_init.lua' })
    child.lua([[
        vim.cmd('runtime plugin/mkdnflow.lua')
        vim.api.nvim_buf_set_name(0, 'test_bib_key.md')
        vim.bo.filetype = 'markdown'
        require('mkdnflow').setup({
            modules = { yaml = true, bib = true },
            silent = true,
        })
    ]])
    set_lines({ '---', 'bib: refs.bib', '---', 'Content' })
    child.lua('vim.cmd("doautocmd FileType")')
    local paths = child.lua_get('require("mkdnflow").bib.bib_paths.yaml')
    eq(#paths, 1)
    eq(paths[1], 'refs.bib')
end

T['bib_paths']['both bib and bibliography keys are merged'] = function()
    child.restart({ '-u', 'scripts/minimal_init.lua' })
    child.lua([[
        vim.cmd('runtime plugin/mkdnflow.lua')
        vim.api.nvim_buf_set_name(0, 'test_bib_merge.md')
        vim.bo.filetype = 'markdown'
        require('mkdnflow').setup({
            modules = { yaml = true, bib = true },
            silent = true,
        })
    ]])
    set_lines({ '---', 'bib: first.bib', 'bibliography: second.bib', '---', 'Content' })
    child.lua('vim.cmd("doautocmd FileType")')
    local paths = child.lua_get('require("mkdnflow").bib.bib_paths.yaml')
    eq(#paths, 2)
    eq(paths[1], 'first.bib')
    eq(paths[2], 'second.bib')
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

T['edge_cases']['handles --- in content after YAML'] = function()
    set_lines({ '---', 'title: Test', '---', '', '---', 'This is a horizontal rule' })
    child.lua('_start, _finish = require("mkdnflow.yaml").hasYaml()')
    local start = child.lua_get('_start')
    local finish = child.lua_get('_finish')
    -- Should only find the first YAML block
    eq(start, 0)
    eq(finish, 2)
end

T['edge_cases']['handles numeric values'] = function()
    set_lines({ '---', 'count: 42', 'price: 19.99', '---' })
    child.lua([[
        local yaml = require('mkdnflow.yaml')
        _start, _finish = yaml.hasYaml()
        _data = yaml.ingestYamlBlock(_start, _finish)
    ]])
    eq(child.lua_get('_data.count[1]'), '42')
    eq(child.lua_get('_data.price[1]'), '19.99')
end

T['edge_cases']['handles boolean-like values'] = function()
    set_lines({ '---', 'draft: true', 'published: false', '---' })
    child.lua([[
        local yaml = require('mkdnflow.yaml')
        _start, _finish = yaml.hasYaml()
        _data = yaml.ingestYamlBlock(_start, _finish)
    ]])
    eq(child.lua_get('_data.draft[1]'), 'true')
    eq(child.lua_get('_data.published[1]'), 'false')
end

T['edge_cases']['handles file path values'] = function()
    set_lines({ '---', 'image: /path/to/image.png', 'file: ./relative/path.md', '---' })
    child.lua([[
        local yaml = require('mkdnflow.yaml')
        _start, _finish = yaml.hasYaml()
        _data = yaml.ingestYamlBlock(_start, _finish)
    ]])
    eq(child.lua_get('_data.image[1]'), '/path/to/image.png')
    eq(child.lua_get('_data.file[1]'), './relative/path.md')
end

T['edge_cases']['handles list items with colons'] = function()
    set_lines({ '---', 'links:', '  - https://example.com', '  - http://test.org', '---' })
    child.lua([[
        local yaml = require('mkdnflow.yaml')
        _start, _finish = yaml.hasYaml()
        _data = yaml.ingestYamlBlock(_start, _finish)
    ]])
    local links = child.lua_get('_data.links')
    eq(#links, 2)
    eq(links[1], 'https://example.com')
    eq(links[2], 'http://test.org')
end

-- =============================================================================
-- YAMLFrontmatter Class - Construction & Factory
-- =============================================================================
T['YAMLFrontmatter'] = new_set()
T['YAMLFrontmatter']['construction'] = new_set()

T['YAMLFrontmatter']['construction'][':new() creates empty instance with valid=false'] = function()
    child.lua('_fm = require("mkdnflow.yaml").YAMLFrontmatter:new()')
    eq(child.lua_get('_fm.valid'), false)
    eq(child.lua_get('_fm.bufnr'), -1)
    eq(child.lua_get('_fm.line_range.start'), -1)
    eq(child.lua_get('_fm.line_range.finish'), -1)
    eq(child.lua_get('vim.tbl_isempty(_fm.data)'), true)
end

T['YAMLFrontmatter']['construction'][':new(opts) accepts initial data'] = function()
    child.lua([[
        _fm = require("mkdnflow.yaml").YAMLFrontmatter:new({
            data = { title = { 'Test' } },
            valid = true,
            bufnr = 5,
            line_range = { start = 0, finish = 2 }
        })
    ]])
    eq(child.lua_get('_fm.valid'), true)
    eq(child.lua_get('_fm.bufnr'), 5)
    eq(child.lua_get('_fm.data.title[1]'), 'Test')
    eq(child.lua_get('_fm.line_range.start'), 0)
    eq(child.lua_get('_fm.line_range.finish'), 2)
end

T['YAMLFrontmatter']['construction'][':read() from buffer with valid YAML'] = function()
    set_lines({ '---', 'title: Hello', 'author: World', '---', 'Content' })
    child.lua('_fm = require("mkdnflow.yaml").YAMLFrontmatter:read()')
    eq(child.lua_get('_fm.valid'), true)
    eq(child.lua_get('_fm.line_range.start'), 0)
    eq(child.lua_get('_fm.line_range.finish'), 3)
    eq(child.lua_get('_fm.data.title[1]'), 'Hello')
    eq(child.lua_get('_fm.data.author[1]'), 'World')
end

T['YAMLFrontmatter']['construction'][':read() from buffer without YAML returns valid=false'] = function()
    set_lines({ '# Heading', 'Some content' })
    child.lua('_fm = require("mkdnflow.yaml").YAMLFrontmatter:read()')
    eq(child.lua_get('_fm.valid'), false)
    eq(child.lua_get('_fm.line_range.start'), -1)
end

T['YAMLFrontmatter']['construction'][':read(0) explicitly reads current buffer'] = function()
    set_lines({ '---', 'key: value', '---' })
    child.lua('_fm = require("mkdnflow.yaml").YAMLFrontmatter:read(0)')
    eq(child.lua_get('_fm.valid'), true)
    eq(child.lua_get('_fm.bufnr'), 0)
end

-- =============================================================================
-- YAMLFrontmatter Class - :get() method
-- =============================================================================
T['YAMLFrontmatter']['get'] = new_set()

T['YAMLFrontmatter']['get'][':get(key) returns first value for existing key'] = function()
    set_lines({ '---', 'title: My Title', '---' })
    child.lua('_fm = require("mkdnflow.yaml").YAMLFrontmatter:read()')
    eq(child.lua_get('_fm:get("title")'), 'My Title')
end

T['YAMLFrontmatter']['get'][':get(key) returns nil for non-existent key'] = function()
    set_lines({ '---', 'title: Test', '---' })
    child.lua('_fm = require("mkdnflow.yaml").YAMLFrontmatter:read()')
    eq(child.lua_get('_fm:get("missing") == nil'), true)
end

T['YAMLFrontmatter']['get'][':get(key) returns first item for list keys'] = function()
    set_lines({ '---', 'tags:', '  - first', '  - second', '---' })
    child.lua('_fm = require("mkdnflow.yaml").YAMLFrontmatter:read()')
    eq(child.lua_get('_fm:get("tags")'), 'first')
end

T['YAMLFrontmatter']['get'][':get(key) returns nil for key with empty value'] = function()
    set_lines({ '---', 'empty:', '---' })
    child.lua('_fm = require("mkdnflow.yaml").YAMLFrontmatter:read()')
    eq(child.lua_get('_fm:get("empty") == nil'), true)
end

-- =============================================================================
-- YAMLFrontmatter Class - :get_all() method
-- =============================================================================
T['YAMLFrontmatter']['get_all'] = new_set()

T['YAMLFrontmatter']['get_all'][':get_all(key) returns all values as array'] = function()
    set_lines({ '---', 'tags:', '  - lua', '  - neovim', '  - markdown', '---' })
    child.lua('_fm = require("mkdnflow.yaml").YAMLFrontmatter:read()')
    local tags = child.lua_get('_fm:get_all("tags")')
    eq(#tags, 3)
    eq(tags[1], 'lua')
    eq(tags[2], 'neovim')
    eq(tags[3], 'markdown')
end

T['YAMLFrontmatter']['get_all'][':get_all(key) returns empty array for non-existent key'] = function()
    set_lines({ '---', 'title: Test', '---' })
    child.lua('_fm = require("mkdnflow.yaml").YAMLFrontmatter:read()')
    local result = child.lua_get('_fm:get_all("missing")')
    eq(type(result), 'table')
    eq(#result, 0)
end

T['YAMLFrontmatter']['get_all'][':get_all(key) returns single-element array for scalar values'] = function()
    set_lines({ '---', 'title: Single Value', '---' })
    child.lua('_fm = require("mkdnflow.yaml").YAMLFrontmatter:read()')
    local result = child.lua_get('_fm:get_all("title")')
    eq(#result, 1)
    eq(result[1], 'Single Value')
end

T['YAMLFrontmatter']['get_all'][':get_all(key) returns empty array for key with empty value'] = function()
    set_lines({ '---', 'empty:', '---' })
    child.lua('_fm = require("mkdnflow.yaml").YAMLFrontmatter:read()')
    local result = child.lua_get('_fm:get_all("empty")')
    eq(type(result), 'table')
    eq(#result, 0)
end

-- =============================================================================
-- YAMLFrontmatter Class - :has() method
-- =============================================================================
T['YAMLFrontmatter']['has'] = new_set()

T['YAMLFrontmatter']['has'][':has(key) returns true for existing key'] = function()
    set_lines({ '---', 'title: Test', '---' })
    child.lua('_fm = require("mkdnflow.yaml").YAMLFrontmatter:read()')
    eq(child.lua_get('_fm:has("title")'), true)
end

T['YAMLFrontmatter']['has'][':has(key) returns false for non-existent key'] = function()
    set_lines({ '---', 'title: Test', '---' })
    child.lua('_fm = require("mkdnflow.yaml").YAMLFrontmatter:read()')
    eq(child.lua_get('_fm:has("missing")'), false)
end

T['YAMLFrontmatter']['has'][':has(key) returns true for key with empty value'] = function()
    set_lines({ '---', 'empty:', '---' })
    child.lua('_fm = require("mkdnflow.yaml").YAMLFrontmatter:read()')
    eq(child.lua_get('_fm:has("empty")'), true)
end

-- =============================================================================
-- YAMLFrontmatter Class - :is_valid() method
-- =============================================================================
T['YAMLFrontmatter']['is_valid'] = new_set()

T['YAMLFrontmatter']['is_valid'][':is_valid() returns true after successful read'] = function()
    set_lines({ '---', 'title: Test', '---' })
    child.lua('_fm = require("mkdnflow.yaml").YAMLFrontmatter:read()')
    eq(child.lua_get('_fm:is_valid()'), true)
end

T['YAMLFrontmatter']['is_valid'][':is_valid() returns false for new empty instance'] = function()
    child.lua('_fm = require("mkdnflow.yaml").YAMLFrontmatter:new()')
    eq(child.lua_get('_fm:is_valid()'), false)
end

T['YAMLFrontmatter']['is_valid'][':is_valid() returns false after read from buffer without YAML'] = function()
    set_lines({ '# Heading', 'Content' })
    child.lua('_fm = require("mkdnflow.yaml").YAMLFrontmatter:read()')
    eq(child.lua_get('_fm:is_valid()'), false)
end

-- =============================================================================
-- YAMLFrontmatter Class - :get_line_range() method
-- =============================================================================
T['YAMLFrontmatter']['get_line_range'] = new_set()

T['YAMLFrontmatter']['get_line_range'][':get_line_range() returns {start, finish} for valid frontmatter'] = function()
    set_lines({ '---', 'title: Test', 'author: Someone', '---', 'Content' })
    child.lua('_fm = require("mkdnflow.yaml").YAMLFrontmatter:read()')
    local range = child.lua_get('_fm:get_line_range()')
    eq(range.start, 0)
    eq(range.finish, 3)
end

T['YAMLFrontmatter']['get_line_range'][':get_line_range() returns {-1, -1} for invalid'] = function()
    set_lines({ '# No YAML' })
    child.lua('_fm = require("mkdnflow.yaml").YAMLFrontmatter:read()')
    local range = child.lua_get('_fm:get_line_range()')
    eq(range.start, -1)
    eq(range.finish, -1)
end

-- =============================================================================
-- YAMLFrontmatter Class - :keys() method
-- =============================================================================
T['YAMLFrontmatter']['keys'] = new_set()

T['YAMLFrontmatter']['keys'][':keys() returns array of all keys'] = function()
    set_lines({ '---', 'title: Test', 'author: Jake', 'date: 2024-01-01', '---' })
    child.lua('_fm = require("mkdnflow.yaml").YAMLFrontmatter:read()')
    local keys = child.lua_get('_fm:keys()')
    eq(#keys, 3)
    -- Keys are sorted alphabetically
    eq(keys[1], 'author')
    eq(keys[2], 'date')
    eq(keys[3], 'title')
end

T['YAMLFrontmatter']['keys'][':keys() returns empty array for invalid frontmatter'] = function()
    set_lines({ '# No YAML' })
    child.lua('_fm = require("mkdnflow.yaml").YAMLFrontmatter:read()')
    local keys = child.lua_get('_fm:keys()')
    eq(#keys, 0)
end

T['YAMLFrontmatter']['keys'][':keys() returns empty array for empty YAML block'] = function()
    set_lines({ '---', '---' })
    child.lua('_fm = require("mkdnflow.yaml").YAMLFrontmatter:read()')
    local keys = child.lua_get('_fm:keys()')
    eq(#keys, 0)
end

-- =============================================================================
-- YAMLFrontmatter Class - :to_table() method
-- =============================================================================
T['YAMLFrontmatter']['to_table'] = new_set()

T['YAMLFrontmatter']['to_table'][':to_table() returns raw data table'] = function()
    set_lines({ '---', 'title: Test', 'tags:', '  - one', '  - two', '---' })
    child.lua('_fm = require("mkdnflow.yaml").YAMLFrontmatter:read()')
    child.lua('_data = _fm:to_table()')
    eq(child.lua_get('_data.title[1]'), 'Test')
    eq(child.lua_get('#_data.tags'), 2)
end

T['YAMLFrontmatter']['to_table'][':to_table() returns empty table for invalid frontmatter'] = function()
    set_lines({ '# No YAML' })
    child.lua('_fm = require("mkdnflow.yaml").YAMLFrontmatter:read()')
    child.lua('_data = _fm:to_table()')
    eq(child.lua_get('vim.tbl_isempty(_data)'), true)
end

-- =============================================================================
-- YAMLFrontmatter Class - Edge Cases
-- =============================================================================
T['YAMLFrontmatter']['edge_cases'] = new_set()

T['YAMLFrontmatter']['edge_cases']['handles URL values with colons'] = function()
    set_lines({ '---', 'url: https://example.com/path?query=1', '---' })
    child.lua('_fm = require("mkdnflow.yaml").YAMLFrontmatter:read()')
    eq(child.lua_get('_fm:get("url")'), 'https://example.com/path?query=1')
end

T['YAMLFrontmatter']['edge_cases']['handles time values (HH:MM:SS)'] = function()
    set_lines({ '---', 'time: 14:30:45', '---' })
    child.lua('_fm = require("mkdnflow.yaml").YAMLFrontmatter:read()')
    eq(child.lua_get('_fm:get("time")'), '14:30:45')
end

T['YAMLFrontmatter']['edge_cases']['handles keys with underscores and hyphens'] = function()
    set_lines({ '---', 'created_at: 2024-01-01', 'last-modified: 2024-01-02', '---' })
    child.lua('_fm = require("mkdnflow.yaml").YAMLFrontmatter:read()')
    eq(child.lua_get('_fm:get("created_at")'), '2024-01-01')
    eq(child.lua_get('_fm:get("last-modified")'), '2024-01-02')
end

T['YAMLFrontmatter']['edge_cases']['handles quoted values'] = function()
    set_lines({ '---', 'title: "A: Special Title"', '---' })
    child.lua('_fm = require("mkdnflow.yaml").YAMLFrontmatter:read()')
    eq(child.lua_get('_fm:get("title")'), '"A: Special Title"')
end

T['YAMLFrontmatter']['edge_cases']['handles mixed scalar and list content'] = function()
    set_lines({
        '---',
        'title: My Document',
        'tags:',
        '  - lua',
        '  - neovim',
        'author: Jake',
        'categories:',
        '  - programming',
        '---',
    })
    child.lua('_fm = require("mkdnflow.yaml").YAMLFrontmatter:read()')
    eq(child.lua_get('_fm:get("title")'), 'My Document')
    eq(child.lua_get('_fm:get("author")'), 'Jake')
    eq(child.lua_get('#_fm:get_all("tags")'), 2)
    eq(child.lua_get('#_fm:get_all("categories")'), 1)
end

T['YAMLFrontmatter']['edge_cases']['handles empty YAML block'] = function()
    set_lines({ '---', '---', 'Content' })
    child.lua('_fm = require("mkdnflow.yaml").YAMLFrontmatter:read()')
    eq(child.lua_get('_fm:is_valid()'), true)
    eq(child.lua_get('#_fm:keys()'), 0)
end

T['YAMLFrontmatter']['edge_cases']['class has __className property'] = function()
    child.lua('_fm = require("mkdnflow.yaml").YAMLFrontmatter:new()')
    eq(child.lua_get('getmetatable(_fm).__className'), 'YAMLFrontmatter')
end

-- =============================================================================
-- Backward Compatibility
-- =============================================================================
T['backward_compat'] = new_set()

T['backward_compat']['hasYaml() function still works'] = function()
    set_lines({ '---', 'title: Test', '---', 'Content' })
    child.lua('_start, _finish = require("mkdnflow.yaml").hasYaml()')
    eq(child.lua_get('_start'), 0)
    eq(child.lua_get('_finish'), 2)
end

T['backward_compat']['ingestYamlBlock() function still works'] = function()
    set_lines({ '---', 'title: Test', 'author: Jake', '---' })
    child.lua([[
        local yaml = require('mkdnflow.yaml')
        _start, _finish = yaml.hasYaml()
        _data = yaml.ingestYamlBlock(_start, _finish)
    ]])
    eq(child.lua_get('_data.title[1]'), 'Test')
    eq(child.lua_get('_data.author[1]'), 'Jake')
end

T['backward_compat']['YAMLFrontmatter class is exported'] = function()
    child.lua('_class = require("mkdnflow.yaml").YAMLFrontmatter')
    eq(child.lua_get('_class ~= nil'), true)
    eq(child.lua_get('type(_class.new) == "function"'), true)
    eq(child.lua_get('type(_class.read) == "function"'), true)
end

return T
