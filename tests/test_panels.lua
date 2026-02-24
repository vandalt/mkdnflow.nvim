-- tests/test_panels.lua
-- Tests for panel infrastructure (lua/mkdnflow/panels.lua)

local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

local T = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
        end,
        post_once = child.stop,
    },
})

-- =============================================================================
-- open
-- =============================================================================
T['open'] = new_set()

T['open']['requires name option'] = function()
    local handle = child.lua_get([[require('mkdnflow.panels').open({})]])
    eq(handle, vim.NIL)
end

T['open']['opens a float panel'] = function()
    child.lua([[
        _G._handle = require('mkdnflow.panels').open({
            name = 'test_float',
            position = 'float',
            lines = { 'hello', 'world' },
        })
    ]])
    local buf_valid = child.lua_get([[vim.api.nvim_buf_is_valid(_G._handle.buf)]])
    local win_valid = child.lua_get([[vim.api.nvim_win_is_valid(_G._handle.win)]])
    local name = child.lua_get([[_G._handle.name]])
    local position = child.lua_get([[_G._handle.position]])
    eq(buf_valid, true)
    eq(win_valid, true)
    eq(name, 'test_float')
    eq(position, 'float')

    -- Verify it's a floating window
    local win_config = child.lua_get([[vim.api.nvim_win_get_config(_G._handle.win)]])
    eq(win_config.relative, 'editor')
end

T['open']['opens a right split panel'] = function()
    child.lua([[
        _G._handle = require('mkdnflow.panels').open({
            name = 'test_split',
            position = 'right',
            lines = { 'content' },
            width = 30,
        })
    ]])
    local buf_valid = child.lua_get([[vim.api.nvim_buf_is_valid(_G._handle.buf)]])
    local win_valid = child.lua_get([[vim.api.nvim_win_is_valid(_G._handle.win)]])
    eq(buf_valid, true)
    eq(win_valid, true)

    -- Verify it's NOT a floating window
    local win_config = child.lua_get([[vim.api.nvim_win_get_config(_G._handle.win)]])
    eq(win_config.relative, '')
end

T['open']['opens a left split panel'] = function()
    child.lua([[
        _G._handle = require('mkdnflow.panels').open({
            name = 'test_left',
            position = 'left',
            lines = { 'left panel' },
            width = 25,
        })
    ]])
    local win_valid = child.lua_get([[vim.api.nvim_win_is_valid(_G._handle.win)]])
    eq(win_valid, true)
    eq(child.lua_get([[_G._handle.position]]), 'left')
end

T['open']['creates scratch buffer with correct options'] = function()
    child.lua([[
        _G._handle = require('mkdnflow.panels').open({
            name = 'test_buf_opts',
            position = 'float',
        })
    ]])
    local buftype = child.lua_get([[vim.bo[_G._handle.buf].buftype]])
    local bufhidden = child.lua_get([[vim.bo[_G._handle.buf].bufhidden]])
    local swapfile = child.lua_get([[vim.bo[_G._handle.buf].swapfile]])
    local buflisted = child.lua_get([[vim.bo[_G._handle.buf].buflisted]])
    eq(buftype, 'nofile')
    eq(bufhidden, 'wipe')
    eq(swapfile, false)
    eq(buflisted, false)
end

T['open']['disables gutter and wrap on split panels'] = function()
    -- Set gutter options globally so they'd bleed in without the fix
    child.lua([[
        vim.o.number = true
        vim.o.relativenumber = true
        vim.o.signcolumn = 'yes'
        vim.o.foldcolumn = '1'
        vim.o.wrap = true
        _G._handle = require('mkdnflow.panels').open({
            name = 'test_gutter',
            position = 'right',
            lines = { 'no gutter' },
        })
    ]])
    eq(child.lua_get([[vim.wo[_G._handle.win].number]]), false)
    eq(child.lua_get([[vim.wo[_G._handle.win].relativenumber]]), false)
    eq(child.lua_get([[vim.wo[_G._handle.win].signcolumn]]), 'no')
    eq(child.lua_get([[vim.wo[_G._handle.win].foldcolumn]]), '0')
    eq(child.lua_get([[vim.wo[_G._handle.win].wrap]]), false)
end

T['open']['sets buffer filetype when specified'] = function()
    child.lua([[
        _G._handle = require('mkdnflow.panels').open({
            name = 'test_ft',
            position = 'float',
            filetype = 'lua',
        })
    ]])
    local ft = child.lua_get([[vim.bo[_G._handle.buf].filetype]])
    eq(ft, 'lua')
end

T['open']['sets initial content lines'] = function()
    child.lua([[
        _G._handle = require('mkdnflow.panels').open({
            name = 'test_content',
            position = 'float',
            lines = { 'line 1', 'line 2', 'line 3' },
            modifiable = true,
        })
    ]])
    local lines = child.lua_get([[vim.api.nvim_buf_get_lines(_G._handle.buf, 0, -1, false)]])
    eq(lines, { 'line 1', 'line 2', 'line 3' })
end

T['open']['buffer is not modifiable by default'] = function()
    child.lua([[
        _G._handle = require('mkdnflow.panels').open({
            name = 'test_nomod',
            position = 'float',
            lines = { 'read only' },
        })
    ]])
    local modifiable = child.lua_get([[vim.bo[_G._handle.buf].modifiable]])
    eq(modifiable, false)
end

T['open']['buffer is modifiable when requested'] = function()
    child.lua([[
        _G._handle = require('mkdnflow.panels').open({
            name = 'test_mod',
            position = 'float',
            lines = { 'editable' },
            modifiable = true,
        })
    ]])
    local modifiable = child.lua_get([[vim.bo[_G._handle.buf].modifiable]])
    eq(modifiable, true)
end

T['open']['re-opens if same name already open'] = function()
    child.lua([[
        local panels = require('mkdnflow.panels')
        _G._handle1 = panels.open({
            name = 'test_reopen',
            position = 'float',
            lines = { 'first' },
        })
        _G._handle2 = panels.open({
            name = 'test_reopen',
            position = 'float',
            lines = { 'second' },
            modifiable = true,
        })
    ]])
    -- First window should be closed
    local win1_valid = child.lua_get([[vim.api.nvim_win_is_valid(_G._handle1.win)]])
    eq(win1_valid, false)
    -- Second should be open with new content
    local win2_valid = child.lua_get([[vim.api.nvim_win_is_valid(_G._handle2.win)]])
    eq(win2_valid, true)
    local lines = child.lua_get([[vim.api.nvim_buf_get_lines(_G._handle2.buf, 0, -1, false)]])
    eq(lines, { 'second' })
    -- Only one entry in registry
    child.lua([[
        _G._reg_count = 0
        for _ in pairs(require('mkdnflow.panels')._registry) do _G._reg_count = _G._reg_count + 1 end
    ]])
    local count = child.lua_get([[_G._reg_count]])
    eq(count, 1)
end

T['open']['validates position and falls back'] = function()
    child.lua([[
        _G._handle = require('mkdnflow.panels').open({
            name = 'test_bad_pos',
            position = 'rihgt',
            lines = { 'fallback' },
        })
    ]])
    -- Should fall back to 'right' and still open successfully
    local win_valid = child.lua_get([[vim.api.nvim_win_is_valid(_G._handle.win)]])
    eq(win_valid, true)
    eq(child.lua_get([[_G._handle.position]]), 'right')
end

-- =============================================================================
-- close
-- =============================================================================
T['close'] = new_set()

T['close']['closes an open panel'] = function()
    child.lua([[
        local panels = require('mkdnflow.panels')
        _G._handle = panels.open({
            name = 'test_close',
            position = 'float',
            lines = { 'goodbye' },
        })
        _G._result = panels.close('test_close')
    ]])
    eq(child.lua_get([[_G._result]]), true)
    local win_valid = child.lua_get([[vim.api.nvim_win_is_valid(_G._handle.win)]])
    eq(win_valid, false)
end

T['close']['returns false for unknown panel name'] = function()
    local result = child.lua_get([[require('mkdnflow.panels').close('nonexistent')]])
    eq(result, false)
end

T['close']['removes panel from registry'] = function()
    child.lua([[
        local panels = require('mkdnflow.panels')
        panels.open({ name = 'test_reg', position = 'float' })
        panels.close('test_reg')
    ]])
    local is_open = child.lua_get([[require('mkdnflow.panels').isOpen('test_reg')]])
    eq(is_open, false)
end

-- =============================================================================
-- refresh
-- =============================================================================
T['refresh'] = new_set()

T['refresh']['updates panel content'] = function()
    child.lua([[
        local panels = require('mkdnflow.panels')
        _G._handle = panels.open({
            name = 'test_refresh',
            position = 'float',
            lines = { 'old content' },
            modifiable = true,
        })
        _G._result = panels.refresh('test_refresh', { 'new content', 'more lines' })
    ]])
    eq(child.lua_get([[_G._result]]), true)
    local lines = child.lua_get([[vim.api.nvim_buf_get_lines(_G._handle.buf, 0, -1, false)]])
    eq(lines, { 'new content', 'more lines' })
end

T['refresh']['returns false for unknown panel'] = function()
    local result = child.lua_get([[require('mkdnflow.panels').refresh('nonexistent', { 'x' })]])
    eq(result, false)
end

T['refresh']['restores modifiable state'] = function()
    child.lua([[
        local panels = require('mkdnflow.panels')
        _G._handle = panels.open({
            name = 'test_refresh_mod',
            position = 'float',
            lines = { 'initial' },
            modifiable = false,
        })
        panels.refresh('test_refresh_mod', { 'updated' })
    ]])
    -- Buffer should still be non-modifiable after refresh
    local modifiable = child.lua_get([[vim.bo[_G._handle.buf].modifiable]])
    eq(modifiable, false)
    -- But content should be updated
    local lines = child.lua_get([[vim.api.nvim_buf_get_lines(_G._handle.buf, 0, -1, false)]])
    eq(lines, { 'updated' })
end

-- =============================================================================
-- toggle
-- =============================================================================
T['toggle'] = new_set()

T['toggle']['opens when closed'] = function()
    child.lua([[
        _G._handle = require('mkdnflow.panels').toggle('test_toggle', {
            position = 'float',
            lines = { 'toggled on' },
        })
    ]])
    local is_open = child.lua_get([[require('mkdnflow.panels').isOpen('test_toggle')]])
    eq(is_open, true)
    -- toggle returns the handle when opening
    local name = child.lua_get([[_G._handle.name]])
    eq(name, 'test_toggle')
end

T['toggle']['closes when open'] = function()
    child.lua([[
        local panels = require('mkdnflow.panels')
        panels.open({ name = 'test_toggle2', position = 'float' })
        _G._result = panels.toggle('test_toggle2')
    ]])
    local is_open = child.lua_get([[require('mkdnflow.panels').isOpen('test_toggle2')]])
    eq(is_open, false)
    -- toggle returns nil when closing
    eq(child.lua_get([[_G._result]]), vim.NIL)
end

-- =============================================================================
-- isOpen
-- =============================================================================
T['isOpen'] = new_set()

T['isOpen']['returns true for open panel'] = function()
    child.lua([[
        require('mkdnflow.panels').open({
            name = 'test_isopen',
            position = 'float',
        })
    ]])
    local result = child.lua_get([[require('mkdnflow.panels').isOpen('test_isopen')]])
    eq(result, true)
end

T['isOpen']['returns false for unknown panel'] = function()
    local result = child.lua_get([[require('mkdnflow.panels').isOpen('nonexistent')]])
    eq(result, false)
end

T['isOpen']['returns false after close'] = function()
    child.lua([[
        local panels = require('mkdnflow.panels')
        panels.open({ name = 'test_isopen_close', position = 'float' })
        panels.close('test_isopen_close')
    ]])
    local result = child.lua_get([[require('mkdnflow.panels').isOpen('test_isopen_close')]])
    eq(result, false)
end

T['isOpen']['returns false if window was externally closed'] = function()
    child.lua([[
        local panels = require('mkdnflow.panels')
        _G._handle = panels.open({ name = 'test_ext_close', position = 'float' })
        vim.api.nvim_win_close(_G._handle.win, true)
    ]])
    local result = child.lua_get([[require('mkdnflow.panels').isOpen('test_ext_close')]])
    eq(result, false)
end

-- =============================================================================
-- WinClosed cleanup
-- =============================================================================
T['cleanup'] = new_set()

T['cleanup']['cleans up buffer when window closed via API'] = function()
    child.lua([[
        local panels = require('mkdnflow.panels')
        _G._handle = panels.open({
            name = 'test_winclosed',
            position = 'float',
            lines = { 'will be cleaned' },
        })
        _G._buf = _G._handle.buf
        -- Close window directly (simulates :q or other non-keymap close)
        vim.api.nvim_win_close(_G._handle.win, true)
    ]])
    -- Registry should be cleaned up
    local is_open = child.lua_get([[require('mkdnflow.panels').isOpen('test_winclosed')]])
    eq(is_open, false)
    -- Buffer should be wiped
    local buf_valid = child.lua_get([[vim.api.nvim_buf_is_valid(_G._buf)]])
    eq(buf_valid, false)
end

T['cleanup']['cleans up via close keymap'] = function()
    child.lua([[
        local panels = require('mkdnflow.panels')
        _G._handle = panels.open({
            name = 'test_keymap_close',
            position = 'float',
            lines = { 'close me' },
            close_maps = { 'q' },
        })
        _G._buf = _G._handle.buf
    ]])
    -- The panel window should be focused; press q
    child.type_keys('q')
    local is_open = child.lua_get([[require('mkdnflow.panels').isOpen('test_keymap_close')]])
    eq(is_open, false)
    local buf_valid = child.lua_get([[vim.api.nvim_buf_is_valid(_G._buf)]])
    eq(buf_valid, false)
end

-- =============================================================================
-- Config resolution
-- =============================================================================
T['config'] = new_set()

T['config']['uses hardcoded defaults when setup not called'] = function()
    -- Do NOT call require('mkdnflow').setup()
    child.lua([[
        _G._handle = require('mkdnflow.panels').open({
            name = 'test_no_setup',
            position = 'float',
        })
    ]])
    -- Should still work with hardcoded defaults
    local win_valid = child.lua_get([[vim.api.nvim_win_is_valid(_G._handle.win)]])
    eq(win_valid, true)
end

T['config']['per-invocation opts override global config'] = function()
    child.lua([[
        vim.api.nvim_buf_set_name(0, 'test.md')
        vim.bo.filetype = 'markdown'
        require('mkdnflow').setup({ panels = { position = 'right' } })
        _G._handle = require('mkdnflow.panels').open({
            name = 'test_override',
            position = 'float',
            lines = { 'overridden' },
        })
    ]])
    -- Should be a float despite global config saying 'right'
    local win_config = child.lua_get([[vim.api.nvim_win_get_config(_G._handle.win)]])
    eq(win_config.relative, 'editor')
    eq(child.lua_get([[_G._handle.position]]), 'float')
end

T['config']['global panels config overrides hardcoded defaults'] = function()
    child.lua([[
        vim.api.nvim_buf_set_name(0, 'test.md')
        vim.bo.filetype = 'markdown'
        require('mkdnflow').setup({ panels = { width = 50 } })
        _G._handle = require('mkdnflow.panels').open({
            name = 'test_global',
            position = 'right',
        })
    ]])
    -- Width should be 50 from global config, not 40 from hardcoded defaults
    local win_width = child.lua_get([[vim.api.nvim_win_get_width(_G._handle.win)]])
    eq(win_width, 50)
end

-- =============================================================================
-- Stacking
-- =============================================================================
T['stacking'] = new_set()

T['stacking']['second panel on same side stacks within first'] = function()
    child.lua([[
        local panels = require('mkdnflow.panels')
        _G._handle_a = panels.open({
            name = 'stack_a',
            position = 'right',
            width = 30,
            lines = { 'panel A' },
        })
        _G._handle_b = panels.open({
            name = 'stack_b',
            position = 'right',
            width = 30,
            lines = { 'panel B' },
        })
    ]])
    -- Both panels should be open
    local a_valid = child.lua_get([[vim.api.nvim_win_is_valid(_G._handle_a.win)]])
    local b_valid = child.lua_get([[vim.api.nvim_win_is_valid(_G._handle_b.win)]])
    eq(a_valid, true)
    eq(b_valid, true)

    -- Both should be registered
    child.lua([[
        _G._reg_count = 0
        for _ in pairs(require('mkdnflow.panels')._registry) do _G._reg_count = _G._reg_count + 1 end
    ]])
    local count = child.lua_get([[_G._reg_count]])
    eq(count, 2)

    -- They should be different windows
    local same_win = child.lua_get([[_G._handle_a.win == _G._handle_b.win]])
    eq(same_win, false)
end

-- =============================================================================
-- Float sizing
-- =============================================================================
T['float_sizing'] = new_set()

T['float_sizing']['absolute width/height used directly'] = function()
    child.lua([[
        _G._handle = require('mkdnflow.panels').open({
            name = 'test_abs_size',
            position = 'float',
            float = { width = 60, height = 20 },
        })
    ]])
    local win_width = child.lua_get([[vim.api.nvim_win_get_width(_G._handle.win)]])
    local win_height = child.lua_get([[vim.api.nvim_win_get_height(_G._handle.win)]])
    eq(win_width, 60)
    eq(win_height, 20)
end

T['float_sizing']['fractional width/height resolved relative to editor'] = function()
    child.lua([[
        _G._cols = vim.o.columns
        _G._lines = vim.o.lines
        _G._handle = require('mkdnflow.panels').open({
            name = 'test_frac_size',
            position = 'float',
            float = { width = 0.5, height = 0.5 },
        })
    ]])
    local expected_width = child.lua_get([[math.floor(_G._cols * 0.5)]])
    local expected_height = child.lua_get([[math.floor(_G._lines * 0.5)]])
    local win_width = child.lua_get([[vim.api.nvim_win_get_width(_G._handle.win)]])
    local win_height = child.lua_get([[vim.api.nvim_win_get_height(_G._handle.win)]])
    eq(win_width, expected_width)
    eq(win_height, expected_height)
end

-- =============================================================================
-- Rich lines (highlights)
-- =============================================================================
T['rich_lines'] = new_set()

T['rich_lines']['open renders mixed plain and rich lines'] = function()
    child.lua([[
        _G._handle = require('mkdnflow.panels').open({
            name = 'test_rich_open',
            position = 'float',
            lines = {
                'plain line',
                { { 'bold ', 'Title' }, { 'text' } },
                { { 'all highlighted', 'Comment' } },
            },
            modifiable = true,
        })
    ]])
    local lines = child.lua_get([[vim.api.nvim_buf_get_lines(_G._handle.buf, 0, -1, false)]])
    eq(lines, { 'plain line', 'bold text', 'all highlighted' })
end

T['rich_lines']['open applies highlight groups'] = function()
    child.lua([=[
        local panels = require('mkdnflow.panels')
        _G._handle = panels.open({
            name = 'test_rich_hl',
            position = 'float',
            lines = {
                { { 'header', 'MkdnflowPanelHeader' }, { ' rest' } },
            },
        })
        -- Retrieve extmarks from the panels namespace
        local ns = panels._ns
        _G._marks = vim.api.nvim_buf_get_extmarks(
            _G._handle.buf, ns, 0, -1, { details = true }
        )
    ]=])
    local marks = child.lua_get('_G._marks')
    -- Should have exactly one highlight (for 'header')
    eq(#marks, 1)
    -- Check the highlight group
    eq(marks[1][4].hl_group, 'MkdnflowPanelHeader')
    -- Check column range: 'header' is bytes 0-6
    eq(marks[1][3], 0) -- start col
    eq(marks[1][4].end_col, 6)
end

T['rich_lines']['refresh with rich lines updates highlights'] = function()
    child.lua([=[
        local panels = require('mkdnflow.panels')
        _G._handle = panels.open({
            name = 'test_rich_refresh',
            position = 'float',
            lines = { 'initial plain' },
        })
        -- Refresh with rich lines
        panels.refresh('test_rich_refresh', {
            { { 'file.md', 'MkdnflowPanelFile' }, { ':' }, { '10', 'MkdnflowPanelLineNr' } },
        })
        local ns = panels._ns
        _G._marks = vim.api.nvim_buf_get_extmarks(
            _G._handle.buf, ns, 0, -1, { details = true }
        )
        _G._lines = vim.api.nvim_buf_get_lines(_G._handle.buf, 0, -1, false)
    ]=])
    local lines = child.lua_get('_G._lines')
    eq(lines, { 'file.md:10' })

    local marks = child.lua_get('_G._marks')
    -- Should have 2 highlights: file and line number (colon has no hl group)
    eq(#marks, 2)
end

T['rich_lines']['refresh clears old highlights'] = function()
    child.lua([=[
        local panels = require('mkdnflow.panels')
        _G._handle = panels.open({
            name = 'test_rich_clear',
            position = 'float',
            lines = {
                { { 'old highlight', 'MkdnflowPanelHeader' } },
            },
        })
        -- Refresh with plain string — old highlights should be gone
        panels.refresh('test_rich_clear', { 'no highlights' })
        local ns = panels._ns
        _G._marks = vim.api.nvim_buf_get_extmarks(
            _G._handle.buf, ns, 0, -1, { details = true }
        )
        _G._lines = vim.api.nvim_buf_get_lines(_G._handle.buf, 0, -1, false)
    ]=])
    local marks = child.lua_get('_G._marks')
    eq(#marks, 0)
    local lines = child.lua_get('_G._lines')
    eq(lines, { 'no highlights' })
end

return T
