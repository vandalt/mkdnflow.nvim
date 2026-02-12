-- tests/test_delimited.lua
-- Tests for delimited data to markdown table conversion

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

-- Helper to setup mkdnflow with fresh module state
local function setup_fresh(config_str)
    child.lua([[
        for name, _ in pairs(package.loaded) do
            if name:match('^mkdnflow') then
                package.loaded[name] = nil
            end
        end
        vim.api.nvim_buf_set_name(0, 'test.md')
        vim.bo.filetype = 'markdown'
    ]] .. config_str)
end

-- Shortcut: call delimited module function and return result
local function delimited_call(fn_call)
    return child.lua_get(
        '(function() local d = require("mkdnflow.tables.delimited"); return d.'
            .. fn_call
            .. ' end)()'
    )
end

local T = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
                require('mkdnflow').setup({})
            ]])
        end,
        post_once = child.stop,
    },
})

-- =============================================================================
-- Delimiter detection
-- =============================================================================
T['detectDelimiter'] = new_set()

T['detectDelimiter']['detects comma'] = function()
    local result = delimited_call([[detectDelimiter({'a,b,c', 'd,e,f'})]])
    eq(result, ',')
end

T['detectDelimiter']['detects tab'] = function()
    local result = delimited_call([[detectDelimiter({'a\tb\tc', 'd\te\tf'})]])
    eq(result, '\t')
end

T['detectDelimiter']['detects semicolon'] = function()
    local result = delimited_call([[detectDelimiter({'a;b;c', 'd;e;f'})]])
    eq(result, ';')
end

T['detectDelimiter']['detects pipe'] = function()
    local result = delimited_call([[detectDelimiter({'a|b|c', 'd|e|f'})]])
    eq(result, '|')
end

T['detectDelimiter']['prefers tab over comma'] = function()
    local result = delimited_call([[detectDelimiter({'a,1\tb,2\tc,3', 'd,4\te,5\tf,6'})]])
    eq(result, '\t')
end

T['detectDelimiter']['ignores delimiters inside double-quoted fields'] = function()
    local result =
        delimited_call([[detectDelimiter({'"Smith, John",30,NYC', '"Doe, Jane",25,LA'})]])
    eq(result, ',')
end

T['detectDelimiter']['handles single-line input'] = function()
    local result = delimited_call([[detectDelimiter({'a,b,c'})]])
    eq(result, ',')
end

T['detectDelimiter']['falls back to comma for empty input'] = function()
    local result = delimited_call([[detectDelimiter({})]])
    eq(result, ',')
end

-- =============================================================================
-- Delimited parsing
-- =============================================================================
T['parseDelimited'] = new_set()

T['parseDelimited']['parses simple CSV'] = function()
    local result = delimited_call([[parseDelimited({'a,b,c', 'd,e,f'}, ',')]])
    eq(result, { { 'a', 'b', 'c' }, { 'd', 'e', 'f' } })
end

T['parseDelimited']['parses TSV'] = function()
    local result = delimited_call([[parseDelimited({'a\tb\tc', 'd\te\tf'}, '\t')]])
    eq(result, { { 'a', 'b', 'c' }, { 'd', 'e', 'f' } })
end

T['parseDelimited']['parses semicolon-delimited'] = function()
    local result = delimited_call([[parseDelimited({'a;b;c', 'd;e;f'}, ';')]])
    eq(result, { { 'a', 'b', 'c' }, { 'd', 'e', 'f' } })
end

T['parseDelimited']['parses pipe-delimited'] = function()
    local result = delimited_call([[parseDelimited({'a|b|c', 'd|e|f'}, '|')]])
    eq(result, { { 'a', 'b', 'c' }, { 'd', 'e', 'f' } })
end

T['parseDelimited']['handles quoted fields with embedded commas'] = function()
    local result = delimited_call([[parseDelimited({'"Smith, John",30,NYC'}, ',')]])
    eq(result, { { 'Smith, John', '30', 'NYC' } })
end

T['parseDelimited']['handles doubled quotes'] = function()
    local result = delimited_call([[parseDelimited({'"He said ""hello""",b'}, ',')]])
    eq(result, { { 'He said "hello"', 'b' } })
end

T['parseDelimited']['handles escaped delimiters with backslash'] = function()
    local result = delimited_call([[parseDelimited({'Smith\\, John,30'}, ',')]])
    eq(result, { { 'Smith, John', '30' } })
end

T['parseDelimited']['trims whitespace from unquoted fields'] = function()
    local result = delimited_call([[parseDelimited({'  a  ,  b  ,  c  '}, ',')]])
    eq(result, { { 'a', 'b', 'c' } })
end

T['parseDelimited']['preserves whitespace in quoted fields'] = function()
    local result = delimited_call([[parseDelimited({'"  a  ",b'}, ',')]])
    eq(result, { { '  a  ', 'b' } })
end

T['parseDelimited']['equalizes row lengths'] = function()
    local result = delimited_call([[parseDelimited({'a,b,c', 'd,e'}, ',')]])
    eq(result, { { 'a', 'b', 'c' }, { 'd', 'e', '' } })
end

T['parseDelimited']['handles empty fields'] = function()
    local result = delimited_call([[parseDelimited({'a,,c'}, ',')]])
    eq(result, { { 'a', '', 'c' } })
end

T['parseDelimited']['handles \\r\\n line endings'] = function()
    local result = delimited_call([[parseDelimited({'a,b,c\r', 'd,e,f\r'}, ',')]])
    eq(result, { { 'a', 'b', 'c' }, { 'd', 'e', 'f' } })
end

-- =============================================================================
-- Table generation (pipe)
-- =============================================================================
T['buildTable'] = new_set()

T['buildTable']['pipe: produces header + separator + data'] = function()
    local result = delimited_call([[buildTable({{'Name', 'Age'}, {'Alice', '30'}}, true)]])
    eq(result, {
        '| Name  | Age |',
        '| ----- | --- |',
        '| Alice | 30  |',
    })
end

T['buildTable']['pipe: produces table without separator when noh'] = function()
    local result = delimited_call([[buildTable({{'a', 'b'}, {'c', 'd'}}, false)]])
    eq(result, {
        '| a | b |',
        '| c | d |',
    })
end

T['buildTable']['pipe: single column'] = function()
    local result = delimited_call([[buildTable({{'Header'}, {'data'}}, true)]])
    eq(result, {
        '| Header |',
        '| ------ |',
        '| data   |',
    })
end

T['buildTable']['pipe: single row with header'] = function()
    local result = delimited_call([[buildTable({{'a', 'b', 'c'}}, true)]])
    eq(result, {
        '| a   | b   | c   |',
        '| --- | --- | --- |',
    })
end

T['buildTable']['pipe: empty data returns empty'] = function()
    local result = delimited_call([[buildTable({}, true)]])
    eq(result, {})
end

T['buildTable']['pipe: respects outer_pipes = false'] = function()
    setup_fresh([[
        require('mkdnflow').setup({
            tables = { style = { outer_pipes = false } }
        })
    ]])
    local result = delimited_call([[buildTable({{'a', 'b'}, {'c', 'd'}}, true)]])
    eq(result, {
        ' a   | b   ',
        ' --- | --- ',
        ' c   | d   ',
    })
end

-- =============================================================================
-- Table generation (grid)
-- =============================================================================
T['buildTable_grid'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            setup_fresh([[
                require('mkdnflow').setup({
                    tables = { type = 'grid' }
                })
            ]])
        end,
    },
})

T['buildTable_grid']['produces correct grid table with header'] = function()
    local result = delimited_call([[buildTable({{'Name', 'Age'}, {'Alice', '30'}}, true)]])
    eq(result, {
        '+-------+-----+',
        '| Name  | Age |',
        '+=======+=====+',
        '| Alice | 30  |',
        '+-------+-----+',
    })
end

T['buildTable_grid']['produces grid table without header separator'] = function()
    local result = delimited_call([[buildTable({{'a', 'b'}, {'c', 'd'}}, false)]])
    eq(result, {
        '+-----+-----+',
        '| a   | b   |',
        '+-----+-----+',
        '| c   | d   |',
        '+-----+-----+',
    })
end

-- =============================================================================
-- Integration: pasteTable
-- =============================================================================
T['pasteTable'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                -- Mock clipboard
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
                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
                require('mkdnflow').setup({})
            ]])
        end,
    },
})

T['pasteTable']['pastes CSV from clipboard as pipe table'] = function()
    child.lua([[vim.fn.setreg('+', 'Name,Age\nAlice,30\nBob,25\n')]])
    set_lines({ 'Some text above', '' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.tables.delimited').pasteTable(nil, true)]])
    local lines = get_lines()
    eq(lines, {
        'Some text above',
        '| Name  | Age |',
        '| ----- | --- |',
        '| Alice | 30  |',
        '| Bob   | 25  |',
        '',
    })
end

T['pasteTable']['pastes TSV from clipboard'] = function()
    child.lua([[vim.fn.setreg('+', 'a\tb\nc\td\n')]])
    set_lines({ '' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.tables.delimited').pasteTable(nil, true)]])
    local lines = get_lines()
    eq(lines, {
        '',
        '| a   | b   |',
        '| --- | --- |',
        '| c   | d   |',
    })
end

T['pasteTable']['does nothing with empty clipboard'] = function()
    child.lua([[vim.fn.setreg('+', '')]])
    set_lines({ 'unchanged' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.tables.delimited').pasteTable(nil, true)]])
    eq(get_lines(), { 'unchanged' })
end

T['pasteTable']['explicit delimiter overrides auto-detect'] = function()
    child.lua([[vim.fn.setreg('+', 'a;b;c\nd;e;f\n')]])
    set_lines({ '' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.tables.delimited').pasteTable(';', true)]])
    local lines = get_lines()
    eq(lines[2], '| a   | b   | c   |')
end

T['pasteTable']['noh flag suppresses separator'] = function()
    child.lua([[vim.fn.setreg('+', 'a,b\nc,d\n')]])
    set_lines({ '' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.tables.delimited').pasteTable(nil, false)]])
    local lines = get_lines()
    eq(lines, {
        '',
        '| a | b |',
        '| c | d |',
    })
end

T['pasteTable']['preserves surrounding buffer content'] = function()
    child.lua([[vim.fn.setreg('+', 'x,y\n')]])
    set_lines({ 'above', 'below' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.tables.delimited').pasteTable(nil, false)]])
    local lines = get_lines()
    eq(lines[1], 'above')
    eq(lines[#lines], 'below')
end

-- =============================================================================
-- Integration: tableFromSelection
-- =============================================================================
T['tableFromSelection'] = new_set()

T['tableFromSelection']['converts CSV lines to pipe table'] = function()
    set_lines({ 'above', 'Name,Age', 'Alice,30', 'below' })
    child.lua([[require('mkdnflow.tables.delimited').tableFromSelection(2, 3, nil, true)]])
    local lines = get_lines()
    eq(lines, {
        'above',
        '| Name  | Age |',
        '| ----- | --- |',
        '| Alice | 30  |',
        'below',
    })
end

T['tableFromSelection']['preserves lines above and below selection'] = function()
    set_lines({ 'line 1', 'a,b', 'c,d', 'line 4' })
    child.lua([[require('mkdnflow.tables.delimited').tableFromSelection(2, 3, nil, true)]])
    local lines = get_lines()
    eq(lines[1], 'line 1')
    eq(lines[#lines], 'line 4')
end

T['tableFromSelection']['handles quoted CSV fields'] = function()
    set_lines({ '"Smith, John",30', 'Jane,25' })
    child.lua([[require('mkdnflow.tables.delimited').tableFromSelection(1, 2, nil, true)]])
    local lines = get_lines()
    eq(lines, {
        '| Smith, John | 30  |',
        '| ----------- | --- |',
        '| Jane        | 25  |',
    })
end

T['tableFromSelection']['auto-detects tab delimiter'] = function()
    set_lines({ 'a\tb', 'c\td' })
    child.lua([[require('mkdnflow.tables.delimited').tableFromSelection(1, 2, nil, true)]])
    local lines = get_lines()
    eq(lines, {
        '| a   | b   |',
        '| --- | --- |',
        '| c   | d   |',
    })
end

-- =============================================================================
-- E2E command tests
-- =============================================================================
T['commands'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                -- Mock clipboard
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

                vim.cmd('runtime plugin/mkdnflow.lua')
                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
                require('mkdnflow').setup({})
                vim.cmd('doautocmd BufEnter')
            ]])
        end,
    },
})

T['commands']['MkdnTableFromSelection via range command'] = function()
    set_lines({ 'Name,Age', 'Alice,30' })
    child.lua([[vim.cmd('1,2MkdnTableFromSelection')]])
    local lines = get_lines()
    eq(lines, {
        '| Name  | Age |',
        '| ----- | --- |',
        '| Alice | 30  |',
    })
end

T['commands']['MkdnTablePaste inserts table from clipboard'] = function()
    child.lua([[vim.fn.setreg('+', 'a,b\nc,d\n')]])
    set_lines({ 'text' })
    set_cursor(1, 0)
    child.lua([[vim.cmd('MkdnTablePaste')]])
    local lines = get_lines()
    eq(lines, {
        'text',
        '| a   | b   |',
        '| --- | --- |',
        '| c   | d   |',
    })
end

T['commands']['MkdnTablePaste with noh'] = function()
    child.lua([[vim.fn.setreg('+', 'a,b\nc,d\n')]])
    set_lines({ '' })
    set_cursor(1, 0)
    child.lua([[vim.cmd('MkdnTablePaste noh')]])
    local lines = get_lines()
    eq(lines, {
        '',
        '| a | b |',
        '| c | d |',
    })
end

T['commands']['MkdnTablePaste with explicit delimiter via Lua'] = function()
    child.lua([[vim.fn.setreg('+', 'a;b\nc;d\n')]])
    set_lines({ '' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.tables').pasteTable({ delimiter = ';', header = true })]])
    local lines = get_lines()
    eq(lines, {
        '',
        '| a   | b   |',
        '| --- | --- |',
        '| c   | d   |',
    })
end

return T
