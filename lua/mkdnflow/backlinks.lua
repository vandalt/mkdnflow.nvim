-- mkdnflow.nvim (Tools for personal markdown notebook navigation and management)
-- Copyright (C) 2022 Jake W. Vincent <https://github.com/jakewvincent>
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.

-- Backlinks panel: shows files that link to the current buffer

local M = {}

local panels = require('mkdnflow.panels')
local paths = require('mkdnflow.paths')

local function mkdn()
    return require('mkdnflow')
end
local function cfg()
    return mkdn().config
end

local PANEL_NAME = 'backlinks'

-- Module state
local current_target = nil
local current_results = {}
local current_line_map = {}
local scan_generation = 0

--- Build rich display lines and line_map from a sorted results array.
---@param results table[] Array of reference entries
---@param target_path string Absolute path of the target file
---@return (string | (string | string[])[])[] lines Rich lines for the panel
---@return table<integer, integer> line_map Maps panel line number → results index
local function format_panel(results, target_path)
    local rel_target = paths.relativeToBase(target_path)
    local lines = {
        {
            { 'Backlinks to: ', 'MkdnflowPanelHeader' },
            { rel_target, 'MkdnflowPanelFile' },
        },
        { { string.rep('-', 38), 'MkdnflowPanelSeparator' } },
        '',
    }
    local line_map = {}

    if #results == 0 then
        table.insert(lines, { { '(no backlinks found)', 'MkdnflowPanelEmpty' } })
        return lines, line_map
    end

    for i, ref in ipairs(results) do
        local rel_path = paths.relativeToBase(ref.filepath)
        local match_text = ref.match or ''
        -- Sanitize: replace newlines with spaces, trim
        match_text = match_text:gsub('\n', ' '):gsub('\r', '')
        -- Truncate long matches
        if #match_text > 60 then
            match_text = match_text:sub(1, 57) .. '...'
        end
        table.insert(lines, {
            { rel_path, 'MkdnflowPanelFile' },
            { ':' },
            { tostring(ref.lnum), 'MkdnflowPanelLineNr' },
            { '  ' },
            { match_text, 'MkdnflowPanelMatch' },
        })
        line_map[#lines] = i
    end

    return lines, line_map
end

--- Sort results by filepath then line number.
---@param results table[] Array of reference entries (mutated in place)
local function sort_results(results)
    table.sort(results, function(a, b)
        if a.filepath == b.filepath then
            return a.lnum < b.lnum
        end
        return a.filepath < b.filepath
    end)
end

--- Scan for backlinks and display them in the panel.
---@param target_path string Resolved absolute path of the file to find backlinks for
local function scan_and_display(target_path)
    scan_generation = scan_generation + 1
    local my_generation = scan_generation

    -- Pass target_path as skip_filepath to exclude self-references
    paths.findReferencesAsync(target_path, target_path, nil, function(refs)
        if my_generation ~= scan_generation then
            return
        end

        sort_results(refs)
        current_results = refs
        current_target = target_path

        local lines, line_map = format_panel(refs, target_path)
        current_line_map = line_map

        panels.refresh(PANEL_NAME, lines)
    end)
end

--- Jump to the backlink reference under the cursor.
local function jump_to_reference()
    local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
    local idx = current_line_map[cursor_line]
    if not idx then
        return
    end
    local ref = current_results[idx]
    if not ref then
        return
    end

    -- Jump to previous window, falling back to first editable window
    vim.cmd('wincmd p')
    local target_win = vim.api.nvim_get_current_win()
    local target_buf = vim.api.nvim_win_get_buf(target_win)
    local bt = vim.bo[target_buf].buftype
    if bt ~= '' then
        -- Find first window with an editable buffer
        for _, win in ipairs(vim.api.nvim_list_wins()) do
            local buf = vim.api.nvim_win_get_buf(win)
            if vim.bo[buf].buftype == '' then
                vim.api.nvim_set_current_win(win)
                break
            end
        end
    end

    vim.cmd.edit(ref.filepath)
    local line_count = vim.api.nvim_buf_line_count(0)
    local lnum = math.min(ref.lnum, line_count)
    local col = ref.col or 0
    if col > 0 then
        col = col - 1
    end
    vim.api.nvim_win_set_cursor(0, { lnum, col })
end

--- Shared handler for BufEnter and FileType autocmds.
---@param filetype_set? table<string, boolean> Set of valid filetypes (nil = skip ft check)
local function maybe_refresh(filetype_set)
    -- Guard 1: skip non-file buffers
    if vim.bo.buftype ~= '' then
        return
    end

    -- Guard 2: skip unnamed buffers
    local buf_name = vim.api.nvim_buf_get_name(0)
    if buf_name == '' then
        return
    end

    -- Guard 3: skip if panel is not open
    if not panels.isOpen(PANEL_NAME) then
        return
    end

    -- Guard 4: skip if entering the panel buffer itself
    local reg = panels._registry[PANEL_NAME]
    if reg and reg.buf == vim.api.nvim_get_current_buf() then
        return
    end

    -- Guard 5: skip if filetype doesn't match (BufEnter path)
    if filetype_set and not filetype_set[vim.bo.filetype] then
        return
    end

    -- Guard 6: skip if target hasn't changed
    local resolved = vim.fn.resolve(buf_name)
    if resolved == current_target then
        return
    end

    scan_and_display(resolved)
end

M.toggleBacklinks = function()
    if not mkdn().notebook then
        vim.notify('⬇️  Enable the notebook module to use backlinks', vim.log.levels.WARN)
        return
    end

    local handle = panels.toggle(PANEL_NAME, { focus = false, filetype = 'mkdnflow-backlinks' })
    if not handle then
        -- Panel was closed
        return
    end

    -- Install <CR> keymap on the panel buffer
    vim.keymap.set('n', '<CR>', jump_to_reference, { buffer = handle.buf, nowait = true })

    -- Trigger initial scan
    local buf_name = vim.api.nvim_buf_get_name(0)
    if buf_name ~= '' then
        scan_and_display(vim.fn.resolve(buf_name))
    end
end

M.refreshBacklinks = function()
    if not mkdn().notebook then
        vim.notify('⬇️  Enable the notebook module to use backlinks', vim.log.levels.WARN)
        return
    end

    if not panels.isOpen(PANEL_NAME) then
        vim.notify('⬇️  Backlinks panel is not open', vim.log.levels.WARN)
        return
    end

    local buf_name = vim.api.nvim_buf_get_name(0)
    if buf_name ~= '' then
        scan_and_display(vim.fn.resolve(buf_name))
    end
end

M.init = function()
    if not mkdn().notebook then
        return
    end

    local auto_refresh = cfg().backlinks.auto_refresh
    if auto_refresh == false then
        return
    end

    -- Build filetype set for O(1) lookup
    local resolved_filetypes = cfg().resolved_filetypes or {}
    local ft_set = {}
    for _, ft in ipairs(resolved_filetypes) do
        ft_set[ft] = true
    end

    local group = vim.api.nvim_create_augroup('MkdnflowBacklinks', { clear = true })

    -- BufEnter: handles switching between already-loaded buffers
    vim.api.nvim_create_autocmd('BufEnter', {
        group = group,
        pattern = '*',
        callback = function()
            maybe_refresh(ft_set)
        end,
    })

    -- FileType: handles newly opened files where filetype wasn't set at BufEnter time
    if #resolved_filetypes > 0 then
        vim.api.nvim_create_autocmd('FileType', {
            group = group,
            pattern = resolved_filetypes,
            callback = function()
                maybe_refresh(nil)
            end,
        })
    end
end

--- Expose internals for testing
M._test = {
    format_panel = format_panel,
    sort_results = sort_results,
    scan_and_display = scan_and_display,
    maybe_refresh = maybe_refresh,
    get_state = function()
        return {
            current_target = current_target,
            current_results = current_results,
            current_line_map = current_line_map,
            scan_generation = scan_generation,
        }
    end,
    reset_state = function()
        current_target = nil
        current_results = {}
        current_line_map = {}
        scan_generation = 0
    end,
    PANEL_NAME = PANEL_NAME,
}

return M
