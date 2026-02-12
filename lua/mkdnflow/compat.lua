-- mkdnflow.nvim (Tools for fluent markdown notebook navigation and management)
-- Copyright (C) 2022-2024 Jake W. Vincent <https://github.com/jakewvincent>
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

local utils = require('mkdnflow').utils
local silent = require('mkdnflow').config.silent
local warn = function(message)
    vim.api.nvim_echo({ { message, 'WarningMsg' } }, true, {})
end
-- Show a warning message if nvim < 0.9.x
if require('mkdnflow').nvim_version < 9 and not silent then
    warn(
        '⬇️  Not all Mkdnflow functionality will work for your current version of Neovim, including mappings. Please upgrade to Neovim >= 0.9 or make sure to set your mappings in your Neovim config.'
    )
end
local M = {}

--- Check a user config for deprecated settings and migrate them to their modern equivalents
---@param user_config table The raw user configuration table
---@return table user_config The migrated configuration table (same reference, modified in-place)
M.userConfigCheck = function(user_config)
    -- COMPAT(added=v2.8, remove=v3.0): extension-based filetypes → filetype-based
    -- Migrate old extension-based filetypes config to filetype-based
    -- Extensions like 'md' are migrated to their corresponding filetype ('markdown')
    local extension_to_filetype = {
        md = 'markdown',
        mkd = 'markdown',
        mkdn = 'markdown',
        mdwn = 'markdown',
        mdown = 'markdown',
    }

    if user_config.filetypes then
        local new_filetypes = {}
        local migrated = false

        for key, value in pairs(user_config.filetypes) do
            if extension_to_filetype[key] then
                -- Known extension, migrate to filetype
                local ft = extension_to_filetype[key]
                -- false takes precedence over true (explicit disable wins)
                if new_filetypes[ft] == nil or value == false then
                    new_filetypes[ft] = value
                end
                migrated = true
            else
                -- Already a filetype or unknown extension, keep as-is
                -- But still respect false precedence
                if new_filetypes[key] == nil or value == false then
                    new_filetypes[key] = value
                end
            end
        end

        if migrated and not silent then
            warn(
                "⬇️  Config 'filetypes' now uses Neovim filetypes. "
                    .. "Extensions like 'md' are auto-migrated to 'markdown'. "
                    .. 'See :h mkdnflow-filetypes'
            )
        end

        user_config.filetypes = new_filetypes
    end

    -- COMPAT(added=v1.x, remove=v3.0): to_do.symbols → to_do.statuses
    -- Check if to-do markers are being customized but no values were provided
    -- for not_started, in_progress, and complete
    if user_config.to_do then
        if
            user_config.to_do.symbols
            and not (
                user_config.to_do.not_started
                or user_config.to_do.in_progress
                or user_config.to_do.complete
            )
        then
            if #user_config.to_do.symbols == 3 then
                user_config.to_do.not_started = user_config.to_do.symbols[1]
                user_config.to_do.in_progress = user_config.to_do.symbols[2]
                user_config.to_do.complete = user_config.to_do.symbols[3]
            elseif #user_config.to_do.symbols > 3 then
                local max = #user_config.to_do.symbols
                user_config.to_do.not_started = user_config.to_do.symbols[1]
                user_config.to_do.in_progress = user_config.to_do.symbols[2]
                user_config.to_do.complete = user_config.to_do.symbols[max]
            elseif #user_config.to_do.symbols == 2 then
                user_config.to_do.not_started = user_config.to_do.symbols[1]
                user_config.to_do.in_progress = user_config.to_do.symbols[1]
                user_config.to_do.complete = user_config.to_do.symbols[2]
            end
        end
        -- COMPAT(added=v2.x, remove=v3.0): to_do.not_started/in_progress/complete → to_do.statuses
        -- Update to June 2024 format
        if
            not user_config.to_do.statuses
            and (
                user_config.to_do.not_started
                or user_config.to_do.in_progress
                or user_config.to_do.complete
            )
        then
            user_config.to_do['statuses'] = {
                { name = 'not_started', marker = user_config.to_do.not_started },
                { name = 'in_progress', marker = user_config.to_do.in_progress },
                { name = 'complete', marker = user_config.to_do.complete },
            }
            warn(
                "⬇️  The 'not_started', 'in_progress', and 'complete' keys in to_do are deprecated. Use 'statuses' instead. See :h mkdnflow-configuration."
            )
        end
        -- COMPAT(added=v2.x, remove=v3.0): to_do.update_parents → to_do.status_propagation.up
        if user_config.to_do.update_parents ~= nil then
            user_config.to_do['status_propagation'] = {
                up = user_config.to_do.update_parents,
            }
            warn(
                "⬇️  The 'update_parents' key in to_do is deprecated. Use 'status_propagation.up' instead. See :h mkdnflow-configuration."
            )
        end
        -- COMPAT(added=v2.x, remove=v3.0): to_do.statuses[*].symbol → marker, colors → highlight
        if user_config.to_do.statuses then
            local warned_symbol = false
            local warned_colors = false
            for _, status in ipairs(user_config.to_do.statuses) do
                -- Migrate symbol → marker
                if status.symbol ~= nil and status.marker == nil then
                    status.marker = status.symbol
                    if not warned_symbol then
                        warn(
                            "⬇️  The 'symbol' key in to_do.statuses is deprecated. Use 'marker' instead. See :h mkdnflow-configuration."
                        )
                        warned_symbol = true
                    end
                end
                -- Migrate colors → highlight
                if status.colors ~= nil and status.highlight == nil then
                    status.highlight = status.colors
                    if not warned_colors then
                        warn(
                            "⬇️  The 'colors' key in to_do.statuses is deprecated. Use 'highlight' instead. See :h mkdnflow-configuration."
                        )
                        warned_colors = true
                    end
                end
            end
        end
    end

    -- COMPAT(added=v1.x, remove=v3.0): default_bib_path → bib.default_path
    -- Look for default bib path
    if user_config.default_bib_path then
        if user_config.default_bib_path == '' then
            user_config.bib.default_path = nil
        else
            user_config.bib.default_path = user_config.default_bib_path
        end
        warn(
            '⬇️  The default_bib_path key has now been migrated into the bib key under the default_path option. Please update your config. See :h mkdnflow-changes, commit e9f7815...'
        )
    end

    -- COMPAT(added=v1.x, remove=v3.0): link_style → links.style
    -- Look for link style
    if user_config.link_style then
        user_config.links.style = user_config.link_style
    end

    -- COMPAT(added=v1.x, remove=v3.0): links.implicit_extension period stripping
    -- Look for implicit extension and remove periods
    if user_config.links then
        if user_config.links.implicit_extension then
            user_config.links.implicit_extension =
                string.gsub(user_config.links.implicit_extension, '%.', '')
        end
    end

    -- COMPAT(added=v1.x, remove=v3.0): links_relative_to → perspective (now path_resolution)
    -- Look for links_relative_to
    if user_config.links_relative_to then
        user_config.perspective = user_config.links_relative_to
        warn(
            '⬇️  The links_relative_to key is now called "path_resolution". Please update your config. See :h mkdnflow-changes, commit e42290...'
        )
    end

    -- COMPAT(added=v1.x, remove=v3.0): wrap_to_beginning/end → wrap
    -- Look for wrap preferences
    if user_config.wrap_to_beginning or user_config.wrap_to_end then
        user_config.wrap = true
        warn(
            '⬇️  The wrap_to_beginning/end keys have been merged into a single "wrap" key. Please update your config. See :h mkdnflow-changes, commit 9068e1...'
        )
    end

    -- COMPAT(added=v1.x, remove=v3.0): perspective (string) → perspective (table)
    -- COMPAT(added=v1.x, remove=v3.0): vimwd_heel → nvim_wd_heel (now sync_cwd)
    -- Inspect perspective setting, if specified
    if user_config.perspective then
        if type(user_config.perspective) ~= 'table' then
            warn(
                '⬇️  The perspective key (previously "links_relative_to") should now be associated with a table value. Please update your config. See :h mkdnflow-changes, commit 75c8ec...'
            )
            if user_config.perspective == 'current' then
                local table = {
                    priority = 'current',
                    fallback = 'first',
                }
                user_config.perspective = table
            elseif user_config.perspective == 'first' then
                local table = {
                    priority = 'first',
                    fallback = 'current',
                }
                user_config.perspective = table
            end
        end
        if user_config.perspective.vimwd_heel ~= nil then
            user_config.perspective['nvim_wd_heel'] = user_config.perspective.vimwd_heel
        end
    end

    -- COMPAT(added=v2.10, remove=v3.0): perspective → path_resolution (and sub-keys)
    if user_config.perspective ~= nil and user_config.path_resolution == nil then
        user_config.path_resolution = user_config.perspective
        user_config.perspective = nil
    end
    if user_config.path_resolution and type(user_config.path_resolution) == 'table' then
        local pr = user_config.path_resolution
        if pr.priority ~= nil and pr.primary == nil then
            pr.primary = pr.priority
            pr.priority = nil
        end
        if pr.root_tell ~= nil and pr.root_marker == nil then
            pr.root_marker = pr.root_tell
            pr.root_tell = nil
        end
        if pr.nvim_wd_heel ~= nil and pr.sync_cwd == nil then
            pr.sync_cwd = pr.nvim_wd_heel
            pr.nvim_wd_heel = nil
        end
        if pr.update ~= nil and pr.update_on_navigate == nil then
            pr.update_on_navigate = pr.update
            pr.update = nil
        end
    end

    -- COMPAT(added=v2.10, remove=v3.0): links key renames
    if user_config.links then
        local l = user_config.links
        if l.name_is_source ~= nil and l.compact == nil then
            l.compact = l.name_is_source
            l.name_is_source = nil
        end
        if l.context ~= nil and l.search_range == nil then
            l.search_range = l.context
            l.context = nil
        end
        if l.transform_explicit ~= nil and l.transform_on_create == nil then
            l.transform_on_create = l.transform_explicit
            l.transform_explicit = nil
        end
        if l.transform_implicit ~= nil and l.transform_on_follow == nil then
            l.transform_on_follow = l.transform_implicit
            l.transform_implicit = nil
        end
        if l.create_on_follow_failure ~= nil and l.auto_create == nil then
            l.auto_create = l.create_on_follow_failure
            l.create_on_follow_failure = nil
        end
    end

    -- COMPAT(added=v2.10, remove=v3.0): to_do, tables, new_file_template renames
    if user_config.to_do and user_config.to_do.statuses then
        for _, status in ipairs(user_config.to_do.statuses) do
            if status.exclude_from_rotation ~= nil and status.skip_on_toggle == nil then
                status.skip_on_toggle = status.exclude_from_rotation
                status.exclude_from_rotation = nil
            end
        end
    end
    if user_config.tables and user_config.tables.style then
        local s = user_config.tables.style
        if s.mimic_alignment ~= nil and s.apply_alignment == nil then
            s.apply_alignment = s.mimic_alignment
            s.mimic_alignment = nil
        end
    end
    if user_config.new_file_template then
        local nft = user_config.new_file_template
        if nft.use_template ~= nil and nft.enabled == nil then
            nft.enabled = nft.use_template
            nft.use_template = nil
        end
    end

    -- COMPAT(added=v1.x, remove=v3.0): use_mappings_table → modules.maps
    -- Check for old use_mappings_table config option
    if user_config.use_mappings_table == false then
        if user_config.modules then
            user_config.modules.maps = false
        else
            user_config.modules = {
                maps = false,
            }
        end
    end

    -- COMPAT(added=v1.x, remove=v3.0): mappings string values → table values
    -- COMPAT(added=v2.x, remove=v3.0): MkdnCR → MkdnEnter
    -- Inspect mappings
    if user_config.mappings then
        local string = false
        for _, value in pairs(user_config.mappings) do
            if type(value) == 'string' then
                string = true
            end
        end
        if string then
            warn(
                '⬇️  In the mappings table, commands should now be associated with a table value instead of a string. See :h mkdnflow-changes, commit 436510...'
            )
            local compatible_mappings = {}
            for key, value in pairs(user_config.mappings) do
                if key == 'MkdnFollowLink' then
                    compatible_mappings[key] = { { 'n', 'v' }, value }
                else
                    compatible_mappings[key] = { 'n', value }
                end
            end
            user_config.mappings = compatible_mappings
        end
        -- If MkdnCR has a mapping, update it to MkdnImodeMultiFunc
        if user_config.mappings.MkdnCR then
            if user_config.mappings.MkdnEnter then
                if
                    user_config.mappings.MkdnEnter[2]:lower()
                    == user_config.mappings.MkdnCR[2]:lower()
                then
                    local mode = user_config.mappings.MkdnEnter[1]
                    local mapping = user_config.mappings.MkdnEnter[2]
                    if type(mode) == 'table' then
                        table.insert(mode, 'i')
                    else
                        mode = { mode, 'i' }
                    end
                    user_config.mappings.MkdnEnter = { mode, mapping }
                    warn(
                        '⬇️  Merging MkdnCR mapping (deprecated) with MkdnEnter. Consider merging these in your Mkdnflow config.'
                    )
                else
                    warn(
                        '⬇️  MkdnCR is deprecated in favor of MkdnEnter. Could not merge your mapping for MkdnCR with that for MkdnEnter because they have different key mappings.'
                    )
                end
            else
                local mode = user_config.mappings.MkdnCR[1]
                local mapping = user_config.mappings.MkdnCR[2]
                if type(mode) == 'table' then
                    table.insert(mode, 'n')
                    table.insert(mode, 'v')
                else
                    mode = { mode, 'n', 'v' }
                end
                if mapping:lower() ~= '<cr>' then
                    warn(
                        '⬇️  MkdnCR is deprecated in favor of MkdnEnter. Could not merge your mapping for MkdnCR with the default mapping for MkdnEnter because they have different key mappings.'
                    )
                else
                    warn(
                        '⬇️  Merging MkdnCR mapping (deprecated) with default mapping for MkdnEnter. Consider merging your MkdnCR mapping with a mapping for MkdnEnter in your Mkdnflow config.'
                    )
                    user_config.mappings.MkdnEnter = { mode, mapping }
                end
            end
            user_config.mappings.MkdnCR = nil
        end

        --
        local cmp, _ = pcall(require, 'cmp')
        if user_config.modules and user_config.modules.cmp and not cmp then
            vim.notify(
                "⬇️  cmp module is enabled, but require('cmp') failed.",
                vim.log.levels.WARN,
                {
                    title = 'mkdnflow.nvim',
                }
            )
            user_config.cmp = false
        end
    end
    return user_config
end

return M
