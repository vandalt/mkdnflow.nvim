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

local M = {}

--- Internal registry of open panels, keyed by panel name
---@type table<string, { buf: integer, win: integer, name: string, position: string }>
local registry = {}

--- Fallback defaults used when require('mkdnflow').config is unavailable
local defaults = {
    position = 'right',
    width = 40,
    height = 15,
    close_maps = { 'q' },
    focus = true,
    float = {
        border = 'rounded',
        width = 0.6,
        height = 0.7,
    },
}

local valid_positions = {
    right = true,
    left = true,
    bottom = true,
    top = true,
    float = true,
}

--- Resolve effective config for a panel invocation.
--- Merges: defaults < global panels config < per-invocation opts.
---@param opts table Caller-provided overrides
---@return table resolved The merged options
local function resolve_config(opts)
    local ok, mkdnflow = pcall(require, 'mkdnflow')
    local global_cfg = (ok and mkdnflow.config and mkdnflow.config.panels) or {}

    local resolved = vim.tbl_deep_extend('force', defaults, global_cfg, opts)

    if not valid_positions[resolved.position] then
        vim.notify(
            "⬇️  panels: invalid position '"
                .. tostring(resolved.position)
                .. "'. Using 'right'.",
            vim.log.levels.WARN
        )
        resolved.position = 'right'
    end

    return resolved
end

--- Find an existing mkdnflow panel window on the given side.
---@param position string 'right', 'left', 'top', 'bottom'
---@return integer|nil win_id The window ID, or nil if none found
local function find_panel_on_side(position)
    for _, handle in pairs(registry) do
        if handle.position == position and vim.api.nvim_win_is_valid(handle.win) then
            return handle.win
        end
    end
    return nil
end

--- Open a split window and load the given buffer into it.
---@param buf integer Buffer handle
---@param cfg table Resolved config
---@return integer|nil win Window handle, or nil on failure
local function open_split(buf, cfg)
    local position = cfg.position
    local width = cfg.width or 40
    local height = cfg.height or 15

    -- Save the current window to restore focus if needed
    local prev_win = vim.api.nvim_get_current_win()

    -- Check for stacking: if an mkdnflow panel already exists on the same side,
    -- split within that window rather than from the editor edge
    local target_win = find_panel_on_side(position)

    if target_win then
        vim.api.nvim_set_current_win(target_win)
        if position == 'right' or position == 'left' then
            vim.cmd('belowright ' .. height .. ' split')
        else
            vim.cmd('belowright ' .. width .. ' vsplit')
        end
    else
        if position == 'right' then
            vim.cmd('botright vertical ' .. width .. ' split')
        elseif position == 'left' then
            vim.cmd('topleft vertical ' .. width .. ' split')
        elseif position == 'bottom' then
            vim.cmd('botright ' .. height .. ' split')
        elseif position == 'top' then
            vim.cmd('topleft ' .. height .. ' split')
        end
    end

    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)

    -- Restore focus if not requested
    if cfg.focus == false then
        vim.api.nvim_set_current_win(prev_win)
    end

    return win
end

--- Open a floating window and load the given buffer into it.
---@param buf integer Buffer handle
---@param cfg table Resolved config
---@return integer|nil win Window handle, or nil on failure
local function open_float(buf, cfg)
    local float_cfg = cfg.float or {}
    local editor_width = vim.o.columns
    local editor_height = vim.o.lines

    -- Resolve width: fraction (0.0-1.0) or absolute
    local width = float_cfg.width or 0.6
    if width > 0 and width <= 1.0 then
        width = math.floor(editor_width * width)
    end
    width = math.floor(width)

    -- Resolve height: fraction (0.0-1.0) or absolute
    local height = float_cfg.height or 0.7
    if height > 0 and height <= 1.0 then
        height = math.floor(editor_height * height)
    end
    height = math.floor(height)

    local border = float_cfg.border or 'rounded'

    local win_opts = {
        relative = 'editor',
        row = math.floor((editor_height - height) / 2),
        col = math.floor((editor_width - width) / 2),
        width = width,
        height = height,
        style = 'minimal',
        border = border,
    }

    if cfg.title then
        win_opts.title = cfg.title
        win_opts.title_pos = 'center'
    end

    local win = vim.api.nvim_open_win(buf, cfg.focus ~= false, win_opts)
    return win
end

--- Open a panel (split or float) with a scratch buffer.
---@param opts table Options for the panel:
---   - name (string, required): Panel identifier (e.g., 'clean_config', 'backlinks')
---   - lines (string[]|nil): Initial content lines
---   - position (string|nil): 'right', 'left', 'bottom', 'top', 'float'
---   - width (integer|nil): Column count for vertical splits
---   - height (integer|nil): Row count for horizontal splits
---   - close_maps (string[]|nil): Buffer-local keymaps that close the panel
---   - focus (boolean|nil): Whether to focus the new window
---   - filetype (string|nil): Buffer filetype (e.g., 'lua')
---   - title (string|nil): Window title (floats and Neovim 0.10+ splits)
---   - float (table|nil): Float-specific overrides { border, width, height }
---   - modifiable (boolean|nil): Whether the buffer is modifiable (default false)
---@return { buf: integer, win: integer, name: string, position: string }|nil handle
M.open = function(opts)
    opts = opts or {}
    local name = opts.name
    if not name then
        vim.notify('⬇️  panels.open(): name is required', vim.log.levels.ERROR)
        return nil
    end

    -- If already open, close the existing one first
    if registry[name] then
        M.close(name)
    end

    local cfg = resolve_config(opts)

    -- Create scratch buffer
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = 'nofile'
    vim.bo[buf].bufhidden = 'wipe'
    vim.bo[buf].swapfile = false
    if cfg.filetype then
        vim.bo[buf].filetype = cfg.filetype
    end

    -- Set initial content
    if cfg.lines then
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, cfg.lines)
    end
    if not cfg.modifiable then
        vim.bo[buf].modifiable = false
    end

    -- Open window
    local win
    if cfg.position == 'float' then
        win = open_float(buf, cfg)
    else
        win = open_split(buf, cfg)
    end

    if not win then
        if vim.api.nvim_buf_is_valid(buf) then
            vim.api.nvim_buf_delete(buf, { force = true })
        end
        return nil
    end

    -- Register in the internal registry
    local handle = { buf = buf, win = win, name = name, position = cfg.position }
    registry[name] = handle

    -- Install close keymaps
    local close_maps = cfg.close_maps or {}
    for _, key in ipairs(close_maps) do
        vim.keymap.set('n', key, function()
            M.close(name)
        end, { buffer = buf, nowait = true })
    end

    -- Register WinClosed autocmd for guaranteed cleanup
    vim.api.nvim_create_autocmd('WinClosed', {
        pattern = tostring(win),
        once = true,
        callback = function()
            registry[name] = nil
            if vim.api.nvim_buf_is_valid(buf) then
                vim.api.nvim_buf_delete(buf, { force = true })
            end
        end,
    })

    return handle
end

--- Close a panel by name.
---@param name string The panel name
---@return boolean closed Whether a panel was actually closed
M.close = function(name)
    local handle = registry[name]
    if not handle then
        return false
    end
    -- Closing the window triggers WinClosed, which handles buffer cleanup
    -- and registry removal
    if vim.api.nvim_win_is_valid(handle.win) then
        vim.api.nvim_win_close(handle.win, true)
    end
    -- Safety: clean up manually in case WinClosed didn't fire
    registry[name] = nil
    if vim.api.nvim_buf_is_valid(handle.buf) then
        vim.api.nvim_buf_delete(handle.buf, { force = true })
    end
    return true
end

--- Refresh a panel's content. Only updates buffer lines; never replaces the window.
---@param name string The panel name
---@param lines string[] New content lines
---@return boolean success Whether the panel exists and was updated
M.refresh = function(name, lines)
    local handle = registry[name]
    if not handle or not vim.api.nvim_buf_is_valid(handle.buf) then
        return false
    end
    local was_modifiable = vim.bo[handle.buf].modifiable
    vim.bo[handle.buf].modifiable = true
    vim.api.nvim_buf_set_lines(handle.buf, 0, -1, false, lines)
    vim.bo[handle.buf].modifiable = was_modifiable
    return true
end

--- Toggle a panel: close if open, open if closed.
---@param name string The panel name
---@param opts table|nil Same opts as M.open (used when opening)
---@return { buf: integer, win: integer, name: string, position: string }|nil handle
M.toggle = function(name, opts)
    if M.isOpen(name) then
        M.close(name)
        return nil
    else
        opts = opts or {}
        opts.name = name
        return M.open(opts)
    end
end

--- Check if a panel is currently open.
---@param name string The panel name
---@return boolean
M.isOpen = function(name)
    local handle = registry[name]
    if not handle then
        return false
    end
    if not vim.api.nvim_win_is_valid(handle.win) then
        registry[name] = nil
        return false
    end
    return true
end

--- Expose internal registry for testing
M._registry = registry

return M
