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

-- This module: Pandoc grid table support

local M = {}

-- Lazy accessors to avoid circular require with core.lua
local function get_core()
    return require('mkdnflow.tables.core')
end

local function get_config()
    return require('mkdnflow').config
end

-- Display width helper (handles multi-byte characters)
local width = vim.api.nvim_strwidth

-- =============================================================================
-- Helper Functions
-- =============================================================================

--- Parse column boundaries from a border line.
--- Returns array of {start, finish} byte positions of the content areas between + characters.
--- @param border_line string A grid border like "+---+---+---+"
--- @return table[] Array of {start=int, finish=int} positions
local function parse_col_boundaries(border_line)
    local boundaries = {}
    local trimmed = border_line:match('^%s*(.*)$')
    -- Find positions of + characters
    local plus_positions = {}
    for i = 1, #trimmed do
        if trimmed:sub(i, i) == '+' then
            table.insert(plus_positions, i)
        end
    end
    -- Each pair of adjacent + positions defines a column
    for i = 1, #plus_positions - 1 do
        table.insert(boundaries, {
            start = plus_positions[i] + 1,
            finish = plus_positions[i + 1] - 1,
        })
    end
    return boundaries
end

--- Extract cell content from a content line using column boundaries.
--- Falls back to pipe-based parsing when content overflows the border boundaries
--- (e.g. user typed content wider than the current column borders).
--- @param content_line string A grid content line like "| cell1 | cell2 |"
--- @param col_boundaries table[] From parse_col_boundaries
--- @return string[] Array of cell content strings (trimmed)
local function slice_cells(content_line, col_boundaries)
    local cells = {}
    local trimmed = content_line:match('^%s*(.*)$')

    -- Check if content line length doesn't match the border boundaries.
    -- If the content is shorter or wider than the border, pipe positions
    -- won't align with border + positions, so fall back to pipe-based parsing.
    local border_end = col_boundaries[#col_boundaries]
            and (col_boundaries[#col_boundaries].finish + 1)
        or 0
    if #trimmed ~= border_end then
        -- Content overflows borders — parse by | positions instead
        local pipe_positions = {}
        for i = 1, #trimmed do
            if trimmed:sub(i, i) == '|' then
                table.insert(pipe_positions, i)
            end
        end
        for i = 1, #pipe_positions - 1 do
            local cell_text = trimmed:sub(pipe_positions[i] + 1, pipe_positions[i + 1] - 1)
            cell_text = vim.trim(cell_text)
            table.insert(cells, cell_text)
        end
        while #cells < #col_boundaries do
            table.insert(cells, '')
        end
        return cells
    end

    for _, boundary in ipairs(col_boundaries) do
        local cell_text = ''
        if boundary.start <= #trimmed and boundary.finish <= #trimmed then
            cell_text = trimmed:sub(boundary.start, boundary.finish)
        elseif boundary.start <= #trimmed then
            cell_text = trimmed:sub(boundary.start)
        end
        -- Remove leading/trailing pipe and whitespace
        cell_text = vim.trim(cell_text)
        table.insert(cells, cell_text)
    end
    return cells
end

--- Build a grid border line from column widths.
--- @param col_widths integer[] Column widths (content widths, not including padding)
--- @param padding integer Padding per side
--- @param char string '-' or '='
--- @param alignments? string[] Optional alignment markers per column
--- @return string
local function build_border(col_widths, padding, char, alignments)
    local parts = { '+' }
    for i, w in ipairs(col_widths) do
        local segment_width = w + 2 * padding
        local fill = char
        local left_marker = fill
        local right_marker = fill
        if alignments and alignments[i] then
            local a = alignments[i]
            if a == 'left' then
                left_marker = ':'
            elseif a == 'right' then
                right_marker = ':'
            elseif a == 'center' then
                left_marker = ':'
                right_marker = ':'
            end
        end
        local middle_count = segment_width - 2
        if middle_count < 0 then
            middle_count = 0
        end
        table.insert(parts, left_marker .. string.rep(fill, middle_count) .. right_marker .. '+')
    end
    return table.concat(parts)
end

--- Build a content line from cell texts with proper padding.
--- @param cell_texts string[] Content for each cell
--- @param col_widths integer[] Column widths
--- @param padding integer Padding per side
--- @param alignments? string[] Column alignments
--- @return string
local function build_content_line(cell_texts, col_widths, padding, alignments)
    local pad = string.rep(' ', padding)
    local parts = { '|' }
    local config = get_config()
    local mimic = config.tables.style.apply_alignment
    for i, w in ipairs(col_widths) do
        local content = cell_texts[i] or ''
        local content_width = width(content)
        local diff = w - content_width
        if diff < 0 then
            diff = 0
        end
        local formatted
        local alignment = alignments and alignments[i] or 'default'
        if alignment == 'right' and mimic then
            formatted = string.rep(' ', diff) .. content
        elseif alignment == 'center' and mimic then
            local left_fill = string.rep(' ', math.floor(diff / 2))
            local right_fill = string.rep(' ', diff - #left_fill)
            formatted = left_fill .. content .. right_fill
        else
            formatted = content .. string.rep(' ', diff)
        end
        table.insert(parts, pad .. formatted .. pad .. '|')
    end
    return table.concat(parts)
end

--- Parse alignment from a grid header separator segment.
--- @param segment string e.g. "===", ":===", "===:", ":===:"
--- @return string 'left'|'right'|'center'|'default'
local function parse_segment_alignment(segment)
    local trimmed = vim.trim(segment)
    if trimmed:match('^:=+:$') then
        return 'center'
    elseif trimmed:match('^:=+$') then
        return 'left'
    elseif trimmed:match('^=+:$') then
        return 'right'
    else
        return 'default'
    end
end

-- =============================================================================
-- Grid Table Reading
-- =============================================================================

--- Read a grid table from the buffer starting at a line number.
--- @param line_nr integer Starting line number (1-indexed)
--- @return table MarkdownTable instance
function M.read(line_nr)
    local core = get_core()
    local MarkdownTable = core.MarkdownTable
    local TableRow = core.TableRow
    local TableCell = core.TableCell

    local tbl = MarkdownTable:new()
    tbl.table_type = 'grid'

    local line_count = vim.api.nvim_buf_line_count(0)

    -- Scan up from line_nr to find top border
    local top = line_nr
    while top > 1 do
        local l = vim.api.nvim_buf_get_lines(0, top - 2, top - 1, false)[1]
        if not l or l:match('^%s*$') then
            break
        end
        if MarkdownTable.isGridBorder(l) or l:match('^%s*|') then
            top = top - 1
        else
            break
        end
    end

    -- Scan down from line_nr to find bottom border
    local bottom = line_nr
    while bottom < line_count do
        local l = vim.api.nvim_buf_get_lines(0, bottom, bottom + 1, false)[1]
        if not l or l:match('^%s*$') then
            break
        end
        if MarkdownTable.isGridBorder(l) or l:match('^%s*|') then
            bottom = bottom + 1
        else
            break
        end
    end

    tbl.line_range = { start = top, finish = bottom }

    -- Read all lines in the range
    local all_lines = vim.api.nvim_buf_get_lines(0, top - 1, bottom, false)
    if #all_lines == 0 then
        return tbl
    end

    -- Find the first border line to parse column boundaries
    local first_border = nil
    for _, l in ipairs(all_lines) do
        if MarkdownTable.isGridBorder(l) then
            first_border = l
            break
        end
    end
    if not first_border then
        return tbl
    end

    local col_boundaries = parse_col_boundaries(first_border)
    tbl.col_count = #col_boundaries

    -- Initialize alignments
    tbl.metadata.col_alignments = {}
    for _ = 1, tbl.col_count do
        table.insert(tbl.metadata.col_alignments, 'default')
    end

    -- Walk all lines, grouping content between borders into logical rows
    local current_content_lines = {}
    local current_content_line_nrs = {}
    local border_count = 0
    local header_separator_found = false
    local rows_before_header = 0

    for idx, l in ipairs(all_lines) do
        local buf_line_nr = top + idx - 1
        if MarkdownTable.isGridBorder(l) then
            border_count = border_count + 1
            -- If we have accumulated content lines, create a logical row
            if #current_content_lines > 0 then
                -- Parse cells from content lines
                local row_cells = {}
                local max_lines_per_cell = {}

                -- Initialize cells
                for col = 1, tbl.col_count do
                    row_cells[col] = {}
                    max_lines_per_cell[col] = 0
                end

                -- Slice each content line into cells
                for _, content_line in ipairs(current_content_lines) do
                    local cell_texts = slice_cells(content_line, col_boundaries)
                    for col = 1, tbl.col_count do
                        table.insert(row_cells[col], cell_texts[col] or '')
                        max_lines_per_cell[col] = max_lines_per_cell[col] + 1
                    end
                end

                -- Build the primary content line (first content line)
                -- and store rest as continuation_lines
                local primary_line = current_content_lines[1]
                local primary_line_nr = current_content_line_nrs[1]
                local continuation_lines = {}
                for ci = 2, #current_content_lines do
                    table.insert(continuation_lines, current_content_lines[ci])
                end

                -- Create TableRow from the primary line
                local row = TableRow:new({
                    line_nr = primary_line_nr,
                    raw_content = primary_line,
                    is_separator = false,
                    is_header = false,
                    has_outer_pipes = true,
                    outer_pipe_side = 'both',
                    continuation_lines = continuation_lines,
                })

                -- Parse cells from the primary line
                local primary_cells = slice_cells(primary_line, col_boundaries)
                for col = 1, tbl.col_count do
                    local content = primary_cells[col] or ''
                    table.insert(
                        row.cells,
                        TableCell:new({
                            content = content,
                            raw_content = content,
                            display_width = width(content),
                            col_index = col,
                            is_separator = false,
                        })
                    )
                end

                -- Store multiline cell data in row metadata for formatting
                row.grid_cells = row_cells
                row.grid_line_nrs = current_content_line_nrs

                table.insert(tbl.rows, row)

                if not header_separator_found then
                    rows_before_header = rows_before_header + 1
                end

                current_content_lines = {}
                current_content_line_nrs = {}
            end

            -- Check if this is a header separator
            if MarkdownTable.isGridHeaderSeparator(l) then
                header_separator_found = true
                tbl.metadata.separator_row_idx = buf_line_nr
                -- Parse alignment from header separator
                local trimmed = l:match('^%s*(.*)$')
                local plus_positions = {}
                for i = 1, #trimmed do
                    if trimmed:sub(i, i) == '+' then
                        table.insert(plus_positions, i)
                    end
                end
                for col = 1, math.min(#plus_positions - 1, tbl.col_count) do
                    local seg = trimmed:sub(plus_positions[col] + 1, plus_positions[col + 1] - 1)
                    tbl.metadata.col_alignments[col] = parse_segment_alignment(seg)
                end
            end
        else
            -- Content line
            table.insert(current_content_lines, l)
            table.insert(current_content_line_nrs, buf_line_nr)
        end
    end

    -- Mark header rows
    if header_separator_found and rows_before_header > 0 then
        for i = 1, rows_before_header do
            if tbl.rows[i] then
                tbl.rows[i].is_header = true
                tbl.metadata.header_row_idx = tbl.rows[1].line_nr
            end
        end
    end

    -- A grid table is valid when it has at least 2 border lines and at least 1 content row
    if border_count >= 2 and #tbl.rows >= 1 then
        tbl.valid = true
    end

    -- Calculate column widths
    tbl.col_widths = {}
    for i = 1, tbl.col_count do
        tbl.col_widths[i] = 3 -- minimum
    end

    for _, row in ipairs(tbl.rows) do
        if row.grid_cells then
            for col = 1, tbl.col_count do
                if row.grid_cells[col] then
                    for _, cell_line in ipairs(row.grid_cells[col]) do
                        local w = width(cell_line)
                        if w > tbl.col_widths[col] then
                            tbl.col_widths[col] = w
                        end
                    end
                end
            end
        else
            -- Fallback: use cells from the row
            for col, cell in ipairs(row.cells) do
                if cell.display_width > (tbl.col_widths[col] or 3) then
                    tbl.col_widths[col] = cell.display_width
                end
            end
        end
    end

    return tbl
end

-- =============================================================================
-- Grid Table Formatting
-- =============================================================================

--- Format a grid table and write to buffer.
--- @param tbl table MarkdownTable instance with table_type='grid'
function M.format(tbl)
    if not tbl.valid or #tbl.rows == 0 then
        return
    end

    local config = get_config()
    local padding = config.tables.style.cell_padding or 1

    -- Recalculate column widths from all content lines
    tbl.col_widths = {}
    for i = 1, tbl.col_count do
        tbl.col_widths[i] = 3
    end

    for _, row in ipairs(tbl.rows) do
        if row.grid_cells then
            for col = 1, tbl.col_count do
                if row.grid_cells[col] then
                    for _, cell_line in ipairs(row.grid_cells[col]) do
                        local w = width(cell_line)
                        if w > tbl.col_widths[col] then
                            tbl.col_widths[col] = w
                        end
                    end
                end
            end
        else
            for col, cell in ipairs(row.cells) do
                if cell.display_width > (tbl.col_widths[col] or 3) then
                    tbl.col_widths[col] = cell.display_width
                end
            end
        end
    end

    local alignments = tbl.metadata.col_alignments
    local formatted_lines = {}

    -- Top border
    table.insert(formatted_lines, build_border(tbl.col_widths, padding, '-'))

    for row_idx, row in ipairs(tbl.rows) do
        -- Determine how many content lines this row needs
        local max_content_lines = 1
        if row.grid_cells then
            for col = 1, tbl.col_count do
                if row.grid_cells[col] and #row.grid_cells[col] > max_content_lines then
                    max_content_lines = #row.grid_cells[col]
                end
            end
        end

        -- Output content lines
        for line_idx = 1, max_content_lines do
            local cell_texts = {}
            for col = 1, tbl.col_count do
                if row.grid_cells and row.grid_cells[col] and row.grid_cells[col][line_idx] then
                    cell_texts[col] = row.grid_cells[col][line_idx]
                else
                    cell_texts[col] = ''
                end
            end
            table.insert(
                formatted_lines,
                build_content_line(cell_texts, tbl.col_widths, padding, alignments)
            )
        end

        -- Border after this row
        -- Header separator uses = with alignment markers, others use -
        local is_header_row = row.is_header
        -- Check if next row is NOT a header (meaning this row's border is the header separator)
        local next_row = tbl.rows[row_idx + 1]
        if is_header_row and (not next_row or not next_row.is_header) then
            table.insert(formatted_lines, build_border(tbl.col_widths, padding, '=', alignments))
        else
            table.insert(formatted_lines, build_border(tbl.col_widths, padding, '-'))
        end
    end

    -- Write to buffer
    vim.api.nvim_buf_set_lines(
        0,
        tbl.line_range.start - 1,
        tbl.line_range.finish,
        true,
        formatted_lines
    )
end

-- =============================================================================
-- Grid Table Creation
-- =============================================================================

--- Create a new grid table in the buffer.
--- @param cols integer Number of columns
--- @param rows integer Number of data rows
--- @param header boolean Whether to include header row
--- @return table MarkdownTable instance
function M.create(cols, rows, header)
    local core = get_core()
    local MarkdownTable = core.MarkdownTable

    local config = get_config()
    local padding = config.tables.style.cell_padding or 1
    local min_width = 3

    local col_widths = {}
    for _ = 1, cols do
        table.insert(col_widths, min_width)
    end

    local cursor = vim.api.nvim_win_get_cursor(0)

    local new_lines = {}
    local border = build_border(col_widths, padding, '-')
    local header_sep = build_border(col_widths, padding, '=')
    local empty_cells = {}
    for _ = 1, cols do
        table.insert(empty_cells, '')
    end
    local content_line = build_content_line(empty_cells, col_widths, padding)

    -- Build table structure
    table.insert(new_lines, border)
    if header then
        table.insert(new_lines, content_line) -- header row
        table.insert(new_lines, header_sep)
    end
    for _ = 1, rows do
        table.insert(new_lines, content_line) -- data row
        table.insert(new_lines, border)
    end
    -- If no header, the top border is already added; just need data rows
    -- Actually, if header=false but we already added the top border and data rows,
    -- we need to adjust: headerless means no === line
    if not header then
        -- Already correct: border + N*(content_line + border)
    end

    vim.api.nvim_buf_set_lines(0, cursor[1], cursor[1], false, new_lines)

    return MarkdownTable:read(cursor[1] + 1)
end

-- =============================================================================
-- Grid Table Row Operations
-- =============================================================================

--- Add a new row to a grid table.
--- @param tbl table MarkdownTable instance
--- @param offset? integer Position offset (0 = below cursor, -1 = above cursor)
function M.add_row(tbl, offset)
    offset = offset or 0
    local core = get_core()
    local MarkdownTable = core.MarkdownTable

    local cursor = vim.api.nvim_win_get_cursor(0)
    local config = get_config()
    local padding = config.tables.style.cell_padding or 1

    -- Find which logical row the cursor is on
    local target_row = nil
    local target_row_idx = nil
    for idx, row in ipairs(tbl.rows) do
        local row_start = row.line_nr
        local row_end = row.line_nr + #row.continuation_lines
        if cursor[1] >= row_start and cursor[1] <= row_end then
            target_row = row
            target_row_idx = idx
            break
        end
    end

    -- If cursor is on a border line, find the closest row
    if not target_row then
        for idx, row in ipairs(tbl.rows) do
            if row.line_nr >= cursor[1] then
                target_row = row
                target_row_idx = idx
                break
            end
        end
        if not target_row and #tbl.rows > 0 then
            target_row = tbl.rows[#tbl.rows]
            target_row_idx = #tbl.rows
        end
    end

    if not target_row then
        return
    end

    -- Build new empty content line and border
    local empty_cells = {}
    for _ = 1, tbl.col_count do
        table.insert(empty_cells, '')
    end
    local content_line = build_content_line(empty_cells, tbl.col_widths, padding)
    local border = build_border(tbl.col_widths, padding, '-')

    -- Determine insertion point
    local insert_line
    if offset < 0 then
        -- Insert above: before the target row's first content line
        -- We need to insert: content line + border, just before the target row
        insert_line = target_row.line_nr - 1
        vim.api.nvim_buf_set_lines(0, insert_line, insert_line, false, { content_line, border })
    else
        -- Insert below: after the target row's last content line + its border
        local row_end = target_row.line_nr + #target_row.continuation_lines
        -- Find the border line after this row
        local after_border = row_end
        local line_count = vim.api.nvim_buf_line_count(0)
        while after_border <= line_count do
            local l = vim.api.nvim_buf_get_lines(0, after_border, after_border + 1, false)[1]
            if l and MarkdownTable.isGridBorder(l) then
                after_border = after_border + 1
                break
            end
            after_border = after_border + 1
        end
        -- Insert after the border
        vim.api.nvim_buf_set_lines(
            0,
            after_border - 1,
            after_border - 1,
            false,
            { content_line, border }
        )
    end
end

--- Delete a row from a grid table.
--- @param tbl table MarkdownTable instance
function M.delete_row(tbl)
    local core = get_core()
    local MarkdownTable = core.MarkdownTable

    local cursor = vim.api.nvim_win_get_cursor(0)

    -- Find which logical row the cursor is on
    local target_row = nil
    local target_row_idx = nil
    for idx, row in ipairs(tbl.rows) do
        local row_start = row.line_nr
        local row_end = row.line_nr + #row.continuation_lines
        if cursor[1] >= row_start and cursor[1] <= row_end then
            target_row = row
            target_row_idx = idx
            break
        end
    end

    if not target_row then
        return
    end

    -- Don't delete if there's only one data row
    local data_rows = 0
    for _, row in ipairs(tbl.rows) do
        if not row.is_header then
            data_rows = data_rows + 1
        end
    end
    -- If this is a header row and there's only one header row, only block if no data rows
    if data_rows <= 1 and not target_row.is_header then
        return
    end
    if target_row.is_header then
        local header_rows = #tbl.rows - data_rows
        if header_rows <= 1 and data_rows == 0 then
            return
        end
    end

    -- Determine lines to delete: content lines + one adjacent border
    local row_start = target_row.line_nr
    local row_end = target_row.line_nr + #target_row.continuation_lines

    -- Prefer removing the border ABOVE (unless this is the first row)
    local delete_start, delete_end
    if target_row_idx == 1 then
        -- First row: remove content lines and the border BELOW
        delete_start = row_start
        delete_end = row_end + 1 -- +1 for the border below
    else
        -- Other rows: remove the border ABOVE and the content lines
        delete_start = row_start - 1 -- -1 for the border above
        delete_end = row_end
    end

    -- Clamp to table range
    delete_start = math.max(delete_start, tbl.line_range.start)
    delete_end = math.min(delete_end, tbl.line_range.finish)

    vim.api.nvim_buf_set_lines(0, delete_start - 1, delete_end, true, {})

    -- Position cursor sensibly
    local new_line = math.min(delete_start, vim.api.nvim_buf_line_count(0))
    if new_line >= 1 then
        -- Make sure we land on a content line, not a border
        local l = vim.api.nvim_buf_get_lines(0, new_line - 1, new_line, false)[1]
        if l and MarkdownTable.isGridBorder(l) then
            -- Try the next line
            if new_line < vim.api.nvim_buf_line_count(0) then
                new_line = new_line + 1
            end
        end
        vim.api.nvim_win_set_cursor(0, { new_line, cursor[2] })
    end
end

-- =============================================================================
-- Grid Table Column Operations
-- =============================================================================

--- Add a new column to a grid table.
--- @param tbl table MarkdownTable instance
--- @param offset? integer Position offset (0 = after current, -1 = before current)
function M.add_col(tbl, offset)
    offset = offset or 0
    local core = get_core()
    local MarkdownTable = core.MarkdownTable
    local TableRow = core.TableRow

    local cursor = vim.api.nvim_win_get_cursor(0)
    local config = get_config()
    local padding = config.tables.style.cell_padding or 1
    local min_width = 3

    -- Determine which column the cursor is in
    local current_col = 1
    for _, row in ipairs(tbl.rows) do
        if row.line_nr == cursor[1] then
            local temp_row = TableRow:from_string(row.raw_content, row.line_nr)
            current_col = temp_row:which_cell(cursor[2])
            break
        end
    end

    -- If cursor is on a border line, use column from nearest content line
    local cursor_line = vim.api.nvim_buf_get_lines(0, cursor[1] - 1, cursor[1], false)[1]
    if MarkdownTable.isGridBorder(cursor_line) then
        -- Find nearest content line
        for _, row in ipairs(tbl.rows) do
            if row.line_nr > cursor[1] then
                local temp_row = TableRow:from_string(row.raw_content, row.line_nr)
                current_col = temp_row:which_cell(cursor[2])
                break
            end
        end
    end

    -- Build the insert column index
    local insert_col = offset < 0 and current_col or current_col + 1

    -- Read all lines of the table and modify each
    local all_lines =
        vim.api.nvim_buf_get_lines(0, tbl.line_range.start - 1, tbl.line_range.finish, false)
    local new_lines = {}

    -- Parse boundaries from first border
    local first_border = nil
    for _, l in ipairs(all_lines) do
        if MarkdownTable.isGridBorder(l) then
            first_border = l
            break
        end
    end
    if not first_border then
        return
    end
    local col_boundaries = parse_col_boundaries(first_border)

    local pad_str = string.rep(' ', padding)
    local new_cell_width = min_width
    local new_content_segment = pad_str .. string.rep(' ', new_cell_width) .. pad_str

    for _, l in ipairs(all_lines) do
        local trimmed = l:match('^%s*(.*)$')
        if MarkdownTable.isGridBorder(l) then
            -- Insert new border segment
            local char = l:find('=') and '=' or '-'
            local new_seg = string.rep(char, new_cell_width + 2 * padding)

            -- Find the correct + position to split at
            local plus_positions = {}
            for i = 1, #trimmed do
                if trimmed:sub(i, i) == '+' then
                    table.insert(plus_positions, i)
                end
            end

            local split_pos
            if insert_col <= #plus_positions then
                split_pos = plus_positions[insert_col]
            else
                split_pos = plus_positions[#plus_positions]
            end

            local new_line = trimmed:sub(1, split_pos)
                .. new_seg
                .. '+'
                .. trimmed:sub(split_pos + 1)
            table.insert(new_lines, new_line)
        else
            -- Content line: insert new cell segment
            -- Find pipe positions that correspond to column boundaries
            local pipe_positions = {}
            for i = 1, #trimmed do
                if trimmed:sub(i, i) == '|' then
                    table.insert(pipe_positions, i)
                end
            end

            local split_pos
            if insert_col <= #pipe_positions then
                split_pos = pipe_positions[insert_col]
            else
                split_pos = pipe_positions[#pipe_positions]
            end

            local new_line = trimmed:sub(1, split_pos)
                .. new_content_segment
                .. '|'
                .. trimmed:sub(split_pos + 1)
            table.insert(new_lines, new_line)
        end
    end

    vim.api.nvim_buf_set_lines(0, tbl.line_range.start - 1, tbl.line_range.finish, true, new_lines)
end

--- Delete a column from a grid table.
--- @param tbl table MarkdownTable instance
function M.delete_col(tbl)
    local core = get_core()
    local MarkdownTable = core.MarkdownTable
    local TableRow = core.TableRow

    local cursor = vim.api.nvim_win_get_cursor(0)

    -- Don't delete if there's only one column
    if tbl.col_count <= 1 then
        return
    end

    -- Determine which column the cursor is in
    local target_col = 1
    for _, row in ipairs(tbl.rows) do
        if row.line_nr == cursor[1] then
            local temp_row = TableRow:from_string(row.raw_content, row.line_nr)
            target_col = temp_row:which_cell(cursor[2])
            break
        end
    end

    -- If cursor is on a border line, use column from nearest content line
    local cursor_line = vim.api.nvim_buf_get_lines(0, cursor[1] - 1, cursor[1], false)[1]
    if MarkdownTable.isGridBorder(cursor_line) then
        for _, row in ipairs(tbl.rows) do
            if row.line_nr > cursor[1] then
                local temp_row = TableRow:from_string(row.raw_content, row.line_nr)
                target_col = temp_row:which_cell(cursor[2])
                break
            end
        end
    end

    -- Read all lines and remove the target column from each
    local all_lines =
        vim.api.nvim_buf_get_lines(0, tbl.line_range.start - 1, tbl.line_range.finish, false)
    local new_lines = {}

    -- Parse boundaries from first border
    local first_border = nil
    for _, l in ipairs(all_lines) do
        if MarkdownTable.isGridBorder(l) then
            first_border = l
            break
        end
    end
    if not first_border then
        return
    end

    for _, l in ipairs(all_lines) do
        local trimmed = l:match('^%s*(.*)$')
        if MarkdownTable.isGridBorder(l) then
            -- Find + positions and remove the segment for target_col
            local plus_positions = {}
            for i = 1, #trimmed do
                if trimmed:sub(i, i) == '+' then
                    table.insert(plus_positions, i)
                end
            end

            if target_col < #plus_positions then
                local seg_start = plus_positions[target_col]
                local seg_end = plus_positions[target_col + 1]
                local new_line = trimmed:sub(1, seg_start) .. trimmed:sub(seg_end + 1)
                table.insert(new_lines, new_line)
            else
                table.insert(new_lines, trimmed)
            end
        else
            -- Content line: find pipe positions and remove the target column segment
            local pipe_positions = {}
            for i = 1, #trimmed do
                if trimmed:sub(i, i) == '|' then
                    table.insert(pipe_positions, i)
                end
            end

            if target_col < #pipe_positions then
                local seg_start = pipe_positions[target_col]
                local seg_end = pipe_positions[target_col + 1]
                local new_line = trimmed:sub(1, seg_start) .. trimmed:sub(seg_end + 1)
                table.insert(new_lines, new_line)
            else
                table.insert(new_lines, trimmed)
            end
        end
    end

    vim.api.nvim_buf_set_lines(0, tbl.line_range.start - 1, tbl.line_range.finish, true, new_lines)

    -- Position cursor sensibly
    if target_col >= tbl.col_count then
        local new_line_text = vim.api.nvim_buf_get_lines(0, cursor[1] - 1, cursor[1], false)[1]
        if new_line_text then
            local new_row_obj = TableRow:from_string(new_line_text, cursor[1])
            local new_col = math.max(1, tbl.col_count - 1)
            local cell_start, _ = new_row_obj:locate_cell(new_col)
            vim.api.nvim_win_set_cursor(0, { cursor[1], cell_start - 1 })
        end
    end
end

-- =============================================================================
-- Grid Table Cell New Line
-- =============================================================================

--- Insert a new empty content line within the current grid table row.
--- The line is inserted after the cursor's current line, before the next border.
--- Cursor moves to the same cell on the new line.
--- @param tbl table MarkdownTable instance
--- @param cursor_position table {row, col} from nvim_win_get_cursor
function M.add_cell_line(tbl, cursor_position)
    local core = get_core()
    local TableRow = core.TableRow
    local MarkdownTable = core.MarkdownTable
    local config = get_config()
    local padding = config.tables.style.cell_padding or 1

    -- If cursor is on a border line, do nothing
    local current_line_text =
        vim.api.nvim_buf_get_lines(0, cursor_position[1] - 1, cursor_position[1], false)[1]
    if MarkdownTable.isGridBorder(current_line_text) then
        return
    end

    -- Determine which cell the cursor is in before any modifications
    local current_row = TableRow:from_string(current_line_text, cursor_position[1])
    local current_cell = current_row:which_cell(cursor_position[2])

    -- Check if an empty continuation line already exists in this cell
    -- within the same logical row (before the next grid border)
    local line_count = vim.api.nvim_buf_line_count(0)
    for check_linenr = cursor_position[1] + 1, line_count do
        local check_line = vim.api.nvim_buf_get_lines(0, check_linenr - 1, check_linenr, false)[1]
        if not check_line or MarkdownTable.isGridBorder(check_line) then
            break
        end
        local check_row = TableRow:from_string(check_line, check_linenr)
        if #check_row.cells >= current_cell and check_row.cells[current_cell].content == '' then
            local cell_start, _ = check_row:locate_cell(current_cell)
            vim.api.nvim_win_set_cursor(0, { check_linenr, cell_start - 1 })
            return
        end
    end

    -- No empty continuation found — build and insert a new empty content line
    local empty_cells = {}
    for _ = 1, tbl.col_count do
        table.insert(empty_cells, '')
    end
    local new_line = build_content_line(empty_cells, tbl.col_widths, padding)

    -- Insert after the current line
    local insert_at = cursor_position[1] -- 1-indexed line number
    vim.api.nvim_buf_set_lines(0, insert_at, insert_at, false, { new_line })

    -- Re-read and format the table so all lines have consistent widths
    local refreshed_tbl = MarkdownTable:read(insert_at)
    if refreshed_tbl.valid then
        M.format(refreshed_tbl)
    end

    -- Find the new line's position after formatting (line number may have shifted)
    -- The inserted line is still at insert_at + 1 since format replaces in-place
    local new_line_nr = insert_at + 1
    local formatted_line = vim.api.nvim_buf_get_lines(0, new_line_nr - 1, new_line_nr, false)[1]
    local new_row = TableRow:from_string(formatted_line, new_line_nr)
    local cell_start, _ = new_row:locate_cell(current_cell)
    vim.api.nvim_win_set_cursor(0, { new_line_nr, cell_start - 1 })
end

return M
