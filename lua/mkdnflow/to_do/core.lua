-- mkdnflow.nvim (Tools for fluent markdown notebook navigation and management)
-- Copyright (C) 2024 Jake W. Vincent <https://github.com/jakewvincent>
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

-- This module: To-do list related functions
local silent = require('mkdnflow').config.silent
local to_do_statuses = require('mkdnflow').config.to_do.statuses

--- Get the vim indentation unit (spaces or tab) for the current buffer
--- @return string The indentation string (spaces based on shiftwidth, or tab)
local function get_vim_indent()
    if vim.api.nvim_buf_get_option(0, 'expandtab') == true then
        return string.rep(' ', vim.api.nvim_buf_get_option(0, 'shiftwidth'))
    else
        return '\t'
    end
end

-- Item cache to avoid re-parsing the same lines during a single operation
local item_cache = {
    active = false,
    items = {},
}

-- Initialize the cache before a user-initiated operation
local function init_cache()
    item_cache.active = true
    item_cache.items = {}
end

-- Clear the cache after a user-initiated operation
local function clear_cache()
    item_cache.active = false
    item_cache.items = {}
end

-- Get item from cache by line number if it exists
local function get_cached_item(line_nr)
    if item_cache.active and item_cache.items[line_nr] then
        return item_cache.items[line_nr]
    end
    return nil
end

-- Add item to cache
local function cache_item(item)
    if item_cache.active and item.valid and item.line_nr > 0 then
        item_cache.items[item.line_nr] = item
    end
end

local status_methods = {
    __index = {
        get_marker = function(self)
            if type(self.marker) == 'table' then
                return self.marker[1]
            else
                return self.marker
            end
        end,
        get_extra_markers = function(self)
            local markers = {}
            if type(self.marker) == 'table' then
                for i = 2, #self.marker do
                    table.insert(markers, self.marker[i])
                end
            end
            return markers
        end,
    },
}

-- Set the methods for each status table
for _, status in ipairs(to_do_statuses) do
    setmetatable(status, status_methods)
end

--- Method to get the name of a to-do marker
--- @param marker string A to-do status marker
--- @return string|nil # The name of a to-do status marker
function to_do_statuses:name(marker)
    -- Look for the marker first in the primary markers
    for _, status_tbl in ipairs(self) do
        if status_tbl:get_marker() == marker then
            return status_tbl.name
        end
    end
    -- If the name has not been found yet, look in legacy markers
    for _, status_tbl in ipairs(self) do
        if vim.tbl_contains(status_tbl:get_extra_markers(), marker) then
            return status_tbl.name
        end
    end
end

--- Method to get the marker for a to-do status name
--- @param name string A to-do status name
--- @return string|nil # The corresponding marker, or nil if there is no corresponding marker
function to_do_statuses:get_marker(name)
    for _, status_tbl in ipairs(self) do
        if status_tbl.name == name then
            return status_tbl:get_marker()
        end
    end
end

--- Method to get the index of a to-do status name
--- @param status string|table A to-do status name or marker, or a status table
--- @return integer|nil # The index of the status in the list of statuses
function to_do_statuses:index(status)
    status = type(status) == 'table' and status.name or status
    for i, status_tbl in ipairs(self) do
        if status_tbl.name == status or status_tbl:get_marker() == status then
            return i
        end
    end
    -- If the status has not been found yet, look in legacy markers
    for i, status_tbl in ipairs(self) do
        if vim.tbl_contains(status_tbl:get_extra_markers(), status) then
            return i
        end
    end
end

--- Method to get a status table (includes name and marker) based on a name or marker
--- @param status string|table A name or marker by which to retrieve a status table from the config
--- @return table|nil # A table containing at least the name and marker for a status
function to_do_statuses:get(status)
    status = type(status) == 'table' and status.name or status
    for _, status_tbl in ipairs(self) do
        if status_tbl.name == status or status_tbl:get_marker() == status then
            return status_tbl
        end
    end
    -- If the status has not been found yet, look in legacy markers
    for _, status_tbl in ipairs(self) do
        if vim.tbl_contains(status_tbl:get_extra_markers(), status) then
            return status_tbl
        end
    end
end

--- Method to get the next marker
--- @param status string|table A name or marker by which to retrieve a status table from the config
--- @return table # A status table (containing the name and marker of the status)
function to_do_statuses:next(status)
    local cur_status = type(status) == 'table' and (status.name or status[1]) or status
    local idx = self:index(cur_status) -- Index of the current status
    local next_idx = idx
    local count = 0

    repeat
        next_idx = (next_idx % #self) + 1
        count = count + 1
        -- Failure => recycle the current status
        if count > #self then
            return self[idx]
        end
    until not self[next_idx].skip_on_toggle

    return self[next_idx]
end

--- To-do lists
--- @class to_do_list A class for a complete to-do list (series of same-level to-do items)
--- @field items table[] A list of same-level to-do items
--- @field relatives_added boolean
--- @field line_range{start: integer, finish:integer} A table containing the start and end line numbers of the list
--- @field base_level integer
--- @field requester_idx integer
local to_do_list = {}
to_do_list.__index = to_do_list
to_do_list.__className = 'to_do_list'

--- Constructor method for to-do lists
--- @return to_do_list # A skeletal to-do list
function to_do_list:new()
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

--- A class for individual to-do items
--- @class to_do_item
--- @field line_nr integer The (one-based) line number on which the to-do item can be found
--- @field level integer The indentation-based level of the to-do item (0 == the item has no indentation and no parents)
--- @field content string The text of the entire line stored under line_nr
--- @field status {name: string, marker: string|string[], sort: {section: integer, position: string}, propagate: {up: fun(host_list: to_do_list):string|nil, down: fun(children_list: to_do_list): string|nil}} A to-do status table
--- @field valid boolean Whether the line contains a recognized to-do item
--- @field parent to_do_item The closest item in the list that has a level one less than the child item
--- @field children to_do_list A list of to-do items one level higher beneath the main item
--- @field host_list to_do_list The to-do list that contains the item
local to_do_item = {}
to_do_item.__index = to_do_item
to_do_item.__className = 'to_do_item'

--- Constructor method for to-do items
--- @param opts? table # A table of possible options with values for the instance
--- @return to_do_item # A skeletal to-do item
function to_do_item:new(opts)
    opts = opts or {}
    local instance = {
        line_nr = opts.line_nr or -1,
        level = opts.level or -1,
        content = opts.content or '',
        status = opts.status or {},
        valid = opts.valid or false,
        parent = opts.parent or {},
        children = opts.children or to_do_list:new(),
        host_list = opts.host_list or {},
    }
    setmetatable(instance, self)
    return instance
end

--- A method to read a to-do list at the level of the item at the line number passed in
--- @param line_nr integer A line number where a to-do item can be found
--- @return to_do_list # A filled-in to-do list instance
function to_do_list:read(line_nr)
    local item, line_count = to_do_item:read(line_nr), vim.api.nvim_buf_line_count(0)
    if item.valid then
        self:add_item(item)
        self.base_level = item.level
        -- Look up for siblings
        for _line_nr = item.line_nr - 1, 1, -1 do
            local candidate = to_do_item:read(_line_nr)
            if candidate.level < self.base_level or not candidate.valid then
                break
            end
            if candidate.valid and candidate.level == self.base_level then
                self:add_item(candidate)
            end
        end
        -- Look down for siblings
        for _line_nr = item.line_nr + 1, line_count, 1 do
            local candidate = to_do_item:read(_line_nr)
            if candidate.level < self.base_level or not candidate.valid then
                break
            end
            if candidate.valid and candidate.level == self.base_level then
                self:add_item(candidate)
            end
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

--- A method to identify all relationships within a to-do list
--- @param parent? to_do_item The parent that all list members descend from
--- @return to_do_list # A to-do list with relationships identified
function to_do_list:add_relatives(parent)
    -- Look for a parent
    if self.base_level > 0 then
        parent = parent or to_do_item:read(self.line_range.start - 1)
        if parent.valid then
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
            local children = to_do_list:new():read(sibling.line_nr + 1)
            sibling.children = children
        else -- We're at the last sibling; check below it
            local candidate = to_do_item:read(sibling.line_nr + 1)
            if candidate.valid and candidate.level == sibling.level + 1 then
                local children = to_do_list:new():read(sibling.line_nr + 1)
                sibling.children = children
            end
        end
    end
    self.relatives_added = true
    local terminus = self:terminus()
    self.line_range.finish = terminus and terminus.line_nr or self.line_range.start
    return self
end

--- A method to identify the last to-do item in a to-do list, including the most deeply embedded
--- descendant of the last list item, if any
--- @return to_do_item # The last to-do item in the list
function to_do_list:terminus()
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

--- Method to read a to-do item from a line number
--- @param line_nr integer A (one-based) buffer line number from which to read the to-do item
--- @return to_do_item # A complete to-do item
function to_do_item:read(line_nr)
    -- Check cache first
    local cached_item = get_cached_item(line_nr)
    if cached_item then
        return cached_item
    end

    local new_to_do_item = to_do_item:new() -- Create a new instance
    -- Get the line
    local line = vim.api.nvim_buf_get_lines(0, line_nr - 1, line_nr, false)
    new_to_do_item.content = (not vim.tbl_isempty(line)) and line[1] or ''
    -- Check if we have a valid to-do list new_to_do_item
    local valid_str = new_to_do_item.content:match('^%s-[-+*%d]+%.?%s-%[..?.?.?.?.?%]') -- Up to 6 bytes for the status
    if valid_str then
        -- Retrieve the marker from the matching string
        local marker = valid_str:match('%[(..?.?.?.?.?)%]')
        -- Record line nr, status
        new_to_do_item.valid, new_to_do_item.line_nr, new_to_do_item.status =
            true, line_nr, to_do_statuses:get(marker) or {}

        -- Figure out the level of the new_to_do_item (based on indentation)
        _, new_to_do_item.level =
            string.gsub(new_to_do_item.content:match('^%s*'), get_vim_indent(), '')
        -- Add this to-do item to the cache
        cache_item(new_to_do_item)
        return new_to_do_item
    end
    new_to_do_item.valid = false
    -- Cache invalid items too, to avoid re-parsing non-to-do lines
    cache_item(new_to_do_item)
    return new_to_do_item
end

function to_do_item:get(line_nr)
    -- Check validity first to avoid building an empty list
    local item = to_do_item:read(line_nr)
    if not item.valid then
        return item
    end
    -- Build the full list with relationships
    local list = to_do_list:new():read(line_nr)
    local list_item = list.items[list.requester_idx]
    list_item.host_list = list
    return list_item
end

--- Method to retrieve the default marker of a to-do status
--- @return string # The to-do status marker, as a string
function to_do_item:get_marker()
    return self.status:get_marker()
end

--- Method to retrieve the current/active marker of a to-do item
--- @return string # The current to-do status marker (from the `content` attribute)
function to_do_item:current_marker()
    return self.content:match('%s*[-+*%d]+%.?%s*%[(.-)%]')
end

--- Method to get any and all legacy/extra markers from a to-do status table
--- @return string[] # A list of strings
function to_do_item:get_extra_markers()
    return self.status:get_extra_markers()
end

--- Method to get the status object for a target status
--- @param target string|table A string (to-do marker or to-do name) or a table containing both
function to_do_item:set_status(target, dependent_call, propagation_direction)
    dependent_call = dependent_call == nil and false or dependent_call
    local config = require('mkdnflow').config.to_do

    -- Save cursor position before changing the line
    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    local cursor_col = cursor_pos[2]
    local cursor_row = cursor_pos[1]

    -- Get the line content before changes
    local old_line = self.content
    local marker_pos = old_line:find('%[.-%]')
    local old_marker = self:current_marker()

    -- Create the new line, substituting the current status with the target status
    -- Get the status object
    local target_status = type(target) == 'table' and target or to_do_statuses:get(target)
    local new_marker = target_status ~= nil and target_status:get_marker() or old_marker

    -- Prep the updated text for the line
    local new_line = self.content:gsub(
        string.format('%%[(%s)%%]', old_marker), -- The current marker
        -- Recycle the current marker if the target status is not recognized
        string.format('%%[%s%%]', new_marker),
        1
    )

    -- Update the buffer
    vim.api.nvim_buf_set_lines(0, self.line_nr - 1, self.line_nr, false, { new_line })

    -- Update status (or keep the same if no target was found)
    self.status = target_status ~= nil and target_status or self.status
    -- Update the item's content attribute
    self.content = new_line

    -- If this is the cursor's line, restore proper cursor position
    if cursor_row == self.line_nr and marker_pos and cursor_col >= marker_pos then
        -- Calculate cursor position adjustment for marker change
        local old_effective_len = #old_marker
        local new_effective_len = #new_marker

        -- Special handling for blank space - crucially important for cursor position!
        -- When the marker is just a space, effectively treat it as having zero width
        -- for visual cursor positioning purposes
        if old_marker == ' ' then
            old_effective_len = 0
        end
        if new_marker == ' ' then
            new_effective_len = 0
        end

        -- Handle offset correction factor:
        -- If we're departing from a blank status and cursor is at or right after
        -- the marker, we need to adjust by -1 to account for the visual offset
        local correction = 0
        if old_marker == ' ' and new_marker ~= ' ' then
            correction = -1
        elseif old_marker ~= ' ' and new_marker == ' ' then
            correction = 1
        end

        -- Compute difference in effective length with correction
        local diff = (new_effective_len - old_effective_len) + correction

        -- Only adjust cursor if after the marker
        if cursor_col >= marker_pos then
            local new_col = cursor_col + diff

            -- Ensure cursor doesn't go beyond end of line or before marker
            local line_length = #new_line
            if new_col > line_length then
                new_col = line_length
            end

            vim.api.nvim_win_set_cursor(0, { cursor_row, new_col })
        end
    end

    -- Update parents if possible and desired
    if
        not vim.tbl_isempty(self.parent) and config.status_propagation.up
        or config.status_propagation.down
    then
        self:propagate_status(dependent_call, propagation_direction)
    end

    -- Sort the to-do list if desired
    if config.sort.on_status_change and not dependent_call then
        self.host_list:sort(self)
    end
end

--- Method to change a to-do item's status to the next status in the config list
function to_do_item:rotate_status(dependent_call)
    if not self.valid then
        return
    end
    dependent_call = dependent_call == nil and false or dependent_call
    local next_status = to_do_statuses:next(self.status)
    self:set_status(next_status, dependent_call)
end

--- Shortcut method to change a to-do item's status to 'complete'
function to_do_item:complete(dependent_call, propagation_direction)
    dependent_call = dependent_call == nil and false or dependent_call
    self:set_status('complete', dependent_call, propagation_direction)
end

--- Shortcut method to change a to-do item's status to 'not_started'
function to_do_item:not_started(dependent_call, propagation_direction)
    dependent_call = dependent_call == nil and false or dependent_call
    self:set_status('not_started', dependent_call, propagation_direction)
end

--- Shortcut method to change a to-do item's status to 'in_progress'
function to_do_item:in_progress(dependent_call, propagation_direction)
    dependent_call = dependent_call == nil and false or dependent_call
    self:set_status('in_progress', dependent_call, propagation_direction)
end

--- Method to update parents in response to children status changes
function to_do_item:propagate_status(dependent_call, direction)
    local config = require('mkdnflow').config.to_do
    -- Don't do anything if the item has no parent
    if config.status_propagation.up == false and config.status_propagation.down == false then
        return
    end
    -- Update parental lineage first
    if config.status_propagation.up and self:has_parent() and direction ~= 'down' then
        local parent_updated = false
        local target_status = (self.status.propagate and self.status.propagate.up)
            and self.status.propagate.up(self.host_list)
        if target_status and self.parent.status.name ~= target_status then
            self.parent:set_status(target_status, true, 'up')
            parent_updated = true
        end
        if parent_updated then
            local parent_line_nr = self.parent.line_nr
            -- Get parent to-do list
            local parent = to_do_item:get(parent_line_nr)
            parent:propagate_status(true, 'up')
        end
    end
    -- Update children
    if config.status_propagation.down and self:has_children() then
        -- Get a list of target statuses
        local target_statuses = (self.status.propagate and self.status.propagate.down)
            and self.status.propagate.down(self.children)
        if target_statuses and #target_statuses ~= #self.children.items then
            -- TODO: Issue a warning
        end
        if target_statuses and not vim.tbl_isempty(target_statuses) then
            for i, child in ipairs(self.children.items) do
                child:set_status(target_statuses[i], true, 'down')
            end
        end
    end
end

--- Method to identify whether a to-do item has registered siblings or not
--- @return boolean
function to_do_item:has_siblings()
    -- The item will have siblings as long as it is not the only item in the host list
    if #self.host_list.items > 1 then
        return true
    end
    return false
end

--- Method to identify whether a to-do item has registered children or not
--- @return boolean
function to_do_item:has_children()
    if not vim.tbl_isempty(self.children.items) then
        return true
    end
    return false
end

--- Method to identify whether a to-do item has a registered parent or not
--- @return boolean
function to_do_item:has_parent()
    if not vim.tbl_isempty(self.parent) then
        return true
    end
    return false
end

--- Method to flatten a to-do item's descendants into one table
--- @param content_only boolean Whether to return just the content of the flattened lines or the
--- full to-do items
--- @return table[] # A list of descendant to-do items, empty if the item has no descendants
function to_do_list:flatten(content_only)
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

--- Method to add a to-do item to an (internal) to-do list
--- @param item to_do_item A valid to-do item
function to_do_list:add_item(item)
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

--- Method to sort a to-do list
--- @param target_item? to_do_item The item whose status change triggered the sort call
function to_do_list:sort(target_item)
    local sections, cursor =
        {}, {
            new_line = 0,
            old_position = vim.api.nvim_win_get_cursor(0),
            old_column_bytes = 0,
        }

    -- If the cursor is on a to-do item, save the byte position before the marker
    if cursor.old_position[1] > 0 then
        local line_content = vim.api.nvim_buf_get_lines(
            0,
            cursor.old_position[1] - 1,
            cursor.old_position[1],
            false
        )[1]
        local marker_pos = line_content:find('%[.-%]')

        if marker_pos and cursor.old_position[2] > 0 then
            -- Calculate cursor position relative to the marker
            if cursor.old_position[2] < marker_pos then
                -- Cursor is before the marker, keep byte position as is
                cursor.old_column_bytes = cursor.old_position[2]
            else
                -- Cursor is at or after the marker
                -- Store the offset from the beginning of line to the cursor
                cursor.old_column_bytes = cursor.old_position[2]

                -- Also store the marker for reference (to detect changes)
                local marker = line_content:match('%[(.-)%]')
                if marker then
                    cursor.old_marker = marker
                end
            end
        else
            -- No marker found or cursor at start, just keep original position
            cursor.old_column_bytes = cursor.old_position[2]
        end
    end

    -- Put the siblings in their respective section
    local hold = {}
    for _, item in ipairs(self.items) do
        if not sections[item.status.sort.section] then
            sections[item.status.sort.section] = {}
        end
        if
            target_item
            and target_item.line_nr == item.line_nr
            and (item.status.sort.position == 'top' or item.status.sort.position == 'bottom')
        then
            table.insert(hold, item)
        else
            table.insert(sections[item.status.sort.section], item)
        end
    end

    -- Now add the held items (if any)
    for _, item in ipairs(hold) do
        if not sections[item.status.sort.section] then
            sections[item.status.sort.section] = {}
        end
        if item.status.sort.position == 'top' then
            table.insert(sections[item.status.sort.section], 1, item)
        elseif item.status.sort.position == 'bottom' then
            table.insert(sections[item.status.sort.section], item)
        end
    end

    local replacement_lines = {}
    -- Gather the sections, flattening any descendants
    local cur_replacee_line = self.line_range.start
    for _, tbl in vim.spairs(sections) do
        for _, item in ipairs(tbl) do
            table.insert(replacement_lines, item.content)
            if item.line_nr == cursor.old_position[1] then
                cursor.new_line = cur_replacee_line
                cursor.new_content = item.content
            end
            cur_replacee_line = cur_replacee_line + 1
            if item:has_children() then
                local descendants = item.children:flatten()
                for _, item_ in ipairs(descendants) do
                    if item_.line_nr == cursor.old_position[1] then
                        cursor.new_line = cur_replacee_line
                        cursor.new_content = item_.content
                    end
                    cur_replacee_line = cur_replacee_line + 1
                    table.insert(replacement_lines, item_.content)
                end
            end
        end
    end

    -- Replace the lines in the buffer
    vim.api.nvim_buf_set_lines(
        0,
        self.line_range.start - 1,
        self.line_range.finish,
        false,
        replacement_lines
    )

    -- Move the cursor if desired
    if require('mkdnflow').config.to_do.sort.cursor_behavior.track and cursor.new_line > 0 then
        -- Calculate correct cursor column position accounting for marker changes
        local new_col = cursor.old_column_bytes

        if cursor.new_content and cursor.old_marker then
            local new_marker_pos = cursor.new_content:find('%[.-%]')
            local new_marker = cursor.new_content:match('%[(.-)%]')

            if new_marker_pos and new_marker and cursor.old_position[2] >= new_marker_pos then
                -- Cursor was after marker, adjust for any change in marker length
                local marker_len_diff = #new_marker - #cursor.old_marker
                new_col = cursor.old_column_bytes + marker_len_diff

                -- Make sure we don't go beyond line end or before marker
                local line_length = #cursor.new_content
                if new_col > line_length then
                    new_col = line_length
                elseif new_col < new_marker_pos then
                    new_col = new_marker_pos
                end
            end
        end

        vim.api.nvim_win_set_cursor(0, { cursor.new_line, new_col })
    end
end

--- The to_do module table
local M = {}

--- Function to retrieve a to-do item
--- @param line_nr? integer A table, optionally including line_nr (int) and find_ancestors (bool)
--- @param use_cache? boolean Whether to use the cache for this operation, defaults to true
--- @return to_do_item # A processed to-do item
function M.get_to_do_item(line_nr, use_cache)
    -- Use the current (cursor) line if no line number was provided
    line_nr = line_nr or vim.api.nvim_win_get_cursor(0)[1] -- Use cur. line if no line provided

    -- Activate cache if not already active and use_cache not explicitly false
    if use_cache ~= false and not item_cache.active then
        init_cache()
        local item = to_do_item:get(line_nr)
        clear_cache()
        return item
    end

    -- TODO If we have a visual selection spanning multiple lines, take a different approach
    local item = to_do_item:get(line_nr)
    return item
end

--- Function to retrieve an entire to-do list
--- @param line_nr integer A line number (anywhere in the list) from which to look for to-do items
--- @param use_cache? boolean Whether to use the cache for this operation, defaults to true
--- @return to_do_list # A complete to-do list
function M.get_to_do_list(line_nr, use_cache)
    line_nr = line_nr or vim.api.nvim_win_get_cursor(0)[1] -- Use cur. line if no line provided

    -- Activate cache if not already active and use_cache not explicitly false
    if use_cache ~= false and not item_cache.active then
        init_cache()
        local list = to_do_list:new():read(line_nr)
        clear_cache()
        return list
    end

    local list = to_do_list:new():read(line_nr)
    return list
end

--- Function to cycle through the to-do status markers for the item on the current line
--- @param opts? {line1: integer, line2: integer} Optional range (e.g. from a visual-mode command)
function M.toggle_to_do(opts)
    -- Initialize the cache for this operation
    init_cache()

    opts = opts or {}
    local line1, line2 = opts.line1, opts.line2

    if line1 and line2 then
        -- Range provided (from visual mode via command pipeline)
        for line_nr = line1, line2 do
            M.get_to_do_item(line_nr):rotate_status()
        end
    else
        local mode = vim.api.nvim_get_mode()['mode']
        -- If we're in any visual mode (direct call, not via command), toggle selected lines.
        -- getpos('v') returns valid line numbers for v, V, and <C-V> alike.
        if mode == 'v' or mode == 'V' or mode == '\22' then
            local pos_a, pos_b = vim.fn.getpos('v')[2], vim.api.nvim_win_get_cursor(0)[1]
            local first, last =
                (pos_a < pos_b and pos_a) or pos_b, (pos_b > pos_a and pos_b) or pos_a
            if first == 0 or last == 0 then
                M.get_to_do_item(pos_b):rotate_status()
            else
                for line_nr = first, last do
                    M.get_to_do_item(line_nr):rotate_status()
                end
            end
        else
            local item = M.get_to_do_item()
            if item.valid then
                item:rotate_status()
            else
                -- Convert a plain list item to a to-do item (#292)
                local lists = require('mkdnflow').lists
                local row = vim.api.nvim_win_get_cursor(0)[1]
                local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]
                local li_type = lists.hasListType(line)
                if li_type == 'ul' or li_type == 'ol' then
                    local _, last = string.find(line, lists.patterns[li_type].pre)
                    local not_started_marker = to_do_statuses:get('not_started'):get_marker()
                    vim.api.nvim_buf_set_text(
                        0,
                        row - 1,
                        last,
                        row - 1,
                        last,
                        { ' [' .. not_started_marker .. ']' }
                    )
                end
            end
        end
    end

    -- Clear the cache after the operation
    clear_cache()
end

--- Sort the to-do list containing the cursor
function M.sort_to_do_list()
    init_cache()
    local item = M.get_to_do_item()
    if item and item.valid and item.host_list then
        item.host_list:sort()
    elseif not silent then
        vim.api.nvim_echo({ { 'No to-do list found at cursor position', 'WarningMsg' } }, true, {})
    end
    clear_cache()
end

-- Add cache control functions to the module
M.init_cache = init_cache
M.clear_cache = clear_cache

return M
