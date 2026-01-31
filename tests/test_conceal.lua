-- tests/test_conceal.lua
-- Tests for link concealing functionality
--
-- Note: The conceal module works through autocmds that set window-local options
-- and use vim.fn.matchadd(). Testing this in a headless Neovim environment
-- is limited because the autocmds depend on specific events (FileType, BufRead,
-- BufEnter) and file patterns (*.md). We verify module loading and structure here.

local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

local T = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
                require('mkdnflow').setup({
                    modules = { conceal = true },
                    silent = true
                })
            ]])
        end,
        post_once = child.stop,
    },
})

-- =============================================================================
-- Module loading
-- =============================================================================
T['module'] = new_set()

T['module']['loads without error'] = function()
    -- If we got here, the module loaded successfully
    eq(true, true)
end

T['module']['mkdnflow config has conceal enabled'] = function()
    local conceal_enabled = child.lua_get('require("mkdnflow").config.modules.conceal')
    eq(conceal_enabled, true)
end

-- =============================================================================
-- Configuration
-- =============================================================================
T['config'] = new_set()

T['config']['uses markdown style by default'] = function()
    local style = child.lua_get('require("mkdnflow").config.links.style')
    eq(style, 'markdown')
end

T['config']['can use wiki style'] = function()
    child.lua([[
        require('mkdnflow').setup({
            modules = { conceal = true },
            links = { style = 'wiki' },
            silent = true
        })
    ]])
    local style = child.lua_get('require("mkdnflow").config.links.style')
    eq(style, 'wiki')
end

return T
