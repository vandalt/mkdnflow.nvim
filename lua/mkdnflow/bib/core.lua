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

-- This module: BibEntry class and core bibliography parsing logic

-- =============================================================================
-- Helper functions
-- =============================================================================

--- Lazy config accessor to ensure config is accessed after setup()
local function get_config()
    return require('mkdnflow').config
end

-- =============================================================================
-- BibEntry Class
-- =============================================================================

--- @class BibEntry A class representing a bibliography entry
--- @field key string The citation key (e.g., "smith2020")
--- @field entry_type string The entry type (e.g., "article", "book")
--- @field fields table<string, string> All parsed fields
--- @field raw_text string Original entry text
--- @field valid boolean Whether this is a valid entry
local BibEntry = {}
BibEntry.__index = BibEntry
BibEntry.__className = 'BibEntry'

--- Constructor for BibEntry
--- @param opts? table Optional initial values
--- @return BibEntry
function BibEntry:new(opts)
    opts = opts or {}
    local instance = {
        key = opts.key or '',
        entry_type = opts.entry_type or '',
        fields = opts.fields or {},
        raw_text = opts.raw_text or '',
        valid = opts.valid or false,
    }
    setmetatable(instance, self)
    return instance
end

--- Factory method: parse a BibEntry from raw BibTeX entry text
--- @param text string The raw BibTeX entry text (content inside outer braces)
--- @return BibEntry
function BibEntry:read(text)
    local entry = BibEntry:new({ raw_text = text or '' })

    if not text or text == '' then
        return entry
    end

    local fields = {}
    local key_found = false

    for line in text:gmatch('%s*(.-)\n') do
        if not key_found then
            local citekey = line:match('{(.-),')
            if citekey then
                key_found = true
                entry.key = citekey
                entry.valid = true
            end
        else
            local field_key = line:match('^(.-)%s*=')
            if field_key then
                field_key = string.lower(field_key)
                -- Extract value using balanced brace matching
                local eq_pos = line:find('=')
                if eq_pos then
                    local after_eq = line:sub(eq_pos + 1)
                    local brace_start = after_eq:find('{')
                    if brace_start then
                        -- Use %b{} for balanced brace matching
                        local value = after_eq:match('%b{}')
                        if value then
                            -- Remove outer braces and trailing comma
                            value = value:sub(2, -2)
                            fields[field_key] = value
                        end
                    end
                end
            end
        end
    end

    entry.fields = fields
    return entry
end

--- Get the citation key
--- @return string
function BibEntry:get_citation_key()
    return self.key
end

--- Get the entry type (article, book, etc.)
--- @return string
function BibEntry:get_entry_type()
    return self.entry_type
end

--- Get the authors as a list
--- @return string[] List of author names
function BibEntry:get_authors()
    local author_field = self.fields.author
    if not author_field then
        return {}
    end

    local authors = {}

    -- Split on " and " (BibTeX author separator)
    -- Add sentinel to handle last author
    for author in (author_field .. ' and '):gmatch('(.-)%s+and%s+') do
        author = vim.trim(author)
        if author ~= '' then
            table.insert(authors, author)
        end
    end

    -- If no " and " found, the whole field is a single author
    if #authors == 0 and author_field ~= '' then
        local trimmed = vim.trim(author_field)
        if trimmed ~= '' then
            return { trimmed }
        end
    end

    return authors
end

--- Get the title
--- @return string|nil
function BibEntry:get_title()
    return self.fields.title
end

--- Get the year
--- @return string|nil
function BibEntry:get_year()
    return self.fields.year
end

--- Get any field by name
--- @param name string The field name (case-insensitive)
--- @return string|nil
function BibEntry:get_field(name)
    return self.fields[string.lower(name)]
end

--- Check if the entry has a field
--- @param name string The field name (case-insensitive)
--- @return boolean
function BibEntry:has_field(name)
    return self.fields[string.lower(name)] ~= nil
end

--- Check if this is a valid entry
--- @return boolean
function BibEntry:is_valid()
    return self.valid and self.key ~= ''
end

--- Get the best available link from the entry
--- Priority: file > url > doi > howpublished
--- @return string|nil
function BibEntry:get_link()
    if self.fields.file then
        return 'file:' .. self.fields.file
    elseif self.fields.url then
        return self.fields.url
    elseif self.fields.doi then
        return 'https://doi.org/' .. self.fields.doi
    elseif self.fields.howpublished then
        return self.fields.howpublished
    end
    return nil
end

--- Format the citation for display
--- @param style? string Citation style (default: "default")
--- @return string
function BibEntry:format_citation(style)
    style = style or 'default'

    local authors = self:get_authors()
    local year = self:get_year() or ''
    local title = self:get_title() or ''

    if style == 'default' then
        local author_str = ''
        if #authors > 0 then
            if #authors == 1 then
                author_str = authors[1]
            elseif #authors == 2 then
                author_str = authors[1] .. ' and ' .. authors[2]
            else
                author_str = authors[1] .. ' et al.'
            end
        end

        if author_str ~= '' and year ~= '' then
            return author_str .. ' (' .. year .. ')'
        elseif author_str ~= '' then
            return author_str
        elseif title ~= '' then
            return title
        else
            return '@' .. self.key
        end
    end

    return '@' .. self.key
end

-- =============================================================================
-- Private search functions
-- =============================================================================

--- Search a bib file for an entry matching the citekey
--- @param path string Path to the bib file
--- @param citekey string The citation key to search for
--- @return string|nil Raw entry text if found
local function search_bib_file(path, citekey)
    local bib_file = io.open(path, 'r')
    if bib_file then
        local text = bib_file:read('*a')
        bib_file:close()
        if text then
            -- Check first at the beginning of the file text; then at the beginning of each line
            local start, _ = string.find(text, '^%s?@[%a]-{%s?' .. vim.pesc(citekey))
            if not start then
                start, _ = string.find(text, '\n%s?@[%a]-{%s?' .. vim.pesc(citekey))
            end

            -- If we have a match, get the entry based on bracket matching
            if start then
                local match = text:match('%b{}', start)
                return match
            end
        end
    end
    return nil
end

--- Search a bib source for an entry
--- @param citekey string The citation key
--- @param source string The source to search ("yaml", "root", "default")
--- @param bib_paths table The bib_paths table from init
--- @return BibEntry|nil
local function search_bib_source(citekey, source, bib_paths)
    local paths = bib_paths[source]
    if not paths then
        return nil
    end

    local i = #paths
    while i >= 1 do
        local entry_text = search_bib_file(paths[i], citekey)
        if entry_text then
            return BibEntry:read(entry_text)
        end
        i = i - 1
    end
    return nil
end

-- =============================================================================
-- Module exports
-- =============================================================================

local M = {}

--- Find a bibliography entry for a citation
--- @param citation string The citation (with or without @ prefix)
--- @param bib_paths table The bib_paths table
--- @return BibEntry|nil
function M.findEntry(citation, bib_paths)
    -- Extract citekey (remove @ prefix if present)
    local citekey = citation:match('^@(.+)') or citation
    if citekey == '' then
        return nil
    end

    local config = get_config()
    local yaml = config.yaml
    local find_in_root = config.bib.find_in_root
    local root_dir = require('mkdnflow').root_dir

    local entry
    if yaml.bib.override and bib_paths.yaml[1] then
        entry = search_bib_source(citekey, 'yaml', bib_paths)
    elseif find_in_root and root_dir and bib_paths.root[1] then
        entry = search_bib_source(citekey, 'yaml', bib_paths)
            or search_bib_source(citekey, 'root', bib_paths)
            or search_bib_source(citekey, 'default', bib_paths)
    elseif bib_paths.yaml[1] or bib_paths.default[1] then
        entry = search_bib_source(citekey, 'yaml', bib_paths)
            or search_bib_source(citekey, 'default', bib_paths)
    end

    return entry
end

-- Export the BibEntry class
M.BibEntry = BibEntry

return M
