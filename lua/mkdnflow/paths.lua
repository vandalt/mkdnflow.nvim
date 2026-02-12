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

-- Get OS for use in a couple of functions
local this_os = require('mkdnflow').this_os
-- Generic OS message
local this_os_err = '⬇️ Function unavailable for ' .. this_os .. '. Please file an issue.'
-- Set path separator based on OS
local sep = this_os:match('Windows') and '\\' or '/'
-- Get config setting for whether to make missing directories or not
local create_dirs = require('mkdnflow').config.create_dirs
-- Get config setting for where links should be relative to
local path_resolution = require('mkdnflow').config.path_resolution
-- Get directory of first-opened file
local initial_dir = require('mkdnflow').initial_dir
local root_dir = require('mkdnflow').root_dir
local last_resolved_dir = nil
local silent = require('mkdnflow').config.silent
local links_config = require('mkdnflow').config.links
local new_file_config = require('mkdnflow').config.new_file_template
local implicit_extension = links_config.implicit_extension
local link_transform = links_config.transform_on_follow

-- Load modules
local utils = require('mkdnflow.utils')
local buffers = require('mkdnflow.buffers')
local bib = require('mkdnflow.bib')
local cursor = require('mkdnflow.cursor')
local links = require('mkdnflow.links')

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

local M = {}

--- Resolve a relative link path to an absolute path using the configured path resolution strategy
---@param path string The path from a link
---@param sub_home_var? boolean If true, substitute `~/` with `$HOME/` instead of leaving as-is
---@return string derived_path The resolved absolute path
---@private
local resolve_notebook_path = function(path, sub_home_var)
    sub_home_var = sub_home_var or false
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
    elseif path_resolution.primary == 'root' and root_dir then
        -- Paste root directory and the directory in link
        derived_path = root_dir .. sep .. derived_path
    -- See if the path exists
    elseif
        path_resolution.primary == 'first'
        or (path_resolution.primary == 'root' and path_resolution.fallback == 'first')
    then
        -- Paste together the dir of first-opened file & dir in link path
        derived_path = initial_dir .. sep .. derived_path
    else -- Otherwise, they want it relative to the current file
        -- Path of current file
        local cur_file = vim.api.nvim_buf_get_name(0)
        -- Directory current file is in
        local cur_file_dir = vim.fs.dirname(cur_file)
        -- Paste together dir of current file & dir path provided in link
        if cur_file_dir then
            derived_path = cur_file_dir .. sep .. derived_path
        end
    end
    return derived_path
end

local enter_internal_path = function() end

--- Fill in placeholders in the new-file template string
---@param timing? string 'before' or 'after' buffer creation (defaults to 'before')
---@param template? string The template string to fill (defaults to config template)
---@return string template The template with placeholders replaced
M.formatTemplate = function(timing, template)
    timing = timing or 'before'
    template = template or new_file_config.template
    for placeholder_name, replacement in pairs(new_file_config.placeholders[timing]) do
        if replacement == 'link_title' then
            replacement = links.getLinkPart(links.getLinkUnderCursor(), 'name')
        elseif replacement == 'os_date' then
            replacement = os.date('%Y-%m-%d')
        end
        -- Use empty string if replacement is nil (e.g., no link under cursor)
        replacement = replacement or ''
        template = string.gsub(template, '{{%s?' .. placeholder_name .. '%s?}}', replacement)
    end
    return template
end

--- Open a notebook-internal file in Neovim, creating directories and applying templates as needed
---@param path string The file path to open
---@param anchor? string An anchor to jump to after opening (heading or ID)
---@private
local vim_open = function(path, anchor)
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
                vim.api.nvim_echo({
                    {
                        '⬇️  on_create_new callback returned unexpected type: '
                            .. type(result)
                            .. ' (expected string or nil)',
                        'WarningMsg',
                    },
                }, true, {})
            end
        end
        -- Push the current buffer name onto the main buffer stack
        buffers.push(buffers.main, vim.api.nvim_win_get_buf(0))
        -- Prepare to inject the filled-out template at the top of the new file
        local template
        if new_file_config.enabled then
            if not exists(path_w_ext, 'f') then
                template = M.formatTemplate('before')
            end
        end
        vim.cmd.edit(vim.fn.fnameescape(path_w_ext))
        M.updateDirs()
        -- Inject the template
        if new_file_config.enabled and template then
            template = M.formatTemplate('after', template)
            local lines = vim.split(template, '\n', { plain = true })
            vim.api.nvim_buf_set_lines(0, 0, #template, false, lines)
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
    path = path:match(sep .. '$') ~= nil and path or path .. sep
    local input_opts = {
        prompt = '⬇️  Name of file in directory to open or create: ',
        default = path,
        completion = 'file',
    }
    vim.ui.input(input_opts, function(response)
        if response ~= nil and response ~= path .. sep then
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
    local shell_open = function(path_)
        if this_os == 'Linux' then
            vim.fn.jobstart({ 'xdg-open', path_ }, { detach = true })
        elseif this_os == 'Darwin' then
            vim.fn.jobstart({ 'open', path_ }, { detach = true })
        elseif this_os:match('Windows') then
            vim.fn.jobstart({ 'cmd.exe', '/c', 'start', '', path_ }, { detach = true })
        else
            if not silent then
                vim.api.nvim_echo({ { this_os_err, 'ErrorMsg' } }, true, {})
            end
        end
    end
    -- If the file exists, open it; otherwise, issue a warning
    if type == 'url' then
        shell_open(path)
    elseif exists(path, 'f') == false and exists(path, 'd') == false then
        if not silent then
            vim.api.nvim_echo(
                { { '⬇️  ' .. path .. " doesn't seem to exist!", 'ErrorMsg' } },
                true,
                {}
            )
        end
    else
        shell_open(path)
    end
end

--- Handle a `file:` prefixed path by resolving it and opening with the system viewer
---@param path string The path with `file:` prefix
---@private
local handle_external_file = function(path)
    -- Get what's after the file: tag
    local real_path = string.match(path, '^file:(.*)')
    if this_os:match('Windows') then
        real_path = real_path:gsub('/', '\\')
        if real_path:match('^~\\') then
            real_path = string.gsub(real_path, '^~\\', vim.loop.os_homedir() .. '\\')
        end
    end
    -- Check if path provided is absolute or relative to $HOME
    if real_path:match('^~/') or real_path:match('^/') or real_path:match('^%u:\\') then
        if this_os:match('Windows') then
            system_open(real_path)
        else
            -- If the path starts with a tilde, replace it w/ $HOME
            if string.match(real_path, '^~/') then
                real_path = string.gsub(real_path, '^~/', '$HOME/')
            end
        end
    elseif path_resolution.primary == 'root' and root_dir then
        -- Paste together root directory path and path in link and escape
        real_path = root_dir .. sep .. real_path
    elseif
        path_resolution.primary == 'first'
        or (path_resolution.primary == 'root' and path_resolution.fallback == 'first')
    then
        -- Otherwise, links are relative to the first-opened file, so
        -- paste together the directory of the first-opened file and the
        -- path in the link and escape for the shell
        real_path = initial_dir .. sep .. real_path
    else
        -- Get the path of the current file
        local cur_file = vim.api.nvim_buf_get_name(0)
        -- Get the directory the current file is in and paste together the
        -- directory of the current file and the directory path provided in the
        -- link, and escape for shell
        local cur_file_dir = vim.fs.dirname(cur_file)
        real_path = cur_file_dir .. sep .. real_path
    end
    -- Pass to the system_open() function
    if real_path then
        system_open(real_path)
    end
end

--- Update the root directory and/or working directory after navigating to a new buffer
M.updateDirs = function()
    local wd
    -- See if the new file is in a different root directory
    if path_resolution.update_on_navigate or path_resolution.sync_cwd then
        if path_resolution.primary == 'root' then
            local cur_file = vim.api.nvim_buf_get_name(0)
            local dir = vim.fs.dirname(cur_file)
            if not root_dir or dir ~= last_resolved_dir then
                if path_resolution.update_on_navigate then
                    local prev_root = root_dir
                    root_dir = require('mkdnflow').utils.getRootDir(
                        dir,
                        path_resolution.root_marker,
                        this_os
                    )
                    last_resolved_dir = dir
                    require('mkdnflow').root_dir = root_dir
                    if root_dir then
                        wd = root_dir
                        if root_dir ~= prev_root then
                            local name = vim.fs.basename(root_dir)
                            if not silent then
                                vim.api.nvim_echo({ { '⬇️  Notebook: ' .. name } }, true, {})
                            end
                        end
                    else
                        if not silent then
                            vim.api.nvim_echo({
                                {
                                    '⬇️  No notebook found. Fallback perspective: '
                                        .. path_resolution.fallback,
                                    'WarningMsg',
                                },
                            }, true, {})
                        end
                        if path_resolution.fallback == 'first' and path_resolution.sync_cwd then
                            wd = initial_dir
                        elseif path_resolution.sync_cwd then -- Otherwise, set wd to directory the current buffer is in
                            wd = dir
                        end
                    end
                end
            end
        elseif path_resolution.primary == 'first' and path_resolution.sync_cwd then
            wd = initial_dir
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
---@return 'image'|'file'|'url'|'citation'|'anchor'|'nb_page'|nil
M.pathType = function(path, anchor, link_type)
    if not path then
        return nil
    elseif link_type == 'image_link' then
        return 'image'
    elseif string.find(path, '^file:') then
        return 'file'
    elseif links.hasUrl(path) then
        return 'url'
    elseif string.find(path, '^@') then
        return 'citation'
    elseif path == '' and anchor then
        return 'anchor'
    else
        return 'nb_page'
    end
end

--- Apply the user's `transform_on_follow` function to a path, if configured
---@param path string The path to transform
---@return string path The transformed path (or unchanged if no transform is configured)
M.transformPath = function(path)
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
    if path_type == 'image' then
        -- Resolve the path and open with system viewer
        local resolved_path = resolve_notebook_path(path)
        system_open(resolved_path)
    elseif path_type == 'nb_page' then
        vim_open(path, anchor)
    elseif path_type == 'url' then
        system_open(path .. (anchor or ''), 'url')
    elseif path_type == 'file' then
        handle_external_file(path)
    elseif path_type == 'anchor' then
        -- Send cursor to matching heading
        if not cursor.toId(anchor, 1) then
            cursor.toHeading(anchor)
        end
    elseif path_type == 'citation' then
        -- Retrieve highest-priority field in bib entry (if it exists)
        local field = bib.handleCitation(path)
        -- Use this function to do sth with the information returned (if any)
        if field then
            M.handlePath(field)
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
    local last_slash = string.find(string.reverse(newpath), sep)
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
    local derive_path = function(source, type)
        if type == 'file' then
            source = source:gsub('^file:', '')
        end
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
                    vim.api.nvim_echo({
                        { '⬇️  Failed to move file (cross-filesystem?)', 'ErrorMsg' },
                    }, true, {})
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
                vim.api.nvim_echo(
                    { { '⬇️  Success! File moved to ' .. derived_goal } },
                    true,
                    {}
                )
            else
                -- Clear the prompt & print sth
                -- Reset cmdheight value
                vim.cmd('normal! :')
                vim.o.cmdheight = cmdheight
                vim.api.nvim_echo({ { '⬇️  Aborted', 'WarningMsg' } }, true, {})
            end
        end)
    end
    -- Retrieve source from link
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
                    vim.api.nvim_echo({
                        {
                            "⬇️  '" .. location .. "' already exists! Aborting.",
                            'WarningMsg',
                        },
                    }, true, {})
                elseif source_exists then -- If the source location exists, proceed
                    if dir then -- If there's a directory in the goal location, ...
                        local to_dir_exists = exists(dir, 'd')
                        if not to_dir_exists then
                            if create_dirs then
                                vim.fn.mkdir(dir, 'p')
                            else
                                vim.cmd('normal! :')
                                vim.api.nvim_echo({
                                    {
                                        "⬇️  The goal directory doesn't exist. Set create_dirs to true for automatic directory creation.",
                                    },
                                })
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
                    vim.api.nvim_echo({
                        {
                            '⬇️  ' .. derived_source .. " doesn't seem to exist! Aborting.",
                            'WarningMsg',
                        },
                    }, true, {})
                end
            end
        end)
    else
        vim.api.nvim_echo(
            { { "⬇️  Couldn't find a link under the cursor to rename!", 'WarningMsg' } },
            true,
            {}
        )
    end
end

-- Return all the functions added to the table M!
return M
