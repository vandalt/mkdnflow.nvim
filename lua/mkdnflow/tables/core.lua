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

-- This module: Table classes and core logic for markdown table handling

-- Note: We use lazy loading for config to ensure it's accessed after setup()
local function get_config()
    return require('mkdnflow').config
end

local function get_utils()
    return require('mkdnflow').utils
end

table.unpack = table.unpack or unpack -- 5.1 compatibility

-- Display width helper (handles multi-byte characters)
local width = vim.api.nvim_strwidth

-- =============================================================================
-- TableCell Class
-- =============================================================================

--- @class TableCell
--- @field content string Cell text (whitespace stripped)
--- @field raw_content string Original cell text (with whitespace)
--- @field alignment string 'left'|'right'|'center'|'default'
--- @field display_width integer Display width (handles Unicode)
--- @field col_index integer Column position (1-indexed)
--- @field is_separator boolean Is this a separator cell?
local TableCell = {}
TableCell.__index = TableCell
TableCell.__className = 'TableCell'

--- Constructor for TableCell
--- @param opts? table Optional initial values
--- @return TableCell
function TableCell:new(opts)
    opts = opts or {}
    local instance = {
        content = opts.content or '',
        raw_content = opts.raw_content or '',
        alignment = opts.alignment or 'default',
        display_width = opts.display_width or 0,
        col_index = opts.col_index or 0,
        is_separator = opts.is_separator or false,
    }
    setmetatable(instance, self)
    return instance
end

--- Parse a cell from raw content string
--- @param raw_content string The raw cell text (may include whitespace)
--- @param col_index integer The column position (1-indexed)
--- @return TableCell
function TableCell:read(raw_content, col_index)
    local cell = TableCell:new({
        col_index = col_index,
        raw_content = raw_content,
    })
    -- Strip leading/trailing whitespace for content
    cell.content = raw_content:gsub('^%s*', ''):gsub('%s*$', '')
    cell.display_width = width(cell.content)
    cell.is_separator = cell:_detect_separator()
    if cell.is_separator then
        cell.alignment = cell:_parse_alignment()
    end
    return cell
end

--- Detect if this cell is a separator cell (contains only dashes and optional colons)
--- @return boolean
function TableCell:_detect_separator()
    -- Separator cells contain only dashes with optional leading/trailing colons
    return self.content:match('^:?%-+:?$') ~= nil
end

--- Parse alignment from separator cell content
--- @return string 'left'|'right'|'center'|'default'
function TableCell:_parse_alignment()
    if self.content:match('^:%-+:$') then
        return 'center'
    elseif self.content:match('^:%-+$') then
        return 'left'
    elseif self.content:match('^%-+:$') then
        return 'right'
    else
        return 'default'
    end
end

--- Format the cell to a target width with specified alignment
--- @param target_width integer The desired content width
--- @param padding string The padding string to use around content
--- @param alignment? string Override alignment ('left'|'right'|'center'|'default')
--- @return string The formatted cell content (without surrounding pipes)
function TableCell:format(target_width, padding, alignment)
    alignment = alignment or self.alignment
    local content = self.content
    local diff = target_width - self.display_width

    if diff < 0 then
        diff = 0
    end

    local formatted
    if alignment == 'right' and get_config().tables.style.apply_alignment then
        formatted = string.rep(' ', diff) .. content
    elseif alignment == 'center' and get_config().tables.style.apply_alignment then
        local left_fill = string.rep(' ', math.floor(diff / 2))
        local right_fill = string.rep(' ', diff - #left_fill)
        formatted = left_fill .. content .. right_fill
    else
        -- Default to left alignment
        formatted = content .. string.rep(' ', diff)
    end

    return padding .. formatted .. padding
end

--- Format a separator cell to target width
--- @param target_width integer The desired width (excluding padding)
--- @param padding string The padding string
--- @return string The formatted separator cell content
function TableCell:format_separator(target_width, padding)
    local alignment = self.alignment
    local formatted

    if alignment == 'center' then
        formatted = ':' .. string.rep('-', target_width - 2) .. ':'
    elseif alignment == 'left' then
        formatted = ':' .. string.rep('-', target_width - 1)
    elseif alignment == 'right' then
        formatted = string.rep('-', target_width - 1) .. ':'
    else
        formatted = string.rep('-', target_width)
    end

    return padding .. formatted .. padding
end

-- =============================================================================
-- TableRow Class
-- =============================================================================

--- @class TableRow
--- @field cells TableCell[] Array of cells in this row
--- @field line_nr integer Buffer line number (1-indexed)
--- @field raw_content string Original line content from buffer
--- @field is_separator boolean Is this the separator row?
--- @field is_header boolean Is this the header row?
--- @field has_outer_pipes boolean Does this row have outer pipes?
--- @field outer_pipe_side string|nil 'both'|'left'|'right'|nil
--- @field continuation_lines string[] Additional content lines (grid tables only)
local TableRow = {}
TableRow.__index = TableRow
TableRow.__className = 'TableRow'

--- Constructor for TableRow
--- @param opts? table Optional initial values
--- @return TableRow
function TableRow:new(opts)
    opts = opts or {}
    local instance = {
        cells = opts.cells or {},
        line_nr = opts.line_nr or -1,
        raw_content = opts.raw_content or '',
        is_separator = opts.is_separator or false,
        is_header = opts.is_header or false,
        has_outer_pipes = opts.has_outer_pipes or false,
        outer_pipe_side = opts.outer_pipe_side or nil,
        continuation_lines = opts.continuation_lines or {},
    }
    setmetatable(instance, self)
    return instance
end

--- Read a row from a buffer line
--- @param line_nr integer The buffer line number (1-indexed)
--- @return TableRow
function TableRow:read(line_nr)
    local line = vim.api.nvim_buf_get_lines(0, line_nr - 1, line_nr, false)[1]
    return TableRow:from_string(line, line_nr)
end

--- Create a TableRow from a string
--- @param line string The line content
--- @param line_nr? integer Optional line number
--- @return TableRow
function TableRow:from_string(line, line_nr)
    local row = TableRow:new({
        line_nr = line_nr or -1,
        raw_content = line,
    })

    -- Detect outer pipes
    row.has_outer_pipes, row.outer_pipe_side = row:_detect_outer_pipes(line)

    -- Parse cells from the line
    row:_parse_cells(line)

    -- Detect if this is a separator row
    row.is_separator = row:_detect_separator()

    return row
end

--- Detect if the line has outer pipes
--- @param line string
--- @return boolean, string|nil
function TableRow:_detect_outer_pipes(line)
    if line:match('^|.*|%s*$') then
        return true, 'both'
    elseif line:match('^%s*|.*[^|]$') then
        return true, 'left'
    elseif line:match('^%s*[^|].*|%s*$') then
        return true, 'right'
    end
    return false, nil
end

--- Parse cells from line content
--- @param line string The row content
function TableRow:_parse_cells(line)
    -- Temporarily replace escaped pipes to avoid splitting on them
    -- Use a placeholder that won't appear in normal text and is safe for gsub patterns
    local PIPE_PLACEHOLDER = '<<<ESCAPED_PIPE>>>'
    local work_line = line:gsub('\\|', PIPE_PLACEHOLDER)
    local col_index = 1

    for cell_content in work_line:gmatch('([^|]+)') do
        -- Restore escaped pipes in cell content
        cell_content = cell_content:gsub(PIPE_PLACEHOLDER, '\\|')
        local cell = TableCell:read(cell_content, col_index)
        table.insert(self.cells, cell)
        col_index = col_index + 1
    end
end

--- Detect if this row is a separator row
--- @return boolean
function TableRow:_detect_separator()
    if #self.cells == 0 then
        return false
    end

    -- Check if all cells are separator cells and at least one has a hyphen
    local has_hyphen = false
    for _, cell in ipairs(self.cells) do
        if cell.is_separator then
            if cell.content:match('%-') then
                has_hyphen = true
            end
        elseif cell.content ~= '' then
            -- Non-empty, non-separator cell means this isn't a separator row
            return false
        end
    end

    return has_hyphen
end

--- Get the number of cells in this row
--- @return integer
function TableRow:cell_count()
    return #self.cells
end

--- Get a cell by column index
--- @param index integer 1-indexed column number
--- @return TableCell|nil
function TableRow:get_cell(index)
    return self.cells[index]
end

--- Get column alignments from this row (only valid for separator rows)
--- @return string[] Array of alignment values
function TableRow:get_alignments()
    local alignments = {}
    for _, cell in ipairs(self.cells) do
        table.insert(alignments, cell.alignment)
    end
    return alignments
end

--- Determine which cell the cursor is in given a column position
--- @param col integer 0-indexed column position in the line
--- @return integer Cell number (1-indexed), or last cell if on trailing pipe
function TableRow:which_cell(col)
    -- Temporarily replace escaped pipes
    local work_line = self.raw_content:gsub('\\|', '##')
    local cell_num = 1
    local last_cell = nil

    for start, finish in get_utils().gmatch(work_line, '[^|]+') do
        if col + 1 >= start and col <= finish then
            return cell_num
        end
        if col >= finish then
            last_cell = cell_num
        end
        cell_num = cell_num + 1
    end

    -- If cursor is on a pipe, use the cell to its left
    return last_cell or 1
end

--- Locate a cell's position in the row string
--- @param target_cell integer The target cell number (1-indexed)
--- @param locate_content? boolean Whether to locate content start vs cell start (default true)
--- @return integer, integer Start and end positions
function TableRow:locate_cell(target_cell, locate_content)
    locate_content = locate_content == nil and true or locate_content
    local work_line = self.raw_content:gsub('\\|', '  ')
    local cur_cell = 0

    for match_start, match_end, match in get_utils().gmatch(work_line, '([^|]+)') do
        cur_cell = cur_cell + 1
        if cur_cell == target_cell then
            if locate_content then
                -- Find where non-whitespace content starts (first non-space character)
                local content_offset = match:find('%S')
                if content_offset then
                    -- Find where content ends (last non-space character)
                    local content_end_offset = match:match('.*%S()') or content_offset
                    return match_start + content_offset - 1, match_start + content_end_offset - 2
                else
                    -- Empty cell (all whitespace) - position one character into it
                    return match_start + 1, match_end
                end
            else
                return match_start, match_end
            end
        end
    end

    return 1, 1
end

--- Format this row given column widths and config
--- @param col_widths integer[] Array of column widths
--- @param col_alignments string[] Array of column alignments
--- @param style table Style configuration
--- @return string The formatted row string
function TableRow:format(col_widths, col_alignments, style)
    local cell_padding = string.rep(' ', style.cell_padding or 1)
    local sep_padding = string.rep(' ', style.separator_padding or 1)
    local outer_pipes = style.outer_pipes

    local parts = {}

    for idx, cell in ipairs(self.cells) do
        local target_width = col_widths[idx] or 3
        local alignment = col_alignments[idx] or 'default'
        local formatted

        if self.is_separator then
            -- Use separator formatting
            local sep_cell = TableCell:new({
                content = cell.content,
                alignment = alignment,
            })
            -- Adjust width for separator padding difference
            local diff = #cell_padding - #sep_padding
            formatted = sep_cell:format_separator(target_width + 2 * diff, sep_padding)
        else
            formatted = cell:format(target_width, cell_padding, alignment)
        end

        table.insert(parts, formatted)
    end

    local line = table.concat(parts, '|')

    if outer_pipes then
        line = '|' .. line .. '|'
    end

    return line
end

-- =============================================================================
-- MarkdownTable Class
-- =============================================================================

--- @class MarkdownTable
--- @field rows TableRow[] All rows in the table
--- @field metadata table Table metadata (alignments, indices)
--- @field line_range {start: integer, finish: integer} Buffer line range
--- @field col_count integer Number of columns
--- @field col_widths integer[] Maximum width for each column
--- @field valid boolean Is this a valid complete table (has separator)?
local MarkdownTable = {}
MarkdownTable.__index = MarkdownTable
MarkdownTable.__className = 'MarkdownTable'

--- Constructor for MarkdownTable
--- @return MarkdownTable
function MarkdownTable:new()
    local instance = {
        rows = {},
        metadata = {
            col_alignments = {},
            header_row_idx = nil,
            separator_row_idx = nil,
        },
        line_range = { start = 0, finish = 0 },
        col_count = 0,
        col_widths = {},
        valid = false,
        table_type = 'pipe',
    }
    setmetatable(instance, self)
    return instance
end

--- Detect if a line is a grid table border line (+---+---+ or +===+===+)
--- @param line string|nil The line text
--- @return boolean
function MarkdownTable.isGridBorder(line)
    return line ~= nil
        and line:match('^%s*%+[%-=+:]+%+%s*$') ~= nil
        and (line:find('%-') ~= nil or line:find('=') ~= nil)
end

--- Detect if a line is a grid table header separator (+===+===+)
--- @param line string|nil The line text
--- @return boolean
function MarkdownTable.isGridHeaderSeparator(line)
    return line ~= nil and line:match('^%s*%+[=+:]+%+%s*$') ~= nil and line:find('=') ~= nil
end

--- Determine if cursor context is a grid table (vs pipe)
--- Scans nearby lines for +---+ border patterns
--- @param line_nr integer The buffer line number (1-indexed)
--- @return boolean
function MarkdownTable._isGridContext(line_nr)
    local line_count = vim.api.nvim_buf_line_count(0)
    -- Check the line itself first
    local line = vim.api.nvim_buf_get_lines(0, line_nr - 1, line_nr, false)[1]
    if MarkdownTable.isGridBorder(line) then
        return true
    end
    -- Scan up to 50 lines up and down looking for grid borders
    for _, dir in ipairs({ -1, 1 }) do
        local check = line_nr + dir
        while check >= 1 and check <= line_count and math.abs(check - line_nr) <= 50 do
            local l = vim.api.nvim_buf_get_lines(0, check - 1, check, false)[1]
            if MarkdownTable.isGridBorder(l) then
                return true
            end
            -- Stop scanning if we hit an empty line or non-table line
            if not l or l:match('^%s*$') then
                break
            end
            if not l:match('|') and not MarkdownTable.isGridBorder(l) then
                break
            end
            check = check + dir
        end
    end
    return false
end

--- Check if a line is part of a table
--- @param text string The line text
--- @param linenr? integer Optional line number for context checking
--- @return boolean
function MarkdownTable.isPartOfTable(text, linenr)
    -- Grid table border lines are always part of a table
    if MarkdownTable.isGridBorder(text) then
        return true
    end

    -- Check if adjacent lines are grid borders (grid content lines)
    if linenr then
        local line_count = vim.api.nvim_buf_line_count(0)
        if linenr > 1 then
            local above = vim.api.nvim_buf_get_lines(0, linenr - 2, linenr - 1, false)
            if above and MarkdownTable.isGridBorder(above[1]) then
                return true
            end
        end
        if linenr < line_count then
            local below = vim.api.nvim_buf_get_lines(0, linenr, linenr + 1, false)
            if below and MarkdownTable.isGridBorder(below[1]) then
                return true
            end
        end
    end

    local tableyness = 0

    -- Start by looking for a single pipe in the line
    if text and text:match('^.+|.+$') then
        tableyness = tableyness + 1

        -- Do more thorough checks; look up and down if we have linenr
        if linenr then
            local above = vim.api.nvim_buf_get_lines(0, linenr, linenr + 1, false)
            local below = vim.api.nvim_buf_get_lines(0, linenr - 2, linenr - 1, false)
            above = above and above[1] or ''
            below = below and below[1] or ''

            for _, line in ipairs({ above, text, below }) do
                tableyness = tableyness + (line:match('^.+|.+$') and 1 or 0)
                tableyness = tableyness + (line:match('^%s*|.+|%s*$') and 1 or 0)
                tableyness = tableyness + (line:match('^|.+|$') and 1 or 0)
            end
        else
            tableyness = tableyness + (text:match('^.+|.+$') and 1 or 0)
            tableyness = tableyness + (text:match('^%s*|.+|%s*$') and 1 or 0)
            tableyness = tableyness + (text:match('^|.+|$') and 1 or 0)
        end
    end

    return tableyness >= 2
end

--- Read a table from the buffer starting at a line number
--- @param line_nr? integer Starting line number (defaults to cursor position)
--- @return MarkdownTable
function MarkdownTable:read(line_nr)
    line_nr = line_nr or vim.api.nvim_win_get_cursor(0)[1]
    if MarkdownTable._isGridContext(line_nr) then
        return require('mkdnflow.tables.grid').read(line_nr)
    end
    local tbl = MarkdownTable:new()
    local init_line_nr = line_nr

    local line = vim.api.nvim_buf_get_lines(0, line_nr - 1, line_nr, false)[1]

    -- Check if starting line is part of a table
    if not MarkdownTable.isPartOfTable(line) then
        return tbl
    end

    -- Scan in both directions to find table boundaries
    local direction = 1
    local rows_by_line = {}
    local line_count = vim.api.nvim_buf_line_count(0)

    while line and MarkdownTable.isPartOfTable(line, line_nr) do
        local row = TableRow:from_string(line, line_nr)
        rows_by_line[line_nr] = row

        if row.is_separator and not tbl.metadata.separator_row_idx then
            tbl.metadata.separator_row_idx = line_nr
        end

        -- Move to next line
        line_nr = line_nr + direction

        -- Check boundaries before reading
        if line_nr < 1 or line_nr > line_count then
            line = nil
        else
            line = vim.api.nvim_buf_get_lines(0, line_nr - 1, line_nr, false)[1]
        end

        -- If we've reached the end going down, switch to going up
        if direction == 1 and (not line or not MarkdownTable.isPartOfTable(line, line_nr)) then
            line_nr = init_line_nr - 1
            direction = -1
            if line_nr < 1 then
                line = nil
            else
                line = vim.api.nvim_buf_get_lines(0, line_nr - 1, line_nr, false)[1]
            end
        end

        -- If we've reached the end going up, we're done
        if direction == -1 and (not line or not MarkdownTable.isPartOfTable(line, line_nr)) then
            tbl.metadata.header_row_idx = line_nr + 1
            break
        end
    end

    -- Sort rows by line number and add to table
    for line_num, row in get_utils().spairs(rows_by_line) do
        table.insert(tbl.rows, row)
        if tbl.line_range.start == 0 or line_num < tbl.line_range.start then
            tbl.line_range.start = line_num
        end
        if line_num > tbl.line_range.finish then
            tbl.line_range.finish = line_num
        end
    end

    -- Extract column alignments from separator row
    if tbl.metadata.separator_row_idx then
        local sep_row = rows_by_line[tbl.metadata.separator_row_idx]
        if sep_row then
            tbl.metadata.col_alignments = sep_row:get_alignments()
        end
        tbl.valid = true
    end

    -- Calculate column count and equalize rows
    tbl:_calculate_col_count()
    tbl:_equalize_rows()
    tbl:_calculate_col_widths()

    return tbl
end

--- Calculate the maximum column count across all rows
function MarkdownTable:_calculate_col_count()
    local max_cols = 0
    for _, row in ipairs(self.rows) do
        if row:cell_count() > max_cols then
            max_cols = row:cell_count()
        end
    end
    self.col_count = max_cols
end

--- Ensure all rows have the same number of columns
function MarkdownTable:_equalize_rows()
    for _, row in ipairs(self.rows) do
        while row:cell_count() < self.col_count do
            local empty_cell = TableCell:new({
                content = '',
                col_index = row:cell_count() + 1,
            })
            table.insert(row.cells, empty_cell)
        end
    end

    -- Also equalize alignments
    while #self.metadata.col_alignments < self.col_count do
        table.insert(self.metadata.col_alignments, 'default')
    end
end

--- Calculate maximum width for each column
function MarkdownTable:_calculate_col_widths()
    self.col_widths = {}

    -- Initialize with minimum width of 3
    for i = 1, self.col_count do
        self.col_widths[i] = 3
    end

    -- Find maximum width in each column (excluding separator row)
    for _, row in ipairs(self.rows) do
        if not row.is_separator then
            for idx, cell in ipairs(row.cells) do
                if cell.display_width > self.col_widths[idx] then
                    self.col_widths[idx] = cell.display_width
                end
            end
        end
    end
end

--- Get a row by its buffer line number
--- @param line_nr integer
--- @return TableRow|nil
function MarkdownTable:get_row(line_nr)
    for _, row in ipairs(self.rows) do
        if row.line_nr == line_nr then
            return row
        end
    end
    return nil
end

--- Check if the table has a valid separator row
--- @return boolean
function MarkdownTable:has_separator()
    return self.metadata.separator_row_idx ~= nil
end

--- Get column alignments
--- @return string[]
function MarkdownTable:get_alignments()
    return self.metadata.col_alignments
end

--- Format the table and write to buffer
function MarkdownTable:format()
    if not self.valid or #self.rows == 0 then
        return
    end

    if self.table_type == 'grid' then
        return require('mkdnflow.tables.grid').format(self)
    end

    -- Recalculate widths in case content changed
    self:_calculate_col_widths()

    local style = get_config().tables.style
    local formatted_lines = {}

    for _, row in ipairs(self.rows) do
        table.insert(
            formatted_lines,
            row:format(self.col_widths, self.metadata.col_alignments, style)
        )
    end

    -- Write back to buffer
    vim.api.nvim_buf_set_lines(
        0,
        self.line_range.start - 1,
        self.line_range.finish,
        true,
        formatted_lines
    )
end

--- Create a new table in the buffer
--- @param cols integer Number of columns
--- @param rows integer Number of data rows
--- @param header boolean Whether to include header row
--- @return MarkdownTable
function MarkdownTable:create(cols, rows, header)
    local table_type = get_config().tables.type or 'pipe'
    if table_type == 'grid' then
        return require('mkdnflow.tables.grid').create(cols, rows, header)
    end
    local style = get_config().tables.style
    local cell_padding = string.rep(' ', style.cell_padding or 1)
    local sep_padding = string.rep(' ', style.separator_padding or 1)
    local min_width =
        math.max(#(sep_padding .. '---' .. sep_padding), #(cell_padding .. cell_padding))

    local cursor = vim.api.nvim_win_get_cursor(0)

    -- Build prototype row
    local table_row = style.outer_pipes and '|' or ''
    local divider_row = style.outer_pipes and '|' or ''
    local new_cell = cell_padding .. string.rep(' ', min_width - 2 * #cell_padding) .. cell_padding
    local new_divider = sep_padding .. string.rep('-', min_width - 2 * #sep_padding) .. sep_padding

    for i = 1, cols do
        local end_sep = (i < cols and '|') or (style.outer_pipes and '|') or ''
        table_row = table_row .. new_cell .. end_sep
        divider_row = divider_row .. new_divider .. end_sep
    end

    local new_rows = {}
    table.insert(new_rows, table_row)

    if header then
        table.insert(new_rows, divider_row)
        for _ = 1, rows do
            table.insert(new_rows, table_row)
        end
    else
        for _ = 2, rows do
            table.insert(new_rows, table_row)
        end
    end

    vim.api.nvim_buf_set_lines(0, cursor[1], cursor[1], false, new_rows)

    -- Return a MarkdownTable representing what we just created
    return MarkdownTable:read(cursor[1] + 1)
end

--- Add a new row to the table
--- @param offset? integer Position offset (0 = below cursor, -1 = above cursor)
function MarkdownTable:add_row(offset)
    if self.table_type == 'grid' then
        return require('mkdnflow.tables.grid').add_row(self, offset)
    end
    offset = offset or 0
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row_line = cursor[1] + offset
    local line = vim.api.nvim_buf_get_lines(0, cursor[1] - 1, cursor[1], false)[1]

    if not MarkdownTable.isPartOfTable(line, cursor[1]) then
        return
    end

    -- Replace escaped pipes with spaces (same length)
    local work_line = line:gsub('\\|', '  ')
    local new_line = ''
    local init = 1

    for match_start, match_end, match in get_utils().gmatch(work_line, '([^|]+)') do
        -- Add any pipe characters before this match
        if match_start > init then
            new_line = new_line .. work_line:sub(init, match_start - 1)
        end
        -- Replace content with spaces
        new_line = new_line .. string.rep(' ', width(match))
        init = match_end + 1
    end

    -- Add any trailing content (like closing pipe)
    if init <= #work_line then
        new_line = new_line .. work_line:sub(init)
    end

    vim.api.nvim_buf_set_lines(0, row_line, row_line, false, { new_line })
end

--- Add a new column to the table
--- @param offset? integer Position offset (0 = after current, -1 = before current)
function MarkdownTable:add_col(offset)
    if self.table_type == 'grid' then
        return require('mkdnflow.tables.grid').add_col(self, offset)
    end
    offset = offset or 0
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = vim.api.nvim_get_current_line()

    if not MarkdownTable.isPartOfTable(line, cursor[1]) then
        return
    end

    -- Read the table to get structure info
    local tbl = MarkdownTable:read(cursor[1])
    if not tbl.valid or #tbl.rows == 0 then
        return
    end

    -- Determine which cell the cursor is in
    local current_row = tbl:get_row(cursor[1])
    local current_col = current_row and current_row:which_cell(cursor[2]) or 1

    local style = get_config().tables.style
    local cell_padding = string.rep(' ', style.cell_padding or 1)
    local sep_padding = string.rep(' ', style.separator_padding or 1)
    local min_width =
        math.max(#(sep_padding .. '---' .. sep_padding), #(cell_padding .. cell_padding))

    local replacements = {}
    local escaped_pipe_placeholder = '##'

    for _, row in ipairs(tbl.rows) do
        local row_text = row.raw_content
        local row_text_work = row_text:gsub('\\|', escaped_pipe_placeholder)

        local pattern
        if offset < 0 then
            if row.has_outer_pipes then
                pattern = string.rep('|[^|]*', current_col - 1)
            else
                pattern = '[^|]*' .. string.rep('|[^|]*', current_col - 2)
            end
        else
            if row.has_outer_pipes then
                pattern = string.rep('|[^|]*', current_col)
            else
                pattern = '[^|]*' .. string.rep('|[^|]*', current_col - 1)
            end
        end

        local new_cell
        if row.is_separator then
            new_cell = sep_padding .. string.rep('-', min_width - 2 * #sep_padding) .. sep_padding
        else
            new_cell = cell_padding
                .. string.rep(' ', min_width - 2 * #cell_padding)
                .. cell_padding
        end

        if not (offset < 0 and current_col == 1 and style.outer_pipes == false) then
            new_cell = '|' .. new_cell
        end

        local _, finish, match
        if pattern == '' then
            finish, match = 0, ''
        else
            _, finish, match = row_text_work:find('(' .. pattern .. ')')
        end

        -- Restore escaped pipes and build replacement
        local match_restored = match and match:gsub(escaped_pipe_placeholder, '\\|') or ''
        local suffix_restored =
            row_text_work:sub((finish or 0) + 1):gsub(escaped_pipe_placeholder, '\\|')
        local replacement = match_restored .. new_cell .. suffix_restored

        table.insert(replacements, replacement)
    end

    vim.api.nvim_buf_set_lines(
        0,
        tbl.line_range.start - 1,
        tbl.line_range.finish,
        true,
        replacements
    )
end

--- Delete the current row from the table
--- Does nothing if cursor is on separator row
function MarkdownTable:delete_row()
    if self.table_type == 'grid' then
        return require('mkdnflow.tables.grid').delete_row(self)
    end
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = vim.api.nvim_get_current_line()

    if not MarkdownTable.isPartOfTable(line, cursor[1]) then
        return
    end

    -- Read the table to get structure info
    local tbl = MarkdownTable:read(cursor[1])
    if not tbl.valid or #tbl.rows == 0 then
        return
    end

    -- Find which row the cursor is on
    local current_row = tbl:get_row(cursor[1])
    if not current_row then
        return
    end

    -- Skip if on separator row
    if current_row.is_separator then
        return
    end

    -- Build replacements without the target row
    local replacements = {}
    local deleted_row_idx = nil

    for idx, row in ipairs(tbl.rows) do
        if row.line_nr ~= cursor[1] then
            table.insert(replacements, row.raw_content)
        else
            deleted_row_idx = idx
        end
    end

    -- Replace the table lines
    vim.api.nvim_buf_set_lines(
        0,
        tbl.line_range.start - 1,
        tbl.line_range.finish,
        true,
        replacements
    )

    -- Position cursor sensibly
    -- If we deleted the last row, move cursor to the previous row
    if deleted_row_idx then
        local new_row_count = #tbl.rows - 1
        if deleted_row_idx > new_row_count then
            -- We deleted the last row, move up
            local new_line = math.max(tbl.line_range.start, cursor[1] - 1)
            vim.api.nvim_win_set_cursor(0, { new_line, cursor[2] })
        end
        -- Otherwise cursor stays at same line number which is now the next row
    end
end

--- Delete the current column from the table
function MarkdownTable:delete_col()
    if self.table_type == 'grid' then
        return require('mkdnflow.tables.grid').delete_col(self)
    end
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = vim.api.nvim_get_current_line()

    if not MarkdownTable.isPartOfTable(line, cursor[1]) then
        return
    end

    -- Read the table to get structure info
    local tbl = MarkdownTable:read(cursor[1])
    if not tbl.valid or #tbl.rows == 0 then
        return
    end

    -- Determine which cell the cursor is in
    local current_row = tbl:get_row(cursor[1])
    local target_col = current_row and current_row:which_cell(cursor[2]) or 1

    -- Don't delete if there's only one column
    if tbl.col_count <= 1 then
        return
    end

    local style = get_config().tables.style
    local escaped_pipe_placeholder = '##'

    local replacements = {}

    for _, row in ipairs(tbl.rows) do
        local row_text = row.raw_content
        local row_text_work = row_text:gsub('\\|', escaped_pipe_placeholder)

        -- Parse cells from the working line
        local cells = {}
        local col_index = 1
        for cell_content in row_text_work:gmatch('([^|]+)') do
            -- Restore escaped pipes in cell content
            cell_content = cell_content:gsub(escaped_pipe_placeholder, '\\|')
            table.insert(cells, cell_content)
            col_index = col_index + 1
        end

        -- Remove the target column
        if target_col <= #cells then
            table.remove(cells, target_col)
        end

        -- Rebuild the row
        local new_row
        if style.outer_pipes then
            new_row = '|' .. table.concat(cells, '|') .. '|'
        else
            new_row = table.concat(cells, '|')
        end

        table.insert(replacements, new_row)
    end

    -- Replace the table lines
    vim.api.nvim_buf_set_lines(
        0,
        tbl.line_range.start - 1,
        tbl.line_range.finish,
        true,
        replacements
    )

    -- Position cursor sensibly
    -- If we deleted the last column, move cursor to the new last column
    if target_col >= tbl.col_count then
        -- We deleted the last column, move cursor left within the row
        local new_line = vim.api.nvim_buf_get_lines(0, cursor[1] - 1, cursor[1], false)[1]
        if new_line then
            local new_row_obj = TableRow:from_string(new_line, cursor[1])
            local new_col = math.max(1, tbl.col_count - 1)
            local cell_start, _ = new_row_obj:locate_cell(new_col)
            vim.api.nvim_win_set_cursor(0, { cursor[1], cell_start - 1 })
        end
    end
end

-- =============================================================================
-- Module exports
-- =============================================================================

return {
    TableCell = TableCell,
    TableRow = TableRow,
    MarkdownTable = MarkdownTable,
}
