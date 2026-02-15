-- mkdnflow.nvim (Tools for personal markdown notebook navigation and management)
-- Copyright (C) 2022-2023 Jake W. Vincent <https://github.com/jakewvincent>
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

local cmp = require('cmp')

--- Build completion items from all notebook files using the plugin's path resolution
---@return table[] items Array of nvim-cmp completion items
---@private
local function get_files_items()
    local mkdn = require('mkdnflow')
    local config = mkdn.config
    local paths = require('mkdnflow.paths')
    local links = require('mkdnflow.links')

    -- Determine scan base using the same fallback chain as paths.relativeToBase()
    local path_resolution = config.path_resolution
    local base
    if path_resolution.primary == 'root' and mkdn.root_dir then
        base = mkdn.root_dir
    elseif
        path_resolution.primary == 'first'
        or (path_resolution.primary == 'root' and path_resolution.fallback == 'first')
    then
        base = mkdn.initial_dir
    else
        base = vim.fs.dirname(vim.api.nvim_buf_get_name(0))
    end
    if not base or base == '' then
        base = vim.fn.getcwd()
    end

    -- Use all enabled notebook extensions instead of hardcoded .md
    local extensions = config.notebook_extensions or { md = true }

    -- Find all matching files recursively
    local filepaths = vim.fs.find(function(name)
        local ext = name:match('%.([^%.]+)$')
        return ext and extensions[ext:lower()]
    end, { path = base, type = 'file', limit = math.huge })

    local implicit_ext = config.links.implicit_extension
    local items = {}
    for _, abs_path in ipairs(filepaths) do
        -- Compute path relative to the configured resolution base
        local rel_path = paths.relativeToBase(abs_path)

        -- Strip extension from link target when implicit_extension is configured
        local source_path = rel_path
        if implicit_ext then
            source_path = rel_path:gsub('%.[^%.]+$', '')
        end

        -- Display label is the filename without extension
        local label = vim.fs.basename(abs_path):gsub('%.[^%.]+$', '')

        -- Format link using the canonical formatter (respects style, compact, etc.)
        local formatted = links.formatLink(label, source_path)
        if formatted then
            -- Read first 1KB for documentation preview
            local f = io.open(abs_path, 'rb')
            local preview = f and f:read(1024)
            if f then
                f:close()
            end

            table.insert(items, {
                label = label,
                insertText = formatted[1],
                kind = cmp.lsp.CompletionItemKind.File,
                documentation = preview and { kind = cmp.lsp.MarkupKind.Markdown, value = preview }
                    or nil,
            })
        end
    end
    return items
end

--- Remove newline characters and collapse excessive whitespace
---@param text? string The text to clean
---@return string|nil text The cleaned text, or nil if input was nil
---@private
local function clean(text)
    if text then
        text = text:gsub('\n', ' ')
        return text:gsub('%s%s+', ' ')
    else
        return text
    end
end

--- Parse a .bib file and build nvim-cmp completion items for each entry
---@param filename string The path to the .bib file
---@return table[] items Array of nvim-cmp completion items
---@private
local function parse_bib(filename)
    local items = {}
    local file = io.open(filename, 'rb')
    if not file then
        return items
    end
    local bibentries = file:read('*all')
    file:close()
    for bibentry in bibentries:gmatch('@.-\n}\n') do
        local item = {}

        local title = clean(bibentry:match('title%s*=%s*["{]*(.-)["}],?')) or ''
        local author = clean(bibentry:match('author%s*=%s*["{]*(.-)["}],?')) or ''
        local year = bibentry:match('year%s*=%s*["{]?(%d+)["}]?,?') or ''

        local doc = { '**' .. title .. '**', '', '*' .. author .. '*', year }

        item.documentation = {
            kind = cmp.lsp.MarkupKind.Markdown,
            value = table.concat(doc, '\n'),
        }
        item.label = '@' .. bibentry:match('@%w+{(.-),')
        item.kind = cmp.lsp.CompletionItemKind.Reference
        item.insertText = item.label

        table.insert(items, item)
    end
    return items
end

---@class MkdnflowCmpSource
local source = {}

--- Create a new completion source instance
---@return MkdnflowCmpSource
source.new = function()
    return setmetatable({}, { __index = source })
end

--- Provide completion items (files + bib entries) when triggered by `@`
---@param params table nvim-cmp completion parameters
---@param callback fun(items: table[]) Callback to return completion items
function source:complete(params, callback)
    -- Only provide suggestions if the current word in the context starts with the trigger character '@'
    local line = params.context.cursor_before_line
    if not line or not (line:match('^@%w*$') or line:match('%W@%w*$')) then
        callback({})
        return
    end
    local items = get_files_items()
    local bib_paths = require('mkdnflow').bib and require('mkdnflow').bib.bib_paths or nil
    if bib_paths then
        -- For bib files, there are three lists (tables) in mkdnflow where we might find the paths for a bib file
        if bib_paths.default then
            for _, v in pairs(bib_paths.default) do
                local bib_items_default = parse_bib(v)
                for _, item in ipairs(bib_items_default) do
                    table.insert(items, item)
                end
            end
        end
        if bib_paths.root then
            for _, v in pairs(bib_paths.root) do
                local bib_items_root = parse_bib(v)
                for _, item in ipairs(bib_items_root) do
                    table.insert(items, item)
                end
            end
        end
        if bib_paths.yaml then
            for _, v in pairs(bib_paths.yaml) do
                local bib_items_yaml = parse_bib(v)
                for _, item in ipairs(bib_items_yaml) do
                    table.insert(items, item)
                end
            end
        end
    end
    callback(items)
end

local M = {}

--- Initialize cmp module: register as a completion source
M.init = function()
    cmp.register_source('mkdnflow', source.new())
end

return M
