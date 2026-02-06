-- mkdnflow.nvim (Tools for personal markdown notebook navigation and management)
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

-- Default config table (where defaults and user-provided config will be combined)
local default_config = {
    create_dirs = true,
    silent = false,
    wrap = false,
    modules = {
        bib = true,
        buffers = true,
        conceal = true,
        cursor = true,
        folds = true,
        foldtext = true,
        links = true,
        lists = true,
        maps = true,
        paths = true,
        tables = true,
        to_do = true,
        yaml = false,
        cmp = false,
    },
    perspective = {
        priority = 'first',
        fallback = 'current',
        root_tell = false,
        nvim_wd_heel = false,
        update = true,
    },
    filetypes = {
        markdown = true, -- Covers .md, .markdown, .mkd, .mkdn, .mdwn, .mdown
        rmd = true, -- Covers .rmd
    },
    foldtext = {
        object_count = true,
        object_count_icon_set = 'emoji',
        object_count_opts = function()
            return require('mkdnflow').foldtext.default_count_opts
        end,
        line_count = true,
        line_percentage = true,
        word_count = false,
        title_transformer = function()
            return require('mkdnflow').foldtext.default_title_transformer
        end,
        fill_chars = {
            left_edge = '⢾⣿⣿',
            right_edge = '⣿⣿⡷',
            item_separator = ' · ',
            section_separator = ' ⣹⣿⣏ ',
            left_inside = ' ⣹',
            right_inside = '⣏ ',
            middle = '⣿',
        },
    },
    bib = {
        default_path = nil,
        find_in_root = true,
    },
    cursor = {
        jump_patterns = nil,
        yank_register = '"',
    },
    links = {
        style = 'markdown',
        name_is_source = false,
        conceal = false,
        context = 0,
        implicit_extension = nil,
        transform_implicit = false,
        transform_explicit = function(text)
            text = text:gsub('[ /]', '-')
            text = text:lower()
            text = os.date('%Y-%m-%d_') .. text
            return text
        end,
        create_on_follow_failure = true,
    },
    new_file_template = {
        use_template = false,
        placeholders = {
            before = {
                title = 'link_title',
                date = 'os_date',
            },
            after = {},
        },
        template = '# {{title}}',
    },
    to_do = {
        highlight = false,
        statuses = {
            {
                name = 'not_started',
                marker = ' ',
                highlight = {
                    marker = { link = 'Conceal' },
                    content = { link = 'Conceal' },
                },
                sort = { section = 2, position = 'top' },
                exclude_from_rotation = false,
                propagate = {
                    up = function(host_list)
                        local no_items_started = true
                        for _, item in ipairs(host_list.items) do
                            if item.status.name ~= 'not_started' then
                                no_items_started = false
                            end
                        end
                        if no_items_started then
                            return 'not_started'
                        else
                            return 'in_progress'
                        end
                    end,
                    down = function(child_list)
                        local target_statuses = {}
                        for _ = 1, #child_list.items, 1 do
                            table.insert(target_statuses, 'not_started')
                        end
                        return target_statuses
                    end,
                },
            },
            {
                name = 'in_progress',
                marker = '-',
                highlight = {
                    marker = { link = 'WarningMsg' },
                    content = { bold = true },
                },
                sort = { section = 1, position = 'bottom' },
                exclude_from_rotation = false,
                propagate = {
                    up = function(host_list)
                        return 'in_progress'
                    end,
                    down = function(child_list) end,
                },
            },
            {
                name = 'complete',
                marker = { 'X', 'x' },
                highlight = {
                    marker = { link = 'String' },
                    content = { link = 'Conceal' },
                },
                sort = { section = 3, position = 'top' },
                exclude_from_rotation = false,
                propagate = {
                    up = function(host_list)
                        local all_items_complete = true
                        for _, item in ipairs(host_list.items) do
                            if item.status.name ~= 'complete' then
                                all_items_complete = false
                            end
                        end
                        if all_items_complete then
                            return 'complete'
                        else
                            return 'in_progress'
                        end
                    end,
                    down = function(child_list)
                        local target_statuses = {}
                        for _ = 1, #child_list.items, 1 do
                            table.insert(target_statuses, 'complete')
                        end
                        return target_statuses
                    end,
                },
            },
        },
        status_propagation = {
            up = true,
            down = true,
        },
        sort = {
            on_status_change = false,
            recursive = false,
            cursor_behavior = {
                track = true,
            },
        },
    },
    tables = {
        type = 'pipe',
        trim_whitespace = true,
        format_on_move = true,
        auto_extend_rows = false,
        auto_extend_cols = false,
        line_breaks = {
            pandoc = true, -- Handle \ as line break in cells
            html = false, -- Handle <br> as line break in cells
        },
        style = {
            cell_padding = 1,
            separator_padding = 1,
            outer_pipes = true,
            mimic_alignment = true,
        },
    },
    yaml = {
        bib = { override = false },
    },
    mappings = {
        MkdnEnter = { { 'n', 'v' }, '<CR>' },
        MkdnGoBack = { 'n', '<BS>' },
        MkdnGoForward = { 'n', '<Del>' },
        MkdnMoveSource = { 'n', '<F2>' },
        MkdnNextLink = { 'n', '<Tab>' },
        MkdnPrevLink = { 'n', '<S-Tab>' },
        MkdnFollowLink = false,
        MkdnDestroyLink = { 'n', '<M-CR>' },
        MkdnTagSpan = { 'v', '<M-CR>' },
        MkdnYankAnchorLink = { 'n', 'yaa' },
        MkdnYankFileAnchorLink = { 'n', 'yfa' },
        MkdnNextHeading = { 'n', ']]' },
        MkdnPrevHeading = { 'n', '[[' },
        MkdnIncreaseHeading = { { 'n', 'v' }, '+' },
        MkdnDecreaseHeading = { { 'n', 'v' }, '-' },
        MkdnIncreaseHeadingOp = { { 'n', 'v' }, 'g+' },
        MkdnDecreaseHeadingOp = { { 'n', 'v' }, 'g-' },
        MkdnToggleToDo = { { 'n', 'v' }, '<C-Space>' },
        MkdnNewListItem = false,
        MkdnNewListItemBelowInsert = { 'n', 'o' },
        MkdnNewListItemAboveInsert = { 'n', 'O' },
        MkdnExtendList = false,
        MkdnUpdateNumbering = { 'n', '<leader>nn' },
        MkdnTableNextCell = { 'i', '<Tab>' },
        MkdnTablePrevCell = { 'i', '<S-Tab>' },
        MkdnTableNextRow = false,
        MkdnTablePrevRow = { 'i', '<M-CR>' },
        MkdnTableNewRowBelow = { 'n', '<leader>ir' },
        MkdnTableNewRowAbove = { 'n', '<leader>iR' },
        MkdnTableNewColAfter = { 'n', '<leader>ic' },
        MkdnTableNewColBefore = { 'n', '<leader>iC' },
        MkdnTableDeleteRow = { 'n', '<leader>dr' },
        MkdnTableDeleteCol = { 'n', '<leader>dc' },
        MkdnFoldSection = { 'n', '<leader>f' },
        MkdnUnfoldSection = { 'n', '<leader>F' },
        MkdnTab = false,
        MkdnSTab = false,
        MkdnCreateLink = false,
        MkdnCreateLinkFromClipboard = { { 'n', 'v' }, '<leader>p' },
    },
}

-- Known Neovim filetypes (explicit list to avoid fragile heuristics)
local known_filetypes = {
    markdown = true,
    rmd = true,
}

-- Extensions that map to known filetypes
local extension_to_filetype = {
    md = 'markdown',
    markdown = 'markdown',
    mkd = 'markdown',
    mkdn = 'markdown',
    mdwn = 'markdown',
    mdown = 'markdown',
    rmd = 'rmd',
}

-- Process filetypes config and return list of filetype patterns for autocmd
-- Also registers unknown extensions via vim.filetype.add()
local function resolve_filetypes(filetypes_config)
    local patterns = {} -- Set of filetypes to enable
    local disabled = {} -- Set of filetypes explicitly disabled

    -- First pass: collect disabled filetypes (false takes precedence)
    for key, value in pairs(filetypes_config) do
        if value == false then
            local ft = extension_to_filetype[key] or key
            disabled[ft] = true
        end
    end

    -- Second pass: process enabled filetypes
    for key, value in pairs(filetypes_config) do
        if value == false then
            -- Skip (handled above)
        elseif known_filetypes[key] then
            -- Direct filetype name (e.g., 'markdown')
            if not disabled[key] then
                patterns[key] = true
            end
        elseif extension_to_filetype[key] then
            -- Known extension (e.g., 'md' -> 'markdown')
            local ft = extension_to_filetype[key]
            if not disabled[ft] then
                patterns[ft] = true
            end
        elseif type(value) == 'string' then
            -- Unknown extension, register as specified filetype
            vim.filetype.add({ extension = { [key] = value } })
            if not disabled[value] then
                patterns[value] = true
            end
        else
            -- Unknown extension (value = true), register as its own filetype
            vim.filetype.add({ extension = { [key] = key } })
            if not disabled[key] then
                patterns[key] = true
            end
        end
    end

    -- Convert to array for autocmd pattern
    local result = {}
    for ft, _ in pairs(patterns) do
        table.insert(result, ft)
    end
    return result
end

local init = {} -- Init functions & variables
init.utils = require('mkdnflow.utils')
init.user_config = {} -- For user config
init.config = {} -- For merged configs
init.loaded = nil -- For load status

-- Activate: loads modules and sets up perspective/root directory.
-- This is defined at module level so both setup() and forceStart() can call it.
local function activate()
    if init.loaded then
        return
    end

    -- Get silence preference
    local silent = init.config.silent
    -- Determine perspective
    local perspective = init.config.perspective
    if perspective.priority == 'root' then
        -- Retrieve the root 'tell'
        local root_tell = perspective.root_tell
        -- If one was provided, try to find the root directory for the notebook/wiki using the tell
        if root_tell then
            init.root_dir = init.utils.getRootDir(init.initial_dir, root_tell, init.this_os)
            -- Get notebook name
            if init.root_dir then
                vim.api.nvim_set_current_dir(init.root_dir)
                local name = init.root_dir:match('.*/(.*)') or init.root_dir
                if not silent then
                    vim.api.nvim_echo({ { '⬇️  Notebook: ' .. name } }, true, {})
                end
            else
                local fallback = init.config.perspective.fallback
                if not silent then
                    vim.api.nvim_echo({
                        {
                            '⬇️  No notebook found. Fallback perspective: ' .. fallback,
                            'WarningMsg',
                        },
                    }, true, {})
                end
                -- Set working directory according to current perspective
                if fallback == 'first' then
                    vim.api.nvim_set_current_dir(init.initial_dir)
                else
                    local bufname = vim.api.nvim_buf_get_name(0)
                    if init.this_os:match('Windows') then
                        vim.api.nvim_set_current_dir(bufname:match('(.*)\\.-$'))
                    else
                        vim.api.nvim_set_current_dir(bufname:match('(.*)/.-$'))
                    end
                end
            end
        else
            if not silent then
                vim.api.nvim_echo({
                    {
                        "⬇️  No tell was provided for the notebook's root directory. See :h mkdnflow-configuration.",
                        'WarningMsg',
                    },
                }, true, {})
            end
            if init.config.perspective.fallback == 'first' then
                vim.api.nvim_set_current_dir(init.initial_dir)
            else
                -- Set working directory
                local bufname = vim.api.nvim_buf_get_name(0)
                if init.this_os:match('Windows') then
                    vim.api.nvim_set_current_dir(bufname:match('(.*)\\.-$'))
                else
                    vim.api.nvim_set_current_dir(bufname:match('(.*)/.-$'))
                end
            end
        end
    end
    -- Set jump pattern set based on user's link type
    if init.config.cursor.jump_patterns == nil then
        if init.config.links.style == 'markdown' then
            init.config.cursor.jump_patterns = {
                '!%b[]%b()', -- Image links
                '%b[]%b()',
                '<[^<>]->',
                '%b[] ?%b[]',
                '%[@[^%[%]]-%]',
            }
        elseif init.config.links.style == 'wiki' then
            init.config.cursor.jump_patterns = {
                '%[%[[^%[%]]-%]%]',
            }
        else
            init.config.cursor.jump_patterns = {}
        end
    end
    -- Load modules
    init.conceal = init.config.links.conceal and require('mkdnflow.conceal')
    init.bib = init.config.modules.bib and require('mkdnflow.bib')
    init.buffers = init.config.modules.buffers and require('mkdnflow.buffers')
    init.folds = init.config.modules.folds and require('mkdnflow.folds')
    init.foldtext = init.config.modules.foldtext and require('mkdnflow.foldtext')
    init.links = init.config.modules.links and require('mkdnflow.links')
    init.cursor = init.config.modules.cursor and require('mkdnflow.cursor')
    init.lists = init.config.modules.lists and require('mkdnflow.lists')
    init.maps = init.config.modules.maps and require('mkdnflow.maps')
    init.paths = init.config.modules.paths and require('mkdnflow.paths')
    init.tables = init.config.modules.tables and require('mkdnflow.tables')
    init.yaml = init.config.modules.yaml and require('mkdnflow.yaml')
    init.cmp = init.config.modules.cmp and require('mkdnflow.cmp')
    init.to_do = init.config.modules.to_do and require('mkdnflow.to_do')
    -- Record load status
    init.loaded = true
    -- Re-trigger FileType so module autocmds (maps, conceal, foldtext, yaml) fire
    vim.cmd('doautocmd FileType')
end

init.command_deps = {
    MkdnGoBack = { 'buffers' },
    MkdnGoForward = { 'buffers' },
    MkdnMoveSource = { 'paths', 'links' },
    MkdnNextLink = { 'links', 'cursor' },
    MkdnPrevLink = { 'links', 'cursor' },
    MkdnCreateLink = { 'links' },
    MkdnCreateLinkFromClipboard = { 'links' },
    MkdnTagSpan = { 'links' },
    MkdnFollowLink = { 'links', 'paths' },
    MkdnDestroyLink = { 'links' },
    MkdnYankAnchorLink = { 'cursor' },
    MkdnYankFileAnchorLink = { 'cursor' },
    MkdnNextHeading = { 'cursor' },
    MkdnPrevHeading = { 'cursor' },
    MkdnIncreaseHeading = { 'cursor' },
    MkdnDecreaseHeading = { 'cursor' },
    MkdnIncreaseHeadingOp = { 'cursor' },
    MkdnDecreaseHeadingOp = { 'cursor' },
    MkdnToggleToDo = { 'lists' },
    MkdnSortToDoList = { 'to_do' },
    MkdnNewListItem = { 'lists' },
    MkdnNewListItemAboveInsert = { 'lists' },
    MkdnNewListItemBelowInsert = { 'lists' },
    MkdnExtendList = { 'lists' },
    MkdnUpdateNumbering = { 'lists' },
    MkdnTable = { 'tables' },
    MkdnTableFormat = { 'tables' },
    MkdnTableNextCell = { 'tables' },
    MkdnTablePrevCell = { 'tables' },
    MkdnTableNextRow = { 'tables' },
    MkdnTablePrevRow = { 'tables' },
    MkdnTableNewRowBelow = { 'tables' },
    MkdnTableNewRowAbove = { 'tables' },
    MkdnTableNewColAfter = { 'tables' },
    MkdnTableNewColBefore = { 'tables' },
    MkdnTableDeleteRow = { 'tables' },
    MkdnTableDeleteCol = { 'tables' },
    MkdnFoldSection = { 'folds' },
    MkdnUnfoldSection = { 'folds' },
    -- The following three depend on multiple modules; they will be defined but will
    -- self-limit their functionality depending on the available modules
    MkdnEnter = {},
    MkdnTab = {},
    MkdnSTab = {},
}

-- Run setup
init.setup = function(user_config)
    user_config = user_config or {}
    init.this_os = vim.loop.os_uname().sysname -- Get OS
    init.nvim_version = vim.fn.api_info().version.minor
    -- Get first opened file/buffer path and directory
    init.initial_buf = vim.api.nvim_buf_get_name(0)
    -- Determine initial_dir according to OS
    init.initial_dir = (init.this_os:match('Windows') ~= nil and init.initial_buf:match('(.*)\\.-'))
        or init.initial_buf:match('(.*)/.-')

    -- Store user config for potential re-setup
    if next(user_config) then
        init.user_config = user_config
    end

    -- Read compatibility module & pass user config through config checker
    local compat = require('mkdnflow.compat')
    user_config = compat.userConfigCheck(user_config)

    -- Merge user config with defaults
    init.config = init.utils.mergeTables(default_config, user_config)

    -- Resolve filetypes (registers unknown extensions via vim.filetype.add)
    local filetype_patterns = resolve_filetypes(init.config.filetypes)
    init.config.resolved_filetypes = filetype_patterns

    -- Re-detect current buffer's filetype if it was opened before registration
    local current_file = vim.api.nvim_buf_get_name(0)
    if current_file ~= '' then
        local detected = vim.filetype.match({ filename = current_file })
        if
            detected
            and vim.tbl_contains(filetype_patterns, detected)
            and vim.bo.filetype ~= detected
        then
            vim.bo.filetype = detected -- This triggers FileType autocmd
        end
    end

    -- Register activation augroup (clear ensures repeated setup() calls are safe)
    vim.api.nvim_create_augroup('MkdnflowActivation', { clear = true })

    -- Only create FileType autocmd if there are filetypes to watch
    if #filetype_patterns > 0 then
        vim.api.nvim_create_autocmd('FileType', {
            group = 'MkdnflowActivation',
            pattern = filetype_patterns,
            callback = function()
                activate()
            end,
        })
    end

    -- If current buffer already matches, activate immediately
    local ft = vim.bo.filetype
    if vim.tbl_contains(filetype_patterns, ft) then
        activate()
    end
end

-- Force start
init.forceStart = function(opts)
    local silent = (opts[1] == 'silent') or (init.config and init.config.silent)
    if init.loaded then
        if not silent then
            vim.api.nvim_echo({ { '⬇️  Mkdnflow is already running!', 'ErrorMsg' } }, true, {})
        end
    else
        -- If setup() was never called, call it first
        if not init.config.resolved_filetypes then
            init.setup(init.user_config or {})
        end
        -- If still not loaded (e.g. non-matching buffer), force activate
        if not init.loaded then
            activate()
        end
        if not silent then
            vim.api.nvim_echo({ { '⬇️  Mkdnflow started!', 'WarningMsg' } }, true, {})
        end
    end
end

return init
