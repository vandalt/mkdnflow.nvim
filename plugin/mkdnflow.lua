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

-- Only define these commands if the plugin hasn't already been loaded
if vim.fn.exists('g:loaded_mkdnflow') == 0 then
    -- Save user coptions
    local save_cpo = vim.api.nvim_get_option('cpoptions')
    -- Retrieve defaults
    local cpo_defaults = vim.api.nvim_get_option_info('cpoptions')['default']
    -- Set to defaults
    vim.api.nvim_set_option('cpoptions', cpo_defaults)
    local user_command = vim.api.nvim_create_user_command
    local mkdnflow = require('mkdnflow')

    -- Helper to check if mkdnflow is initialized before running a command
    local function require_module(module_name)
        local module = mkdnflow[module_name]
        if not module then
            vim.api.nvim_echo({
                { '⬇️  Mkdnflow not initialized. ', 'WarningMsg' },
                { 'Call ', 'Normal' },
                { "require('mkdnflow').setup()", 'String' },
                { ' first, or check that the ', 'Normal' },
                { module_name, 'Identifier' },
                { ' module is enabled.', 'Normal' },
            }, true, {})
            return nil
        end
        return module
    end

    user_command('Mkdnflow', function(opts)
        mkdnflow.forceStart(opts.fargs)
    end, { nargs = '*' })
    user_command('MkdnEnter', function(opts)
        if opts.range > 0 then
            require('mkdnflow.wrappers').multiFuncEnter({ range = true })
        else
            require('mkdnflow.wrappers').multiFuncEnter()
        end
    end, { range = true })
    user_command('MkdnTab', function(opts)
        require('mkdnflow.wrappers').indentListItemOrJumpTableCell(1)
    end, {})
    user_command('MkdnSTab', function(opts)
        require('mkdnflow.wrappers').indentListItemOrJumpTableCell(-1)
    end, {})
    user_command('MkdnGoBack', function(opts)
        local buffers = require_module('buffers')
        if buffers then
            buffers.goBack()
        end
    end, {})
    user_command('MkdnGoForward', function(opts)
        local buffers = require_module('buffers')
        if buffers then
            buffers.goForward()
        end
    end, {})
    user_command('MkdnMoveSource', function(opts)
        local paths = require_module('paths')
        if paths then
            paths.moveSource()
        end
    end, {})
    user_command('MkdnNextLink', function(opts)
        local cursor = require_module('cursor')
        if cursor then
            cursor.toNextLink()
        end
    end, {})
    user_command('MkdnPrevLink', function(opts)
        local cursor = require_module('cursor')
        if cursor then
            cursor.toPrevLink()
        end
    end, {})
    user_command('MkdnFollowLink', function(opts)
        local links = require_module('links')
        if links then
            links.followLink()
        end
    end, {})
    user_command('MkdnCreateLink', function(opts)
        local links = require_module('links')
        if not links then
            return
        end
        if opts.range > 0 then
            links.createLink({ range = true })
        else
            links.createLink()
        end
    end, { range = true })
    user_command('MkdnCreateLinkFromClipboard', function(opts)
        local links = require_module('links')
        if not links then
            return
        end
        if opts.range > 0 then
            links.createLink({ from_clipboard = true, range = true })
        else
            links.createLink({ from_clipboard = true })
        end
    end, { range = true })
    user_command('MkdnDestroyLink', function(opts)
        local links = require_module('links')
        if links then
            links.destroyLink()
        end
    end, {})
    user_command('MkdnTagSpan', function(opts)
        local links = require_module('links')
        if links then
            links.tagSpan()
        end
    end, {})
    user_command('MkdnYankAnchorLink', function(opts)
        local cursor = require_module('cursor')
        if cursor then
            cursor.yankAsAnchorLink()
        end
    end, {})
    user_command('MkdnYankFileAnchorLink', function(opts)
        local cursor = require_module('cursor')
        if cursor then
            cursor.yankAsAnchorLink({})
        end
    end, {})
    user_command('MkdnNextHeading', function(opts)
        local cursor = require_module('cursor')
        if cursor then
            cursor.toHeading(nil)
        end
    end, {})
    user_command('MkdnPrevHeading', function(opts)
        local cursor = require_module('cursor')
        if cursor then
            cursor.toHeading(nil, {})
        end
    end, {})
    user_command('MkdnIncreaseHeading', function(opts)
        local cursor = require_module('cursor')
        if cursor then
            if opts.range > 0 then
                cursor.changeHeadingLevel('increase', { line1 = opts.line1, line2 = opts.line2 })
            else
                cursor.changeHeadingLevel('increase')
            end
        end
    end, { range = true })
    user_command('MkdnDecreaseHeading', function(opts)
        local cursor = require_module('cursor')
        if cursor then
            if opts.range > 0 then
                cursor.changeHeadingLevel('decrease', { line1 = opts.line1, line2 = opts.line2 })
            else
                cursor.changeHeadingLevel('decrease')
            end
        end
    end, { range = true })
    user_command('MkdnToggleToDo', function(opts)
        local to_do = require_module('to_do')
        if to_do then
            to_do.toggle_to_do()
        end
    end, {})
    user_command('MkdnSortToDoList', function(opts)
        local to_do = require_module('to_do')
        if to_do then
            to_do.sort_to_do_list()
        end
    end, {})
    user_command('MkdnNewListItem', function(opts)
        local lists = require_module('lists')
        if lists then
            lists.newListItem(true, false, true, 'i', '<CR>')
        end
    end, {})
    user_command('MkdnNewListItemBelowInsert', function(opts)
        local lists = require_module('lists')
        if lists then
            lists.newListItem(false, false, true, 'i', 'o')
        end
    end, {})
    user_command('MkdnNewListItemAboveInsert', function(opts)
        local lists = require_module('lists')
        if lists then
            lists.newListItem(false, true, true, 'i', 'O')
        end
    end, {})
    user_command('MkdnExtendList', function(opts)
        local lists = require_module('lists')
        if lists then
            lists.newListItem(false, 'n')
        end
    end, {})
    user_command('MkdnUpdateNumbering', function(opts)
        local lists = require_module('lists')
        if lists then
            lists.updateNumbering(opts.fargs)
        end
    end, { nargs = '*' })
    user_command('MkdnTable', function(opts)
        local tables = require_module('tables')
        if tables then
            tables.newTable(opts.fargs)
        end
    end, { nargs = '*' })
    user_command('MkdnTableFormat', function(opts)
        local tables = require_module('tables')
        if tables then
            tables.formatTable()
        end
    end, {})
    user_command('MkdnTableNextCell', function(opts)
        local tables = require_module('tables')
        if tables then
            tables.moveToCell(0, 1)
        end
    end, {})
    user_command('MkdnTablePrevCell', function(opts)
        local tables = require_module('tables')
        if tables then
            tables.moveToCell(0, -1)
        end
    end, {})
    user_command('MkdnTableNextRow', function(opts)
        local tables = require_module('tables')
        if tables then
            tables.moveToCell(1, 0)
        end
    end, {})
    user_command('MkdnTablePrevRow', function(opts)
        local tables = require_module('tables')
        if tables then
            tables.moveToCell(-1, 0)
        end
    end, {})
    user_command('MkdnTableNewRowBelow', function(opts)
        local tables = require_module('tables')
        if tables then
            tables.addRow()
        end
    end, {})
    user_command('MkdnTableNewRowAbove', function(opts)
        local tables = require_module('tables')
        if tables then
            tables.addRow(-1)
        end
    end, {})
    user_command('MkdnTableNewColAfter', function(opts)
        local tables = require_module('tables')
        if tables then
            tables.addCol()
        end
    end, {})
    user_command('MkdnTableNewColBefore', function(opts)
        local tables = require_module('tables')
        if tables then
            tables.addCol(-1)
        end
    end, {})
    user_command('MkdnTableDeleteRow', function(opts)
        local tables = require_module('tables')
        if tables then
            tables.deleteRow()
        end
    end, {})
    user_command('MkdnTableDeleteCol', function(opts)
        local tables = require_module('tables')
        if tables then
            tables.deleteCol()
        end
    end, {})
    user_command('MkdnTableCellNewLine', function(opts)
        local tables = require_module('tables')
        if tables then
            tables.cellNewLine()
        end
    end, {})
    user_command('MkdnTableAlignLeft', function(opts)
        local tables = require_module('tables')
        if tables then
            tables.alignCol('left')
        end
    end, {})
    user_command('MkdnTableAlignRight', function(opts)
        local tables = require_module('tables')
        if tables then
            tables.alignCol('right')
        end
    end, {})
    user_command('MkdnTableAlignCenter', function(opts)
        local tables = require_module('tables')
        if tables then
            tables.alignCol('center')
        end
    end, {})
    user_command('MkdnFoldSection', function(opts)
        local folds = require_module('folds')
        if folds then
            folds.foldSection()
        end
    end, {})
    user_command('MkdnUnfoldSection', function(opts)
        local folds = require_module('folds')
        if folds then
            folds.unfoldSection()
        end
    end, {})

    -- Return coptions to user values
    vim.api.nvim_set_option('cpoptions', save_cpo)

    -- Record that the plugin has been loaded
    vim.api.nvim_set_var('loaded_mkdnflow', true)
end
