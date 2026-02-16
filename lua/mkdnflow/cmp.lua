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
-- TODO: Use vim.uv directly when v0.9.5 support is dropped
local uv = vim.uv or vim.loop

--- Generation counter for cancelling stale async completion requests.
--- Incremented on each source:complete() call; the deferred callback bails
--- if its captured generation no longer matches.
local generation = 0

local MAX_SCAN_DEPTH = 20

--- Recursively scan a directory for files matching a predicate, asynchronously.
---
--- uv.fs_scandir offloads the directory read to libuv's thread pool (async),
--- while uv.fs_scandir_next iterates over already-loaded in-memory results
--- (synchronous). The async benefit comes from the directory read, not the
--- entry iteration.
---
---@param dir string Base directory to scan
---@param predicate fun(name: string): boolean Filter function for file names
---@param on_done fun(filepaths: string[]) Called with all matching absolute paths
---@private
local function async_scan_dir(dir, predicate, on_done)
    local results = {}
    local pending = 0

    local function scan(path, depth)
        if depth > MAX_SCAN_DEPTH then
            return
        end
        pending = pending + 1
        uv.fs_scandir(path, function(err, handle)
            if err or not handle then
                pending = pending - 1
                if pending == 0 then
                    on_done(results)
                end
                return
            end

            -- Collect entries first, then process (scandir_next is synchronous
            -- iteration over already-loaded results)
            local entries = {}
            while true do
                local name, entry_type = uv.fs_scandir_next(handle)
                if not name then
                    break
                end
                table.insert(entries, { name = name, type = entry_type })
            end

            local function process_entry(full_path, resolved_type)
                if resolved_type == 'directory' then
                    scan(full_path, depth + 1)
                elseif resolved_type == 'file' then
                    local name = full_path:match('[^/]+$')
                    if name and predicate(name) then
                        table.insert(results, full_path)
                    end
                end
                -- Other types (socket, fifo, etc.) are silently skipped
            end

            for _, entry in ipairs(entries) do
                local full_path = path .. '/' .. entry.name
                if entry.type == 'link' or entry.type == 'unknown' then
                    -- Resolve symlinks and unknown dirent types via stat to
                    -- maintain behavioral parity with vim.fs.find (which follows
                    -- symlinks transparently). On NFS or older ext4 without
                    -- dirent.d_type, all entries may come back as 'unknown'.
                    pending = pending + 1
                    uv.fs_stat(full_path, function(stat_err, stat)
                        if not stat_err and stat then
                            local resolved = stat.type
                            process_entry(full_path, resolved)
                        end
                        pending = pending - 1
                        if pending == 0 then
                            on_done(results)
                        end
                    end)
                else
                    process_entry(full_path, entry.type)
                end
            end

            pending = pending - 1
            if pending == 0 then
                on_done(results)
            end
        end)
    end

    scan(dir, 0)
end

--- Read an entire file asynchronously.
--- Every error branch after a successful fs_open closes the fd to prevent leaks.
---@param filepath string Absolute file path
---@param on_done fun(data: string|nil) Called with file content or nil on error
---@private
local function async_read_file(filepath, on_done)
    uv.fs_open(filepath, 'r', 438, function(err_open, fd)
        if err_open or not fd then
            on_done(nil)
            return
        end
        uv.fs_fstat(fd, function(err_stat, stat)
            if err_stat or not stat then
                uv.fs_close(fd, function()
                    on_done(nil)
                end)
                return
            end
            uv.fs_read(fd, stat.size, 0, function(err_read, data)
                uv.fs_close(fd, function()
                    on_done(err_read and nil or data)
                end)
            end)
        end)
    end)
end

--- Compute a path relative to a base directory.
--- Inlined from paths.relativeToBase() to avoid calling Neovim APIs
--- (nvim_buf_get_name) from a deferred vim.schedule callback, which would
--- be racy if the user switches buffers during async I/O.
---@param abs_path string Absolute file path
---@param base string Base directory (captured on the main thread before async)
---@return string rel_path Relative path, or basename if not under base
---@private
local function relative_to(abs_path, base)
    local prefix = base:match('/$') and base or (base .. '/')
    if abs_path:sub(1, #prefix) == prefix then
        return abs_path:sub(#prefix + 1)
    end
    return vim.fs.basename(abs_path)
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

--- Parse bib entries from a string and build nvim-cmp completion items
---@param bibentries string The raw contents of a .bib file
---@return table[] items Array of nvim-cmp completion items
---@private
local function parse_bib_string(bibentries)
    local items = {}
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

--- Build completion items from async results on the main thread.
---@param file_paths string[] Absolute paths discovered by async_scan_dir
---@param bib_contents table<integer, string|nil> Bib file contents indexed by position
---@param base string Base directory captured before async (for relative path computation)
---@param implicit_ext string|nil Implicit extension config value
---@param links_mod table The links module (for formatLink)
---@return table[] items Array of nvim-cmp completion items
---@private
local function build_items(file_paths, bib_contents, base, implicit_ext, links_mod)
    local items = {}

    -- Process discovered file paths into file completion items
    if file_paths then
        for _, abs_path in ipairs(file_paths) do
            local rel_path = relative_to(abs_path, base)

            -- Strip extension from link target when implicit_extension is configured
            local source_path = rel_path
            if implicit_ext then
                source_path = rel_path:gsub('%.[^%.]+$', '')
            end

            -- Display label is the filename without extension
            local label = vim.fs.basename(abs_path):gsub('%.[^%.]+$', '')

            -- Format link using the canonical formatter (respects style, compact, etc.)
            local formatted = links_mod.formatLink(label, source_path)
            if formatted then
                -- Read first 1KB for documentation preview (synchronous — fast per file)
                local f = io.open(abs_path, 'rb')
                local preview = f and f:read(1024)
                if f then
                    f:close()
                end

                table.insert(items, {
                    label = label,
                    insertText = formatted[1],
                    kind = cmp.lsp.CompletionItemKind.File,
                    documentation = preview
                            and { kind = cmp.lsp.MarkupKind.Markdown, value = preview }
                        or nil,
                })
            end
        end
    end

    -- Process bib file contents into citation completion items
    for _, content in pairs(bib_contents) do
        if content then
            local bib_items = parse_bib_string(content)
            for _, item in ipairs(bib_items) do
                table.insert(items, item)
            end
        end
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

--- Provide completion items (files + bib entries) when triggered by `@`.
--- File scanning and bib reading are performed asynchronously via vim.uv to
--- avoid blocking the editor. The callback is invoked from a vim.schedule
--- once all async I/O completes.
---@param params table nvim-cmp completion parameters
---@param callback fun(items: table[]) Callback to return completion items
function source:complete(params, callback)
    -- Only provide suggestions if the current word starts with '@'
    local line = params.context.cursor_before_line
    if not line or not (line:match('^@%w*$') or line:match('%W@%w*$')) then
        callback({})
        return
    end

    -- Bump generation to cancel any in-flight async work from prior calls
    generation = generation + 1
    local my_gen = generation

    -- Capture all Neovim-dependent state on the main thread before going async
    local mkdn = require('mkdnflow')
    local config = mkdn.config
    local links_mod = require('mkdnflow.links')

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

    local extensions = config.notebook_extensions or { md = true }
    local implicit_ext = config.links.implicit_extension

    -- Collect all bib file paths into a flat list
    local bib_file_list = {}
    local bib_paths = mkdn.bib and mkdn.bib.bib_paths or nil
    if bib_paths then
        for _, group in ipairs({ 'default', 'root', 'yaml' }) do
            if bib_paths[group] then
                for _, v in pairs(bib_paths[group]) do
                    table.insert(bib_file_list, v)
                end
            end
        end
    end

    -- Async coordination: pending must be computed before any async launches
    local file_paths = nil
    local bib_contents = {}
    local pending = 1 + #bib_file_list -- 1 for dir scan + N for bib reads

    local function check_done()
        if pending > 0 then
            return
        end
        vim.schedule(function()
            -- Bail if a newer complete() call has superseded this one
            if my_gen ~= generation then
                return
            end
            callback(build_items(file_paths, bib_contents, base, implicit_ext, links_mod))
        end)
    end

    -- Launch async directory scan
    async_scan_dir(base, function(name)
        local ext = name:match('%.([^%.]+)$')
        return ext and extensions[ext:lower()] or false
    end, function(paths_result)
        file_paths = paths_result
        pending = pending - 1
        check_done()
    end)

    -- Launch async bib file reads in parallel
    for i, bib_path in ipairs(bib_file_list) do
        async_read_file(bib_path, function(data)
            bib_contents[i] = data
            pending = pending - 1
            check_done()
        end)
    end
end

local M = {}

--- Initialize cmp module: register as a completion source
M.init = function()
    cmp.register_source('mkdnflow', source.new())
end

return M
