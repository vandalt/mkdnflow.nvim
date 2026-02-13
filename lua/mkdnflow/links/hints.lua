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

-- This module: Virtual text hints for reference-style links

local M = {}

local ns = vim.api.nvim_create_namespace('mkdnflow_ref_hint')
local timers = {} -- debounce timers per buffer
local DEBOUNCE_MS = 50

--- Count how many times a reference label is used in the buffer
--- @param label string The reference label to search for
--- @param bufnr integer Buffer number
--- @param skip_row integer Row to skip (the definition line itself)
--- @return integer count Number of references found
local function count_refs(label, bufnr, skip_row)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local escaped = vim.pesc(label)
    local count = 0

    for i, line in ipairs(lines) do
        if i ~= skip_row then
            -- Full reference: [text][label]
            if string.find(line, '%]%[' .. escaped .. '%]') then
                -- Count all occurrences on this line
                for _ in string.gmatch(line, '%]%[' .. escaped .. '%]') do
                    count = count + 1
                end
            end
            -- Collapsed reference: [label][]
            if string.find(line, '%[' .. escaped .. '%]%[%]') then
                for _ in string.gmatch(line, '%[' .. escaped .. '%]%[%]') do
                    count = count + 1
                end
            end
            -- Shortcut reference: [label] not followed by ( [ or :
            -- Use a pattern that matches [label] at positions not already counted
            for pos in string.gmatch(line, '()%[' .. escaped .. '%]') do
                local after = string.sub(line, pos + #label + 2, pos + #label + 2)
                local before = pos > 1 and string.sub(line, pos - 1, pos - 1) or ''
                -- Not a full/collapsed ref (preceded by ]) and not a definition (followed by :)
                -- and not an md_link (followed by ()
                if before ~= ']' and after ~= '[' and after ~= '(' and after ~= ':' then
                    count = count + 1
                end
            end
        end
    end

    return count
end

--- Update the virtual text hint for the current cursor position
--- @param bufnr integer Buffer number
local function update_hint(bufnr)
    -- Clear previous hints
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

    -- Detect link under cursor
    local Link = require('mkdnflow.links.core').Link
    local link = Link:read(nil, bufnr)
    if not link then
        return
    end

    local row = link.start_row - 1 -- convert to 0-indexed
    local hint_text

    if link.type == 'ref_style_link' or link.type == 'shortcut_ref_link' then
        local source = link:get_source()
        local url = source:get_full_text()
        if url and url ~= '' then
            hint_text = { { '→ ' .. url, 'MkdnflowRefHint' } }
        end
    elseif link.type == 'ref_definition' then
        local name = link:get_name()
        local label = name and name.text or ''
        if label ~= '' then
            local count = count_refs(label, bufnr, link.start_row)
            local word = count == 1 and 'reference' or 'references'
            hint_text = { { '(' .. count .. ' ' .. word .. ')', 'MkdnflowRefHint' } }
        end
    end

    if hint_text then
        vim.api.nvim_buf_set_extmark(bufnr, ns, row, 0, {
            virt_text = hint_text,
            virt_text_pos = 'eol',
        })
    end
end

--- Attach CursorMoved autocmd with debounce to the current buffer
local function attach_to_buffer()
    local bufnr = vim.api.nvim_get_current_buf()

    vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
        buffer = bufnr,
        group = 'MkdnflowRefHint',
        callback = function()
            if not timers[bufnr] then
                -- TODO: Use vim.uv directly when v0.9.5 support is dropped
                timers[bufnr] = (vim.uv or vim.loop).new_timer()
            end
            timers[bufnr]:stop()
            timers[bufnr]:start(
                DEBOUNCE_MS,
                0,
                vim.schedule_wrap(function()
                    if vim.api.nvim_buf_is_valid(bufnr) then
                        update_hint(bufnr)
                    end
                end)
            )
        end,
    })

    -- Clean up timer when buffer is deleted
    vim.api.nvim_create_autocmd('BufDelete', {
        buffer = bufnr,
        group = 'MkdnflowRefHint',
        callback = function()
            if timers[bufnr] then
                timers[bufnr]:stop()
                timers[bufnr]:close()
                timers[bufnr] = nil
            end
        end,
    })
end

M.init = function()
    -- Set up default highlight group
    vim.api.nvim_set_hl(0, 'MkdnflowRefHint', { link = 'Comment', default = true })

    vim.api.nvim_create_augroup('MkdnflowRefHint', { clear = true })

    vim.api.nvim_create_autocmd('FileType', {
        pattern = require('mkdnflow').config.resolved_filetypes,
        callback = function()
            attach_to_buffer()
        end,
        group = 'MkdnflowRefHint',
    })
end

return M
