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

--- Split cell content at line break markers (\ or <br>)
--- Returns an array of content parts. The marker stays with the preceding part.
--- @param content string The cell content to split
--- @param line_breaks table Config: { pandoc = bool, html = bool }
--- @return string[] parts Array of content parts (first is primary, rest are continuations)
local function split_at_line_breaks(content, line_breaks)
    if not content or content == '' then
        return { content }
    end

    local parts = {}
    local remaining = content

    while remaining and remaining ~= '' do
        local split_pos = nil
        local marker_end = nil
        local marker_type = nil

        -- Look for pandoc-style line break: \ followed by space (but not \|)
        if line_breaks.pandoc then
            -- Find \ that is:
            -- 1. NOT followed by | (that's escaped pipe)
            -- 2. NOT preceded by \ (that's escaped backslash)
            -- 3. Followed by space or end of content
            local pos = 1
            while pos <= #remaining do
                local found = remaining:find('\\', pos, true)
                if not found then
                    break
                end
                -- Check if this is escaped backslash (preceded by \)
                local is_escaped = found > 1 and remaining:sub(found - 1, found - 1) == '\\'
                -- Check what follows
                local next_char = remaining:sub(found + 1, found + 1)
                if not is_escaped and next_char ~= '|' and next_char ~= '\\' then
                    -- This is a valid line break marker
                    -- Check if there's content after (space + something)
                    local after = remaining:sub(found + 1)
                    if after:match('^%s+%S') then
                        -- There's content after the break
                        split_pos = found
                        -- Find where the content starts (skip the \ and whitespace)
                        local _, ws_end = after:find('^%s+')
                        marker_end = found + ws_end
                        marker_type = 'pandoc'
                        break
                    end
                end
                pos = found + 1
            end
        end

        -- Look for HTML line break: <br> (only if no pandoc break found first)
        if line_breaks.html and not split_pos then
            local br_pos = remaining:find('<br>', 1, true)
            if br_pos then
                -- Check if there's content after
                local after = remaining:sub(br_pos + 4)
                if after:match('%S') then
                    split_pos = br_pos + 3 -- Position at end of <br>
                    -- Find where content starts (skip whitespace after <br>)
                    local _, ws_end = after:find('^%s*')
                    marker_end = br_pos + 3 + (ws_end or 0)
                    marker_type = 'html'
                end
            end
        end

        if split_pos and marker_end then
            -- Split at the marker
            local first_part = remaining:sub(1, split_pos)
            if marker_type == 'pandoc' then
                first_part = first_part .. ' ' -- Keep the \ and add space for readability
            end
            table.insert(parts, first_part)
            remaining = remaining:sub(marker_end + 1)
        else
            -- No more breaks, add the rest
            table.insert(parts, remaining)
            remaining = nil
        end
    end

    return parts
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
    if alignment == 'right' and get_config().tables.style.mimic_alignment then
        formatted = string.rep(' ', diff) .. content
    elseif alignment == 'center' and get_config().tables.style.mimic_alignment then
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
--- @field continuation_lines string[] For future multiline row support
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

--- Detect if this row has a continuation marker (backslash before final pipe)
--- @param line? string Optional line to check (defaults to raw_content)
--- @return boolean
function TableRow:_has_continuation(line)
    line = line or self.raw_content
    -- Match backslash followed by optional whitespace and optional final pipe
    -- But NOT double backslash (escaped backslash)
    -- Pattern: single \ (not preceded by \) followed by whitespace and optional |
    if line:match('\\\\%s*|?%s*$') then
        -- Double backslash at end - this is an escaped backslash, not continuation
        return false
    end
    return line:match('\\%s*|?%s*$') ~= nil
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
--- @return string|string[] The formatted row string, or table of strings for multiline rows
function TableRow:format(col_widths, col_alignments, style)
    local cell_padding = string.rep(' ', style.cell_padding or 1)
    local sep_padding = string.rep(' ', style.separator_padding or 1)
    local outer_pipes = style.outer_pipes
    local config = get_config()
    local line_breaks = config.tables.line_breaks or {}

    -- Collect all continuation parts (from inline splits + pre-existing continuations)
    local continuation_parts = {}

    -- Check if last cell needs inline splitting (only for non-separator rows)
    local last_cell = self.cells[#self.cells]
    local inline_split_parts = {}
    if last_cell and not self.is_separator then
        inline_split_parts = split_at_line_breaks(last_cell.content, line_breaks)
    end

    local parts = {}
    local last_cell_start = 0 -- Track position where last cell content starts
    local last_cell_alignment = 'default'

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
            -- Check if this is the last cell and we have inline splits
            local cell_content = cell.content
            if idx == #self.cells and #inline_split_parts > 1 then
                -- Use only the first part for the primary line
                cell_content = inline_split_parts[1]
                -- Store the rest as continuation parts
                for i = 2, #inline_split_parts do
                    table.insert(continuation_parts, inline_split_parts[i])
                end
            end

            -- Create a temporary cell with the (possibly modified) content
            local format_cell = TableCell:new({
                content = cell_content,
                raw_content = cell.raw_content,
                alignment = cell.alignment,
                display_width = width(cell_content),
                col_index = cell.col_index,
            })
            formatted = format_cell:format(target_width, cell_padding, alignment)
        end

        -- Calculate where the last cell's content starts (for continuation indent)
        if idx == #self.cells then
            -- Position = outer pipe (if any) + all previous cells + separators + padding
            last_cell_start = (outer_pipes and 1 or 0)
            for i = 1, idx - 1 do
                last_cell_start = last_cell_start + #parts[i] + 1 -- +1 for separator pipe
            end
            last_cell_start = last_cell_start + #cell_padding -- Add padding before content
            last_cell_alignment = alignment
        end

        table.insert(parts, formatted)
    end

    -- Add pre-existing continuation lines (from already-split tables)
    for _, cont_line in ipairs(self.continuation_lines) do
        -- Strip leading whitespace
        local content = cont_line:gsub('^%s*', '')
        -- Strip trailing | and padding from already-formatted continuation lines
        -- (we'll add the closing | back when formatting the final line)
        content = content:gsub('%s*|%s*$', '')
        -- Check if this continuation also needs splitting
        local cont_parts = split_at_line_breaks(content, line_breaks)
        for _, part in ipairs(cont_parts) do
            table.insert(continuation_parts, part)
        end
    end

    -- Handle multiline rows differently per Pandoc spec:
    -- The \ must be immediately followed by newline (no padding, no closing pipe on that line)
    -- Only the final continuation line gets the closing pipe
    if #continuation_parts > 0 then
        local lines = {}
        local indent = string.rep(' ', last_cell_start)
        local col_width = col_widths[#self.cells] or 3

        -- Build the primary line WITHOUT the last cell's normal formatting
        -- We need to rebuild it with just the content (ending in \ or <br>), no padding
        local primary_parts = {}
        for i = 1, #parts - 1 do
            table.insert(primary_parts, parts[i])
        end

        -- Format the first part of the split cell (ends with \ or <br>)
        local first_content = inline_split_parts[1] or last_cell.content
        local primary_line
        if #primary_parts > 0 then
            primary_line = table.concat(primary_parts, '|') .. '|' .. cell_padding .. first_content
        else
            primary_line = cell_padding .. first_content
        end
        if outer_pipes then
            primary_line = '|' .. primary_line
            -- Note: NO closing | here - that goes on the last continuation line
        end
        table.insert(lines, primary_line)

        -- Format continuation lines
        for idx, cont_content in ipairs(continuation_parts) do
            local is_last = (idx == #continuation_parts)
            local padded_content
            local content_width = width(cont_content)

            if is_last then
                -- Last continuation line gets full formatting with padding and closing pipe
                if last_cell_alignment == 'right' then
                    local pad_needed = col_width - content_width
                    if pad_needed > 0 then
                        padded_content = string.rep(' ', pad_needed) .. cont_content
                    else
                        padded_content = cont_content
                    end
                elseif last_cell_alignment == 'center' then
                    local pad_needed = col_width - content_width
                    local left_pad = math.floor(pad_needed / 2)
                    local right_pad = pad_needed - left_pad
                    padded_content = string.rep(' ', math.max(0, left_pad))
                        .. cont_content
                        .. string.rep(' ', math.max(0, right_pad))
                else
                    local pad_needed = col_width - content_width
                    if pad_needed > 0 then
                        padded_content = cont_content .. string.rep(' ', pad_needed)
                    else
                        padded_content = cont_content
                    end
                end

                local cont_line_formatted = indent .. padded_content
                if outer_pipes then
                    cont_line_formatted = cont_line_formatted .. cell_padding .. '|'
                end
                table.insert(lines, cont_line_formatted)
            else
                -- Intermediate continuation lines: just content (ends with \ or <br>), no closing pipe
                table.insert(lines, indent .. cont_content)
            end
        end

        return lines
    end

    -- No continuation - build normal line
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
    }
    setmetatable(instance, self)
    return instance
end

--- Check if a line is part of a table
--- @param text string The line text
--- @param linenr? integer Optional line number for context checking
--- @return boolean
function MarkdownTable.isPartOfTable(text, linenr)
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
    elseif linenr and linenr > 1 then
        -- Check if this might be a continuation line (previous line ends with \)
        local config = get_config()
        local line_breaks = config.tables.line_breaks or {}
        if line_breaks.pandoc or line_breaks.html then
            local prev_line = vim.api.nvim_buf_get_lines(0, linenr - 2, linenr - 1, false)
            prev_line = prev_line and prev_line[1] or ''
            -- If previous line is a table row ending with backslash continuation
            if prev_line:match('^%s*|') and prev_line:match('\\%s*|?%s*$') then
                -- And this line doesn't start with | (continuation, not new row)
                if text and not text:match('^%s*|') then
                    return true
                end
            end
        end
    end

    return tableyness >= 2
end

--- Check if a line looks like a new table row (starts with pipe or has table structure)
--- @param line string
--- @return boolean
local function is_new_table_row(line)
    if not line then
        return false
    end
    -- A new table row starts with optional whitespace then a pipe
    return line:match('^%s*|') ~= nil
end

--- Read a table from the buffer starting at a line number
--- @param line_nr? integer Starting line number (defaults to cursor position)
--- @return MarkdownTable
function MarkdownTable:read(line_nr)
    line_nr = line_nr or vim.api.nvim_win_get_cursor(0)[1]
    local tbl = MarkdownTable:new()
    local init_line_nr = line_nr
    local config = get_config()
    local line_breaks = config.tables.line_breaks or {}
    local multiline_enabled = line_breaks.pandoc or line_breaks.html

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
        -- Check if this is a continuation line (not a proper table row)
        -- A continuation line: doesn't start with |, but isPartOfTable returns true
        -- because the previous line ends with \
        -- Distinguish from tables without outer pipes by checking for internal | structure
        local is_continuation = false
        if multiline_enabled and not is_new_table_row(line) then
            -- Doesn't start with |. Check if it's a continuation or a no-outer-pipes row
            -- A continuation line has pipe only at the END (like "  content |")
            -- A table row without outer pipes has pipe(s) in the MIDDLE (like "a | b")
            local trimmed = line:gsub('^%s*', ''):gsub('%s*$', '')
            -- Check if the only pipe is at the end
            local content_before_pipe = trimmed:match('^(.+)|$')
            if content_before_pipe and not content_before_pipe:find('|') then
                -- Only has a trailing pipe, no internal pipes - this is a continuation line
                is_continuation = true
            elseif not trimmed:find('|') then
                -- No pipes at all - also a continuation line (or not a table line)
                is_continuation = true
            end
        end

        if is_continuation then
            -- Skip continuation lines - they'll be collected by their primary row
            line_nr = line_nr + direction
            if line_nr < 1 or line_nr > line_count then
                line = nil
            else
                line = vim.api.nvim_buf_get_lines(0, line_nr - 1, line_nr, false)[1]
            end
            -- Handle direction switching
            if direction == 1 and (not line or not MarkdownTable.isPartOfTable(line, line_nr)) then
                line_nr = init_line_nr - 1
                direction = -1
                if line_nr >= 1 then
                    line = vim.api.nvim_buf_get_lines(0, line_nr - 1, line_nr, false)[1]
                else
                    line = nil
                end
            end
            if direction == -1 and (not line or not MarkdownTable.isPartOfTable(line, line_nr)) then
                tbl.metadata.header_row_idx = line_nr + 1
                break
            end
            -- Continue to next iteration
        else
            -- This is a proper table row (starts with |)
            local row = TableRow:from_string(line, line_nr)
            rows_by_line[line_nr] = row

            if row.is_separator and not tbl.metadata.separator_row_idx then
                tbl.metadata.separator_row_idx = line_nr
            end

            -- Move to next line (within else block for proper rows)
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
        end -- end of else block for proper table rows
    end -- end of while loop

    -- Post-process: collect continuation lines for rows that need them
    -- This handles cases where we scanned upward and found the primary row
    -- but didn't collect its continuations
    if multiline_enabled then
        for line_num, row in pairs(rows_by_line) do
            if not row.is_separator and row:_has_continuation() and #row.continuation_lines == 0 then
                -- This row has a continuation marker but no collected continuations
                -- Look ahead for continuation lines
                local cont_line_nr = line_num + 1
                while cont_line_nr <= line_count do
                    local cont_line = vim.api.nvim_buf_get_lines(0, cont_line_nr - 1, cont_line_nr, false)[1]
                    -- Stop if we hit a new table row (starts with |) or empty/nil line
                    if not cont_line or cont_line:match('^%s*$') or is_new_table_row(cont_line) then
                        break
                    end
                    -- This is a continuation line
                    table.insert(row.continuation_lines, cont_line)
                    cont_line_nr = cont_line_nr + 1
                    -- Check if this continuation also continues
                    if not cont_line:match('\\%s*|?%s*$') then
                        break
                    end
                end
            end
        end
    end

    -- Sort rows by line number and add to table
    for line_num, row in get_utils().spairs(rows_by_line) do
        table.insert(tbl.rows, row)
        -- Track line range (include continuation lines)
        if tbl.line_range.start == 0 or line_num < tbl.line_range.start then
            tbl.line_range.start = line_num
        end
        local row_end = line_num + #row.continuation_lines
        if row_end > tbl.line_range.finish then
            tbl.line_range.finish = row_end
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
--- For cells with line breaks (\ or <br>), use the max width of individual parts
function MarkdownTable:_calculate_col_widths()
    self.col_widths = {}
    local config = get_config()
    local line_breaks = config.tables.line_breaks or {}

    -- Initialize with minimum width of 3
    for i = 1, self.col_count do
        self.col_widths[i] = 3
    end

    -- Find maximum width in each column (excluding separator row)
    for _, row in ipairs(self.rows) do
        if not row.is_separator then
            for idx, cell in ipairs(row.cells) do
                local effective_width = cell.display_width

                -- For the LAST cell only, check if content will be split at line breaks
                -- If so, use the max width of the parts, not the total width
                -- Also consider continuation lines (which only apply to the last cell)
                if idx == #row.cells then
                    if line_breaks.pandoc or line_breaks.html then
                        local parts = split_at_line_breaks(cell.content, line_breaks)
                        if #parts > 1 then
                            -- Find max width among all parts
                            effective_width = 0
                            for _, part in ipairs(parts) do
                                local part_width = width(part)
                                if part_width > effective_width then
                                    effective_width = part_width
                                end
                            end
                        end
                    end

                    -- Also consider continuation lines already collected (only for last cell)
                    if #row.continuation_lines > 0 then
                        for _, cont_line in ipairs(row.continuation_lines) do
                            local content = cont_line:gsub('^%s*', ''):gsub('%s*|%s*$', '')
                            local cont_width = width(content)
                            if cont_width > effective_width then
                                effective_width = cont_width
                            end
                        end
                    end
                end

                if effective_width > self.col_widths[idx] then
                    self.col_widths[idx] = effective_width
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

    -- Recalculate widths in case content changed
    self:_calculate_col_widths()

    local style = get_config().tables.style
    local formatted_lines = {}

    for _, row in ipairs(self.rows) do
        local formatted = row:format(self.col_widths, self.metadata.col_alignments, style)
        -- Handle multiline rows (returns table) vs single-line rows (returns string)
        if type(formatted) == 'table' then
            for _, line in ipairs(formatted) do
                table.insert(formatted_lines, line)
            end
        else
            table.insert(formatted_lines, formatted)
        end
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
    local style = get_config().tables.style
    local cell_padding = string.rep(' ', style.cell_padding or 1)
    local sep_padding = string.rep(' ', style.separator_padding or 1)
    local min_width = math.max(#(sep_padding .. '---' .. sep_padding), #(cell_padding .. cell_padding))

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
    local min_width = math.max(#(sep_padding .. '---' .. sep_padding), #(cell_padding .. cell_padding))

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
            new_cell = cell_padding .. string.rep(' ', min_width - 2 * #cell_padding) .. cell_padding
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
        local suffix_restored = row_text_work:sub((finish or 0) + 1):gsub(escaped_pipe_placeholder, '\\|')
        local replacement = match_restored .. new_cell .. suffix_restored

        table.insert(replacements, replacement)
    end

    vim.api.nvim_buf_set_lines(0, tbl.line_range.start - 1, tbl.line_range.finish, true, replacements)
end

-- =============================================================================
-- Module exports
-- =============================================================================

return {
    TableCell = TableCell,
    TableRow = TableRow,
    MarkdownTable = MarkdownTable,
}
