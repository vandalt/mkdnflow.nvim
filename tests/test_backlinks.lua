-- tests/test_backlinks.lua
-- Tests for backlinks panel (lua/mkdnflow/backlinks.lua)

local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

-- =============================================================================
-- Temp directory fixture
-- =============================================================================

--- Set up a temp notebook with interlinked markdown files.
local function setup_tmpdir()
    child.lua([=[
        _G._tmpdir = vim.fn.resolve(vim.fn.tempname())
        vim.fn.mkdir(_G._tmpdir .. '/subdir', 'p')

        -- index.md: the target file (others link to this)
        vim.fn.writefile({
            '# Index',
            '',
            'Welcome to the notebook.',
            '',
            '[self link](#index)',
        }, _G._tmpdir .. '/index.md')

        -- page_a.md: contains markdown link to index
        vim.fn.writefile({
            '# Page A',
            '',
            'See [the index](index.md) for more.',
        }, _G._tmpdir .. '/page_a.md')

        -- page_b.md: contains wiki link to index
        vim.fn.writefile({
            '# Page B',
            '',
            'Check out [[index]] for details.',
        }, _G._tmpdir .. '/page_b.md')

        -- page_c.md: no links to index
        vim.fn.writefile({
            '# Page C',
            '',
            'This page has no links to index.',
        }, _G._tmpdir .. '/page_c.md')

        -- subdir/deep.md: contains relative path link to index
        vim.fn.writefile({
            '# Deep Page',
            '',
            'Go to [home](../index.md) from here.',
        }, _G._tmpdir .. '/subdir/deep.md')
    ]=])
end

--- Initialize mkdnflow in the child with the temp dir as notebook root.
local function setup_mkdnflow()
    child.lua([=[
        vim.cmd('runtime plugin/mkdnflow.lua')
        local tmpdir = _G._tmpdir
        local index = tmpdir .. '/index.md'
        vim.cmd('e ' .. index)
        vim.bo.filetype = 'markdown'
        require('mkdnflow').setup({
            modules = { notebook = true, backlinks = true },
            path_resolution = {
                primary = 'current',
            },
            links = {
                style = 'markdown',
                transform_on_create = false,
                transform_on_follow = false,
            },
            silent = true,
        })
        vim.cmd('doautocmd BufEnter')
    ]=])
end

local T = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            setup_tmpdir()
            setup_mkdnflow()
        end,
        post_once = child.stop,
    },
})

-- =============================================================================
-- format_panel
-- =============================================================================
T['format_panel'] = new_set()

T['format_panel']['shows header and separator'] = function()
    child.lua([=[
        local backlinks = require('mkdnflow.backlinks')
        local lines, _ = backlinks._test.format_panel({}, '/tmp/test/index.md')
        -- Extract structure for assertions
        _G._line1 = lines[1]
        _G._line2 = lines[2]
        _G._line3 = lines[3]
        _G._line4 = lines[4]
    ]=])
    -- First line: rich line with header + file highlights
    local line1 = child.lua_get('_G._line1')
    eq(line1[1][1], 'Backlinks to: ')
    eq(line1[1][2], 'MkdnflowPanelHeader')
    eq(line1[2][2], 'MkdnflowPanelFile')
    -- Second line: rich separator
    local line2 = child.lua_get('_G._line2')
    eq(line2[1][2], 'MkdnflowPanelSeparator')
    -- Third line: empty string
    eq(child.lua_get('_G._line3'), '')
    -- Fourth line: rich "no backlinks found"
    local line4 = child.lua_get('_G._line4')
    eq(line4[1][1], '(no backlinks found)')
    eq(line4[1][2], 'MkdnflowPanelEmpty')
end

T['format_panel']['shows result lines with correct format'] = function()
    child.lua([=[
        local backlinks = require('mkdnflow.backlinks')
        local refs = {
            { filepath = '/tmp/test/page_a.md', lnum = 3, col = 5, match = '[link](index.md)' },
        }
        local lines, map = backlinks._test.format_panel(refs, '/tmp/test/index.md')
        _G._fp_count = #lines
        _G._fp_line4 = lines[4]
        -- Extract specific key to avoid serializing sparse table (fails on 0.9.5)
        _G._fp_map_4 = map[4]
    ]=])
    -- Should have header (3 lines) + 1 result = 4 lines
    eq(child.lua_get('_G._fp_count'), 4)
    -- Result line is a rich line with file, colon, lnum, spacing, match
    local line4 = child.lua_get('_G._fp_line4')
    eq(line4[1][2], 'MkdnflowPanelFile') -- filepath chunk
    eq(line4[2][1], ':') -- colon separator
    eq(line4[3][1], '3') -- line number
    eq(line4[3][2], 'MkdnflowPanelLineNr') -- lnum highlight
    eq(line4[5][1], '[link](index.md)') -- match text
    eq(line4[5][2], 'MkdnflowPanelMatch') -- match highlight
    -- line_map should map line 4 → index 1
    eq(child.lua_get('_G._fp_map_4'), 1)
end

T['format_panel']['truncates long match text'] = function()
    child.lua([=[
        local backlinks = require('mkdnflow.backlinks')
        local long_match = string.rep('x', 100)
        local refs = {
            { filepath = '/tmp/test/a.md', lnum = 1, col = 1, match = long_match },
        }
        local lines, _ = backlinks._test.format_panel(refs, '/tmp/test/index.md')
        -- Result line is a rich line; match text is the 5th chunk
        _G._fp_match_text = lines[4][5][1]
    ]=])
    local match_text = child.lua_get('_G._fp_match_text')
    -- Match text should end with '...' and be shorter than the original
    eq(match_text:match('%.%.%.$') ~= nil, true)
    eq(#match_text < 100, true)
end

-- =============================================================================
-- findReferencesAsync
-- =============================================================================
T['findReferencesAsync'] = new_set()

T['findReferencesAsync']['finds markdown and wiki links to target'] = function()
    child.lua([=[
        local paths = require('mkdnflow.paths')
        local target = vim.fn.resolve(_G._tmpdir .. '/index.md')
        _G._refs = nil
        paths.findReferencesAsync(target, target, nil, function(refs)
            _G._refs = refs
        end)
    ]=])
    -- Wait for async completion
    vim.loop.sleep(500)
    child.lua('vim.wait(2000, function() return _G._refs ~= nil end)')

    local count = child.lua_get('#_G._refs')
    -- page_a.md has one link, page_b.md has one wiki link, subdir/deep.md has one link
    -- Self-references from index.md should be excluded
    eq(count, 3)
end

T['findReferencesAsync']['returns all files when skip_filepath is nil'] = function()
    child.lua([=[
        local paths = require('mkdnflow.paths')
        local target = vim.fn.resolve(_G._tmpdir .. '/index.md')
        _G._refs_all = nil
        paths.findReferencesAsync(target, nil, nil, function(refs)
            _G._refs_all = refs
        end)
    ]=])
    vim.loop.sleep(500)
    child.lua('vim.wait(2000, function() return _G._refs_all ~= nil end)')

    local count_all = child.lua_get('#_G._refs_all')
    -- Should include self-references too (index.md has [self link](#index) which
    -- won't match since it's an anchor-only link, so count should be same as skip case)
    -- Actually the self-link is '#index' which has no file source, so same 3
    eq(count_all, 3)
end

T['findReferencesAsync']['handles empty notebook'] = function()
    child.lua([=[
        -- Create empty notebook dir
        local empty_dir = vim.fn.resolve(vim.fn.tempname())
        vim.fn.mkdir(empty_dir, 'p')

        -- Point mkdnflow to empty dir
        require('mkdnflow').initial_dir = empty_dir
        require('mkdnflow').root_dir = empty_dir

        local paths = require('mkdnflow.paths')
        _G._refs_empty = nil
        paths.findReferencesAsync(empty_dir .. '/nonexistent.md', nil, nil, function(refs)
            _G._refs_empty = refs
        end)
    ]=])
    vim.loop.sleep(500)
    child.lua('vim.wait(2000, function() return _G._refs_empty ~= nil end)')

    local count = child.lua_get('#_G._refs_empty')
    eq(count, 0)
end

-- =============================================================================
-- toggleBacklinks
-- =============================================================================
T['toggleBacklinks'] = new_set()

T['toggleBacklinks']['opens panel'] = function()
    child.lua([[require('mkdnflow.backlinks').toggleBacklinks()]])
    vim.loop.sleep(500)
    child.lua(
        'vim.wait(2000, function() return require("mkdnflow.panels").isOpen("backlinks") end)'
    )

    local is_open = child.lua_get([[require('mkdnflow.panels').isOpen('backlinks')]])
    eq(is_open, true)
end

T['toggleBacklinks']['panel buffer has mkdnflow-backlinks filetype'] = function()
    child.lua([[require('mkdnflow.backlinks').toggleBacklinks()]])
    vim.loop.sleep(200)
    child.lua(
        'vim.wait(1000, function() return require("mkdnflow.panels").isOpen("backlinks") end)'
    )

    local ft =
        child.lua_get([[vim.bo[require('mkdnflow.panels')._registry['backlinks'].buf].filetype]])
    eq(ft, 'mkdnflow-backlinks')
end

T['toggleBacklinks']['closes panel when already open'] = function()
    child.lua([[require('mkdnflow.backlinks').toggleBacklinks()]])
    vim.loop.sleep(200)
    child.lua(
        'vim.wait(1000, function() return require("mkdnflow.panels").isOpen("backlinks") end)'
    )

    -- Toggle again to close
    child.lua([[require('mkdnflow.backlinks').toggleBacklinks()]])
    local is_open = child.lua_get([[require('mkdnflow.panels').isOpen('backlinks')]])
    eq(is_open, false)
end

T['toggleBacklinks']['panel opens without stealing focus'] = function()
    -- Record the current window before opening
    local win_before = child.lua_get('vim.api.nvim_get_current_win()')
    child.lua([[require('mkdnflow.backlinks').toggleBacklinks()]])
    vim.loop.sleep(200)
    child.lua(
        'vim.wait(1000, function() return require("mkdnflow.panels").isOpen("backlinks") end)'
    )

    local win_after = child.lua_get('vim.api.nvim_get_current_win()')
    eq(win_before, win_after)
end

T['toggleBacklinks']['populates panel with results'] = function()
    child.lua([[require('mkdnflow.backlinks').toggleBacklinks()]])
    vim.loop.sleep(500)
    child.lua(
        'vim.wait(2000, function() return require("mkdnflow.backlinks")._test.get_state().current_target ~= nil end)'
    )

    -- Extract fields inside child.lua to avoid serializing sparse current_line_map (fails on 0.9.5)
    child.lua([[
        local state = require('mkdnflow.backlinks')._test.get_state()
        _G._bl_has_target = state.current_target ~= nil
        _G._bl_result_count = #state.current_results
    ]])
    eq(child.lua_get('_G._bl_has_target'), true)
    -- Should have found backlinks
    eq(child.lua_get('_G._bl_result_count') > 0, true)
end

-- =============================================================================
-- <CR> jump
-- =============================================================================
T['CR_jump'] = new_set()

T['CR_jump']['navigates to correct file and line'] = function()
    child.lua([[require('mkdnflow.backlinks').toggleBacklinks()]])
    vim.loop.sleep(500)
    child.lua(
        'vim.wait(2000, function() return #require("mkdnflow.backlinks")._test.get_state().current_results > 0 end)'
    )

    -- Focus the panel window
    local panel_win = child.lua_get([[require('mkdnflow.panels')._registry['backlinks'].win]])
    child.lua('vim.api.nvim_set_current_win(' .. panel_win .. ')')

    -- Move cursor to first result line (line 4, after header/separator/blank)
    child.lua('vim.api.nvim_win_set_cursor(0, {4, 0})')

    -- Get expected target from results
    child.lua([=[
        local state = require('mkdnflow.backlinks')._test.get_state()
        local ref = state.current_results[state.current_line_map[4]]
        _G._expected_ref = { filepath = ref.filepath, lnum = ref.lnum }
    ]=])
    local expected = child.lua_get('_G._expected_ref')

    -- Press <CR>
    child.type_keys('<CR>')
    vim.loop.sleep(100)

    -- Should have jumped to the file
    local cur_buf = child.lua_get('vim.api.nvim_buf_get_name(0)')
    local cur_line = child.lua_get('vim.api.nvim_win_get_cursor(0)[1]')
    eq(vim.fn.resolve(cur_buf), vim.fn.resolve(expected.filepath))
    eq(cur_line, expected.lnum)
end

-- =============================================================================
-- refreshBacklinks
-- =============================================================================
T['refreshBacklinks'] = new_set()

T['refreshBacklinks']['updates panel content'] = function()
    child.lua([[require('mkdnflow.backlinks').toggleBacklinks()]])
    vim.loop.sleep(500)
    child.lua(
        'vim.wait(2000, function() return require("mkdnflow.backlinks")._test.get_state().current_target ~= nil end)'
    )

    local gen_before =
        child.lua_get([[require('mkdnflow.backlinks')._test.get_state().scan_generation]])

    child.lua([[require('mkdnflow.backlinks').refreshBacklinks()]])
    vim.loop.sleep(500)
    child.lua(
        'vim.wait(2000, function() return require("mkdnflow.backlinks")._test.get_state().scan_generation > '
            .. gen_before
            .. ' end)'
    )

    local gen_after =
        child.lua_get([[require('mkdnflow.backlinks')._test.get_state().scan_generation]])
    eq(gen_after > gen_before, true)
end

T['refreshBacklinks']['warns when panel not open'] = function()
    -- Capture notifications
    child.lua([[
        _G._notifications = {}
        vim.notify = function(msg, level)
            table.insert(_G._notifications, { msg = msg, level = level })
        end
    ]])

    child.lua([[require('mkdnflow.backlinks').refreshBacklinks()]])

    local notifications = child.lua_get('_G._notifications')
    eq(#notifications > 0, true)
    eq(notifications[1].msg:match('not open') ~= nil, true)
end

-- =============================================================================
-- Auto-refresh on BufEnter
-- =============================================================================
T['auto_refresh'] = new_set()

T['auto_refresh']['updates on buffer switch'] = function()
    child.lua([[require('mkdnflow.backlinks').toggleBacklinks()]])
    vim.loop.sleep(500)
    child.lua(
        'vim.wait(2000, function() return require("mkdnflow.backlinks")._test.get_state().current_target ~= nil end)'
    )

    local target_before =
        child.lua_get([[require('mkdnflow.backlinks')._test.get_state().current_target]])

    -- Switch to page_a.md
    child.lua([[
        vim.cmd('e ' .. _G._tmpdir .. '/page_a.md')
        vim.bo.filetype = 'markdown'
        vim.cmd('doautocmd BufEnter')
    ]])
    vim.loop.sleep(500)
    child.lua(
        'vim.wait(2000, function() return require("mkdnflow.backlinks")._test.get_state().current_target ~= "'
            .. target_before:gsub('\\', '\\\\')
            .. '" end)'
    )

    local target_after =
        child.lua_get([[require('mkdnflow.backlinks')._test.get_state().current_target]])

    -- Target should have changed
    eq(target_after ~= target_before, true)
    eq(target_after:match('page_a%.md$') ~= nil, true)
end

T['auto_refresh']['skips same target'] = function()
    child.lua([[require('mkdnflow.backlinks').toggleBacklinks()]])
    vim.loop.sleep(500)
    child.lua(
        'vim.wait(2000, function() return require("mkdnflow.backlinks")._test.get_state().current_target ~= nil end)'
    )

    local gen_before =
        child.lua_get([[require('mkdnflow.backlinks')._test.get_state().scan_generation]])

    -- Re-enter the same buffer (trigger BufEnter without actually switching)
    child.lua([[vim.cmd('doautocmd BufEnter')]])
    vim.loop.sleep(200)

    local gen_after =
        child.lua_get([[require('mkdnflow.backlinks')._test.get_state().scan_generation]])

    -- Generation should NOT have changed (no re-scan)
    eq(gen_after, gen_before)
end

T['auto_refresh']['skips non-markdown buffers'] = function()
    child.lua([[require('mkdnflow.backlinks').toggleBacklinks()]])
    vim.loop.sleep(500)
    child.lua(
        'vim.wait(2000, function() return require("mkdnflow.backlinks")._test.get_state().current_target ~= nil end)'
    )

    local gen_before =
        child.lua_get([[require('mkdnflow.backlinks')._test.get_state().scan_generation]])

    -- Open a non-markdown buffer
    child.lua([[
        vim.cmd('enew')
        vim.bo.filetype = 'lua'
        vim.api.nvim_buf_set_name(0, '/tmp/test.lua')
        vim.cmd('doautocmd BufEnter')
    ]])
    vim.loop.sleep(200)

    local gen_after =
        child.lua_get([[require('mkdnflow.backlinks')._test.get_state().scan_generation]])

    -- Generation should NOT have changed
    eq(gen_after, gen_before)
end

-- =============================================================================
-- Edge cases
-- =============================================================================
T['edge_cases'] = new_set()

T['edge_cases']['warns when notebook module disabled'] = function()
    child.restart({ '-u', 'scripts/minimal_init.lua' })
    child.lua([[
        vim.cmd('runtime plugin/mkdnflow.lua')
        vim.api.nvim_buf_set_name(0, 'test.md')
        vim.bo.filetype = 'markdown'
        require('mkdnflow').setup({
            modules = { notebook = false, backlinks = true },
            silent = true,
        })

        _G._notifications = {}
        vim.notify = function(msg, level)
            table.insert(_G._notifications, { msg = msg, level = level })
        end
    ]])

    child.lua([[require('mkdnflow.backlinks').toggleBacklinks()]])

    local notifications = child.lua_get('_G._notifications')
    eq(#notifications > 0, true)
    eq(notifications[1].msg:match('notebook') ~= nil, true)
end

T['edge_cases']['re-setup with module disabled clears old state'] = function()
    child.restart({ '-u', 'scripts/minimal_init.lua' })
    child.lua([[
        vim.cmd('runtime plugin/mkdnflow.lua')
        vim.api.nvim_buf_set_name(0, 'test.md')
        vim.bo.filetype = 'markdown'
        -- First setup: notebook enabled
        require('mkdnflow').setup({
            modules = { notebook = true, backlinks = true },
            silent = true,
        })
    ]])
    -- Verify notebook is loaded
    local notebook_truthy = child.lua_get([[require('mkdnflow').notebook ~= false]])
    eq(notebook_truthy, true)

    -- Re-setup: notebook disabled
    child.lua([[
        require('mkdnflow').setup({
            modules = { notebook = false, backlinks = false },
            silent = true,
        })
    ]])
    local notebook_after = child.lua_get([[require('mkdnflow').notebook]])
    eq(notebook_after, false)
    local backlinks_after = child.lua_get([[require('mkdnflow').backlinks]])
    eq(backlinks_after, false)
end

return T
