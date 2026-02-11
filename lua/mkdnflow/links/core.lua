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

-- This module: Link and LinkPart classes for link management

-- =============================================================================
-- Helper functions
-- =============================================================================

--- Check if a position is contained within a range
--- @param start_row integer Start row (1-indexed)
--- @param start_col integer Start column (1-indexed)
--- @param end_row integer End row (1-indexed)
--- @param end_col integer End column (1-indexed)
--- @param cur_row integer Current row (1-indexed)
--- @param cur_col integer Current column (1-indexed)
--- @return boolean Whether the position is contained
local function contains(start_row, start_col, end_row, end_col, cur_row, cur_col)
    local contained = cur_row > start_row and cur_row < end_row
    if cur_row == start_row and start_row == end_row then
        contained = cur_col > start_col - 1 and cur_col <= end_col
    elseif cur_row == start_row then
        contained = cur_col > start_col - 1
    elseif cur_row == end_row then
        contained = cur_col <= end_col
    end
    return contained
end

--- Extract anchor from a source string
--- @param text string The source text
--- @return string, string The text without anchor, and the anchor (or empty string)
local function extract_anchor(text)
    if not text then
        return '', ''
    end
    local anchor_start, _, anchor = string.find(text, '(#.*)')
    if anchor_start then
        return string.sub(text, 1, anchor_start - 1), anchor
    end
    return text, ''
end

-- =============================================================================
-- Link cache (for avoiding re-parsing during single operations)
-- =============================================================================

local link_cache = {
    active = false,
    links = {},
}

--- Initialize the cache before a user-initiated operation
local function init_cache()
    link_cache.active = true
    link_cache.links = {}
end

--- Clear the cache after a user-initiated operation
local function clear_cache()
    link_cache.active = false
    link_cache.links = {}
end

--- Get link from cache by row and col if it exists
--- @param row integer The row number
--- @param col integer The column number
--- @return Link|nil The cached link, or nil if not found
local function get_cached_link(row, col)
    if link_cache.active then
        local key = string.format('%d:%d', row, col)
        return link_cache.links[key]
    end
    return nil
end

--- Add link to cache
--- @param link Link The link to cache
--- @param row integer The row number
--- @param col integer The column number
local function cache_link(link, row, col)
    if link_cache.active then
        local key = string.format('%d:%d', row, col)
        link_cache.links[key] = link
    end
end

-- =============================================================================
-- Pattern definitions
-- =============================================================================

-- Pattern order: more specific patterns should come before less specific ones
local pattern_order = {
    'image_link',
    'md_link',
    'wiki_link',
    'auto_link',
    'ref_style_link',
    'pandoc_citation',
    'citation',
}

local patterns = {
    image_link = '(!%b[]%b())', -- Must come before md_link
    md_link = '(%b[]%b())',
    wiki_link = '(%[%b[]%])',
    ref_style_link = '(%b[]%s?%b[])',
    auto_link = '(%b<>)',
    pandoc_citation = '(%[@[^%[%]]+%])', -- Pandoc-style bracketed citation [@citekey]
    citation = "[^%a%d]-(@[%a%d_%.%-']*[%a%d]+)[%s%p%c]?",
}

-- Part extraction patterns for each link type
local part_patterns = {
    name = {
        image_link = '!%[(.-)%]',
        md_link = '%[(.-)%]',
        wiki_link = '|(.-)%]',
        wiki_link_no_bar = '%[%[(.-)%]%]',
        wiki_link_anchor_no_bar = '%[%[(.-)#.-%]%]',
        ref_style_link = '%[(.-)%]%s?%[',
        pandoc_citation = '%[@([^%[%]]+)%]', -- Captures citekey without @ or brackets
        citation = '(@.*)',
    },
    source = {
        image_link = { '!%b[](%b())', '%((.-)%)' },
        md_link = { '%](%b())', '%((.-)%)' },
        wiki_link = '%[%[(.-)|.-%]%]',
        wiki_link_no_bar = '%[%[(.-)%]%]',
        ref_style_link = '%]%[(.-)%]',
        auto_link = '<(.-)>',
        pandoc_citation = '%[(@[^%[%]]+)%]', -- Captures @citekey (without brackets)
        citation = '(@.*)',
    },
    anchor = {
        image_link = '(#.-)%)',
        md_link = '(#.-)%)',
        wiki_link = '(#.-)|',
        wiki_link_no_bar = '(#.-)%]%]',
        auto_link = '<.-(#.-)>',
    },
}

-- =============================================================================
-- LinkPart class
-- =============================================================================

--- @class LinkPart A class representing an extracted part of a link
--- @field text string The extracted text
--- @field anchor string The anchor portion (may be empty)
--- @field start_row integer Start row (1-indexed)
--- @field start_col integer Start column (1-indexed)
--- @field end_row integer End row (1-indexed)
--- @field end_col integer End column (1-indexed)
local LinkPart = {}
LinkPart.__index = LinkPart
LinkPart.__className = 'LinkPart'

--- Constructor method for link parts
--- @param opts? table A table of options
--- @return LinkPart A link part instance
function LinkPart:new(opts)
    opts = opts or {}
    local instance = {
        text = opts.text or '',
        anchor = opts.anchor or '',
        start_row = opts.start_row or 0,
        start_col = opts.start_col or 0,
        end_row = opts.end_row or 0,
        end_col = opts.end_col or 0,
    }
    setmetatable(instance, self)
    return instance
end

--- Check if this part has an anchor
--- @return boolean True if this part has an anchor
function LinkPart:has_anchor()
    return self.anchor ~= nil and self.anchor ~= ''
end

--- Get the text without the anchor
--- @return string The text without the anchor
function LinkPart:get_text()
    return self.text
end

--- Get the anchor
--- @return string The anchor
function LinkPart:get_anchor()
    return self.anchor
end

--- Get the full text including the anchor
--- @return string The text with the anchor appended
function LinkPart:get_full_text()
    if self:has_anchor() then
        return self.text .. self.anchor
    end
    return self.text
end

-- =============================================================================
-- Link class
-- =============================================================================

--- @class Link A class representing a detected link
--- @field match string The raw matched text
--- @field match_lines table The multiline context
--- @field type string The link type ('image_link'|'md_link'|'wiki_link'|'auto_link'|'ref_style_link'|'pandoc_citation'|'citation')
--- @field start_row integer Start row (1-indexed)
--- @field start_col integer Start column (1-indexed)
--- @field end_row integer End row (1-indexed)
--- @field end_col integer End column (1-indexed)
--- @field valid boolean Whether this is a valid link
--- @field _source LinkPart|nil Cached source part
--- @field _name LinkPart|nil Cached name part
--- @field _anchor LinkPart|nil Cached anchor part
local Link = {}
Link.__className = 'Link'

-- Index map for backwards compatibility with tuple-style access
local index_map = {
    [1] = 'match',
    [2] = 'match_lines',
    [3] = 'type',
    [4] = 'start_row',
    [5] = 'start_col',
    [6] = 'end_row',
    [7] = 'end_col',
}

-- Custom __index to support both property access and numeric indexing
Link.__index = function(self, key)
    if type(key) == 'number' then
        local prop = index_map[key]
        if prop then
            return rawget(self, prop)
        end
        return nil
    end
    return Link[key] or rawget(self, key)
end

--- Constructor method for links
--- @param opts? table A table of options
--- @return Link A link instance
function Link:new(opts)
    opts = opts or {}
    local instance = {
        match = opts.match or '',
        match_lines = opts.match_lines or {},
        type = opts.type or '',
        start_row = opts.start_row or 0,
        start_col = opts.start_col or 0,
        end_row = opts.end_row or 0,
        end_col = opts.end_col or 0,
        valid = opts.valid or false,
        _source = nil,
        _name = nil,
        _anchor = nil,
    }
    setmetatable(instance, self)
    return instance
end

--- Factory method to read a link from the cursor position (lightweight, no parts extraction)
--- @param col? integer Column position (0-indexed, uses cursor position if nil)
--- @param buffer? integer Buffer number (uses current buffer if nil)
--- @return Link|nil A link instance if found, nil otherwise
function Link:read(col, buffer)
    buffer = buffer or 0
    local position = vim.api.nvim_win_get_cursor(0)
    col = col or position[2]
    local row = position[1]

    -- Check cache first
    local cached = get_cached_link(row, col)
    if cached then
        return cached
    end

    -- Get config
    local config = require('mkdnflow').config or {}
    local links_config = config.links or {}
    local context = links_config.context or 0

    -- Get lines with context
    local lines = vim.api.nvim_buf_get_lines(buffer, row - 1 - context, row + context, false)

    local utils = require('mkdnflow').utils

    -- Iterate through patterns in order to find a matching link
    for _, link_type in ipairs(pattern_order) do
        local pattern = patterns[link_type]
        local init_row, init_col = 1, 1
        local continue = true

        while continue do
            local start_row, start_col, end_row, end_col, capture, match_lines =
                utils.mFind(lines, pattern, row - context, init_row, init_col)

            if start_row and link_type == 'citation' then
                -- Skip if @ is preceded by an alphanumeric character (e.g. email
                -- addresses like user@domain.com are not citations)
                if start_col > 1 then
                    local line_idx = start_row - (row - context) + 1
                    local preceding_char = lines[line_idx]:sub(start_col - 1, start_col - 1)
                    if preceding_char:match('[%a%d]') then
                        init_row, init_col = end_row, end_col
                        goto continue_search
                    end
                end
                -- Remove Saxon genitive if present
                local possessor = string.gsub(capture, "'s$", '')
                if #capture > #possessor then
                    capture = possessor
                    end_col = end_col - 2
                end
            end

            -- Check for overlap with cursor
            if start_row then
                local overlaps =
                    contains(start_row, start_col, end_row, end_col, position[1], position[2] + 1)
                if overlaps then
                    local link = Link:new({
                        match = capture,
                        match_lines = match_lines,
                        type = link_type,
                        start_row = start_row,
                        start_col = start_col,
                        end_row = end_row,
                        end_col = end_col,
                        valid = true,
                    })
                    cache_link(link, row, col)
                    return link
                else
                    init_row, init_col = end_row, end_col
                end
            else
                continue = false
            end
            ::continue_search::
        end
    end

    return nil
end

--- Get the reference definition for a ref-style link
--- @param refnr string The reference number/label
--- @param start_row? integer Starting row for search
--- @return string|nil, integer|nil, integer|nil, integer|nil The source, row, start col, end col
local function get_ref(refnr, start_row)
    if not refnr then
        return nil
    end
    start_row = start_row or vim.api.nvim_win_get_cursor(0)[1]
    local row = start_row + 1
    local line_count = vim.api.nvim_buf_line_count(0)

    while row <= line_count do
        local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]
        local start, finish, match = string.find(line, '^(%[' .. refnr .. '%]: .*)')
        if match then
            local _, label_finish = string.find(match, '^%[.-%]: ')
            return string.sub(match, label_finish + 1), row, label_finish + 1, finish
        else
            row = row + 1
        end
    end
    return nil
end

--- Get the source part of the link (lazy, cached)
--- @return LinkPart The source part
function Link:get_source()
    if self._source then
        return self._source
    end

    if not self.valid then
        self._source = LinkPart:new()
        return self._source
    end

    local utils = require('mkdnflow').utils
    local text, anchor, s_row, s_col, e_row, e_col

    if self.type == 'image_link' then
        local pats = part_patterns.source.image_link
        s_row, s_col, e_row, e_col, text =
            utils.mFind(self.match_lines, pats, self.start_row, nil, self.start_col)
        if text then
            -- Check for angle brackets
            if text:find('^<.*>$') then
                s_row, s_col, e_row, e_col, text =
                    utils.mFind(self.match_lines, '%(<(.*)>%)', s_row)
            end
            text, anchor = extract_anchor(text)
        end
    elseif self.type == 'md_link' then
        local pats = part_patterns.source.md_link
        s_row, s_col, e_row, e_col, text =
            utils.mFind(self.match_lines, pats, self.start_row, nil, self.start_col)
        if text then
            -- Check for angle brackets
            if text:find('^<.*>$') then
                s_row, s_col, e_row, e_col, text =
                    utils.mFind(self.match_lines, '%(<(.*)>%)', s_row)
            end
            text, anchor = extract_anchor(text)
        end
    elseif self.type == 'wiki_link' then
        local pat = part_patterns.source.wiki_link
        s_row, s_col, e_row, e_col, text =
            utils.mFind(self.match_lines, pat, self.start_row, nil, self.start_col)
        if text then
            -- Check for angle brackets
            if text:find('^<.*>$') then
                s_row, s_col, e_row, e_col, text = utils.mFind(self.match_lines, '%[<(.*)>|', s_row)
            end
            text, anchor = extract_anchor(text)
        else
            -- Try no-bar pattern
            pat = part_patterns.source.wiki_link_no_bar
            s_row, s_col, e_row, e_col, text =
                utils.mFind(self.match_lines, pat, self.start_row, nil, self.start_col)
            if text then
                -- Check for angle brackets
                if text:find('^<.*>$') then
                    s_row, s_col, e_row, e_col, text =
                        utils.mFind(self.match_lines, '%[<(.*)>]', s_row)
                end
                text, anchor = extract_anchor(text)
            end
        end
    elseif self.type == 'ref_style_link' then
        local pat = part_patterns.source.ref_style_link
        s_row, s_col, e_row, e_col, text = utils.mFind(self.match_lines, pat, self.start_row)
        if text then
            local source, source_row, source_start, source_end = get_ref(text, s_row)
            if source then
                -- Check for title
                local title = string.match(source, '.* (["\'%(%[].*["\'%)%]])')
                if title then
                    local start, ref_source
                    start, _, ref_source = string.find(source, '^<(.*)> ["\'%(%[].*["\'%)%]]')
                    if not start then
                        start, _, source = string.find(source, '^(.*) ["\'%(%[].*["\'%)%]]')
                    else
                        start = start + 1
                        source = ref_source
                    end
                    s_col = source_start + start - 1
                    e_col = s_col + #source - 1
                else
                    local start, ref_source
                    start, _, ref_source = string.find(source, '^<(.*)>')
                    if not start then
                        start, _, source = string.find(source, '^(.-)%s*$')
                    else
                        start = start + 1
                        source = ref_source
                    end
                    s_col = source_start + start - 1
                    e_col = s_col + #source - 1
                end
                s_row, e_row = source_row, source_row
                text, anchor = extract_anchor(source)
            else
                text = nil
            end
        end
    elseif self.type == 'auto_link' then
        local pat = part_patterns.source.auto_link
        s_row, s_col, e_row, e_col, text = utils.mFind(self.match_lines, pat, self.start_row)
        if text then
            text, anchor = extract_anchor(text)
        end
    elseif self.type == 'citation' then
        local pat = part_patterns.source.citation
        s_col, e_col, text = string.find(self.match, pat)
        s_row, e_row = self.start_row, self.end_row
        anchor = ''
    elseif self.type == 'pandoc_citation' then
        local pat = part_patterns.source.pandoc_citation
        s_col, e_col, text = string.find(self.match, pat)
        s_row, e_row = self.start_row, self.end_row
        anchor = ''
    end

    self._source = LinkPart:new({
        text = text or '',
        anchor = anchor or '',
        start_row = s_row or 0,
        start_col = s_col or 0,
        end_row = e_row or 0,
        end_col = e_col or 0,
    })

    return self._source
end

--- Get the name/display text part of the link (lazy, cached)
--- @return LinkPart The name part
function Link:get_name()
    if self._name then
        return self._name
    end

    if not self.valid then
        self._name = LinkPart:new()
        return self._name
    end

    local utils = require('mkdnflow').utils
    local text, s_row, s_col, e_row, e_col

    if self.type == 'image_link' then
        local pat = part_patterns.name.image_link
        s_row, s_col, e_row, e_col, text =
            utils.mFind(self.match_lines, pat, self.start_row, nil, self.start_col)
    elseif self.type == 'md_link' then
        local pat = part_patterns.name.md_link
        s_row, s_col, e_row, e_col, text =
            utils.mFind(self.match_lines, pat, self.start_row, nil, self.start_col)
    elseif self.type == 'wiki_link' then
        local pat = part_patterns.name.wiki_link
        s_row, s_col, e_row, e_col, text =
            utils.mFind(self.match_lines, pat, self.start_row, nil, self.start_col)
        if not text then
            -- Try pattern for link with anchor but no bar
            if self.match and string.match(self.match, '#') then
                pat = part_patterns.name.wiki_link_anchor_no_bar
                s_row, s_col, e_row, e_col, text =
                    utils.mFind(self.match_lines, pat, self.start_row, nil, self.start_col)
            end
            if not text then
                -- Try no-bar pattern
                pat = part_patterns.name.wiki_link_no_bar
                s_row, s_col, e_row, e_col, text =
                    utils.mFind(self.match_lines, pat, self.start_row, nil, self.start_col)
            end
        end
    elseif self.type == 'ref_style_link' then
        local pat = part_patterns.name.ref_style_link
        s_row, s_col, e_row, e_col, text = utils.mFind(self.match_lines, pat, self.start_row)
    elseif self.type == 'citation' then
        local pat = part_patterns.name.citation
        s_col, e_col, text = string.find(self.match, pat)
        s_row, e_row = self.start_row, self.end_row
    elseif self.type == 'pandoc_citation' then
        local pat = part_patterns.name.pandoc_citation
        s_col, e_col, text = string.find(self.match, pat)
        s_row, e_row = self.start_row, self.end_row
    end

    self._name = LinkPart:new({
        text = text or '',
        anchor = '',
        start_row = s_row or 0,
        start_col = s_col or 0,
        end_row = e_row or 0,
        end_col = e_col or 0,
    })

    return self._name
end

--- Get the anchor part of the link (lazy, cached)
--- @return LinkPart The anchor part
function Link:get_anchor()
    if self._anchor then
        return self._anchor
    end

    -- Anchor is extracted as part of get_source, so ensure that's called first
    local source = self:get_source()

    self._anchor = LinkPart:new({
        text = source.anchor,
        anchor = source.anchor,
        start_row = source.start_row,
        start_col = source.start_col,
        end_row = source.end_row,
        end_col = source.end_col,
    })

    return self._anchor
end

-- =============================================================================
-- Query methods
-- =============================================================================

--- Check if this is an image link
--- @return boolean
function Link:is_image()
    return self.type == 'image_link'
end

--- Check if this is a wiki link
--- @return boolean
function Link:is_wiki()
    return self.type == 'wiki_link'
end

--- Check if this is a citation
--- @return boolean
function Link:is_citation()
    return self.type == 'citation'
end

--- Check if this is a Pandoc-style bracketed citation
--- @return boolean
function Link:is_pandoc_citation()
    return self.type == 'pandoc_citation'
end

--- Check if this is a markdown link
--- @return boolean
function Link:is_markdown()
    return self.type == 'md_link'
end

--- Check if this is an auto link
--- @return boolean
function Link:is_auto()
    return self.type == 'auto_link'
end

--- Check if this is a reference-style link
--- @return boolean
function Link:is_ref_style()
    return self.type == 'ref_style_link'
end

--- Check if this link has an anchor
--- @return boolean
function Link:has_anchor()
    local source = self:get_source()
    return source.anchor ~= nil and source.anchor ~= ''
end

--- Get the link type
--- @return string
function Link:get_type()
    return self.type
end

-- =============================================================================
-- Module exports
-- =============================================================================

return {
    Link = Link,
    LinkPart = LinkPart,
    patterns = patterns,
    pattern_order = pattern_order,
    part_patterns = part_patterns,
    init_cache = init_cache,
    clear_cache = clear_cache,
    contains = contains,
    extract_anchor = extract_anchor,
}
