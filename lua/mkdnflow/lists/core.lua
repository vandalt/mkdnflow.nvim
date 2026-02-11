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

-- This module: List item and list classes for list management

-- =============================================================================
-- Helper functions
-- =============================================================================

--- Get the vim indentation unit (spaces or tab)
--- @return string The indentation string (spaces based on shiftwidth, or tab)
local function get_vim_indent()
    if vim.api.nvim_buf_get_option(0, 'expandtab') == true then
        return string.rep(' ', vim.api.nvim_buf_get_option(0, 'shiftwidth'))
    else
        return '\t'
    end
end

--- Calculate the indentation level based on the indentation string
--- @param indentation string The whitespace indentation prefix
--- @return integer The level (0 = no indent, 1 = one indent unit, etc.)
local function calculate_level(indentation)
    if not indentation or indentation == '' then
        return 0
    end
    local indent_unit = get_vim_indent()
    local level = 0
    local remaining = indentation
    while remaining:sub(1, #indent_unit) == indent_unit do
        level = level + 1
        remaining = remaining:sub(#indent_unit + 1)
    end
    return level
end

-- =============================================================================
-- Item cache (for avoiding re-parsing during single operations)
-- =============================================================================

local item_cache = {
    active = false,
    items = {},
}

--- Initialize the cache before a user-initiated operation
local function init_cache()
    item_cache.active = true
    item_cache.items = {}
end

--- Clear the cache after a user-initiated operation
local function clear_cache()
    item_cache.active = false
    item_cache.items = {}
end

--- Get item from cache by line number if it exists
--- @param line_nr integer The line number
--- @return ListItem|nil The cached item, or nil if not found
local function get_cached_item(line_nr)
    if item_cache.active and item_cache.items[line_nr] then
        return item_cache.items[line_nr]
    end
    return nil
end

--- Add item to cache
--- @param item ListItem The item to cache
local function cache_item(item)
    if item_cache.active and item.line_nr > 0 then
        item_cache.items[item.line_nr] = item
    end
end

-- =============================================================================
-- Pattern definitions
-- =============================================================================

local patterns = {
    ultd = { -- allow up to 4 bytes in the to-do checkbox
        li_type = 'ultd',
        main = '^%s*[+*-]%s+%[..?.?.?%]%s+',
        indentation = '^(%s*)[+*-]%s+%[..?.?.?%]',
        marker = '^%s*([+*-]%s+)%[..?.?.?%]%s+',
        content = '^%s*[+*-]%s+%[..?.?.?%]%s+(.+)',
        demotion = '^%s*[+*-]%s+',
        empty = '^%s*[+*-]%s+%[..?.?.?%]%s+$',
    },
    oltd = { -- allow up to 4 bytes in the to-do checkbox
        li_type = 'oltd',
        main = '^%s*%d+%.%s+%[..?.?.?%]%s+',
        indentation = '^(%s*)%d+%.%s+',
        marker = '^%s*%d+(%.%s+)%[..?.?.?%]%s+',
        number = '^%s*(%d+)%.',
        content = '^%s*%d+%.%s+%[..?.?.?%]%s+(.+)',
        demotion = '^%s*%d+%.%s+',
        empty = '^%s*%d+%.%s+%[..?.?.?%]%s+$',
    },
    ul = {
        li_type = 'ul',
        main = '^%s*[-*+]%s+',
        indentation = '^(%s*)[-*+]%s+',
        marker = '^%s*([-*+]%s+)',
        pre = '^%s*[-*+]',
        content = '^%s*[-*+]%s+(.+)',
        demotion = '^%s*',
        empty = '^%s*[-*+]%s+$',
    },
    ol = {
        li_type = 'ol',
        main = '^%s*%d+%.%s+',
        indentation = '^(%s*)%d+%.',
        marker = '^%s*%d+(%.%s+)',
        pre = '^%s*%d+%.',
        number = '^%s*(%d+)%.',
        content = '^%s*%d+%.%s+(.+)',
        demotion = '^%s*',
        empty = '^%s*%d+%.%s+$',
    },
}

-- =============================================================================
-- ListItem class
-- =============================================================================

--- @class ListItem A class for individual list items
--- @field line_nr integer The (one-based) line number on which the list item can be found
--- @field level integer The indentation-based level of the list item (0 == no indentation)
--- @field content string The text of the entire line stored under line_nr
--- @field text_content string The content after the marker
--- @field marker string The list marker (e.g., "- ", "1. ")
--- @field li_type string The list type ('ul', 'ol', 'ultd', 'oltd')
--- @field number integer|nil The number for ordered lists
--- @field valid boolean Whether the line contains a recognized list item
--- @field indentation string The raw whitespace indentation
--- @field parent ListItem|{} The parent item (if any)
--- @field children List The list of child items
--- @field host_list List|{} The list that contains this item
local ListItem = {}
ListItem.__index = ListItem
ListItem.__className = 'ListItem'

--- Constructor method for list items
--- @param opts? table A table of possible options with values for the instance
--- @return ListItem A skeletal list item
function ListItem:new(opts)
    opts = opts or {}
    local instance = {
        line_nr = opts.line_nr or -1,
        level = opts.level or -1,
        content = opts.content or '',
        text_content = opts.text_content or '',
        marker = opts.marker or '',
        li_type = opts.li_type or '',
        number = opts.number or nil,
        valid = opts.valid or false,
        indentation = opts.indentation or '',
        parent = opts.parent or {},
        children = nil, -- Will be set to List:new() on demand
        host_list = opts.host_list or {},
    }
    setmetatable(instance, self)
    return instance
end

--- Factory method to read a list item from a buffer line (lightweight, no relationships)
--- @param line_nr integer A (one-based) buffer line number from which to read the list item
--- @return ListItem A complete list item (without relationship data)
function ListItem:read(line_nr)
    -- Check cache first
    local cached_item = get_cached_item(line_nr)
    if cached_item then
        return cached_item
    end

    local new_item = ListItem:new()
    new_item.line_nr = line_nr

    -- Get the line
    local line = vim.api.nvim_buf_get_lines(0, line_nr - 1, line_nr, false)
    new_item.content = (not vim.tbl_isempty(line)) and line[1] or ''

    -- Check if we have a valid list item
    local li_types = { 'ultd', 'oltd', 'ul', 'ol' }
    for _, li_type in ipairs(li_types) do
        local match = string.match(new_item.content, patterns[li_type].main)
        if match then
            new_item.valid = true
            new_item.li_type = li_type
            new_item.indentation = new_item.content:match(patterns[li_type].indentation) or ''
            new_item.level = calculate_level(new_item.indentation)
            new_item.marker = new_item.content:match(patterns[li_type].marker) or ''
            new_item.text_content = new_item.content:match(patterns[li_type].content) or ''

            if patterns[li_type].number then
                local num_str = new_item.content:match(patterns[li_type].number)
                new_item.number = num_str and tonumber(num_str) or nil
            end

            cache_item(new_item)
            return new_item
        end
    end

    new_item.valid = false
    cache_item(new_item)
    return new_item
end

--- Factory method to read a list item with full context (builds relationships)
--- @param line_nr integer A (one-based) buffer line number
--- @return ListItem A complete list item with relationships
function ListItem:get(line_nr)
    -- Check validity first to avoid building an empty list
    local item = ListItem:read(line_nr)
    if not item.valid then
        return item
    end
    -- Build the full list with relationships
    local List = require('mkdnflow.lists.core').List
    local list = List:new():read(line_nr)
    local list_item = list.items[list.requester_idx]
    if list_item then
        list_item.host_list = list
    end
    return list_item or item
end

--- Method to check if the list item has a registered parent
--- @return boolean
function ListItem:has_parent()
    return not vim.tbl_isempty(self.parent)
end

--- Method to check if the list item has registered children
--- @return boolean
function ListItem:has_children()
    return self.children ~= nil and not vim.tbl_isempty(self.children.items)
end

--- Method to check if the list item has registered siblings
--- @return boolean
function ListItem:has_siblings()
    if self.host_list and self.host_list.items and #self.host_list.items > 1 then
        return true
    end
    return false
end

--- Method to check if the list item is empty (no text content)
--- @return boolean
function ListItem:is_empty()
    return self.content:match(patterns[self.li_type].empty) ~= nil
end

--- Method to check if the list item is ordered
--- @return boolean
function ListItem:is_ordered()
    return self.li_type == 'ol' or self.li_type == 'oltd'
end

--- Method to check if the list item is a to-do item
--- @return boolean
function ListItem:is_todo()
    return self.li_type == 'ultd' or self.li_type == 'oltd'
end

-- =============================================================================
-- List class
-- =============================================================================

--- @class List A class for a complete list (series of same-level list items)
--- @field items ListItem[] A list of same-level list items
--- @field relatives_added boolean Whether relationships have been built
--- @field parent ListItem|{} The parent item (if any)
--- @field line_range {start: integer, finish: integer} The start and end line numbers
--- @field base_level integer The indentation level of items in this list
--- @field requester_idx integer The index of the item that triggered the read
local List = {}
List.__index = List
List.__className = 'List'

--- Constructor method for lists
--- @return List A skeletal list
function List:new()
    local instance = {
        items = {},
        relatives_added = false,
        parent = {},
        line_range = { start = 0, finish = 0 },
        base_level = -1,
        requester_idx = -1,
    }
    setmetatable(instance, self)
    return instance
end

--- Method to add a list item to the list (maintains line order)
--- @param item ListItem A valid list item
function List:add_item(item)
    if item.valid then
        local added = false
        for i = 1, #self.items, 1 do
            if self.items[i].line_nr > item.line_nr then
                table.insert(self.items, i, item)
                added = true
                break
            end
        end
        if not added then
            table.insert(self.items, item)
        end
        -- Update line range
        self.line_range.start = self.items[1].line_nr
        self.line_range.finish = self.items[#self.items].line_nr
    end
end

--- Method to read a list at the level of the item at the given line number
--- Uses bidirectional scanning to find all siblings
--- @param line_nr integer A line number where a list item can be found
--- @return List A filled-in list instance
function List:read(line_nr)
    local item = ListItem:read(line_nr)
    local line_count = vim.api.nvim_buf_line_count(0)

    if item.valid then
        self:add_item(item)
        self.base_level = item.level

        -- Look up for siblings
        for _line_nr = item.line_nr - 1, 1, -1 do
            local candidate = ListItem:read(_line_nr)
            if candidate.level < self.base_level or not candidate.valid then
                break
            end
            if candidate.valid and candidate.level == self.base_level then
                -- Check if it's the same list type
                if candidate.li_type == item.li_type then
                    self:add_item(candidate)
                else
                    break
                end
            end
            -- If candidate level > base_level, it's a child of a previous sibling, skip it
        end

        -- Look down for siblings
        for _line_nr = item.line_nr + 1, line_count, 1 do
            local candidate = ListItem:read(_line_nr)
            if candidate.level < self.base_level or not candidate.valid then
                break
            end
            if candidate.valid and candidate.level == self.base_level then
                -- Check if it's the same list type
                if candidate.li_type == item.li_type then
                    self:add_item(candidate)
                else
                    break
                end
            end
            -- If candidate level > base_level, it's a child, skip it
        end

        -- Set the index of the requester
        for i, sibling in ipairs(self.items) do
            if sibling.line_nr == line_nr then
                self.requester_idx = i
                break
            end
        end
    end

    return self:add_relatives()
end

--- Method to identify all relationships within a list
--- @param parent? ListItem The parent that all list members descend from
--- @return List A list with relationships identified
function List:add_relatives(parent)
    -- Look for a parent
    if self.base_level > 0 and self.line_range.start > 1 then
        parent = parent or ListItem:read(self.line_range.start - 1)
        if parent.valid and parent.level == self.base_level - 1 then
            parent.children = self
            self.parent = parent
            for _, child in ipairs(self.items) do
                child.parent = self.parent
            end
        end
    end

    -- Register any children
    for i, sibling in ipairs(self.items) do
        -- If there is space between the next item and the current item, there must be children
        if self.items[i + 1] and self.items[i + 1].line_nr > sibling.line_nr + 1 then
            local children = List:new():read(sibling.line_nr + 1)
            if children.base_level == sibling.level + 1 then
                sibling.children = children
            end
        elseif not self.items[i + 1] then
            -- We're at the last sibling; check below it
            local candidate = ListItem:read(sibling.line_nr + 1)
            if candidate.valid and candidate.level == sibling.level + 1 then
                local children = List:new():read(sibling.line_nr + 1)
                sibling.children = children
            end
        end
    end

    self.relatives_added = true
    local terminus = self:terminus()
    self.line_range.finish = terminus and terminus.line_nr or self.line_range.start

    return self
end

--- Method to identify the last list item in a list, including the most deeply embedded
--- descendant of the last list item, if any
--- @return ListItem|nil The last list item in the list
function List:terminus()
    local function last_item(list)
        if #list.items == 0 then
            return nil
        end
        local last_sib = list.items[#list.items]
        if last_sib:has_children() then
            last_sib = last_item(last_sib.children)
        end
        return last_sib
    end
    return last_item(self)
end

--- Method to flatten a list's descendants into one table
--- @param content_only boolean Whether to return just the content of the flattened lines
--- @return table[] A list of descendant list items or content strings
function List:flatten(content_only)
    local flattened = {}
    local function flatten_item(item)
        table.insert(flattened, content_only and item.content or item)
        if item:has_children() then
            for _, child in ipairs(item.children.items) do
                flatten_item(child)
            end
        end
    end

    for _, item in ipairs(self.items) do
        flatten_item(item)
    end
    return flattened
end

--- Method to update numbering for all items in an ordered list
--- @param start_num? integer The number to start from (defaults to first item's number or 1)
function List:update_numbering(start_num)
    if #self.items == 0 then
        return
    end

    -- Only update ordered lists
    local first_item = self.items[1]
    if not first_item:is_ordered() then
        return
    end

    local n = start_num
    for i, item in ipairs(self.items) do
        if not n then
            n = item.number and (item.number + 1) or 2
        else
            if item.number ~= n then
                -- Replace with the correct number on that line
                local line = vim.api.nvim_buf_get_lines(0, item.line_nr - 1, item.line_nr, false)[1]
                local replacement =
                    line:gsub('^' .. item.indentation .. '%d+%.', item.indentation .. n .. '.')
                vim.api.nvim_buf_set_lines(
                    0,
                    item.line_nr - 1,
                    item.line_nr,
                    false,
                    { replacement }
                )
                item.number = n
                item.content = replacement
            end
            n = n + 1
        end
    end
end

-- =============================================================================
-- Module exports
-- =============================================================================

return {
    ListItem = ListItem,
    List = List,
    patterns = patterns,
    get_vim_indent = get_vim_indent,
    calculate_level = calculate_level,
    init_cache = init_cache,
    clear_cache = clear_cache,
}
