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
local extension = '.md' -- Keep the '.'

--- Build completion items from all markdown files in the notebook root directory
---@return table[] items Array of nvim-cmp completion items
---@private
local function get_files_items()
    local mkdnflow_root_dir = require('mkdnflow').root_dir
    local transform_on_create = require('mkdnflow').config.links.transform_on_create
    -- Find all markdown files recursively in the root directory
    local filepaths_in_root = vim.fs.find(function(name)
        return name:match('%' .. extension .. '$')
    end, { path = mkdnflow_root_dir, type = 'file', limit = math.huge })
    local items = {}
    -- Iterate over files in the root directory & prepare for completion (if md file)
    for _, path in ipairs(filepaths_in_root) do
        if vim.endswith(path, extension) then
            local item = {}
            -- Absolute path of the file
            item.path = path
            -- Anything except / and \ (\\) followed by the extension so that folders will be excluded
            -- from the label
            item.label = path:match('([^/^\\]+)' .. extension .. '$')
            local explicit_link = transform_on_create
                    and transform_on_create(item.label) .. extension
                or item.label .. extension
            -- Text should be inserted in markdown format
            item.insertText = '[' .. item.label .. '](' .. explicit_link .. ')'
            -- For beautification
            item.kind = cmp.lsp.CompletionItemKind.File

            local filepath = item.path
            local binary = assert(io.open(filepath, 'rb'))
            local first_kb = binary:read(1024)

            -- Close the file
            binary:close()

            local contents = {}
            -- Add to the table if it's not an empty file
            if first_kb then
                for content in first_kb:gmatch('[^\r\n]+') do
                    table.insert(contents, content)
                end
            end

            item.documentation = { kind = cmp.lsp.MarkupKind.Markdown, value = first_kb }

            table.insert(items, item)
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
