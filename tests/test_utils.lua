-- tests/test_utils.lua
-- Tests for pure utility functions in mkdnflow.utils

local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

-- Load the utils module
local utils = require('mkdnflow.utils')

local T = new_set()

-- =============================================================================
-- luaEscape tests
-- =============================================================================
T['luaEscape'] = new_set()

T['luaEscape']['escapes dash'] = function()
    eq(utils.luaEscape('foo-bar'), 'foo%-bar')
end

T['luaEscape']['escapes dot'] = function()
    eq(utils.luaEscape('file.md'), 'file%.md')
end

T['luaEscape']['escapes plus'] = function()
    eq(utils.luaEscape('c++'), 'c%+%+')
end

T['luaEscape']['escapes question mark'] = function()
    eq(utils.luaEscape('what?'), 'what%?')
end

T['luaEscape']['escapes percent'] = function()
    eq(utils.luaEscape('100%'), '100%%')
end

T['luaEscape']['handles multiple special chars'] = function()
    eq(utils.luaEscape('file-name.md?v=1'), 'file%-name%.md%?v=1')
end

T['luaEscape']['passes through plain text'] = function()
    eq(utils.luaEscape('hello world'), 'hello world')
end

T['luaEscape']['escapes parentheses'] = function()
    eq(utils.luaEscape('foo(bar)'), 'foo%(bar%)')
end

T['luaEscape']['escapes square brackets'] = function()
    eq(utils.luaEscape('foo[bar]'), 'foo%[bar%]')
end

T['luaEscape']['escapes caret'] = function()
    eq(utils.luaEscape('^start'), '%^start')
end

T['luaEscape']['escapes dollar sign'] = function()
    eq(utils.luaEscape('end$'), 'end%$')
end

T['luaEscape']['escapes asterisk'] = function()
    eq(utils.luaEscape('foo*bar'), 'foo%*bar')
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
    -- This is the to_do.statuses use case
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
