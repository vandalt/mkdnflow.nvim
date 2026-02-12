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

-- This module: Delimited data to markdown table conversion

local M = {}

local width = vim.api.nvim_strwidth

local function get_config()
    return require('mkdnflow').config
end

-- Candidate delimiters in priority order (most unambiguous first)
local DELIMITER_PRIORITY = { '\t', '|', ';', ',' }

--- Count occurrences of a delimiter in a line, ignoring delimiters inside double-quoted fields.
--- @param line string
--- @param delimiter string
--- @return integer
local function count_delimiter(line, delimiter)
    local count = 0
    local in_quotes = false
    local i = 1
    while i <= #line do
        local ch = line:sub(i, i)
        if ch == '"' then
            if in_quotes then
                -- Check for doubled quote (escaped quote inside quoted field)
                if i < #line and line:sub(i + 1, i + 1) == '"' then
                    i = i + 1 -- skip the second quote
                else
                    in_quotes = false
                end
            else
                in_quotes = true
            end
        elseif ch == delimiter and not in_quotes then
            count = count + 1
        end
        i = i + 1
    end
    return count
end

--- Detect the delimiter used in a set of lines.
--- @param lines string[] Array of lines
--- @return string The detected delimiter
function M.detectDelimiter(lines)
    -- Filter out empty lines
    local non_empty = {}
    for _, line in ipairs(lines) do
        local stripped = line:gsub('%s+$', '')
        if stripped ~= '' then
            table.insert(non_empty, stripped)
        end
    end

    if #non_empty == 0 then
        return ','
    end

    -- For each candidate delimiter, count occurrences per line
    local best_delimiter = ','
    local best_score = -1

    for _, delim in ipairs(DELIMITER_PRIORITY) do
        local counts = {}
        for _, line in ipairs(non_empty) do
            table.insert(counts, count_delimiter(line, delim))
        end

        -- Check consistency: all lines must have the same count >= 1
        local first_count = counts[1]
        if first_count >= 1 then
            local consistent = true
            for i = 2, #counts do
                if counts[i] ~= first_count then
                    consistent = false
                    break
                end
            end

            if consistent then
                -- Score: priority * count. Higher priority delimiters win ties.
                -- Since we iterate in priority order, the first consistent one wins
                -- if it has >= the best score
                local score = first_count
                if score > best_score then
                    best_score = score
                    best_delimiter = delim
                    -- First consistent delimiter in priority order wins
                    return best_delimiter
                end
            end
        end
    end

    -- If none are fully consistent, find the one with highest consistent count
    -- across the most lines
    if best_score < 0 then
        for _, delim in ipairs(DELIMITER_PRIORITY) do
            local counts = {}
            for _, line in ipairs(non_empty) do
                table.insert(counts, count_delimiter(line, delim))
            end

            -- Find the most common non-zero count
            local freq = {}
            for _, c in ipairs(counts) do
                if c >= 1 then
                    freq[c] = (freq[c] or 0) + 1
                end
            end

            for count, f in pairs(freq) do
                local score = count * f
                if score > best_score then
                    best_score = score
                    best_delimiter = delim
                end
            end
        end
    end

    return best_delimiter
end

--- Parse delimited data into a 2D array using an RFC 4180-style state machine.
--- @param lines string[] Array of lines
--- @param delimiter string The delimiter character
--- @return string[][] 2D array of cell content
function M.parseDelimited(lines, delimiter)
    -- Join lines into a single string for proper multiline quoted field handling
    local text = table.concat(lines, '\n')
    -- Strip trailing \r from each position (normalize \r\n)
    text = text:gsub('\r', '')

    local rows = {}
    local current_row = {}
    local current_field = {}
    local state = 'NORMAL' -- NORMAL or QUOTED
    local field_start = true -- true if we're at the start of a field
    local field_was_quoted = false -- true if this field started with a quote

    local function finish_field()
        local field_text = table.concat(current_field)
        -- Only trim whitespace from unquoted fields
        if not field_was_quoted then
            field_text = vim.trim(field_text)
        end
        table.insert(current_row, field_text)
        current_field = {}
        field_start = true
        field_was_quoted = false
    end

    local i = 1
    while i <= #text do
        local ch = text:sub(i, i)

        if state == 'NORMAL' then
            if ch == '"' and field_start then
                -- Enter quoted mode
                state = 'QUOTED'
                field_start = false
                field_was_quoted = true
            elseif ch == delimiter then
                finish_field()
            elseif ch == '\\' and i < #text and text:sub(i + 1, i + 1) == delimiter then
                -- Escaped delimiter in unquoted field
                table.insert(current_field, delimiter)
                field_start = false
                i = i + 1
            elseif ch == '\n' then
                finish_field()
                table.insert(rows, current_row)
                current_row = {}
            else
                table.insert(current_field, ch)
                if ch ~= ' ' and ch ~= '\t' then
                    field_start = false
                end
            end
        elseif state == 'QUOTED' then
            if ch == '"' then
                if i < #text and text:sub(i + 1, i + 1) == '"' then
                    -- Doubled quote: literal quote character
                    table.insert(current_field, '"')
                    i = i + 1
                else
                    -- End of quoted field
                    state = 'NORMAL'
                    field_start = false
                end
            else
                -- Literal content inside quoted field (preserve whitespace)
                table.insert(current_field, ch)
            end
        end

        i = i + 1
    end

    -- Don't forget the last field/row
    if #current_field > 0 or #current_row > 0 then
        finish_field()
    end
    if #current_row > 0 then
        table.insert(rows, current_row)
    end

    -- Equalize row lengths by padding shorter rows with empty strings
    local max_cols = 0
    for _, row in ipairs(rows) do
        if #row > max_cols then
            max_cols = #row
        end
    end
    for _, row in ipairs(rows) do
        while #row < max_cols do
            table.insert(row, '')
        end
    end

    return rows
end

--- Build a formatted pipe table from parsed data.
--- @param parsed_data string[][] 2D array of cell content
--- @param has_header boolean Whether first row is a header
--- @return string[] Array of formatted table lines
local function buildPipeTable(parsed_data, has_header)
    if #parsed_data == 0 then
        return {}
    end

    local config = get_config()
    local style = config.tables.style
    local cell_padding = style.cell_padding or 1
    local sep_padding = style.separator_padding or 1
    local outer_pipes = style.outer_pipes

    local num_cols = #parsed_data[1]
    local pad = string.rep(' ', cell_padding)
    local sep_pad = string.rep(' ', sep_padding)

    -- Calculate column widths (minimum 3 only when header separator is needed)
    local min_width = has_header and 3 or 1
    local col_widths = {}
    for i = 1, num_cols do
        col_widths[i] = min_width
    end
    for _, row in ipairs(parsed_data) do
        for col, cell in ipairs(row) do
            local w = width(cell)
            if w > col_widths[col] then
                col_widths[col] = w
            end
        end
    end

    -- Build formatted lines
    local lines = {}

    for row_idx, row in ipairs(parsed_data) do
        local parts = {}
        for col, cell in ipairs(row) do
            local target_width = col_widths[col]
            local diff = target_width - width(cell)
            if diff < 0 then
                diff = 0
            end
            local formatted = cell .. string.rep(' ', diff)
            table.insert(parts, pad .. formatted .. pad)
        end

        local line = table.concat(parts, '|')
        if outer_pipes then
            line = '|' .. line .. '|'
        end
        table.insert(lines, line)

        -- Insert separator after first row if has_header
        if row_idx == 1 and has_header then
            local sep_parts = {}
            for col = 1, num_cols do
                local target_width = col_widths[col]
                -- Adjust for padding difference between cell and separator
                local padding_diff = cell_padding - sep_padding
                local sep_width = target_width + 2 * padding_diff
                local formatted = string.rep('-', sep_width)
                table.insert(sep_parts, sep_pad .. formatted .. sep_pad)
            end
            local sep_line = table.concat(sep_parts, '|')
            if outer_pipes then
                sep_line = '|' .. sep_line .. '|'
            end
            table.insert(lines, sep_line)
        end
    end

    return lines
end

--- Build a formatted grid table from parsed data.
--- @param parsed_data string[][] 2D array of cell content
--- @param has_header boolean Whether first row is a header
--- @return string[] Array of formatted table lines
local function buildGridTable(parsed_data, has_header)
    local grid = require('mkdnflow.tables.grid')
    return grid.buildFromData(parsed_data, has_header)
end

--- Build a formatted markdown table from parsed data.
--- @param parsed_data string[][] 2D array of cell content
--- @param has_header boolean Whether first row is a header
--- @return string[] Array of formatted table lines
function M.buildTable(parsed_data, has_header)
    local config = get_config()
    local table_type = config.tables.type or 'pipe'

    if table_type == 'grid' then
        return buildGridTable(parsed_data, has_header)
    else
        return buildPipeTable(parsed_data, has_header)
    end
end

--- Paste delimited data from the system clipboard as a formatted markdown table.
--- Inserts the table below the current cursor line.
--- @param delimiter string|nil Explicit delimiter (auto-detected if nil)
--- @param has_header boolean Whether to treat the first row as a header
function M.pasteTable(delimiter, has_header)
    local clipboard = vim.fn.getreg('+')
    if not clipboard or clipboard == '' then
        return
    end

    -- Split clipboard content into lines
    local lines = vim.split(clipboard, '\n', { plain = true })

    -- Remove trailing empty line (common with clipboard)
    if #lines > 0 and lines[#lines]:match('^%s*$') then
        table.remove(lines)
    end

    if #lines == 0 then
        return
    end

    -- Detect delimiter if not provided
    if not delimiter then
        delimiter = M.detectDelimiter(lines)
    end

    -- Parse and build table
    local parsed = M.parseDelimited(lines, delimiter)
    if #parsed == 0 then
        return
    end

    local table_lines = M.buildTable(parsed, has_header)
    if #table_lines == 0 then
        return
    end

    -- Insert below current cursor line
    local cursor = vim.api.nvim_win_get_cursor(0)
    vim.api.nvim_buf_set_lines(0, cursor[1], cursor[1], false, table_lines)
end

--- Convert visually-selected delimited lines into a formatted markdown table.
--- Replaces the selected lines.
--- @param line1 integer Start line (1-indexed)
--- @param line2 integer End line (1-indexed)
--- @param delimiter string|nil Explicit delimiter (auto-detected if nil)
--- @param has_header boolean Whether to treat the first row as a header
function M.tableFromSelection(line1, line2, delimiter, has_header)
    local lines = vim.api.nvim_buf_get_lines(0, line1 - 1, line2, false)

    if #lines == 0 then
        return
    end

    -- Detect delimiter if not provided
    if not delimiter then
        delimiter = M.detectDelimiter(lines)
    end

    -- Parse and build table
    local parsed = M.parseDelimited(lines, delimiter)
    if #parsed == 0 then
        return
    end

    local table_lines = M.buildTable(parsed, has_header)
    if #table_lines == 0 then
        return
    end

    -- Replace the selected lines
    vim.api.nvim_buf_set_lines(0, line1 - 1, line2, false, table_lines)
end

return M
