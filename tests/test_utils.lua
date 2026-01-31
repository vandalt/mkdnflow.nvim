-- tests/test_utils.lua
-- Tests for pure utility functions in mkdnflow.utils

local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

-- Load the utils module
local utils = require('mkdnflow.utils')

local T = new_set()

-- =============================================================================
-- getFileType tests
-- =============================================================================
T['getFileType'] = new_set()

T['getFileType']['detects markdown extension'] = function()
    eq(utils.getFileType('note.md'), 'md')
end

T['getFileType']['detects txt extension'] = function()
    eq(utils.getFileType('file.txt'), 'txt')
end

T['getFileType']['detects lua extension'] = function()
    eq(utils.getFileType('init.lua'), 'lua')
end

T['getFileType']['handles uppercase extensions'] = function()
    eq(utils.getFileType('README.MD'), 'md')
end

T['getFileType']['handles multiple dots'] = function()
    eq(utils.getFileType('archive.tar.gz'), 'gz')
end

T['getFileType']['returns empty string for no extension'] = function()
    eq(utils.getFileType('README'), '')
end

T['getFileType']['handles hidden files with extension'] = function()
    eq(utils.getFileType('.gitignore'), 'gitignore')
end

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

-- =============================================================================
-- strSplit tests
-- =============================================================================
T['strSplit'] = new_set()

T['strSplit']['splits on whitespace by default'] = function()
    local result = utils.strSplit('hello world')
    eq(result[1], 'hello')
    eq(result[2], 'world')
    eq(#result, 2)
end

T['strSplit']['splits on custom separator'] = function()
    local result = utils.strSplit('a,b,c', ',')
    eq(result[1], 'a')
    eq(result[2], 'b')
    eq(result[3], 'c')
    eq(#result, 3)
end

T['strSplit']['handles path splitting'] = function()
    local result = utils.strSplit('/home/user/file.md', '/')
    eq(result[1], 'home')
    eq(result[2], 'user')
    eq(result[3], 'file.md')
end

T['strSplit']['handles single item'] = function()
    local result = utils.strSplit('single')
    eq(result[1], 'single')
    eq(#result, 1)
end

-- =============================================================================
-- inTable tests
-- =============================================================================
T['inTable'] = new_set()

T['inTable']['finds existing string'] = function()
    eq(utils.inTable('b', { 'a', 'b', 'c' }), true)
end

T['inTable']['returns false for missing string'] = function()
    eq(utils.inTable('d', { 'a', 'b', 'c' }), false)
end

T['inTable']['finds number'] = function()
    eq(utils.inTable(2, { 1, 2, 3 }), true)
end

T['inTable']['handles empty table'] = function()
    eq(utils.inTable('a', {}), false)
end

T['inTable']['finds first element'] = function()
    eq(utils.inTable('first', { 'first', 'second', 'third' }), true)
end

T['inTable']['finds last element'] = function()
    eq(utils.inTable('last', { 'first', 'middle', 'last' }), true)
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
