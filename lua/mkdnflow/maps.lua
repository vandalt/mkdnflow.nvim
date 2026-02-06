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

-- Mkdnflow mappings
local config = require('mkdnflow').config
local nvim_version = require('mkdnflow').nvim_version
local command_deps = require('mkdnflow').command_deps
local filetype_patterns = config.resolved_filetypes

-- Command descriptions for which-key compatibility
local descriptions = {
    MkdnEnter = 'Follow link, toggle to-do, or create link from selection',
    MkdnGoBack = 'Go back to previous buffer',
    MkdnGoForward = 'Go forward to next buffer',
    MkdnMoveSource = 'Move link source file and update references',
    MkdnNextLink = 'Jump to next link',
    MkdnPrevLink = 'Jump to previous link',
    MkdnFollowLink = 'Follow link under cursor',
    MkdnDestroyLink = 'Remove link formatting, keep text',
    MkdnTagSpan = 'Wrap selection with span and generate ID',
    MkdnYankAnchorLink = 'Yank heading as anchor link',
    MkdnYankFileAnchorLink = 'Yank heading as full file anchor link',
    MkdnNextHeading = 'Jump to next heading',
    MkdnPrevHeading = 'Jump to previous heading',
    MkdnIncreaseHeading = 'Increase heading level (supports visual selection)',
    MkdnDecreaseHeading = 'Decrease heading level (supports visual selection)',
    MkdnIncreaseHeadingOp = 'Increase heading level (operator with motion, dot-repeatable)',
    MkdnDecreaseHeadingOp = 'Decrease heading level (operator with motion, dot-repeatable)',
    MkdnToggleToDo = 'Toggle to-do item status',
    MkdnNewListItem = 'Create new list item (insert mode)',
    MkdnNewListItemBelowInsert = 'Create list item below and enter insert mode',
    MkdnNewListItemAboveInsert = 'Create list item above and enter insert mode',
    MkdnExtendList = 'Extend list with new item',
    MkdnUpdateNumbering = 'Update numbering in ordered list',
    MkdnTableNextCell = 'Jump to next table cell',
    MkdnTablePrevCell = 'Jump to previous table cell',
    MkdnTableCellNewLine = 'Insert new line in table cell',
    MkdnTableNextRow = 'Jump to next table row',
    MkdnTablePrevRow = 'Jump to previous table row',
    MkdnTableNewRowBelow = 'Insert table row below',
    MkdnTableNewRowAbove = 'Insert table row above',
    MkdnTableNewColAfter = 'Insert table column after',
    MkdnTableNewColBefore = 'Insert table column before',
    MkdnTableDeleteRow = 'Delete current table row',
    MkdnTableDeleteCol = 'Delete current table column',
    MkdnFoldSection = 'Fold current section',
    MkdnUnfoldSection = 'Unfold current section',
    MkdnTab = 'Indent list item or jump to next table cell',
    MkdnSTab = 'Dedent list item or jump to previous table cell',
    MkdnCreateLink = 'Create link from word or selection',
    MkdnCreateLinkFromClipboard = 'Create link using clipboard URL',
}

-- Operator commands that need special handling (expression mappings for dot-repeat)
local operator_commands = {
    MkdnIncreaseHeadingOp = 'increase',
    MkdnDecreaseHeadingOp = 'decrease',
}

-- Commands that use operator-style visual mode handling (for dot-repeat) but
-- direct action in normal mode. Visual mode uses headingOperatorVisual() so
-- dot-repeat works like Vim's built-in < and > operators.
local visual_operator_commands = {
    MkdnIncreaseHeading = 'increase',
    MkdnDecreaseHeading = 'decrease',
}

-- Commands with fallback behavior that need special callback mappings
-- NOTE: We CANNOT use expr=true mappings for these because they have side effects
-- (buffer changes, cursor moves, text edits) which are not allowed during expr
-- mapping evaluation. Instead, we use regular callbacks with feedkeys for fallback.
local fallback_commands = {
    MkdnEnter = true,
    MkdnTab = true,
    MkdnSTab = true,
    MkdnTableCellNewLine = true,
}

-- Helper to set up a single mapping
local function setup_mapping(mode, lhs, command)
    local is_operator = operator_commands[command]

    if is_operator then
        -- Operator commands need expression mappings for normal mode
        -- and special handling for visual mode
        if mode == 'n' then
            -- Normal mode: expression mapping that returns g@
            vim.api.nvim_buf_set_keymap(0, mode, lhs, '', {
                noremap = true,
                expr = true,
                desc = descriptions[command],
                callback = function()
                    return require('mkdnflow.cursor').setupHeadingOperator(is_operator)
                end,
            })
        elseif mode == 'v' then
            -- Visual mode: escape and call the visual handler
            vim.api.nvim_buf_set_keymap(0, mode, lhs, '', {
                noremap = true,
                desc = descriptions[command],
                callback = function()
                    -- Exit visual mode first so marks are set
                    vim.api.nvim_feedkeys(
                        vim.api.nvim_replace_termcodes('<Esc>', true, false, true),
                        'nx',
                        false
                    )
                    require('mkdnflow.cursor').headingOperatorVisual(is_operator)
                end,
            })
        end
    elseif visual_operator_commands[command] and mode == 'v' then
        -- Visual mode heading commands: use operator-style handling for dot-repeat
        -- (same as g+/g- but without requiring a motion in normal mode)
        local direction = visual_operator_commands[command]
        vim.api.nvim_buf_set_keymap(0, mode, lhs, '', {
            noremap = true,
            desc = descriptions[command],
            callback = function()
                -- Exit visual mode first so marks are set
                vim.api.nvim_feedkeys(
                    vim.api.nvim_replace_termcodes('<Esc>', true, false, true),
                    'nx',
                    false
                )
                require('mkdnflow.cursor').headingOperatorVisual(direction)
            end,
        })
    elseif fallback_commands[command] then
        -- Commands with fallback behavior use regular callbacks (NOT expr mappings)
        -- because they have side effects that aren't allowed in expr context
        if command == 'MkdnEnter' then
            if mode == 'v' then
                -- Visual mode needs ':' prefix to preserve range
                vim.api.nvim_buf_set_keymap(0, mode, lhs, ':' .. command .. '<CR>', {
                    noremap = true,
                    desc = descriptions[command],
                })
            elseif mode == 'i' then
                -- Insert mode: callback with feedkeys fallback
                vim.api.nvim_buf_set_keymap(0, mode, lhs, '', {
                    noremap = true,
                    desc = descriptions[command],
                    callback = function()
                        local fallback = require('mkdnflow.wrappers').multiFuncEnter()
                        if fallback then
                            vim.api.nvim_feedkeys(fallback, 'n', true)
                        end
                    end,
                })
            else
                -- Normal mode: standard command mapping
                vim.api.nvim_buf_set_keymap(0, mode, lhs, '<Cmd>' .. command .. '<CR>', {
                    noremap = true,
                    desc = descriptions[command],
                })
            end
        elseif command == 'MkdnTab' then
            vim.api.nvim_buf_set_keymap(0, mode, lhs, '', {
                noremap = true,
                desc = descriptions[command],
                callback = function()
                    local fallback = require('mkdnflow.wrappers').indentListItemOrJumpTableCell(1)
                    if fallback then
                        vim.api.nvim_feedkeys(fallback, 'n', true)
                    end
                end,
            })
        elseif command == 'MkdnSTab' then
            vim.api.nvim_buf_set_keymap(0, mode, lhs, '', {
                noremap = true,
                desc = descriptions[command],
                callback = function()
                    local fallback = require('mkdnflow.wrappers').indentListItemOrJumpTableCell(-1)
                    if fallback then
                        vim.api.nvim_feedkeys(fallback, 'n', true)
                    end
                end,
            })
        elseif command == 'MkdnTableCellNewLine' then
            vim.api.nvim_buf_set_keymap(0, mode, lhs, '', {
                noremap = true,
                desc = descriptions[command],
                callback = function()
                    local fallback = require('mkdnflow.tables').cellNewLine()
                    if fallback then
                        vim.api.nvim_feedkeys(fallback, 'n', true)
                    end
                end,
            })
        end
    else
        -- Standard command mapping
        -- Use different mapping for visual mode to preserve range
        -- <Cmd> doesn't pass visual selection; ':' does (with '<,'>)
        local rhs = (mode == 'v') and (':' .. command .. '<CR>') or ('<Cmd>:' .. command .. '<CR>')
        vim.api.nvim_buf_set_keymap(0, mode, lhs, rhs, {
            noremap = true,
            desc = descriptions[command],
        })
    end
end

-- Enable mappings in buffers in which Mkdnflow activates
if nvim_version >= 9 and #filetype_patterns > 0 then
    vim.api.nvim_create_augroup('MkdnflowMappings', { clear = true })
    vim.api.nvim_create_autocmd('FileType', {
        pattern = filetype_patterns,
        callback = function()
            for command, mapping in pairs(config.mappings) do
                local available = true
                -- Check if the modules the command is dependent on are disabled by user
                if command_deps[command] then
                    for _, module in ipairs(command_deps[command]) do
                        if not config.modules[module] then
                            available = false
                        end
                    end
                end
                if available and mapping and type(mapping[1]) == 'table' then
                    for _, mode in ipairs(mapping[1]) do
                        setup_mapping(mode, mapping[2], command)
                    end
                elseif available and type(mapping) == 'table' then
                    setup_mapping(mapping[1], mapping[2], command)
                end
            end
        end,
    })
end
