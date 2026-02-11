-- demo_init.lua — Standalone Neovim config for VHS demo recordings
-- Bootstraps lazy.nvim and installs only the plugins needed for visual demos:
-- kanagawa (colorscheme), lualine (statusline), screenkey (keystroke display),
-- and mkdnflow (loaded from the current working directory).
--
-- Usage: nvim -u scripts/demos/demo_init.lua

local root = vim.fn.fnamemodify('./scripts/demos/.lazy', ':p')

-- Set stdpaths to use isolated directory (avoids polluting real config)
for _, name in ipairs({ 'config', 'data', 'state', 'cache' }) do
    vim.env[('XDG_%s_HOME'):format(name:upper())] = root .. '/' .. name
end

-- Bootstrap lazy.nvim
local lazypath = root .. '/plugins/lazy.nvim'
if not vim.loop.fs_stat(lazypath) then
    vim.fn.system({
        'git', 'clone', '--filter=blob:none', '--single-branch',
        'https://github.com/folke/lazy.nvim.git',
        lazypath,
    })
end
vim.opt.runtimepath:prepend(lazypath)

-- Add the plugin repo itself to runtimepath
vim.cmd([[let &rtp.=','.getcwd()]])

-- Visual options
vim.o.number = true
vim.o.relativenumber = true
vim.o.cursorline = true
vim.o.signcolumn = 'yes'
vim.o.termguicolors = true
vim.o.laststatus = 3
vim.o.showmode = false
vim.o.showcmd = false
vim.o.tabstop = 4
vim.o.shiftwidth = 4
vim.o.expandtab = true
vim.o.breakindent = true
vim.o.linebreak = true
vim.o.numberwidth = 3
vim.o.cmdheight = 0
vim.o.scrolloff = 4

-- Shared state between lualine (display) and screenkey (updates)
local screenkey_old = ""
local screenkey_new = ""
local screenkey_new_fg = nil

require('lazy').setup({
    -- Colorscheme
    {
        'rebelot/kanagawa.nvim',
        lazy = false,
        priority = 1000,
        config = function()
            require('kanagawa').setup({
                transparent = false,
                colors = {
                    theme = {
                        all = {
                            ui = {
                                bg_gutter = "none"
                            }
                        }
                    }
                },
                overrides = function(colors)
                    return {
                        StatusLine = { bg = colors.palette.sumiInk4 },
                        StatusLineNC = { bg = colors.palette.sumiInk4 }
                    }
                end
            })
            vim.cmd('colorscheme kanagawa')
        end,
    },

    -- Statusline
    {
        'nvim-lualine/lualine.nvim',
        dependencies = { 'nvim-tree/nvim-web-devicons' },
        config = function()
            local colors = require('kanagawa.colors').setup().palette
            require('lualine').setup({
                options = {
                    theme = 'kanagawa',
                    component_separators = { left = '', right = '' },
                    section_separators = { left = '', right = '' },
                    icons_enabled = true,
                    globalstatus = true,
                },
                sections = {
                    lualine_a = { {'mode', separator = { left = '', right = ''} } },
                    lualine_b = {},
                    lualine_c = {
                        {
                            function() return screenkey_old end,
                            color = { fg = colors.surimiOrange },
                            padding = { left = 1, right = 0},
                            cond = function() return #screenkey_old > 0 end,
                            separator = '',
                        },
                        {
                            function() return screenkey_new end,
                            color = function()
                                return { fg = screenkey_new_fg or colors.surimiOrange }
                            end,
                            padding = { left = 1, right = 1 },
                            separator = '',
                        },
                    },
                    lualine_x = {},
                    lualine_y = {
                        { 'filetype', separator = { left = '', right = '' } }
                    },
                    lualine_z = {},
                },
            })
        end,
    },

    -- Keystroke display
    {
        'NStefan002/screenkey.nvim',
        lazy = false,
        config = function()
            local relabel_keys = function(keys)
                local custom_names = {
                    ['<Ctrl>+<Space>'] = '<C-Space>',
                    ['<Alt>+<CR>'] = '<Alt-CR>',
                }
                for _, k in ipairs(keys) do
                    k.key = custom_names[k.key] or k.key
                end
                return keys
            end
            require('screenkey').setup({
                win_opts = {
                    row = vim.o.lines - vim.o.cmdheight - 1,
                    col = vim.o.columns - 1,
                    relative = 'editor',
                    anchor = 'SE',
                    width = 40,
                    height = 3,
                    border = 'rounded',
                },
                compress_after = 2,
                clear_after = 3,
                show_leader = true,
                group_mappings = true,
                filter = function(keys)
                    keys = relabel_keys(keys)
                    keys = vim.tbl_filter(function(key)
                        return key.is_mapping
                    end, keys)
                    -- Merge consecutive identical keys after relabeling,
                    -- since relabeling can make different raw names identical
                    local merged = {}
                    for _, k in ipairs(keys) do
                        if #merged > 0 and k.key == merged[#merged].key then
                            merged[#merged].consecutive_repeats = merged[#merged].consecutive_repeats
                                + k.consecutive_repeats
                        else
                            table.insert(merged, k)
                        end
                    end
                    return merged
                end,
                keys = {
                    ['<TAB>'] = '<Tab>',
                    ['<CR>'] = '<CR>',
                    ['<ESC>'] = '<Esc>',
                    ['<SPACE>'] = '<Space>',
                    ['<BS>'] = '<BS>',
                    ['<DEL>'] = '<Del>',
                    ['<LEFT>'] = '<Left>',
                    ['<RIGHT>'] = '<Right>',
                    ['<UP>'] = '<Up>',
                    ['<DOWN>'] = '<Down>',
                    ['<HOME>'] = '<Home>',
                    ['<END>'] = '<End>',
                    ['<PAGEUP>'] = '<PgUp>',
                    ['<PAGEDOWN>'] = '<PgDn>',
                    ['<INSERT>'] = '<Ins>',
                    ['<F1>'] = '<F1>',
                    ['<F2>'] = '<F2>',
                    ['CTRL'] = '<Ctrl>',
                    ['ALT'] = '<Alt>',
                    ['SUPER'] = '<Super>',
                    ['<leader>'] = '<leader>',
                },
            })
            local palette = require('kanagawa.colors').setup().palette
            local flash_color = palette.crystalBlue
            local base_color = palette.surimiOrange
            screenkey_new_fg = base_color

            local function hex_to_rgb(hex)
                hex = hex:gsub('#', '')
                return tonumber(hex:sub(1, 2), 16),
                    tonumber(hex:sub(3, 4), 16),
                    tonumber(hex:sub(5, 6), 16)
            end

            local function lerp_color(c1, c2, t)
                local r1, g1, b1 = hex_to_rgb(c1)
                local r2, g2, b2 = hex_to_rgb(c2)
                return string.format('#%02x%02x%02x',
                    math.floor(r1 + (r2 - r1) * t + 0.5),
                    math.floor(g1 + (g2 - g1) * t + 0.5),
                    math.floor(b1 + (b2 - b1) * t + 0.5))
            end

            local function split_keys(full)
                -- Split at last separator space: old keys stay orange, newest fades
                for i = #full, 1, -1 do
                    if full:sub(i, i) == ' ' then
                        return full:sub(1, i - 1), full:sub(i + 1)
                    end
                end
                return '', full
            end

            local fade_steps = 10
            local fade_interval = 50 -- ms per step (500ms total)
            local fade_timer = nil

            vim.api.nvim_create_autocmd('User', {
                pattern = 'ScreenkeyUpdated',
                callback = function()
                    local full = require('screenkey').get_keys()
                    screenkey_old, screenkey_new = split_keys(full)
                    if fade_timer then
                        fade_timer:stop()
                        fade_timer:close()
                    end
                    screenkey_new_fg = flash_color
                    require('lualine').refresh()
                    local step = 0
                    fade_timer = vim.loop.new_timer()
                    fade_timer:start(fade_interval, fade_interval, vim.schedule_wrap(function()
                        if not fade_timer then
                            return
                        end
                        step = step + 1
                        screenkey_new_fg = lerp_color(flash_color, base_color, step / fade_steps)
                        require('lualine').refresh()
                        if step >= fade_steps then
                            fade_timer:stop()
                            fade_timer:close()
                            fade_timer = nil
                        end
                    end))
                end,
            })
            vim.api.nvim_create_autocmd('User', {
                pattern = 'ScreenkeyCleared',
                callback = function()
                    screenkey_old = ''
                    screenkey_new = ''
                    require('lualine').refresh()
                end,
            })
            require('screenkey').toggle_statusline_component()
        end,
    },

    -- mkdnflow loaded from the current directory (no lazy-loading for demos)
    {
        dir = vim.fn.getcwd(),
        name = 'mkdnflow.nvim',
        lazy = false,
        config = function()
            require('mkdnflow').setup({
                new_file_template = {
                    enabled = true,
                    placeholders = {
                        before = { title = 'link_title', date = 'os_date' },
                        after = {},
                    },
                    template = '# {{ title }}',
                },
                to_do = {
                    highlight = true,
                },
                foldtext = {
                    object_count_icon_set = 'nerdfont',
                },
                links = {
                    transform_on_create = false,
                },
                mappings = {
                    MkdnEnter = { { "i", "n", "v" }, "<CR>" },
                    MkdnFollowLink = false,
                    MkdnTab = { "i", "<Tab>" },
                    MkdnSTab = { "i", "<S-Tab>" },
                    MkdnToggleToDo = { { 'n', 'v' }, '<C-Space>' },
                    MkdnTableNextCell = false,
                    MkdnTablePrevCell = false,
                },
            })
        end,
    },
}, {
    root = root .. '/plugins',
})
