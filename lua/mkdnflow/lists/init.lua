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

-- This module: List management public API

local core = require('mkdnflow.lists.core')
local ListItem = core.ListItem
local List = core.List

local M = {}

-- Export patterns for external use
M.patterns = core.patterns

-- Export classes for advanced use
M.ListItem = ListItem
M.List = List

--- Detect the list type of a line
--- @param line? string The line to check (uses current line if nil)
--- @return string|nil, string|nil # The list type ('ul', 'ol', 'ultd', 'oltd') and indentation, or nil if not a list
function M.hasListType(line)
    local match
    local i = 1
    local li_types = { 'ultd', 'oltd', 'ul', 'ol' }
    local result
    local indentation

    if line == nil then
        local row = vim.api.nvim_win_get_cursor(0)[1]
        line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]
    end

    while not match and i <= 4 do
        local li_type = li_types[i]
        match = string.match(line, M.patterns[li_type].main)
        if match then
            result = li_type
            indentation = line:match(M.patterns[li_type].indentation)
        else
            i = i + 1
        end
    end

    return result, indentation
end

--- Internal function to get siblings and their numbers
--- @param row integer The starting row
--- @param indentation string The indentation to match
--- @param li_type string The list type
--- @param up boolean Whether to scan upward first
--- @return integer[], string[] # Arrays of line numbers and list numbers
local function get_siblings(row, indentation, li_type, up)
    up = up == nil and true or up
    local orig_row = row
    local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]
    local number = M.patterns[li_type].number and line and line:match(M.patterns[li_type].number)
    local sibling_linenrs = {} -- Store line numbers of sibling list items
    local list_numbers = {} -- Store numbers of sibling list items

    if number then
        list_numbers = { number }
    end
    sibling_linenrs = { row }

    -- Look up till we find a parent or non-list-item
    local done = false
    local list_pos = 1
    local inc = up and -1 or 1

    while not done do
        local adj_line = (
            (up and row - 2 >= 0) and vim.api.nvim_buf_get_lines(0, row - 2, row - 1, true)[1]
        )
            or (up == false and vim.api.nvim_buf_get_lines(0, row, row + 1, false)[1])
            or nil

        if adj_line then
            local adj_li_type = M.hasListType(adj_line)
            if adj_li_type then
                local adj_indentation = string.match(adj_line, M.patterns[adj_li_type].indentation)
                    or nil
                if adj_li_type == li_type and adj_indentation == indentation then -- Add row
                    if number then
                        table.insert(
                            list_numbers,
                            up and list_pos or #list_numbers + 1,
                            adj_line:match(M.patterns[li_type].number)
                        )
                    end
                    table.insert(
                        sibling_linenrs,
                        up and list_pos or #sibling_linenrs + 1,
                        row + inc
                    )
                    row = row + inc
                elseif #adj_indentation > #indentation then -- List item is a child; keep looking
                    row = row + inc
                else
                    if up then -- Look downwards on the next iteration
                        up, row, inc = false, orig_row, 1
                    else -- Row is not a list item or indentation is lesser than original row
                        done = true
                    end
                end
            else
                if up then -- Look downwards on the next iteration
                    up, row, inc = false, orig_row, 1
                else -- Row is not a list item
                    done = true
                end
            end
        else -- Found no adjacent line
            if up then -- Look downwards on the next iteration
                up, row, inc = false, orig_row, 1
            else -- Row doesn't exist
                done = true
            end
        end
    end

    return sibling_linenrs, list_numbers
end

--- Internal function to update numbering for ordered lists
--- @param row integer The starting row
--- @param indentation string The indentation to match
--- @param li_type string The list type
--- @param up boolean Whether to scan upward first
--- @param start? integer The number to start from
local function update_numbering(row, indentation, li_type, up, start)
    local sibling_linenrs, list_numbers = get_siblings(row, indentation, li_type, up)
    local n = start

    for i, v in ipairs(list_numbers) do
        if not n then
            n = tonumber(v) + 1
        else
            if tonumber(v) ~= n then
                -- Replace with the correct number on that line
                local line = vim.api.nvim_buf_get_lines(
                    0,
                    sibling_linenrs[i] - 1,
                    sibling_linenrs[i],
                    false
                )[1]
                local replacement =
                    line:gsub('^' .. indentation .. '%d+%.', indentation .. n .. '.')
                vim.api.nvim_buf_set_lines(
                    0,
                    sibling_linenrs[i] - 1,
                    sibling_linenrs[i],
                    false,
                    { replacement }
                )
            end
            n = n + 1
        end
    end
end

--- Valid target types for changeListType
local valid_types = { ul = true, ol = true, ultd = true, oltd = true }

--- Convert a single list line from its current type to a target type.
--- Returns the converted line string, or nil if the line is not a list item or already the target type.
---@param line string The buffer line text
---@param target_type string One of 'ul', 'ol', 'ultd', 'oltd'
---@param number integer The number to use for ordered target types
---@param marker? string The unordered list marker to use ('-', '*', or '+'). Defaults to '-'.
---@return string|nil converted The converted line, or nil if no conversion needed
local function convert_line(line, target_type, number, marker)
    local source_type = M.hasListType(line)
    if not source_type then
        return nil
    end
    -- Skip if already the target type, unless a marker was specified for an
    -- unordered target (allows swapping bullet characters, e.g. - → *)
    if source_type == target_type and not marker then
        return nil
    end

    local indent = line:match(M.patterns[source_type].indentation) or ''
    local text = line:match(M.patterns[source_type].content) or ''

    -- Extract checkbox content if source is a to-do type
    local checkbox
    if source_type == 'ultd' or source_type == 'oltd' then
        checkbox = line:match('%[(..?.?.?)%]')
    end

    -- Determine checkbox for the target type
    if target_type == 'ultd' or target_type == 'oltd' then
        if not checkbox then
            -- Source is plain → use not_started marker from config
            local statuses = require('mkdnflow').config.to_do.statuses
            local not_started = vim.tbl_filter(function(t)
                return type(t) == 'table' and t.name == 'not_started'
            end, statuses)[1]
            checkbox = type(not_started.marker) == 'table' and not_started.marker[1]
                or not_started.marker
        end
    end

    -- Reconstruct the line with the target type's format
    marker = marker or '-'
    if target_type == 'ul' then
        return indent .. marker .. ' ' .. text
    elseif target_type == 'ol' then
        return indent .. tostring(number) .. '. ' .. text
    elseif target_type == 'ultd' then
        return indent .. marker .. ' [' .. checkbox .. '] ' .. text
    elseif target_type == 'oltd' then
        return indent .. tostring(number) .. '. [' .. checkbox .. '] ' .. text
    end
end

--- Change the list type of list items in scope.
--- Without a range, converts all siblings at the cursor's indentation level.
--- With a range (visual selection), converts all list items in the range.
---@param target_type string One of 'ul', 'ol', 'ultd', 'oltd'
---@param opts? {line1: integer, line2: integer, marker: string} Optional range and/or unordered marker
function M.changeListType(target_type, opts)
    opts = opts or {}

    if not valid_types[target_type] then
        vim.api.nvim_echo({
            { 'Mkdnflow: ', 'WarningMsg' },
            {
                "Invalid list type '" .. tostring(target_type) .. "'. Use ul, ol, ultd, or oltd.",
                'Normal',
            },
        }, true, {})
        return
    end

    local valid_markers = { ['-'] = true, ['*'] = true, ['+'] = true }
    local marker = opts.marker
    if marker and not valid_markers[marker] then
        vim.api.nvim_echo({
            { 'Mkdnflow: ', 'WarningMsg' },
            {
                "Invalid list marker '" .. tostring(marker) .. "'. Use -, *, or +.",
                'Normal',
            },
        }, true, {})
        return
    end

    local line_nrs
    if opts.line1 and opts.line2 then
        -- Visual selection: collect all lines in range
        line_nrs = {}
        for i = opts.line1, opts.line2 do
            table.insert(line_nrs, i)
        end
    else
        -- No selection: find siblings at the cursor's level
        local row = vim.api.nvim_win_get_cursor(0)[1]
        local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]
        local li_type, indentation = M.hasListType(line)
        if not li_type then
            return
        end
        line_nrs = get_siblings(row, indentation, li_type)
    end

    -- Track sequential numbering per indentation level for ordered targets.
    -- Reset when a non-list line breaks the sequence (separate lists get
    -- independent numbering).
    local number_by_indent = {}

    for _, line_nr in ipairs(line_nrs) do
        local line = vim.api.nvim_buf_get_lines(0, line_nr - 1, line_nr, false)[1]
        if not line then
            number_by_indent = {}
            goto continue
        end

        local source_type = M.hasListType(line)
        if not source_type then
            number_by_indent = {}
            goto continue
        end

        local indent = line:match(M.patterns[source_type].indentation) or ''

        -- Assign a sequential number for this indentation level
        local num = 1
        if target_type == 'ol' or target_type == 'oltd' then
            number_by_indent[indent] = (number_by_indent[indent] or 0) + 1
            num = number_by_indent[indent]
        end

        local converted = convert_line(line, target_type, num, marker)
        if converted then
            vim.api.nvim_buf_set_lines(0, line_nr - 1, line_nr, false, { converted })
        end

        ::continue::
    end
end

--- Compatibility wrapper for toggleToDo
--- @param opts? table Options table
function M.toggleToDo(opts)
    opts = opts or {}
    require('mkdnflow').to_do.toggle_to_do(opts)
end

--- Create a new list item
--- @param carry boolean Whether to carry text after cursor to new line
--- @param above boolean Whether to create the new item above the current line
--- @param cursor_moves boolean Whether to move cursor to new line
--- @param mode_after string The mode to end in ('n' or 'i')
--- @param alt? string Alternative keys to feed if not on a list line
--- @param line? string The line to check (uses current line if nil)
function M.newListItem(carry, above, cursor_moves, mode_after, alt, line)
    carry = (carry == nil and true) or (carry ~= nil and carry)
    above = above and true
    local current_mode = vim.api.nvim_get_mode()['mode']
    mode_after = mode_after or current_mode

    if mode_after ~= 'i' and mode_after ~= 'n' then
        mode_after = 'i'
    end

    -- Get the line and list type
    line = line or vim.api.nvim_get_current_line()
    local li_type = M.hasListType(line)

    if li_type then -- If the line has an item, do some stuff
        local has_contents = carry == false or string.match(line, M.patterns[li_type].content)
        local row, col = vim.api.nvim_win_get_cursor(0)[1], vim.api.nvim_win_get_cursor(0)[2]
        row = (above and row - 1) or row
        local indentation = string.match(line, M.patterns[li_type].indentation)

        if has_contents then
            local next_line = indentation
            local next_number

            if (not above) and line:sub(#line, #line) == ':' then
                -- If the current line ends in a colon, indent the next line
                next_line = next_line .. core.get_vim_indent()
                if li_type == 'ol' or li_type == 'oltd' then
                    next_number = 1
                    next_line = next_line .. next_number
                end
            else
                if li_type == 'ol' or li_type == 'oltd' then
                    local current_number = string.match(line, M.patterns[li_type].number)
                    next_number = (above and current_number) or current_number + 1
                    next_line = next_line .. next_number
                end
            end

            -- Add the marker
            next_line = next_line .. string.match(line, M.patterns[li_type].marker)

            if li_type == 'oltd' or li_type == 'ultd' then
                -- Make sure new to-do items have not_started status
                local to_do_not_started = vim.tbl_filter(function(t)
                    return type(t) == 'table' and t.name == 'not_started'
                end, require('mkdnflow').config.to_do.statuses)[1].marker
                next_line = next_line .. '[' .. to_do_not_started .. '] '
            end

            -- The current length is where we want the cursor to go
            local next_col = #next_line

            if (not above) and carry and col ~= #line then
                -- Add material from the current line if the cursor isn't @ end of line
                -- Get the material following the cursor for the next line
                next_line = next_line .. line:sub(col + 1, #line)
                -- Rid the current line of the material following the cursor
                vim.api.nvim_buf_set_text(0, row - 1, col, row - 1, #line, { '' })
            end

            -- Set the next line and move the cursor
            vim.api.nvim_buf_set_lines(0, row, row, false, { next_line })

            if cursor_moves then
                vim.api.nvim_win_set_cursor(0, { row + 1, next_col })
            end

            if li_type == 'ol' or li_type == 'oltd' then
                -- Update the numbering
                if above then
                    update_numbering(row + 1, indentation, li_type, false)
                else
                    update_numbering(row, indentation, li_type, false)
                end
            end

            if mode_after == 'i' then
                vim.cmd('startinsert')
                if cursor_moves and current_mode == 'n' then
                    vim.api.nvim_win_set_cursor(0, { row + 1, (next_col + 1) })
                end
            elseif mode_after == 'n' then
                vim.cmd('stopinsert')
            end
        else
            -- Empty item - demote
            local vim_indent = core.get_vim_indent()

            if line:match('^' .. vim_indent) then
                -- If the line is indented, demote by removing the indentation
                local replacement = line:gsub('^' .. vim_indent, '')
                local new_indentation = replacement:match(M.patterns[li_type].indentation)
                vim.api.nvim_buf_set_text(0, row - 1, 0, row - 1, #line, { replacement })
                -- Update w/ the new indentation
                update_numbering(row, new_indentation, li_type)
                -- Update any adopted children
                update_numbering(row + 1, new_indentation .. vim_indent, li_type, false, 1)
            else
                -- Otherwise, demote using the canonical demotion
                -- Make a new line with the demotion
                local demotion = string.match(line, M.patterns[li_type].demotion)
                vim.api.nvim_buf_set_lines(0, row - 1, row, false, { demotion })
                vim.api.nvim_win_set_cursor(0, { row, #demotion })
                update_numbering(row - 1, indentation, li_type, false)
                -- Update any subsequent ordered list items that had the same indentation
                if vim.api.nvim_buf_get_lines(0, row, row + 1, false)[1] then
                    update_numbering(row + 1, indentation, li_type, false, 1)
                end
            end
        end
    elseif alt then
        -- Feed the requested keys
        vim.api.nvim_feedkeys(vim.keycode(alt), 'n', true)
    end
end

--- Update numbering for ordered lists
--- @param opts? table Options table, opts[1] is the starting number
--- @param offset? integer Line offset from cursor
function M.updateNumbering(opts, offset)
    opts = opts or {}
    offset = offset or 0
    local start = opts[1] or 1
    local row = vim.api.nvim_win_get_cursor(0)[1]

    if row + offset <= vim.api.nvim_buf_line_count(0) then
        row = row + offset
        local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]
        local li_type, indentation = M.hasListType(line)

        if li_type ~= nil then
            update_numbering(row, indentation, li_type, true, start)
        end
    end
end

return M
