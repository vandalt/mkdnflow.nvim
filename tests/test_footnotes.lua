-- tests/test_footnotes.lua
-- Tests for footnote reference support ([^label] and [^label]: text)

local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

-- Helper to set buffer content
local function set_lines(lines)
    child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, ' .. vim.inspect(lines) .. ')')
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

-- Helper to get extmarks with virtual text in the ref_hint namespace
local function get_hint_extmarks()
    child.lua([[
        local ns = vim.api.nvim_create_namespace('mkdnflow_ref_hint')
        local marks = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
        _G._hint_marks = {}
        for _, mark in ipairs(marks) do
            local details = mark[4]
            if details.virt_text then
                local text = ''
                for _, chunk in ipairs(details.virt_text) do
                    text = text .. chunk[1]
                end
                table.insert(_G._hint_marks, { row = mark[2] + 1, text = text })
            end
        end
    ]])
    return child.lua_get('_G._hint_marks')
end

-- Helper to wait for debounced hint to appear
local function wait_for_hint()
    child.lua('vim.cmd("doautocmd CursorMoved")')
    vim.loop.sleep(100)
    child.lua('vim.wait(50, function() return false end)')
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
                        transform_on_create = false,
                    }
                })
            ]])
        end,
        post_once = child.stop,
    },
})

-- =============================================================================
-- Detection: footnote_ref
-- =============================================================================
T['detection'] = new_set()

T['detection']['[^1] detected as footnote_ref'] = function()
    set_lines({ 'Some text[^1] here.', '', '[^1]: Footnote text' })
    set_cursor(1, 10) -- on [^1]
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'footnote_ref')
end

T['detection']['[^footnoteref] detected as footnote_ref'] = function()
    set_lines({ 'Some text[^footnoteref] here.' })
    set_cursor(1, 12)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'footnote_ref')
end

T['detection']['[^1] at start of line detected as footnote_ref'] = function()
    set_lines({ '[^1] some text.' })
    set_cursor(1, 1)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'footnote_ref')
end

T['detection']['[^1]: text detected as footnote_definition'] = function()
    set_lines({ '[^1]: Footnote text' })
    set_cursor(1, 3)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'footnote_definition')
end

T['detection']['footnote definition with leading spaces'] = function()
    set_lines({ '   [^1]: Footnote text' })
    set_cursor(1, 5)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'footnote_definition')
end

T['detection']['[^1] NOT detected as shortcut_ref_link'] = function()
    set_lines({ 'Text [^1] here.' })
    set_cursor(1, 6)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'footnote_ref')
end

T['detection']['regular [label] still detected as shortcut_ref_link'] = function()
    set_lines({ 'See [gh] for details.', '', '[gh]: https://github.com/' })
    set_cursor(1, 5)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'shortcut_ref_link')
end

T['detection']['[ref]: url still detected as ref_definition'] = function()
    set_lines({ '[ref]: https://example.com' })
    set_cursor(1, 3)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    local result = child.lua_get('_G.test_link and _G.test_link[3] or nil')
    eq(result, 'ref_definition')
end

T['detection']['extracts footnote label as name'] = function()
    set_lines({ 'Text [^myref] here.' })
    set_cursor(1, 7)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.test_name = require("mkdnflow.links").getLinkPart(_G.test_link, "name")')
    local result = child.lua_get('_G.test_name')
    eq(result, 'myref')
end

T['detection']['extracts footnote definition label as name'] = function()
    set_lines({ '[^myref]: Some footnote text.' })
    set_cursor(1, 3)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua('_G.test_name = require("mkdnflow.links").getLinkPart(_G.test_link, "name")')
    local result = child.lua_get('_G.test_name')
    eq(result, 'myref')
end

-- =============================================================================
-- Source resolution
-- =============================================================================
T['source'] = new_set()

T['source']['footnote_ref source points to definition row'] = function()
    set_lines({ 'Text[^1] here.', '', '[^1]: Footnote text' })
    set_cursor(1, 5)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua([[
        _G.src = _G.test_link:get_source()
    ]])
    local start_row = child.lua_get('_G.src.start_row')
    eq(start_row, 3)
end

T['source']['footnote_definition source points to first ref row'] = function()
    set_lines({ 'Text[^1] here.', '', '[^1]: Footnote text' })
    set_cursor(3, 3)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua([[
        _G.src = _G.test_link:get_source()
    ]])
    local start_row = child.lua_get('_G.src.start_row')
    eq(start_row, 1)
end

T['source']['footnote_ref with no definition has zero position'] = function()
    set_lines({ 'Text[^orphan] here.' })
    set_cursor(1, 5)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua([[
        _G.src = _G.test_link:get_source()
    ]])
    local start_row = child.lua_get('_G.src.start_row')
    eq(start_row, 0)
end

T['source']['footnote_definition with no ref has zero position'] = function()
    set_lines({ '[^orphan]: Unused footnote.' })
    set_cursor(1, 5)
    child.lua('_G.test_link = require("mkdnflow.links").getLinkUnderCursor()')
    child.lua([[
        _G.src = _G.test_link:get_source()
    ]])
    local start_row = child.lua_get('_G.src.start_row')
    eq(start_row, 0)
end

-- =============================================================================
-- Follow behavior (integration)
-- =============================================================================
T['follow'] = new_set()

T['follow']['followLink on [^1] jumps to definition line'] = function()
    set_lines({ 'Text[^1] here.', '', '[^1]: Footnote text' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.links').followLink()]])
    local cursor = get_cursor()
    eq(cursor[1], 3) -- jumped to definition row
end

T['follow']['followLink on [^1]: jumps to first reference'] = function()
    set_lines({ 'Text[^1] here.', '', '[^1]: Footnote text' })
    set_cursor(3, 3)
    child.lua([[require('mkdnflow.links').followLink()]])
    local cursor = get_cursor()
    eq(cursor[1], 1) -- jumped to reference row
end

T['follow']['followLink on orphan [^1] shows warning'] = function()
    set_lines({ 'Text[^orphan] here.' })
    set_cursor(1, 5)
    child.lua([[
        _G._notify_msg = nil
        _G._notify_level = nil
        local orig = vim.notify
        vim.notify = function(msg, level)
            _G._notify_msg = msg
            _G._notify_level = level
        end
        require('mkdnflow.links').followLink()
        vim.notify = orig
    ]])
    local msg = child.lua_get('_G._notify_msg')
    eq(msg, "Couldn't find footnote definition!")
end

T['follow']['followLink on orphan definition shows warning'] = function()
    set_lines({ '[^orphan]: Unused footnote.' })
    set_cursor(1, 5)
    child.lua([[
        _G._notify_msg = nil
        local orig = vim.notify
        vim.notify = function(msg, level)
            _G._notify_msg = msg
            _G._notify_level = level
        end
        require('mkdnflow.links').followLink()
        vim.notify = orig
    ]])
    local msg = child.lua_get('_G._notify_msg')
    eq(msg, "Couldn't find footnote reference!")
end

T['follow']['multiple footnotes jump to their own definitions'] = function()
    set_lines({
        'Text[^1] and[^2] here.',
        '',
        '[^1]: First footnote',
        '[^2]: Second footnote',
    })
    -- Follow [^2]
    set_cursor(1, 13)
    child.lua([[require('mkdnflow.links').followLink()]])
    local cursor = get_cursor()
    eq(cursor[1], 4) -- jumped to second definition
end

-- =============================================================================
-- E2E keypress tests
-- =============================================================================
T['keypress'] = new_set({
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
                    }
                })
                vim.cmd('doautocmd BufEnter')
            ]])
        end,
    },
})

T['keypress']['<CR> on [^1] jumps to definition'] = function()
    set_lines({ 'Text[^1] here.', '', '[^1]: Footnote text' })
    set_cursor(1, 5)
    child.type_keys('<CR>')
    local cursor = get_cursor()
    eq(cursor[1], 3)
end

T['keypress']['<CR> on definition jumps to reference'] = function()
    set_lines({ 'Text[^1] here.', '', '[^1]: Footnote text' })
    set_cursor(3, 3)
    child.type_keys('<CR>')
    local cursor = get_cursor()
    eq(cursor[1], 1)
end

-- =============================================================================
-- Hints (virtual text)
-- =============================================================================
T['hints'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
                require('mkdnflow').setup({
                    links = {
                        ref_hint = true,
                        transform_on_create = false,
                    }
                })
                vim.cmd('doautocmd FileType')
            ]])
        end,
    },
})

T['hints']['footnote_ref shows footnote text as hint'] = function()
    set_lines({ 'Text[^1] here.', '', '[^1]: Footnote text' })
    set_cursor(1, 5)
    wait_for_hint()
    local marks = get_hint_extmarks()
    eq(#marks, 1)
    eq(marks[1].row, 1)
    eq(marks[1].text, '→ Footnote text')
end

T['hints']['footnote_definition shows reference count'] = function()
    set_lines({ 'Text[^1] here.', 'Also[^1].', '', '[^1]: Footnote text' })
    set_cursor(4, 3)
    wait_for_hint()
    local marks = get_hint_extmarks()
    eq(#marks, 1)
    eq(marks[1].row, 4)
    eq(marks[1].text, '(2 references)')
end

T['hints']['footnote_definition singular reference'] = function()
    set_lines({ 'Text[^1] here.', '', '[^1]: Footnote text' })
    set_cursor(3, 3)
    wait_for_hint()
    local marks = get_hint_extmarks()
    eq(#marks, 1)
    eq(marks[1].text, '(1 reference)')
end

T['hints']['orphan footnote_ref no hint'] = function()
    set_lines({ 'Text[^orphan] here.' })
    set_cursor(1, 5)
    wait_for_hint()
    local marks = get_hint_extmarks()
    eq(#marks, 0)
end

T['hints']['orphan footnote_definition zero references'] = function()
    set_lines({ '[^orphan]: Unused footnote.' })
    set_cursor(1, 5)
    wait_for_hint()
    local marks = get_hint_extmarks()
    eq(#marks, 1)
    eq(marks[1].text, '(0 references)')
end

T['hints']['long footnote text truncated'] = function()
    local long_text = string.rep('a', 100)
    set_lines({ 'Text[^1] here.', '', '[^1]: ' .. long_text })
    set_cursor(1, 5)
    wait_for_hint()
    local marks = get_hint_extmarks()
    eq(#marks, 1)
    -- Should end with '...' when truncated
    eq(string.sub(marks[1].text, -3), '...')
end

-- =============================================================================
-- Footnote creation: smart placement
-- =============================================================================
T['placement'] = new_set()

-- Word boundary: cursor in middle of word, no trailing punctuation
T['placement']['mid-word, no punct'] = function()
    set_lines({ 'I suppose that' })
    set_cursor(1, 4) -- on 'p' in 'suppose'
    child.lua([[require('mkdnflow.links').createFootnote()]])
    child.type_keys('<Esc>')
    eq(get_line(1), 'I suppose[^1] that')
end

-- Word boundary: cursor at start of word, no trailing punctuation
T['placement']['start of word, no punct'] = function()
    set_lines({ 'I suppose that' })
    set_cursor(1, 2) -- on 's' in 'suppose'
    child.lua([[require('mkdnflow.links').createFootnote()]])
    child.type_keys('<Esc>')
    eq(get_line(1), 'I suppose[^1] that')
end

-- Word boundary: cursor on last char of word, no trailing punctuation
T['placement']['end of word, no punct'] = function()
    set_lines({ 'I suppose that' })
    set_cursor(1, 8) -- on 'e' in 'suppose'
    child.lua([[require('mkdnflow.links').createFootnote()]])
    child.type_keys('<Esc>')
    eq(get_line(1), 'I suppose[^1] that')
end

-- Word boundary: cursor on word at end of line
T['placement']['word at end of line'] = function()
    set_lines({ 'end word' })
    set_cursor(1, 6) -- on 'o' in 'word'
    child.lua([[require('mkdnflow.links').createFootnote()]])
    child.type_keys('<Esc>')
    eq(get_line(1), 'end word[^1]')
end

-- Word + period: cursor on last char before period
T['placement']['last char before period'] = function()
    set_lines({ 'word.' })
    set_cursor(1, 3) -- on 'd'
    child.lua([[require('mkdnflow.links').createFootnote()]])
    child.type_keys('<Esc>')
    eq(get_line(1), 'word.[^1]')
end

-- Word + period: cursor mid-word before period
T['placement']['mid-word before period'] = function()
    set_lines({ 'I suppose.' })
    set_cursor(1, 4) -- on 'p' in 'suppose'
    child.lua([[require('mkdnflow.links').createFootnote()]])
    child.type_keys('<Esc>')
    eq(get_line(1), 'I suppose.[^1]')
end

-- Word + comma: cursor mid-word before comma
T['placement']['mid-word before comma'] = function()
    set_lines({ 'word, more' })
    set_cursor(1, 2) -- on 'r' in 'word'
    child.lua([[require('mkdnflow.links').createFootnote()]])
    child.type_keys('<Esc>')
    eq(get_line(1), 'word,[^1] more')
end

-- Cursor directly on punctuation
T['placement']['cursor on period'] = function()
    set_lines({ 'word.' })
    set_cursor(1, 4) -- on '.'
    child.lua([[require('mkdnflow.links').createFootnote()]])
    child.type_keys('<Esc>')
    eq(get_line(1), 'word.[^1]')
end

T['placement']['cursor on comma'] = function()
    set_lines({ 'word, more' })
    set_cursor(1, 4) -- on ','
    child.lua([[require('mkdnflow.links').createFootnote()]])
    child.type_keys('<Esc>')
    eq(get_line(1), 'word,[^1] more')
end

T['placement']['cursor on question mark'] = function()
    set_lines({ 'really?' })
    set_cursor(1, 6) -- on '?'
    child.lua([[require('mkdnflow.links').createFootnote()]])
    child.type_keys('<Esc>')
    eq(get_line(1), 'really?[^1]')
end

T['placement']['cursor on exclamation mark'] = function()
    set_lines({ 'wow!' })
    set_cursor(1, 3) -- on '!'
    child.lua([[require('mkdnflow.links').createFootnote()]])
    child.type_keys('<Esc>')
    eq(get_line(1), 'wow![^1]')
end

T['placement']['cursor on semicolon'] = function()
    set_lines({ 'clause; another' })
    set_cursor(1, 6) -- on ';'
    child.lua([[require('mkdnflow.links').createFootnote()]])
    child.type_keys('<Esc>')
    eq(get_line(1), 'clause;[^1] another')
end

T['placement']['cursor on colon'] = function()
    set_lines({ 'note: detail' })
    set_cursor(1, 4) -- on ':'
    child.lua([[require('mkdnflow.links').createFootnote()]])
    child.type_keys('<Esc>')
    eq(get_line(1), 'note:[^1] detail')
end

-- Word char before various punctuation types
T['placement']['word before question mark'] = function()
    set_lines({ 'really?' })
    set_cursor(1, 5) -- on 'y'
    child.lua([[require('mkdnflow.links').createFootnote()]])
    child.type_keys('<Esc>')
    eq(get_line(1), 'really?[^1]')
end

T['placement']['word before semicolon'] = function()
    set_lines({ 'clause; another' })
    set_cursor(1, 3) -- on 'u' in 'clause'
    child.lua([[require('mkdnflow.links').createFootnote()]])
    child.type_keys('<Esc>')
    eq(get_line(1), 'clause;[^1] another')
end

T['placement']['word before colon'] = function()
    set_lines({ 'note: detail' })
    set_cursor(1, 2) -- on 't' in 'note'
    child.lua([[require('mkdnflow.links').createFootnote()]])
    child.type_keys('<Esc>')
    eq(get_line(1), 'note:[^1] detail')
end

-- Multiple punctuation
T['placement']['word before period+quote'] = function()
    set_lines({ 'word."' })
    set_cursor(1, 3) -- on 'd'
    child.lua([[require('mkdnflow.links').createFootnote()]])
    child.type_keys('<Esc>')
    eq(get_line(1), 'word."[^1]')
end

T['placement']['cursor on period before quote'] = function()
    set_lines({ 'word."' })
    set_cursor(1, 4) -- on '.'
    child.lua([[require('mkdnflow.links').createFootnote()]])
    child.type_keys('<Esc>')
    eq(get_line(1), 'word."[^1]')
end

T['placement']['closing paren then period'] = function()
    set_lines({ '(aside).' })
    set_cursor(1, 6) -- on ')'
    child.lua([[require('mkdnflow.links').createFootnote()]])
    child.type_keys('<Esc>')
    eq(get_line(1), '(aside).[^1]')
end

-- Whitespace: cursor on space
T['placement']['cursor on space between words'] = function()
    set_lines({ 'word more' })
    set_cursor(1, 4) -- on ' '
    child.lua([[require('mkdnflow.links').createFootnote()]])
    child.type_keys('<Esc>')
    eq(get_line(1), 'word[^1] more')
end

T['placement']['cursor on space after period'] = function()
    set_lines({ 'word. Next' })
    set_cursor(1, 5) -- on ' ' after '.'
    child.lua([[require('mkdnflow.links').createFootnote()]])
    child.type_keys('<Esc>')
    eq(get_line(1), 'word.[^1] Next')
end

-- Contraction: apostrophe should be treated as part of the word
T['placement']['contraction before period'] = function()
    set_lines({ "don't." })
    set_cursor(1, 2) -- on 'n' in "don't"
    child.lua([[require('mkdnflow.links').createFootnote()]])
    child.type_keys('<Esc>')
    eq(get_line(1), "don't.[^1]")
end

-- Single character word
T['placement']['single char word'] = function()
    set_lines({ 'a word' })
    set_cursor(1, 0) -- on 'a'
    child.lua([[require('mkdnflow.links').createFootnote()]])
    child.type_keys('<Esc>')
    eq(get_line(1), 'a[^1] word')
end

-- =============================================================================
-- Footnote creation
-- =============================================================================
T['create'] = new_set()

T['create']['inserts [^1] at cursor and definition at end'] = function()
    set_lines({ 'Some text here.' })
    set_cursor(1, 9)
    child.lua([[require('mkdnflow.links').createFootnote()]])
    child.type_keys('<Esc>')
    eq(get_line(1), 'Some text[^1] here.')
    eq(get_line(2), '')
    eq(get_line(3), '## Footnotes')
    eq(get_line(4), '')
    eq(get_line(5), '[^1]: ')
end

T['create']['auto-increments from highest existing footnote'] = function()
    set_lines({ 'Text[^3] here.', '', '[^3]: Third note' })
    set_cursor(1, 13) -- on the '.'
    child.lua([[require('mkdnflow.links').createFootnote()]])
    child.type_keys('<Esc>')
    eq(get_line(1), 'Text[^3] here.[^4]')
    eq(get_line(4), '[^4]: ')
end

T['create']['explicit label is used when provided'] = function()
    set_lines({ 'Some text here.' })
    set_cursor(1, 9)
    child.lua([[require('mkdnflow.links').createFootnote({ label = 'myref' })]])
    child.type_keys('<Esc>')
    eq(get_line(1), 'Some text[^myref] here.')
end

T['create']['duplicate label warns and aborts'] = function()
    set_lines({ 'Text[^1] here.', '', '[^1]: Existing' })
    set_cursor(1, 14)
    child.lua([[
        _G._notify_msg = nil
        local orig = vim.notify
        vim.notify = function(msg, level)
            _G._notify_msg = msg
        end
        require('mkdnflow.links').createFootnote({ label = '1' })
        vim.notify = orig
    ]])
    local msg = child.lua_get('_G._notify_msg')
    eq(msg, 'Footnote [^1] already exists!')
    -- Buffer should be unchanged
    eq(get_line(1), 'Text[^1] here.')
end

T['create']['places definition after last existing definition'] = function()
    set_lines({
        'Text[^1] and[^2] here.',
        '',
        '[^1]: First',
        '[^2]: Second',
    })
    set_cursor(1, 21)
    child.lua([[require('mkdnflow.links').createFootnote()]])
    child.type_keys('<Esc>')
    eq(get_line(5), '[^3]: ')
end

T['create']['no heading when config is false'] = function()
    child.restart({ '-u', 'scripts/minimal_init.lua' })
    child.lua([[
        vim.api.nvim_buf_set_name(0, 'test.md')
        vim.bo.filetype = 'markdown'
        require('mkdnflow').setup({
            links = { transform_on_create = false },
            footnotes = { heading = false },
        })
    ]])
    set_lines({ 'Some text here.' })
    set_cursor(1, 9)
    child.lua([[require('mkdnflow.links').createFootnote()]])
    child.type_keys('<Esc>')
    eq(get_line(1), 'Some text[^1] here.')
    eq(get_line(2), '')
    eq(get_line(3), '[^1]: ')
end

T['create']['cursor jumps to definition line'] = function()
    set_lines({ 'Some text here.' })
    set_cursor(1, 9)
    child.lua([[require('mkdnflow.links').createFootnote()]])
    child.type_keys('<Esc>')
    local cursor = get_cursor()
    eq(cursor[1], 5) -- blank + heading + blank + def
end

T['create']['jumplist allows return to reference'] = function()
    set_lines({ 'Some text here.' })
    set_cursor(1, 9)
    child.lua([[require('mkdnflow.links').createFootnote()]])
    child.type_keys('<Esc>')
    child.type_keys("''")
    local cursor = get_cursor()
    eq(cursor[1], 1)
end

T['create']['heading not duplicated on second creation'] = function()
    set_lines({ 'Some text here.' })
    set_cursor(1, 9)
    child.lua([[require('mkdnflow.links').createFootnote()]])
    child.type_keys('<Esc>')
    -- Create second footnote
    set_cursor(1, 14) -- inside 'here' after [^1]
    child.lua([[require('mkdnflow.links').createFootnote()]])
    child.type_keys('<Esc>')
    eq(get_line(1), 'Some text[^1] here.[^2]')
    eq(get_line(3), '## Footnotes')
    eq(get_line(5), '[^1]: ')
    eq(get_line(6), '[^2]: ')
end

-- =============================================================================
-- Footnote creation E2E (command invocation)
-- =============================================================================
T['create_e2e'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                vim.cmd('runtime plugin/mkdnflow.lua')
                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
                require('mkdnflow').setup({
                    links = { transform_on_create = false },
                })
                vim.cmd('doautocmd BufEnter')
            ]])
        end,
    },
})

T['create_e2e'][':MkdnCreateFootnote creates footnote'] = function()
    set_lines({ 'Some text here.' })
    set_cursor(1, 9)
    child.lua([[vim.cmd('MkdnCreateFootnote')]])
    child.type_keys('<Esc>')
    eq(get_line(1), 'Some text[^1] here.')
    eq(get_line(5), '[^1]: ')
end

T['create_e2e'][':MkdnCreateFootnote with explicit label'] = function()
    set_lines({ 'Some text here.' })
    set_cursor(1, 9)
    child.lua([[vim.cmd('MkdnCreateFootnote myref')]])
    child.type_keys('<Esc>')
    eq(get_line(1), 'Some text[^myref] here.')
end

return T
