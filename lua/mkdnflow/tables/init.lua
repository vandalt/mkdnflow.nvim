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

-- Tables module entry point
-- This module provides the public API for table operations using a class-based
-- architecture (TableCell, TableRow, MarkdownTable).

local core = require('mkdnflow.tables.core')

-- Import classes for direct access
local TableCell = core.TableCell
local TableRow = core.TableRow
local MarkdownTable = core.MarkdownTable

-- =============================================================================
-- Helper Functions
-- =============================================================================

--- Check if a line is a continuation line (follows a row ending with \)
--- For grid tables, a content line is a continuation if the line above is also
--- a content line (not a border).
--- @param linenr integer The line number to check
--- @return boolean, integer|nil is_continuation, primary_row_linenr
local function is_continuation_line(linenr)
    if linenr < 2 then
        return false, nil
    end

    local line = vim.api.nvim_buf_get_lines(0, linenr - 1, linenr, false)[1]

    -- Grid table continuation: a content line whose previous line is also a content line
    -- (both are | ... | lines, and previous is not a border)
    if line and line:match('^%s*|') then
        local prev_line = vim.api.nvim_buf_get_lines(0, linenr - 2, linenr - 1, false)[1]
        if prev_line and prev_line:match('^%s*|') and not MarkdownTable.isGridBorder(prev_line) then
            -- Both are content lines — check if we're in a grid table context
            if MarkdownTable._isGridContext(linenr) then
                -- Walk up to find the first content line after a border (the primary row)
                local check = linenr - 1
                while check >= 1 do
                    local cl = vim.api.nvim_buf_get_lines(0, check - 1, check, false)[1]
                    if not cl or MarkdownTable.isGridBorder(cl) then
                        return true, check + 1
                    end
                    check = check - 1
                end
                return true, 1
            end
        end
    end

    return false, nil
end

--- Find the next primary table row after a given line (skipping continuations)
--- @param linenr integer Starting line number
--- @param direction integer 1 for down, -1 for up
--- @return integer|nil Next primary row line number
local function find_next_primary_row(linenr, direction)
    local line_count = vim.api.nvim_buf_line_count(0)
    local check_linenr = linenr + direction

    while check_linenr >= 1 and check_linenr <= line_count do
        local line = vim.api.nvim_buf_get_lines(0, check_linenr - 1, check_linenr, false)[1]
        if not line then
            return nil
        end

        if MarkdownTable.isGridBorder(line) then
            -- Skip grid border lines
        elseif line:match('^%s*|') then
            -- Check if this is a continuation line in a grid table
            local is_cont, _ = is_continuation_line(check_linenr)
            if not is_cont then
                -- A primary row starts with |
                return check_linenr
            end
            -- It's a continuation line, keep scanning
        elseif not MarkdownTable.isPartOfTable(line, check_linenr) then
            -- Not a table line at all, we've left the table
            return nil
        end

        check_linenr = check_linenr + direction
    end

    return nil
end

-- =============================================================================
-- Public API
-- =============================================================================

local M = {}

--- Check if text is part of a markdown table
--- @param text string The line text to check
--- @param linenr? integer Optional line number for context-aware detection
--- @return boolean
function M.isPartOfTable(text, linenr)
    -- Use the new class implementation
    return MarkdownTable.isPartOfTable(text, linenr)
end

--- Create a new markdown table at cursor position
--- @param opts table Options: {cols, rows, header?}
function M.newTable(opts)
    local cols, rows, header = opts[1], opts[2], opts[3]
    cols, rows = tonumber(cols), tonumber(rows)

    -- Parse header option
    if header and header:match('noh') then
        header = false
    else
        header = true
    end

    MarkdownTable:create(cols, rows, header)
end

--- Format the table under the cursor
function M.formatTable()
    local config = require('mkdnflow').config
    local position = vim.api.nvim_win_get_cursor(0)

    -- Check if cursor is on a continuation line, and if so, use the primary row
    local is_cont, primary_row_nr = is_continuation_line(position[1])
    local effective_line = is_cont and primary_row_nr or position[1]

    local tbl = MarkdownTable:read(effective_line)
    if tbl.valid then
        tbl:format()
    else
        if not config.silent then
            vim.api.nvim_echo({
                { '⬇️  Table formatting failed.', 'WarningMsg' },
            }, true, {})
        end
    end
end

--- Navigate to a different cell in the table
--- @param row_offset integer Row offset (positive = down, negative = up)
--- @param cell_offset integer Cell offset (positive = right, negative = left)
function M.moveToCell(row_offset, cell_offset)
    row_offset = row_offset or 0
    cell_offset = cell_offset or 0
    local config = require('mkdnflow').config
    local position = vim.api.nvim_win_get_cursor(0)

    -- Check if cursor is on a grid border line; if so, redirect to nearest content line
    local current_line_raw = vim.api.nvim_buf_get_lines(0, position[1] - 1, position[1], false)[1]
    if MarkdownTable.isGridBorder(current_line_raw) then
        -- Find the nearest content line (prefer direction of movement, default down)
        local dir = row_offset ~= 0 and (row_offset > 0 and 1 or -1)
            or (cell_offset >= 0 and 1 or -1)
        local content_line_nr = find_next_primary_row(position[1], dir)
        if content_line_nr then
            vim.api.nvim_win_set_cursor(0, { content_line_nr, position[2] })
            position = vim.api.nvim_win_get_cursor(0)
        end
    end

    -- Check if cursor is on a continuation line, and if so, use the primary row
    local is_cont, primary_row_nr = is_continuation_line(position[1])
    local effective_position = is_cont and primary_row_nr or position[1]

    -- Check if this is a complete table (has separator row)
    local current_line =
        vim.api.nvim_buf_get_lines(0, effective_position - 1, effective_position, false)[1]
    if MarkdownTable.isPartOfTable(current_line, effective_position) then
        local table_data = MarkdownTable:read(effective_position)
        if not table_data.valid then
            -- Incomplete table (no separator row), pass through the keypress
            if row_offset ~= 0 then
                -- Moving vertically (Enter key) - insert newline
                vim.api.nvim_feedkeys(
                    vim.api.nvim_replace_termcodes('<CR>', true, false, true),
                    'n',
                    true
                )
            else
                -- Moving horizontally (Tab key) - insert tab
                vim.api.nvim_feedkeys(
                    vim.api.nvim_replace_termcodes('<C-I>', true, false, true),
                    'n',
                    true
                )
            end
            return
        end
    end

    -- Figure out which cell the cursor is currently in
    local current_row = TableRow:from_string(current_line, effective_position)
    local cursor_cell
    if is_cont then
        -- On a continuation line, cursor is always in the last cell of the primary row
        cursor_cell = #current_row.cells
    else
        cursor_cell = current_row:which_cell(position[2])
    end
    local line_count = vim.api.nvim_buf_line_count(0)

    -- Calculate target row, accounting for multiline rows
    local row
    if row_offset ~= 0 then
        -- For vertical navigation, find the next/previous primary row
        row = find_next_primary_row(effective_position, row_offset > 0 and 1 or -1)
        if not row then
            row = effective_position + row_offset
        end
        -- Handle multiple row offsets (e.g., row_offset = 2)
        local abs_offset = math.abs(row_offset)
        for _ = 2, abs_offset do
            local next_row = find_next_primary_row(row, row_offset > 0 and 1 or -1)
            if next_row then
                row = next_row
            else
                break
            end
        end
    else
        row = effective_position
    end

    if row > line_count then
        row = line_count
    end
    if row < 1 then
        row = 1
    end

    local target_line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]
    local target_row = target_line and TableRow:from_string(target_line, row) or nil

    if target_row and (target_row.is_separator or MarkdownTable.isGridBorder(target_line)) then
        -- Skip separator rows and grid border lines
        local next_offset = row_offset + (row_offset < 0 and -1 or 1)
        local next_row = position[1] + next_offset

        if next_row >= 1 and next_row <= line_count then
            local next_line = vim.api.nvim_buf_get_lines(0, next_row - 1, next_row, false)[1]
            local next_row_obj = next_line and TableRow:from_string(next_line, next_row) or nil
            if
                next_row_obj
                and MarkdownTable.isPartOfTable(next_line, next_row)
                and not next_row_obj.is_separator
                and not MarkdownTable.isGridBorder(next_line)
            then
                M.moveToCell(next_offset, cell_offset)
                return
            end
        end

        -- No valid non-separator row found
        if row_offset > 0 then
            if config.tables.auto_extend_rows then
                M.addRow()
                M.moveToCell(1, 0)
            else
                local current_line_count = vim.api.nvim_buf_line_count(0)
                if current_line_count == position[1] then
                    vim.api.nvim_buf_set_lines(0, position[1], position[1], false, { '' })
                end
                if config.tables.format_on_move then
                    local tbl = MarkdownTable:read(position[1])
                    if tbl.valid then
                        tbl:format()
                    end
                end
                vim.api.nvim_win_set_cursor(0, { position[1] + 1, 0 })
            end
        end
    elseif target_line and MarkdownTable.isPartOfTable(target_line, row) then
        local table_rows = MarkdownTable:read(row)

        if config.tables.format_on_move and table_rows.valid then
            table_rows:format()
            target_line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]
        end

        local ncols = table_rows.col_count
        local target_cell = cell_offset + cursor_cell

        -- Handle column wrapping
        if cell_offset > 0 and target_cell > ncols then
            if config.tables.auto_extend_cols then
                M.addCol()
                M.moveToCell(row_offset, cell_offset)
            else
                local quotient = math.floor(target_cell / ncols)
                row_offset, cell_offset = row_offset + quotient, (ncols - cell_offset) * -1
                M.moveToCell(row_offset, cell_offset)
            end
        elseif cell_offset < 0 and target_cell < 1 then
            local quotient = math.abs(math.floor((target_cell - 1) / ncols))
            row_offset, cell_offset = row_offset - quotient, target_cell + (ncols * quotient) - 1
            M.moveToCell(row_offset, cell_offset)
        else
            -- Navigate to the cell
            local target_row_obj = TableRow:from_string(target_line, row)
            local cell_start, _ = target_row_obj:locate_cell(target_cell)
            vim.api.nvim_win_set_cursor(0, { row, cell_start - 1 })
        end
    else
        -- Target line is not part of a table
        if position[1] == row then
            vim.api.nvim_feedkeys(
                vim.api.nvim_replace_termcodes('<C-I>', true, false, true),
                'n',
                true
            )
        elseif row_offset == 1 and cell_offset == 0 then
            if config.tables.auto_extend_rows then
                M.addRow()
                M.moveToCell(1, 0)
            else
                if vim.api.nvim_buf_line_count(0) == position[1] then
                    vim.api.nvim_buf_set_lines(0, position[1] + 1, position[1] + 1, false, { '' })
                end
                if config.tables.format_on_move then
                    local tbl = MarkdownTable:read(row - 1)
                    if tbl.valid then
                        tbl:format()
                    end
                end
                vim.api.nvim_win_set_cursor(0, { position[1] + 1, 1 })
            end
        end
    end
end

--- Add a new row to the table
--- @param offset? integer Position offset (0 = below cursor, -1 = above cursor)
function M.addRow(offset)
    local tbl = MarkdownTable:read()
    tbl:add_row(offset)
end

--- Add a new column to the table
--- @param offset? integer Position offset (0 = after current, -1 = before current)
function M.addCol(offset)
    local tbl = MarkdownTable:read()
    tbl:add_col(offset)
end

--- Delete the current row from the table
function M.deleteRow()
    local tbl = MarkdownTable:read()
    tbl:delete_row()
end

--- Delete the current column from the table
function M.deleteCol()
    local tbl = MarkdownTable:read()
    tbl:delete_col()
end

--- Insert a new line within the current table cell.
--- Grid tables: inserts a new empty content line within the current row.
--- Pipe tables: inserts a `<br>` tag at the cursor position.
--- @return string|nil Fallback key if not in a table, nil if handled
function M.cellNewLine()
    local position = vim.api.nvim_win_get_cursor(0)
    local line = vim.api.nvim_get_current_line()

    if not MarkdownTable.isPartOfTable(line, position[1]) then
        return vim.api.nvim_replace_termcodes('<S-CR>', true, false, true)
    end

    -- Check if on a continuation line; use primary row for context
    local is_cont, primary_row_nr = is_continuation_line(position[1])
    local effective_line = is_cont and primary_row_nr or position[1]

    if MarkdownTable._isGridContext(effective_line) then
        -- Grid table: insert new content line within the row
        local tbl = MarkdownTable:read(effective_line)
        if tbl.valid then
            require('mkdnflow.tables.grid').add_cell_line(tbl, position)
        end
    else
        -- Pipe table: insert <br> at cursor position
        local row = position[1]
        local col = position[2]
        local current_line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]
        local before = current_line:sub(1, col)
        local after = current_line:sub(col + 1)
        local new_line = before .. '<br>' .. after
        vim.api.nvim_buf_set_lines(0, row - 1, row, false, { new_line })
        vim.api.nvim_win_set_cursor(0, { row, col + 4 })
    end
    return nil
end

--- Set the alignment of the column under the cursor
--- @param alignment string One of 'left', 'right', 'center', 'default'
function M.alignCol(alignment)
    local position = vim.api.nvim_win_get_cursor(0)
    local is_cont, primary_row_nr = is_continuation_line(position[1])
    local effective_line = is_cont and primary_row_nr or position[1]

    local tbl = MarkdownTable:read(effective_line)
    if not tbl.valid or #tbl.rows == 0 then
        return
    end

    -- Find cursor's column
    local current_row = tbl:get_row(position[1])
    if not current_row then
        -- Cursor on grid border/continuation - find first content row
        for _, row in ipairs(tbl.rows) do
            if not row.is_separator then
                current_row = row
                break
            end
        end
    end
    if not current_row then
        return
    end

    local col_idx = current_row:which_cell(position[2])
    if not col_idx or col_idx < 1 or col_idx > tbl.col_count then
        return
    end

    -- Update alignment and reformat
    tbl.metadata.col_alignments[col_idx] = alignment
    tbl:format()
end

-- =============================================================================
-- Export classes for advanced usage
-- =============================================================================

M.TableCell = TableCell
M.TableRow = TableRow
M.MarkdownTable = MarkdownTable

return M
