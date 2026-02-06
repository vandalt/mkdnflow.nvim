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

-- Check if treesitter highlighting is active for the buffer
local function ts_highlight_active(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local ok, hl = pcall(require, 'vim.treesitter.highlighter')
    return ok and hl.active[bufnr] ~= nil
end

-- Add conceal patterns for wiki-style links: [[target]] and [[target|alias]]
local function add_wiki_patterns()
    -- [[target|alias]] - conceal [[target| prefix
    vim.fn.matchadd('Conceal', '\\zs\\[\\[[^[]\\{-}[|]\\ze[^[]\\{-}\\]\\]', 0, -1, { conceal = '' })
    -- [[target|alias]] - conceal ]] suffix
    vim.fn.matchadd('Conceal', '\\[\\[[^[\\{-}[|][^[]\\{-}\\zs\\]\\]\\ze', 0, -1, { conceal = '' })
    -- [[target]] - conceal [[ prefix
    vim.fn.matchadd('Conceal', '\\zs\\[\\[\\ze[^[]\\{-}\\]\\]', 0, -1, { conceal = '' })
    -- [[target]] - conceal ]] suffix
    vim.fn.matchadd('Conceal', '\\[\\[[^[]\\{-}\\zs\\]\\]\\ze', 0, -1, { conceal = '' })
end

-- Add conceal patterns for markdown-style links: [text](url) and [text][ref]
local function add_markdown_patterns()
    -- Inline links: [text](url)
    vim.fn.matchadd('Conceal', '\\[[^[]\\{-}\\]\\zs([^(]\\{-})\\ze', 0, -1, { conceal = '' })
    vim.fn.matchadd('Conceal', '\\zs\\[\\ze[^[]\\{-}\\]([^(]\\{-})', 0, -1, { conceal = '' })
    vim.fn.matchadd('Conceal', '\\[[^[]\\{-}\\zs\\]\\ze([^(]\\{-})', 0, -1, { conceal = '' })
    -- Reference links: [text][ref] (with optional space, mid-line)
    vim.fn.matchadd(
        'Conceal',
        '\\[[^[]\\{-}\\]\\zs\\%[ ]\\[[^[]\\{-}\\]\\ze\\%[ ]\\v([^(]|$)',
        0,
        -1,
        { conceal = '' }
    )
    vim.fn.matchadd(
        'Conceal',
        '\\zs\\[\\ze[^[]\\{-}\\]\\%[ ]\\[[^[]\\{-}\\]\\%[ ]\\v([^(]|$)',
        0,
        -1,
        { conceal = '' }
    )
    vim.fn.matchadd(
        'Conceal',
        '\\[[^[]\\{-}\\zs\\]\\ze\\%[ ]\\[[^[]\\{-}\\]\\%[ ]\\v([^(]|$)',
        0,
        -1,
        { conceal = '' }
    )
    -- Reference links: [text][ref] (at end of line)
    vim.fn.matchadd(
        'Conceal',
        '\\[[^[]\\{-}\\]\\zs\\%[ ]\\[[^[]\\{-}\\]\\ze\\n',
        0,
        -1,
        { conceal = '' }
    )
    vim.fn.matchadd(
        'Conceal',
        '\\zs\\[\\ze[^[]\\{-}\\]\\%[ ]\\[[^[]\\{-}\\]\\n',
        0,
        -1,
        { conceal = '' }
    )
    vim.fn.matchadd(
        'Conceal',
        '\\[[^[]\\{-}\\zs\\]\\ze\\%[ ]\\[[^[]\\{-}\\]\\n',
        0,
        -1,
        { conceal = '' }
    )
end

local function start_link_concealing()
    -- Always add wiki link patterns (treesitter doesn't handle [[...]] syntax)
    add_wiki_patterns()

    -- Only add markdown link patterns if treesitter isn't already handling them
    if not ts_highlight_active() then
        add_markdown_patterns()
    end

    -- Set conceal level
    vim.wo.conceallevel = 2

    -- Don't change the highlighting of concealed characters
    vim.api.nvim_exec([[highlight Conceal ctermbg=NONE ctermfg=NONE guibg=NONE guifg=NONE]], false)
end

-- Set up autocommands to trigger the link concealing setup in Markdown files
local conceal_augroup = vim.api.nvim_create_augroup('MkdnflowLinkConcealing', { clear = true })

vim.api.nvim_create_autocmd('FileType', {
    pattern = require('mkdnflow').config.resolved_filetypes,
    callback = function()
        start_link_concealing()
    end,
    group = conceal_augroup,
})
