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
--
-- This module: File and link navigation functions

local utils = require('mkdnflow.utils')
local last_resolved_dir = nil

local function mkdn()
    return require('mkdnflow')
end
local function cfg()
    return mkdn().config
end
local function sep()
    return mkdn().this_os:match('Windows') and '\\' or '/'
end

--- Check whether a file or directory exists at the given path
---@param path string The path to check
---@param unit_type? string 'd' for directory (default), 'f' for file
---@return boolean
---@private
local exists = function(path, unit_type)
    unit_type = unit_type or 'd'
    if unit_type == 'd' then
        return vim.fn.isdirectory(path) == 1
    else
        return vim.fn.filereadable(path) == 1
    end
end

--- Extract a URI scheme from a path string (e.g. 'phd' from 'phd://path/to/file')
---@param path string The path to check
---@return string|nil scheme The scheme name, or nil if no scheme found
---@private
local function extractScheme(path)
    return path:match('^(%a[%w%.%+%-]*)://')
end

local M = {}

--- Resolve a relative link path to an absolute path using the configured path resolution strategy
---@param path string The path from a link
---@param sub_home_var? boolean If true, substitute `~/` with `$HOME/` instead of leaving as-is
---@return string derived_path The resolved absolute path
---@private
local resolve_notebook_path = function(path, sub_home_var)
    sub_home_var = sub_home_var or false
    local this_os = mkdn().this_os
    local path_resolution = cfg().path_resolution
    local s = sep()
    local derived_path = path
    if this_os:match('Windows') then
        derived_path = derived_path:gsub('/', '\\')
        if derived_path:match('^~\\') then
            derived_path = string.gsub(derived_path, '^~\\', vim.loop.os_homedir() .. '\\')
        end
    end
    -- Decide what to pass to vim_open function
    if derived_path:match('^~/') or derived_path:match('^/') or derived_path:match('^%u:\\') then
        derived_path = sub_home_var and string.gsub(derived_path, '^~/', '$HOME/') or derived_path
    elseif path_resolution.primary == 'root' and mkdn().root_dir then
        -- Paste root directory and the directory in link
        derived_path = mkdn().root_dir .. s .. derived_path
    -- See if the path exists
    elseif
        path_resolution.primary == 'first'
        or (path_resolution.primary == 'root' and path_resolution.fallback == 'first')
    then
        -- Paste together the dir of first-opened file & dir in link path
        derived_path = mkdn().initial_dir .. s .. derived_path
    else -- Otherwise, they want it relative to the current file
        -- Path of current file
        local cur_file = vim.api.nvim_buf_get_name(0)
        -- Directory current file is in
        local cur_file_dir = vim.fs.dirname(cur_file)
        -- Paste together dir of current file & dir path provided in link
        if cur_file_dir then
            derived_path = cur_file_dir .. s .. derived_path
        end
    end
    return derived_path
end

--- Compute the resolution base directory for the current path resolution strategy.
---@param buf_path? string Buffer path for 'current' strategy (defaults to current buffer)
---@return string base_dir
M.getBaseDir = function(buf_path)
    local path_resolution = cfg().path_resolution
    local base
    if path_resolution.primary == 'root' and mkdn().root_dir then
        base = mkdn().root_dir
    elseif
        path_resolution.primary == 'first'
        or (path_resolution.primary == 'root' and path_resolution.fallback == 'first')
    then
        base = mkdn().initial_dir
    else
        local cur_path = buf_path or vim.api.nvim_buf_get_name(0)
        base = vim.fs.dirname(cur_path)
    end
    if not base or base == '' or base == '.' then
        base = vim.fn.getcwd()
    end
    return base
end

--- Compute a path relative to the resolution base (inverse of resolve_notebook_path)
---@param abs_path string An absolute file path
---@return string relative_path The path relative to the configured resolution base
M.relativeToBase = function(abs_path)
    local s = sep()
    local base = M.getBaseDir()
    if not base:match(s .. '$') then
        base = base .. s
    end
    if abs_path:sub(1, #base) == base then
        return abs_path:sub(#base + 1)
    end
    return vim.fs.basename(abs_path)
end

local enter_internal_path = function() end

--- Fill in placeholders in the new-file template string
---@deprecated Use require('mkdnflow.templates').formatTemplate() instead
---@param timing? string 'before' or 'after' buffer creation (defaults to 'before')
---@param template? string The template string to fill (defaults to config template)
---@return string template The template with placeholders replaced
M.formatTemplate = function(timing, template)
    local templates = mkdn().templates
    if templates then
        return templates.formatTemplate(timing, template)
    end
    -- Fallback: if templates module is disabled, return template unchanged
    return template or cfg().new_file_template.template
end

--- Open a notebook-internal file in Neovim, creating directories and applying templates as needed
---@param path string The file path to open
---@param anchor? string An anchor to jump to after opening (heading or ID)
---@private
local vim_open = function(path, anchor)
    local this_os = mkdn().this_os
    local create_dirs = cfg().create_dirs
    local implicit_extension = cfg().links.implicit_extension
    local links_config = cfg().links
    local new_file_config = cfg().new_file_template
    local links = mkdn().links
    local buffers = mkdn().buffers
    local cursor = mkdn().cursor

    if this_os:match('Windows') then
        path = path:gsub('/', '\\')
    end

    path = resolve_notebook_path(path)

    -- See if a directory is part of the path
    local dir = vim.fs.dirname(path)
    -- If there's a dir & user wants dirs created, do so if necessary
    if dir and create_dirs then
        if not exists(dir) then
            vim.fn.mkdir(dir, 'p')
        end
    end
    -- If the path starts with a tilde, replace it w/ $HOME
    if this_os == 'Linux' or this_os == 'Darwin' then
        if string.match(path, '^~/') then
            path = string.gsub(path, '^~/', '$HOME/')
        end
    end
    local path_w_ext
    if not path:match('%.[%a]+$') then
        if implicit_extension then
            path_w_ext = path .. '.' .. implicit_extension
        else
            path_w_ext = path .. '.md'
        end
    else
        path_w_ext = path
    end
    if exists(path, 'd') and not exists(path_w_ext, 'f') then
        local edit_dirs = links_config.edit_dirs
        if type(edit_dirs) == 'function' then
            buffers.push(buffers.main, vim.api.nvim_win_get_buf(0))
            edit_dirs(path)
        elseif edit_dirs then
            buffers.push(buffers.main, vim.api.nvim_win_get_buf(0))
            vim.cmd.edit(vim.fn.fnameescape(path))
            M.updateDirs()
        else
            enter_internal_path(path)
        end
    else
        -- If the file doesn't exist and on_create_new is set, call the callback
        if not exists(path_w_ext, 'f') and type(links_config.on_create_new) == 'function' then
            local title = links.getLinkPart(links.getLinkUnderCursor(), 'name')
            local result = links_config.on_create_new(path_w_ext, title)
            if result == nil then
                -- Callback handled everything; no buffer push, no file open
                return
            end
            if type(result) == 'string' then
                path_w_ext = result
                -- Ensure directories exist for the callback-returned path
                local result_dir = vim.fs.dirname(path_w_ext)
                if result_dir and create_dirs and not exists(result_dir) then
                    vim.fn.mkdir(result_dir, 'p')
                end
            else
                -- Unexpected return type; warn and proceed with default behavior
                vim.notify(
                    '⬇️  on_create_new callback returned unexpected type: '
                        .. type(result)
                        .. ' (expected string or nil)',
                    vim.log.levels.WARN
                )
            end
        end
        -- Push the current buffer name onto the main buffer stack
        buffers.push(buffers.main, vim.api.nvim_win_get_buf(0))
        -- Prepare to inject the filled-out template at the top of the new file
        local template
        local templates = mkdn().templates
        if templates and new_file_config.enabled then
            if not exists(path_w_ext, 'f') then
                template = templates.formatTemplate('before', nil, { target_path = path_w_ext })
            end
        end
        vim.cmd.edit(vim.fn.fnameescape(path_w_ext))
        M.updateDirs()
        -- Inject the template
        if templates and new_file_config.enabled and template then
            templates.apply(template)
        end
        if anchor and anchor ~= '' then
            if not cursor.toId(anchor) then
                cursor.toHeading(anchor)
            end
        end
    end
end

--- Prompt the user to complete a directory path and open the resulting file
---@param path string The directory path to start from
---@private
enter_internal_path = function(path)
    local s = sep()
    path = path:match(s .. '$') ~= nil and path or path .. s
    local input_opts = {
        prompt = '⬇️  Name of file in directory to open or create: ',
        default = path,
        completion = 'file',
    }
    vim.ui.input(input_opts, function(response)
        if response ~= nil and response ~= path .. s then
            vim_open(response)
            vim.cmd('normal! :')
        end
    end)
end

--- Open a path using the system's default application (xdg-open, open, or cmd.exe)
---@param path string The path or URL to open
---@param type? string 'url' to skip existence check, nil for local files
---@private
local system_open = function(path, type)
    local this_os = mkdn().this_os
    local shell_open = function(path_)
        if this_os == 'Linux' then
            vim.fn.jobstart({ 'xdg-open', path_ }, { detach = true })
        elseif this_os == 'Darwin' then
            vim.fn.jobstart({ 'open', path_ }, { detach = true })
        elseif this_os:match('Windows') then
            vim.fn.jobstart({ 'cmd.exe', '/c', 'start', '', path_ }, { detach = true })
        else
            if not cfg().silent then
                local this_os_err = '⬇️ Function unavailable for '
                    .. this_os
                    .. '. Please file an issue.'
                vim.notify(this_os_err, vim.log.levels.ERROR)
            end
        end
    end
    -- If the file exists, open it; otherwise, issue a warning
    if type == 'url' then
        shell_open(path)
    elseif exists(path, 'f') == false and exists(path, 'd') == false then
        if not cfg().silent then
            vim.notify('⬇️  ' .. path .. " doesn't seem to exist!", vim.log.levels.ERROR)
        end
    else
        shell_open(path)
    end
end

--- Update the root directory and/or working directory after navigating to a new buffer
M.updateDirs = function()
    local this_os = mkdn().this_os
    local path_resolution = cfg().path_resolution
    local silent = cfg().silent
    local wd
    -- See if the new file is in a different root directory
    if path_resolution.update_on_navigate or path_resolution.sync_cwd then
        if path_resolution.primary == 'root' then
            local cur_file = vim.api.nvim_buf_get_name(0)
            local dir = vim.fs.dirname(cur_file)
            if not mkdn().root_dir or dir ~= last_resolved_dir then
                if path_resolution.update_on_navigate then
                    local prev_root = mkdn().root_dir
                    local new_root = utils.getRootDir(dir, path_resolution.root_marker, this_os)
                    last_resolved_dir = dir
                    mkdn().root_dir = new_root
                    if new_root then
                        wd = new_root
                        if new_root ~= prev_root then
                            local name = vim.fs.basename(new_root)
                            if not silent then
                                vim.notify('⬇️  Notebook: ' .. name, vim.log.levels.INFO)
                            end
                        end
                    else
                        if not silent then
                            vim.notify(
                                '⬇️  No notebook found. Fallback perspective: '
                                    .. path_resolution.fallback,
                                vim.log.levels.WARN
                            )
                        end
                        if path_resolution.fallback == 'first' and path_resolution.sync_cwd then
                            wd = mkdn().initial_dir
                        elseif path_resolution.sync_cwd then -- Otherwise, set wd to directory the current buffer is in
                            wd = dir
                        end
                    end
                end
            end
        elseif path_resolution.primary == 'first' and path_resolution.sync_cwd then
            wd = mkdn().initial_dir
        elseif path_resolution.sync_cwd then
            local cur_file = vim.api.nvim_buf_get_name(0)
            wd = vim.fs.dirname(cur_file)
        end
        if path_resolution.sync_cwd and wd then
            vim.api.nvim_set_current_dir(wd)
        end
    end
end

--- Determine the type of a link path
---@param path? string The path to classify
---@param anchor? string An anchor fragment, if present
---@param link_type? string The link type from the parser (e.g., 'image_link')
---@return 'external'|'url'|'uri_handler'|'citation'|'anchor'|'nb_page'|nil
M.pathType = function(path, anchor, link_type)
    if not path then
        return nil
    elseif link_type == 'image_link' then
        return 'external'
    elseif string.find(path, '^file:') then
        return 'external'
    else
        local scheme = extractScheme(path)
        if scheme then
            local handler = cfg().links.uri_handlers[scheme]
            if handler then
                return 'uri_handler'
            end
        end
    end
    if mkdn().links.hasUrl(path) then
        return 'url'
    elseif string.find(path, '^@') then
        return 'citation'
    elseif path == '' and anchor then
        return 'anchor'
    else
        local ext = path:match('%.([^%./\\]+)$')
        if ext and not cfg().notebook_extensions[ext:lower()] then
            return 'external'
        end
        return 'nb_page'
    end
end

--- Apply the user's `transform_on_follow` function to a path, if configured
---@param path string The path to transform
---@return string path The transformed path (or unchanged if no transform is configured)
M.transformPath = function(path)
    local link_transform = cfg().links.transform_on_follow
    if type(link_transform) ~= 'function' or not link_transform then
        return path
    else
        return link_transform(path)
    end
end

--- Route a link path to the appropriate handler based on its type
---@param path string The link path
---@param anchor? string|boolean An anchor fragment (e.g., "#heading"), or false
---@param link_type? string The link type from the parser
M.handlePath = function(path, anchor, link_type)
    anchor = anchor or false
    path = M.transformPath(path)
    local path_type = M.pathType(path, anchor, link_type)
    -- Handle according to path type
    if path_type == 'uri_handler' then
        local scheme = extractScheme(path)
        local handler = cfg().links.uri_handlers[scheme]
        local full_uri = path .. (anchor or '')
        if handler == 'system' then
            system_open(full_uri, 'url')
        elseif type(handler) == 'function' then
            handler(full_uri, scheme, path, anchor or nil)
        end
    elseif path_type == 'external' then
        path = path:gsub('^file:', '')
        local resolved_path = resolve_notebook_path(path)
        system_open(resolved_path)
    elseif path_type == 'nb_page' then
        vim_open(path, anchor)
    elseif path_type == 'url' then
        system_open(path .. (anchor or ''), 'url')
    elseif path_type == 'anchor' then
        -- Send cursor to matching heading
        if not mkdn().cursor.toId(anchor, 1) then
            mkdn().cursor.toHeading(anchor)
        end
    elseif path_type == 'citation' then
        -- Retrieve highest-priority field in bib entry (if it exists)
        local bib = mkdn().bib
        if bib then
            local field = bib.handleCitation(path)
            -- Use this function to do sth with the information returned (if any)
            if field then
                M.handlePath(field)
            end
        elseif not cfg().silent then
            vim.notify('⬇️  Enable the bib module to follow citations', vim.log.levels.WARN)
        end
    end
end

--- Resolve a link's source text to an absolute path.
--- Mirrors the flow in moveSource: raw source -> transformPath -> add extension -> resolve.
---@param source string The link source text
---@param from_filepath string The file containing the link (used for 'current' strategy)
---@return string abs_path The resolved absolute path
---@private
local resolve_link_source = function(source, from_filepath)
    local path_resolution = cfg().path_resolution
    local implicit_extension = cfg().links.implicit_extension
    local s = sep()

    local resolved = M.transformPath(source)

    -- Check basename only; plain '%..+$' would false-positive on relative
    -- paths like '../page' where the dots are path separators.
    local basename = resolved:match('[^/\\]+$') or resolved
    if not basename:match('%..+$') then
        resolved = resolved .. '.' .. (implicit_extension or 'md')
    end

    if resolved:match('^/') or resolved:match('^~/') then
        return resolved
    end

    -- Parent-relative paths (starting with ..) must resolve from the
    -- containing file's directory, regardless of the path_resolution strategy
    if resolved:match('^%.%.') then
        return vim.fs.dirname(from_filepath) .. s .. resolved
    end

    if path_resolution.primary == 'root' and mkdn().root_dir then
        return mkdn().root_dir .. s .. resolved
    elseif
        path_resolution.primary == 'first'
        or (path_resolution.primary == 'root' and path_resolution.fallback == 'first')
    then
        return mkdn().initial_dir .. s .. resolved
    else
        return vim.fs.dirname(from_filepath) .. s .. resolved
    end
end

--- Compute a relative path from a directory to a target file.
---@param from_dir string The starting directory
---@param to_file string The target file
---@return string relative_path
---@private
local compute_relative_path = function(from_dir, to_file)
    local s = sep()
    from_dir = vim.fn.resolve(from_dir)
    local to_resolved = vim.fn.resolve(to_file)
    local from_parts = vim.split(from_dir, s, { plain = true })
    local to_parts = vim.split(to_resolved, s, { plain = true })

    local common = 0
    for i = 1, math.min(#from_parts, #to_parts) do
        if from_parts[i] == to_parts[i] then
            common = i
        else
            break
        end
    end

    local parts = {}
    for _ = 1, #from_parts - common do
        table.insert(parts, '..')
    end
    for i = common + 1, #to_parts do
        table.insert(parts, to_parts[i])
    end

    return table.concat(parts, s)
end

--- Compute the new link source text for a reference in a given file.
---@param old_source string The original link source text
---@param new_abs_path string The new absolute path of the moved file
---@param from_filepath string The file containing the reference
---@return string new_source The new link source text
---@private
local compute_new_source = function(old_source, new_abs_path, from_filepath)
    local path_resolution = cfg().path_resolution
    local implicit_extension = cfg().links.implicit_extension
    -- Check the basename for an extension; plain '%..+$' would false-positive
    -- on relative paths like '../page' where the dots are path components.
    local basename = old_source:match('[^/\\]+$') or old_source
    local had_extension = basename:match('%..+$') ~= nil
    local new_source

    local base_dir
    if path_resolution.primary == 'root' and mkdn().root_dir then
        base_dir = mkdn().root_dir
    elseif
        path_resolution.primary == 'first'
        or (path_resolution.primary == 'root' and path_resolution.fallback == 'first')
    then
        base_dir = mkdn().initial_dir
    else
        base_dir = vim.fs.dirname(from_filepath)
    end
    new_source = compute_relative_path(base_dir, new_abs_path)

    if not had_extension then
        local ext = implicit_extension or 'md'
        new_source = new_source:gsub('%.' .. vim.pesc(ext) .. '$', '')
    end

    return new_source
end

--- Snapshot all loaded, named buffers into a cache table.
---@return table<string, string[]> Map of absolute path to buffer lines
---@private
local function snapshot_buffers()
    local cache = {}
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) then
            local name = vim.api.nvim_buf_get_name(bufnr)
            if name ~= '' then
                cache[name] = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
            end
        end
    end
    return cache
end

--- Asynchronously scan the notebook for links pointing to a given absolute path.
---@param old_abs_path string Resolved absolute path of the moved file (pre-rename)
---@param skip_filepath? string Absolute path to skip (nil = skip nothing)
---@param buffer_cache table<string, string[]> Map of absolute path to buffer lines for loaded buffers
---@param on_done fun(refs: table[]) Called with array of reference entries
---@private
local find_references_async = function(old_abs_path, skip_filepath, buffer_cache, on_done)
    local luv = vim.uv or vim.loop
    local notebook = require('mkdnflow.notebook')
    local base_dir = mkdn().root_dir or mkdn().initial_dir or vim.fn.getcwd()

    old_abs_path = vim.fn.resolve(old_abs_path)
    if skip_filepath then
        skip_filepath = vim.fn.resolve(skip_filepath)
    end

    local references = {}

    notebook.scanFiles(base_dir, function(files)
        local pending = 0
        for _, filepath in ipairs(files) do
            local real = luv.fs_realpath(filepath)
            if (real or filepath) ~= skip_filepath then
                pending = pending + 1
            end
        end

        if pending == 0 then
            vim.schedule(function()
                on_done(references)
            end)
            return
        end

        local function file_done()
            pending = pending - 1
            if pending == 0 then
                vim.schedule(function()
                    on_done(references)
                end)
            end
        end

        local function process_lines(filepath, lines)
            local links = notebook.scanLinks(lines, {
                types = {
                    md_link = true,
                    wiki_link = true,
                    image_link = true,
                    ref_definition = true,
                },
            })

            for _, link in ipairs(links) do
                if link.source and link.source ~= '' then
                    local resolved = resolve_link_source(link.source, filepath)
                    local real_resolved = luv.fs_realpath(resolved)
                    if (real_resolved or resolved) == old_abs_path then
                        table.insert(references, {
                            filepath = filepath,
                            lnum = link.row,
                            col = link.col,
                            match = link.match,
                            source = link.source,
                            anchor = link.anchor or '',
                            type = link.type,
                        })
                    end
                end
            end
        end

        for _, filepath in ipairs(files) do
            local real_filepath = luv.fs_realpath(filepath)
            if (real_filepath or filepath) ~= skip_filepath then
                -- Prefer buffer content over disk for loaded buffers
                local cached = buffer_cache[filepath]
                    or (real_filepath and buffer_cache[real_filepath])
                if cached then
                    process_lines(filepath, cached)
                    file_done()
                else
                    notebook.readFile(filepath, function(lines)
                        if not lines then
                            file_done()
                            return
                        end
                        process_lines(filepath, lines)
                        file_done()
                    end)
                end
            end
        end
    end)
end

--- Open a quickfix list with proposed link changes and set up interactive review keybindings.
---@param changes table[] Array of reference entries from find_references_async
---@param new_abs_path string The new absolute path of the moved file
---@private
local open_review = function(changes, new_abs_path)
    for _, change in ipairs(changes) do
        change.new_source = compute_new_source(change.source, new_abs_path, change.filepath)
    end

    local items = {}
    for _, change in ipairs(changes) do
        table.insert(items, {
            filename = change.filepath,
            lnum = change.lnum,
            col = change.col,
            text = change.source .. ' → ' .. change.new_source,
        })
    end

    local title = 'Update ' .. #items .. ' reference(s) to ' .. changes[1].source
    vim.notify(
        '⬇️  Found ' .. #items .. ' outdated reference(s). Review below:',
        vim.log.levels.INFO
    )
    vim.fn.setqflist({}, ' ', { items = items, title = title })
    vim.cmd.copen()

    local qf_bufnr = vim.api.nvim_get_current_buf()
    local ns_id = vim.api.nvim_create_namespace('mkdnflow_review')

    vim.api.nvim_buf_set_extmark(qf_bufnr, ns_id, 0, 0, {
        virt_text = { { '  a=apply  s=skip  A=all  q=quit', 'Comment' } },
        virt_text_pos = 'eol',
    })

    local function replace_on_line(line, col, old_match, new_match)
        local before = line:sub(1, col - 1)
        local after = line:sub(col)
        local new_after = after:gsub(vim.pesc(old_match), function()
            return new_match
        end, 1)
        return before .. new_after
    end

    local function apply_change(change)
        local old_ref = change.source .. change.anchor
        local new_ref = change.new_source .. change.anchor
        local new_match = change.match:gsub(vim.pesc(old_ref), function()
            return new_ref
        end, 1)

        local bufnr = vim.fn.bufnr(change.filepath)
        if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
            local line = vim.api.nvim_buf_get_lines(bufnr, change.lnum - 1, change.lnum, false)[1]
            local new_line = replace_on_line(line, change.col, change.match, new_match)
            vim.api.nvim_buf_set_lines(bufnr, change.lnum - 1, change.lnum, false, { new_line })
        else
            local lines = vim.fn.readfile(change.filepath)
            if lines and lines[change.lnum] then
                lines[change.lnum] =
                    replace_on_line(lines[change.lnum], change.col, change.match, new_match)
                vim.fn.writefile(lines, change.filepath)
            end
        end
        change.applied = true
    end

    local function update_display()
        local cur_line = vim.fn.line('.')
        local new_items = {}
        for _, change in ipairs(changes) do
            local prefix = ''
            if change.applied then
                prefix = '✓ '
            elseif change.skipped then
                prefix = '⊘ '
            end
            table.insert(new_items, {
                filename = change.filepath,
                lnum = change.lnum,
                col = change.col,
                text = prefix .. change.source .. ' → ' .. change.new_source,
            })
        end
        vim.fn.setqflist(new_items, 'r')
        pcall(vim.api.nvim_win_set_cursor, 0, { cur_line, 0 })
    end

    local cleaned_up = false

    local function cleanup()
        cleaned_up = true
        local applied_count = 0
        for _, c in ipairs(changes) do
            if c.applied then
                applied_count = applied_count + 1
            end
        end
        pcall(vim.api.nvim_buf_clear_namespace, qf_bufnr, ns_id, 0, -1)
        vim.cmd.cclose()
        if applied_count > 0 then
            vim.notify('⬇️  Updated ' .. applied_count .. ' reference(s)', vim.log.levels.INFO)
        end
    end

    local function next_pending()
        local cur = vim.fn.line('.')
        for i = cur + 1, #changes do
            if not changes[i].applied and not changes[i].skipped then
                vim.api.nvim_win_set_cursor(0, { i, 0 })
                return
            end
        end
        cleanup()
    end

    vim.api.nvim_create_autocmd('BufWipeout', {
        buffer = qf_bufnr,
        once = true,
        callback = function()
            if cleaned_up then
                return
            end
            local applied_count = 0
            for _, c in ipairs(changes) do
                if c.applied then
                    applied_count = applied_count + 1
                end
            end
            if applied_count > 0 then
                vim.schedule(function()
                    vim.notify(
                        '⬇️  Updated ' .. applied_count .. ' reference(s)',
                        vim.log.levels.INFO
                    )
                end)
            end
        end,
    })

    local map_opts = { buffer = qf_bufnr, nowait = true }

    vim.keymap.set('n', 'a', function()
        local idx = vim.fn.line('.')
        local change = changes[idx]
        if change and not change.applied and not change.skipped then
            apply_change(change)
            update_display()
        end
        next_pending()
    end, map_opts)

    vim.keymap.set('n', 's', function()
        local idx = vim.fn.line('.')
        local change = changes[idx]
        if change then
            change.skipped = true
            update_display()
        end
        next_pending()
    end, map_opts)

    vim.keymap.set('n', 'A', function()
        for _, change in ipairs(changes) do
            if not change.applied and not change.skipped then
                apply_change(change)
            end
        end
        update_display()
        cleanup()
    end, map_opts)

    vim.keymap.set('n', 'q', function()
        cleanup()
    end, map_opts)
end

--- Interactively rename/move the file referenced by the link under the cursor
M.moveSource = function()
    local resolve_source_path = function(source)
        source = source:gsub('^file:', '')
        return resolve_notebook_path(source, true)
    end
    local implicit_extension = cfg().links.implicit_extension
    local ensure_extension = function(path)
        -- Check basename only; plain '%..+$' would false-positive on relative
        -- paths like '../page' where the dots are path separators.
        local bn = path:match('[^/\\]+$') or path
        if not bn:match('%..+$') then
            return path .. '.' .. (implicit_extension or 'md')
        end
        return path
    end
    local confirm_and_execute = function(opts)
        local rel_source = M.relativeToBase(opts.source_path)
        local rel_goal = M.relativeToBase(opts.goal_path)
        local choice = vim.fn.confirm(
            '⬇️  Move file?\n  ' .. rel_source .. '\n→ ' .. rel_goal,
            '&Yes\n&No'
        )
        if choice ~= 1 then
            vim.notify('⬇️  Aborted', vim.log.levels.WARN)
            return
        end
        -- Capture resolved path while file still exists (before rename)
        local resolved_source = vim.fn.resolve(opts.source_path)
        local ok = vim.fn.rename(opts.source_path, opts.goal_path)
        if ok ~= 0 then
            vim.notify('⬇️  Failed to move file (cross-filesystem?)', vim.log.levels.ERROR)
            return
        end
        -- Update buffer name so statusline, :w, etc. use the new path
        local old_bufnr = vim.fn.bufnr(opts.source_path)
        if old_bufnr ~= -1 and vim.api.nvim_buf_is_loaded(old_bufnr) then
            vim.api.nvim_buf_set_name(old_bufnr, opts.goal_path)
            -- nvim_buf_set_name leaves an unlisted ghost buffer with the
            -- old name; wipe it to avoid confusion
            local ghost = vim.fn.bufnr(opts.source_path)
            if ghost ~= -1 then
                vim.api.nvim_buf_delete(ghost, { force = true })
            end
        end
        -- Change the link content
        vim.api.nvim_buf_set_text(
            0,
            opts.start_row - 1,
            opts.start_col - 1,
            opts.end_row - 1,
            opts.end_col,
            { opts.location .. opts.anchor }
        )
        vim.notify('⬇️  Success! File moved to ' .. opts.goal_path, vim.log.levels.INFO)
        -- Scan notebook for other references to the old path
        if cfg().modules.notebook ~= false then
            local cur_file = vim.api.nvim_buf_get_name(0)
            -- Snapshot loaded buffers so the scan sees in-memory content
            -- (which may differ from disk if apply_change modified them)
            local buf_cache = snapshot_buffers()
            find_references_async(resolved_source, cur_file, buf_cache, function(refs)
                if #refs > 0 then
                    open_review(refs, opts.goal_path)
                end
            end)
        end
    end
    -- Retrieve source from link
    local links = mkdn().links
    local create_dirs = cfg().create_dirs
    local source, anchor, link_type, start_row, start_col, end_row, end_col =
        links.getLinkPart(links.getLinkUnderCursor(), 'source')
    if not source then
        vim.notify("⬇️  Couldn't find a link under the cursor to rename!", vim.log.levels.WARN)
        return
    end
    -- Refuse to rename link types that don't point to files
    local source_type = M.pathType(source, anchor, link_type)
    if
        source_type == 'url'
        or source_type == 'citation'
        or source_type == 'anchor'
        or source_type == 'uri_handler'
    then
        vim.notify('⬇️  Cannot rename a ' .. source_type .. ' link', vim.log.levels.WARN)
        return
    end
    -- Modify source path in the same way as when links are interpreted
    local source_path = ensure_extension(M.transformPath(source))
    source_path = resolve_source_path(source_path)
    -- Warn if the resolved file is outside the notebook root
    local notebook_root = mkdn().root_dir or mkdn().initial_dir or vim.fn.getcwd()
    if not vim.startswith(vim.fn.resolve(source_path), vim.fn.resolve(notebook_root)) then
        local choice = vim.fn.confirm(
            "⬇️  This file is outside the notebook. References in other notebooks won't be updated. Continue?",
            '&Yes\n&No'
        )
        if choice ~= 1 then
            vim.notify('⬇️  Aborted', vim.log.levels.WARN)
            return
        end
    end
    -- Ask user to edit name in console (only display what's in the link)
    vim.ui.input({
        prompt = '⬇️  Move to: ',
        default = source,
        completion = 'file',
    }, function(location)
        if not location then
            return
        end

        local goal_path = ensure_extension(M.transformPath(location))
        goal_path = resolve_source_path(goal_path)

        if exists(goal_path, 'f') then
            vim.notify(
                "⬇️  '" .. location .. "' already exists! Aborting.",
                vim.log.levels.WARN
            )
            return
        end
        if not exists(source_path, 'f') then
            vim.notify(
                '⬇️  ' .. source_path .. " doesn't seem to exist! Aborting.",
                vim.log.levels.WARN
            )
            return
        end

        local dir = vim.fs.dirname(goal_path)
        if dir and not exists(dir, 'd') then
            if not create_dirs then
                vim.notify(
                    "⬇️  The goal directory doesn't exist. Set create_dirs to true for automatic directory creation.",
                    vim.log.levels.WARN
                )
                return
            end
            vim.fn.mkdir(dir, 'p')
        end

        confirm_and_execute({
            source_path = source_path,
            source = source,
            goal_path = goal_path,
            anchor = anchor,
            location = location,
            start_row = start_row,
            start_col = start_col,
            end_row = end_row,
            end_col = end_col,
        })
    end)
end

--- Check whether a link should be validated for dead link detection.
--- Skips URLs, citations, same-file anchors, and registered URI handler schemes.
---@param source string The link source text
---@param anchor string|nil The anchor fragment
---@return boolean true if the link should be checked for existence
---@private
local function is_checkable_link(source, anchor)
    if not source or source == '' then
        return false
    end
    -- Skip same-file anchors (source is empty, anchor is present)
    if source == '' and anchor then
        return false
    end
    -- Skip URLs
    if mkdn().links.hasUrl(source) then
        return false
    end
    -- Skip citations
    if source:match('^@') then
        return false
    end
    -- Skip registered URI handler schemes
    local scheme = extractScheme(source)
    if scheme then
        local handlers = cfg().links.uri_handlers
        if handlers and handlers[scheme] then
            return false
        end
    end
    return true
end

--- Find dead links (links to non-existent files) in the current buffer or notebook.
---@param scope? string 'notebook' to scan all files, nil/omitted for current buffer only
M.deadLinks = function(scope)
    local luv = vim.uv or vim.loop

    -- Validate scope argument
    if scope and scope ~= 'notebook' then
        vim.notify(
            '⬇️  Unknown scope: ' .. scope .. '. Use "notebook" or omit for current buffer.',
            vim.log.levels.WARN
        )
        return
    end

    local notebook = require('mkdnflow.notebook')
    local link_types = {
        md_link = true,
        wiki_link = true,
        image_link = true,
        ref_definition = true,
    }

    local function check_links(filepath, lines, use_luv)
        local dead = {}
        local links = notebook.scanLinks(lines, { types = link_types })
        for _, link in ipairs(links) do
            if link.source and link.source ~= '' then
                if is_checkable_link(link.source, link.anchor) then
                    local source = link.source:gsub('^file:', '')
                    local resolved = resolve_link_source(source, filepath)
                    local is_dead
                    if use_luv then
                        is_dead = not luv.fs_stat(resolved)
                    else
                        is_dead = vim.fn.filereadable(resolved) ~= 1
                    end
                    if is_dead then
                        table.insert(dead, {
                            filename = filepath,
                            lnum = link.row,
                            col = link.col,
                            text = link.match,
                        })
                    end
                end
            end
        end
        return dead
    end

    if not scope then
        -- Buffer scope: synchronous
        local filepath = vim.api.nvim_buf_get_name(0)
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        local dead_links = check_links(filepath, lines, false)
        if #dead_links > 0 then
            vim.fn.setqflist(dead_links)
            vim.cmd.copen()
        else
            vim.notify('⬇️  No dead links found', vim.log.levels.INFO)
        end
        return
    end

    -- Notebook scope: async
    if cfg().modules.notebook == false then
        vim.notify(
            '⬇️  Enable the notebook module to scan the notebook for dead links',
            vim.log.levels.WARN
        )
        return
    end

    vim.notify('⬇️  Scanning notebook for dead links...', vim.log.levels.INFO)
    local base_dir = mkdn().root_dir or mkdn().initial_dir or vim.fn.getcwd()

    -- Snapshot loaded buffer content before entering async
    local buf_cache = snapshot_buffers()

    local dead_links = {}

    notebook.scanFiles(base_dir, function(files)
        local pending = #files

        if pending == 0 then
            vim.schedule(function()
                vim.notify('⬇️  No dead links found', vim.log.levels.INFO)
            end)
            return
        end

        local function file_done()
            pending = pending - 1
            if pending == 0 then
                vim.schedule(function()
                    if #dead_links > 0 then
                        vim.fn.setqflist(dead_links)
                        vim.cmd.copen()
                    else
                        vim.notify('⬇️  No dead links found', vim.log.levels.INFO)
                    end
                end)
            end
        end

        local function process_lines(filepath, lines)
            local dead = check_links(filepath, lines, true)
            for _, entry in ipairs(dead) do
                table.insert(dead_links, entry)
            end
        end

        for _, filepath in ipairs(files) do
            local real_filepath = luv.fs_realpath(filepath)
            local cached = buf_cache[filepath] or (real_filepath and buf_cache[real_filepath])
            if cached then
                process_lines(filepath, cached)
                file_done()
            else
                notebook.readFile(filepath, function(lines)
                    if not lines then
                        file_done()
                        return
                    end
                    process_lines(filepath, lines)
                    file_done()
                end)
            end
        end
    end)
end

---@param target_path string Resolved absolute path to find references to
---@param skip_filepath? string Absolute path to skip (nil = skip nothing)
---@param buffer_cache? table Pre-built cache (nil = snapshot automatically)
---@param on_done fun(refs: table[]) Callback with reference entries
M.findReferencesAsync = function(target_path, skip_filepath, buffer_cache, on_done)
    if not buffer_cache then
        buffer_cache = snapshot_buffers()
    end
    find_references_async(target_path, skip_filepath, buffer_cache, on_done)
end

M._test = {
    resolve_link_source = resolve_link_source,
    compute_relative_path = compute_relative_path,
    compute_new_source = compute_new_source,
    find_references_async = find_references_async,
    open_review = open_review,
    is_checkable_link = is_checkable_link,
}

-- Return all the functions added to the table M!
return M
