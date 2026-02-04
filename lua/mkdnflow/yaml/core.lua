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

--- Detect YAML frontmatter block in a buffer
--- @param bufnr integer Buffer number (0 for current)
--- @return integer|nil start 0-indexed start line (always 0 if found)
--- @return integer|nil finish 0-indexed finish line (the closing ---)
local function detect_yaml_block(bufnr)
    bufnr = bufnr or 0
    local first_line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
    if not first_line or not first_line:match('^---$') then
        return nil, nil
    end

    local line_count = vim.api.nvim_buf_line_count(bufnr)
    for row = 1, line_count - 1 do
        local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
        if line and line:match('^---$') then
            return 0, row
        elseif not line then
            break
        end
    end

    return nil, nil
end

--- Parse YAML frontmatter block from a buffer
--- @param bufnr integer Buffer number (0 for current)
--- @param start integer 0-indexed start line
--- @param finish integer 0-indexed finish line
--- @return table data Parsed key-value pairs (values are arrays)
local function parse_yaml_block(bufnr, start, finish)
    bufnr = bufnr or 0
    local data = {}
    local last_key = nil

    for i = start, finish do
        local line = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1]
        if line then
            local key = line:match('^([%a_-]*):')
            -- Use non-greedy match: [^:]* matches up to first colon only
            -- Use %s* to strip all leading whitespace after colon
            local value = line:match('^[^:]*:%s*(.+)$')
            local item = line:match('^  %- (.*)')

            if key and value then
                data[key] = { value }
                last_key = key
            elseif key and not item then
                last_key = key
                data[key] = {}
            elseif item and last_key then
                table.insert(data[last_key], item)
            end
        end
    end

    return data
end

--- @class YAMLFrontmatter A class representing parsed YAML frontmatter
--- @field data table Parsed key-value pairs (values are arrays)
--- @field line_range {start: integer, finish: integer} 0-indexed line numbers (-1 if invalid)
--- @field valid boolean Whether frontmatter was found and parsed
--- @field bufnr integer Buffer this was read from (-1 if not from buffer)
local YAMLFrontmatter = {}
YAMLFrontmatter.__index = YAMLFrontmatter
YAMLFrontmatter.__className = 'YAMLFrontmatter'

--- Constructor for YAMLFrontmatter
--- @param opts table|nil Optional initial state
--- @return YAMLFrontmatter
function YAMLFrontmatter:new(opts)
    opts = opts or {}
    local instance = {
        data = opts.data or {},
        line_range = opts.line_range or { start = -1, finish = -1 },
        valid = opts.valid or false,
        bufnr = opts.bufnr or -1,
    }
    setmetatable(instance, self)
    return instance
end

--- Factory method: read frontmatter from a buffer
--- @param bufnr integer|nil Buffer number (0 or nil for current)
--- @return YAMLFrontmatter
function YAMLFrontmatter:read(bufnr)
    bufnr = bufnr or 0
    local instance = YAMLFrontmatter:new({ bufnr = bufnr })

    local start, finish = detect_yaml_block(bufnr)
    if start and finish then
        instance.line_range = { start = start, finish = finish }
        instance.data = parse_yaml_block(bufnr, start, finish)
        instance.valid = true
    end

    return instance
end

--- Get the first value for a key
--- @param key string The key to look up
--- @return string|nil The first value, or nil if not found
function YAMLFrontmatter:get(key)
    if self.data[key] and #self.data[key] > 0 then
        return self.data[key][1]
    end
    return nil
end

--- Get all values for a key as an array
--- @param key string The key to look up
--- @return table Array of values (empty if key not found)
function YAMLFrontmatter:get_all(key)
    if self.data[key] then
        return self.data[key]
    end
    return {}
end

--- Check if a key exists in the frontmatter
--- @param key string The key to check
--- @return boolean
function YAMLFrontmatter:has(key)
    return self.data[key] ~= nil
end

--- Check if the frontmatter is valid (was found and parsed)
--- @return boolean
function YAMLFrontmatter:is_valid()
    return self.valid
end

--- Get the line range of the frontmatter block
--- @return table {start: integer, finish: integer} 0-indexed line numbers (-1 if invalid)
function YAMLFrontmatter:get_line_range()
    return self.line_range
end

--- Get all keys in the frontmatter
--- @return table Array of key names
function YAMLFrontmatter:keys()
    local result = {}
    for key, _ in pairs(self.data) do
        table.insert(result, key)
    end
    table.sort(result)
    return result
end

--- Get the raw parsed data table
--- @return table The data table (values are arrays)
function YAMLFrontmatter:to_table()
    return self.data
end

return {
    YAMLFrontmatter = YAMLFrontmatter,
    detect_yaml_block = detect_yaml_block,
    parse_yaml_block = parse_yaml_block,
}
