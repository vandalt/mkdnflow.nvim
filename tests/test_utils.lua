-- tests/test_utils.lua
-- Tests for pure utility functions in mkdnflow.utils

local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

-- Load the utils module
local utils = require('mkdnflow.utils')

local T = new_set()

-- =============================================================================
-- vim.pesc tests (pattern escaping, previously via utils.luaEscape wrapper)
-- =============================================================================
T['vim.pesc'] = new_set()

T['vim.pesc']['escapes dash'] = function()
    eq(vim.pesc('foo-bar'), 'foo%-bar')
end

T['vim.pesc']['escapes dot'] = function()
    eq(vim.pesc('file.md'), 'file%.md')
end

T['vim.pesc']['escapes plus'] = function()
    eq(vim.pesc('c++'), 'c%+%+')
end

T['vim.pesc']['escapes question mark'] = function()
    eq(vim.pesc('what?'), 'what%?')
end

T['vim.pesc']['escapes percent'] = function()
    eq(vim.pesc('100%'), '100%%')
end

T['vim.pesc']['handles multiple special chars'] = function()
    eq(vim.pesc('file-name.md?v=1'), 'file%-name%.md%?v=1')
end

T['vim.pesc']['passes through plain text'] = function()
    eq(vim.pesc('hello world'), 'hello world')
end

T['vim.pesc']['escapes parentheses'] = function()
    eq(vim.pesc('foo(bar)'), 'foo%(bar%)')
end

T['vim.pesc']['escapes square brackets'] = function()
    eq(vim.pesc('foo[bar]'), 'foo%[bar%]')
end

T['vim.pesc']['escapes caret'] = function()
    eq(vim.pesc('^start'), '%^start')
end

T['vim.pesc']['escapes dollar sign'] = function()
    eq(vim.pesc('end$'), 'end%$')
end

T['vim.pesc']['escapes asterisk'] = function()
    eq(vim.pesc('foo*bar'), 'foo%*bar')
end

-- =============================================================================
-- mergeTables tests
-- =============================================================================
T['mergeTables'] = new_set()

T['mergeTables']['merges flat tables'] = function()
    local defaults = { a = 1, b = 2 }
    local user = { b = 3, c = 4 }
    local result = utils.mergeTables(defaults, user)
    eq(result.a, 1)
    eq(result.b, 3)
    eq(result.c, 4)
end

T['mergeTables']['merges nested tables'] = function()
    local defaults = { outer = { inner = 1, keep = true } }
    local user = { outer = { inner = 2 } }
    local result = utils.mergeTables(defaults, user)
    eq(result.outer.inner, 2)
    eq(result.outer.keep, true)
end

T['mergeTables']['user value overrides default'] = function()
    local defaults = { enabled = true }
    local user = { enabled = false }
    local result = utils.mergeTables(defaults, user)
    eq(result.enabled, false)
end

T['mergeTables']['handles empty user config'] = function()
    local defaults = { a = 1, b = 2 }
    local user = {}
    local result = utils.mergeTables(defaults, user)
    eq(result.a, 1)
    eq(result.b, 2)
end

T['mergeTables']['replaces array-like tables entirely'] = function()
    local defaults = { items = { 'a', 'b', 'c' } }
    local user = { items = { 'x', 'y' } }
    local result = utils.mergeTables(defaults, user)
    eq(#result.items, 2)
    eq(result.items[1], 'x')
    eq(result.items[2], 'y')
end

T['mergeTables']['replaces array of tables entirely'] = function()
    -- General array replacement: arrays are always replaced wholesale
    local defaults = {
        statuses = {
            { name = 'a', value = 1 },
            { name = 'b', value = 2 },
            { name = 'c', value = 3 },
        },
    }
    local user = {
        statuses = {
            { name = 'x', value = 10 },
            { name = 'y', value = 20 },
        },
    }
    local result = utils.mergeTables(defaults, user)
    eq(#result.statuses, 2)
    eq(result.statuses[1].name, 'x')
    eq(result.statuses[2].name, 'y')
end

T['mergeTables']['preserves default array when user provides empty table'] = function()
    local defaults = { items = { 'a', 'b', 'c' } }
    local user = { items = {} }
    local result = utils.mergeTables(defaults, user)
    -- Empty table is not array-like, so defaults remain
    eq(#result.items, 3)
end

T['mergeTables']['merges dict-like tables recursively'] = function()
    local defaults = { config = { a = 1, b = 2 } }
    local user = { config = { b = 3 } }
    local result = utils.mergeTables(defaults, user)
    eq(result.config.a, 1) -- preserved from default
    eq(result.config.b, 3) -- overridden by user
end

T['mergeTables']['deep merges dict-like tables with partial override'] = function()
    -- This is the new to_do.statuses use case (dict keyed by status name)
    local defaults = {
        statuses = {
            not_started = { marker = ' ', sort = { section = 2 } },
            in_progress = { marker = '-', sort = { section = 1 } },
            complete = { marker = 'X', sort = { section = 3 } },
        },
    }
    local user = {
        statuses = {
            not_started = { sort = { section = 1 } },
        },
    }
    local result = utils.mergeTables(defaults, user)
    -- User override merges into not_started
    eq(result.statuses.not_started.marker, ' ') -- preserved from default
    eq(result.statuses.not_started.sort.section, 1) -- overridden by user
    -- Other statuses preserved from defaults
    eq(result.statuses.in_progress.marker, '-')
    eq(result.statuses.complete.marker, 'X')
end

T['mergeTables']['handles mixed array and dict siblings'] = function()
    local defaults = {
        items = { 'a', 'b', 'c' },
        settings = { enabled = true, count = 5 },
    }
    local user = {
        items = { 'x' },
        settings = { count = 10 },
    }
    local result = utils.mergeTables(defaults, user)
    -- Array replaced
    eq(#result.items, 1)
    eq(result.items[1], 'x')
    -- Dict merged
    eq(result.settings.enabled, true)
    eq(result.settings.count, 10)
end

-- =============================================================================
-- spairs tests (sorted pairs iterator)
-- =============================================================================
T['spairs'] = new_set()

T['spairs']['iterates in sorted order'] = function()
    local tbl = { c = 3, a = 1, b = 2 }
    local keys = {}
    for k, _ in utils.spairs(tbl) do
        table.insert(keys, k)
    end
    eq(keys[1], 'a')
    eq(keys[2], 'b')
    eq(keys[3], 'c')
end

T['spairs']['handles empty table'] = function()
    local count = 0
    for _, _ in utils.spairs({}) do
        count = count + 1
    end
    eq(count, 0)
end

return T
