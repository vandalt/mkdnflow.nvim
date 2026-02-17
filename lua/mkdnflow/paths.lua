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
        -- Looks like this links to a directory, possibly a notebook
        enter_internal_path(path)
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

--- Truncate a path for display by showing only the divergent suffix
---@param oldpath string The original path (used to determine the common prefix)
---@param newpath string The new path to truncate
---@return string difference The truncated portion of newpath
---@private
local truncate_path = function(oldpath, newpath)
    local difference = ''
    local last_slash = string.find(string.reverse(newpath), sep())
    last_slash = last_slash and #newpath - last_slash + 1 or nil
    local continue = true
    local char = 1
    while continue do
        local newpath_char = newpath:sub(char, char)
        if oldpath:sub(char, char) ~= newpath_char and char <= #newpath then
            continue = false
        else
            char = char + 1
        end
    end
    if last_slash and char > last_slash then
        difference = string.sub(newpath, last_slash)
    else
        difference = string.sub(newpath, char)
    end
    return difference
end

--- Interactively rename/move the file referenced by the link under the cursor
M.moveSource = function()
    local derive_path = function(source, _type)
        source = source:gsub('^file:', '')
        return resolve_notebook_path(source, true)
    end
    local confirm_and_execute = function(
        derived_source,
        source,
        derived_goal,
        anchor,
        location,
        start_row,
        start_col,
        end_row,
        end_col
    )
        local truncated_goal = '...' .. truncate_path(derived_source, derived_goal)
        local prompt = "⬇️  Move '"
            .. derived_source
            .. "' ("
            .. source
            .. ") to '"
            .. truncated_goal
            .. "' ("
            .. location
            .. ')? [y/n] '
        local cmdheight = vim.o.cmdheight
        local str_width, win_width = vim.api.nvim_strwidth(prompt), vim.api.nvim_win_get_width(0)
        local rows_needed = str_width / win_width
        if rows_needed / math.floor(rows_needed) > 1.0 then
            rows_needed = math.floor(rows_needed) + 1
        else
            rows_needed = math.floor(rows_needed)
        end
        vim.o.cmdheight = rows_needed
        vim.ui.input({ prompt = prompt }, function(response)
            if response == 'y' then
                local ok = vim.fn.rename(derived_source, derived_goal)
                if ok ~= 0 then
                    vim.notify(
                        '⬇️  Failed to move file (cross-filesystem?)',
                        vim.log.levels.ERROR
                    )
                    vim.o.cmdheight = cmdheight
                    return
                end
                -- Change the link content
                vim.api.nvim_buf_set_text(
                    0,
                    start_row - 1,
                    start_col - 1,
                    end_row - 1,
                    end_col,
                    { location .. anchor }
                )
                -- Clear the prompt & print sth
                -- Reset cmdheight value
                vim.cmd('normal! :')
                vim.o.cmdheight = cmdheight
                vim.notify('⬇️  Success! File moved to ' .. derived_goal, vim.log.levels.INFO)
            else
                -- Clear the prompt & print sth
                -- Reset cmdheight value
                vim.cmd('normal! :')
                vim.o.cmdheight = cmdheight
                vim.notify('⬇️  Aborted', vim.log.levels.WARN)
            end
        end)
    end
    -- Retrieve source from link
    local links = mkdn().links
    local implicit_extension = cfg().links.implicit_extension
    local create_dirs = cfg().create_dirs
    local source, anchor, link_type, start_row, start_col, end_row, end_col =
        links.getLinkPart(links.getLinkUnderCursor(), 'source')
    if source then
        -- Determine type of source
        local source_type = M.pathType(source)
        -- Modify source path in the same way as when links are interpreted
        local derived_source = M.transformPath(source)
        if not derived_source:match('%..+$') then
            if implicit_extension then
                derived_source = derived_source .. '.' .. implicit_extension
            else
                derived_source = derived_source .. '.md'
            end
        end
        -- If it's a file, determine the full path of the source using perspective
        derived_source = derive_path(derived_source, source_type)
        -- Ask user to edit name in console (only display what's in the link)
        local input_opts = {
            prompt = '⬇️  Move to: ',
            default = source,
            completion = 'file',
        }
        -- Determine what to do based on user input
        vim.ui.input(input_opts, function(location)
            if location then
                local derived_goal = M.transformPath(location)
                if not derived_goal:match('%..+$') then
                    if implicit_extension then
                        derived_goal = derived_goal .. '.' .. implicit_extension
                    else
                        derived_goal = derived_goal .. '.md'
                    end
                end
                derived_goal = derive_path(derived_goal, M.pathType(derived_goal))
                local source_exists = exists(derived_source, 'f')
                local goal_exists = exists(derived_goal, 'f')
                local dir = vim.fs.dirname(derived_goal)
                if goal_exists then -- If the goal location already exists, abort
                    vim.cmd('normal! :')
                    vim.notify(
                        "⬇️  '" .. location .. "' already exists! Aborting.",
                        vim.log.levels.WARN
                    )
                elseif source_exists then -- If the source location exists, proceed
                    if dir then -- If there's a directory in the goal location, ...
                        local to_dir_exists = exists(dir, 'd')
                        if not to_dir_exists then
                            if create_dirs then
                                vim.fn.mkdir(dir, 'p')
                            else
                                vim.cmd('normal! :')
                                vim.notify(
                                    "⬇️  The goal directory doesn't exist. Set create_dirs to true for automatic directory creation.",
                                    vim.log.levels.WARN
                                )
                            end
                        else
                            confirm_and_execute(
                                derived_source,
                                source,
                                derived_goal,
                                anchor,
                                location,
                                start_row,
                                start_col,
                                end_row,
                                end_col
                            )
                        end
                    else -- Move
                        confirm_and_execute(
                            derived_source,
                            source,
                            derived_goal,
                            anchor,
                            location,
                            start_row,
                            start_col,
                            end_row,
                            end_col
                        )
                    end
                else -- Otherwise, the file we're trying to move must not exist
                    -- Clear the prompt & send a warning
                    vim.cmd('normal! :')
                    vim.notify(
                        '⬇️  ' .. derived_source .. " doesn't seem to exist! Aborting.",
                        vim.log.levels.WARN
                    )
                end
            end
        end)
    else
        vim.notify("⬇️  Couldn't find a link under the cursor to rename!", vim.log.levels.WARN)
    end
end

-- Return all the functions added to the table M!
return M
