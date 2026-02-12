-- mkdnflow.nvim (Tools for fluent markdown notebook navigation and management)
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

local silent = require('mkdnflow').config.silent
local path_resolution = require('mkdnflow').config.path_resolution

-- Table for global functions and variables
local M = {}

--- Stack of buffer numbers for backward navigation
---@type integer[]
M.main = {}

--- Stack of buffer numbers for forward navigation (history)
---@type integer[]
M.hist = {}

--- Push a buffer number onto the front of a stack
---@param stack_name integer[] The stack to push onto (M.main or M.hist)
---@param bufnr integer The buffer number to push
M.push = function(stack_name, bufnr)
    -- Add the provided buffer number to the first position in the provided
    -- stack, pushing down the others in the provided stack
    table.insert(stack_name, 1, bufnr)
end

--- Pop the topmost element from a stack
---@param stack_name integer[] The stack to pop from (M.main or M.hist)
M.pop = function(stack_name)
    -- Remove the topmost element in the provided stack
    table.remove(stack_name, 1)
end

--- Navigate to the previous buffer in the main stack
--- Pushes the current buffer onto the history stack for forward navigation.
---@return boolean success Whether navigation succeeded
M.goBack = function()
    local cur_bufnr = vim.api.nvim_win_get_buf(0)
    if cur_bufnr > 1 and #M.main > 0 then
        -- Add current buffer number to history
        M.push(M.hist, cur_bufnr)
        -- Get previous buffer number
        local prev_buf = M.main[1]
        -- Go to buffer
        vim.cmd.buffer(prev_buf)
        -- Pop the buffer we just navigated to off the top of the stack
        M.pop(M.main)
        -- Update the root and/or directory if needed
        require('mkdnflow').paths.updateDirs()
        -- return a boolean if goback succeeded (for users who want <bs> to do
        -- sth else if goback isn't possible)
        return true
    else
        if not silent then
            vim.api.nvim_echo({ { "⬇️  Can't go back any further!", 'WarningMsg' } }, true, {})
        end
        -- Return a boolean if goBack fails
        return false
    end
end

--- Navigate forward to the next buffer in the history stack
--- Pushes the current buffer onto the main stack for backward navigation.
---@return boolean success Whether navigation succeeded
M.goForward = function()
    -- Get current buffer number
    local cur_bufnr = vim.api.nvim_win_get_buf(0)
    -- Get historical buffer number
    local hist_bufnr = M.hist[1]
    -- If there is a buffer number in the history stack, do the following; if
    -- not, print a warning
    if hist_bufnr then
        M.push(M.main, cur_bufnr)
        -- Go to the historical buffer number
        vim.cmd.buffer(hist_bufnr)
        -- Pop historical buffer stack
        M.pop(M.hist)
        -- Update the root and/or working directory if needed
        require('mkdnflow').paths.updateDirs()
        -- Return a boolean if goForward succeeded (for users who want <Del> to
        -- do sth else if goForward isn't possible)
        return true
    else
        -- Print out an error if there's nothing in the historical buffer stack
        if not silent then
            vim.api.nvim_echo(
                { { "⬇️  Can't go forward any further!", 'WarningMsg' } },
                true,
                {}
            )
        end
        -- Return a boolean if goForward failed (for users who want <Del> to do
        -- sth else if goForward isn't possible)
        return false
    end
end

return M
