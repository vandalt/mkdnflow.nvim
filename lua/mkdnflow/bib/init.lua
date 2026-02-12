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

-- Bibliography module entry point
-- This module provides the public API for bibliography operations using a
-- class-based architecture (BibEntry).

local core = require('mkdnflow.bib.core')
local BibEntry = core.BibEntry

-- =============================================================================
-- Module table and path storage
-- =============================================================================

local M = {}

-- Export class for advanced use
M.BibEntry = BibEntry

-- Path storage for bibliography files
M.bib_paths = {
    default = {},
    root = {},
    yaml = {},
}

--- Initialize bib_paths from config and filesystem
M.init = function()
    local bib_path = require('mkdnflow').config.bib.default_path
    local find_in_root = require('mkdnflow').config.bib.find_in_root
    local root_dir = require('mkdnflow').root_dir

    -- Find bib files in root directory
    if find_in_root and root_dir then
        local bib_files = vim.fn.glob(root_dir .. '/*.bib', false, true)
        for _, filepath in ipairs(bib_files) do
            table.insert(M.bib_paths.root, filepath)
        end
    end

    -- Add the default bib path(s)
    if type(bib_path) == 'table' then
        M.bib_paths.default = bib_path
    elseif bib_path then
        table.insert(M.bib_paths.default, bib_path)
    end
end

-- =============================================================================
-- Public API
-- =============================================================================

--[[
handleCitation() takes a citation and returns the most relevant link from
the bibliography entry. If no match is found, returns nil.

Priority: file > url > doi > howpublished

This function maintains backward compatibility with the original API.
--]]
--- @param citation string The citation (with @ prefix, e.g., "@smith2020")
--- @return string|nil The link URL/path, or nil if not found
M.handleCitation = function(citation)
    local silent = require('mkdnflow').config.silent
    local entry = core.findEntry(citation, M.bib_paths)

    if entry and entry:is_valid() then
        local link = entry:get_link()
        if link then
            return link
        else
            if not silent then
                vim.api.nvim_echo({
                    {
                        '⬇️  Bib entry with citekey "'
                            .. entry:get_citation_key()
                            .. '" had no relevant content!',
                        'WarningMsg',
                    },
                }, true, {})
            end
            return nil
        end
    end

    -- Entry not found - show warning
    if not silent then
        local citekey = citation:match('^@(.+)') or citation
        if citekey == '' then
            return nil
        end

        if not M.bib_paths.yaml[1] and not M.bib_paths.default[1] and not M.bib_paths.root[1] then
            vim.api.nvim_echo({
                {
                    '⬇️  Could not find a bib file. The default bib path is currently '
                        .. tostring(M.bib_paths.default[1])
                        .. '. Fix the path or add a default bib path by specifying a value for the "bib.default_path" key.',
                    'ErrorMsg',
                },
            }, true, {})
        else
            vim.api.nvim_echo(
                { { '⬇️  No entry found for "' .. citekey .. '"!', 'WarningMsg' } },
                true,
                {}
            )
        end
    end
    return nil
end

--[[
findEntry() returns the BibEntry instance for a citation.
This is the new class-based API for advanced usage.

Returns nil if no entry is found.
--]]
--- @param citation string The citation (with or without @ prefix)
--- @return BibEntry|nil The bibliography entry, or nil if not found
M.findEntry = function(citation)
    return core.findEntry(citation, M.bib_paths)
end

return M
