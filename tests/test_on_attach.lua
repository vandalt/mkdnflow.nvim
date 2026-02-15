-- tests/test_on_attach.lua
-- Tests for the on_attach callback feature

local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

local T = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
        end,
        post_once = child.stop,
    },
})

-- =============================================================================
-- on_attach fires on matching filetype
-- =============================================================================
T['callback'] = new_set()

T['callback']['fires on matching filetype and receives correct bufnr'] = function()
    child.lua([[
        _G._on_attach_bufnr = nil
        require('mkdnflow').setup({
            silent = true,
            on_attach = function(bufnr)
                _G._on_attach_bufnr = bufnr
            end,
        })
        vim.api.nvim_buf_set_name(0, 'test.md')
        vim.bo.filetype = 'markdown'
    ]])
    local actual = child.lua_get('_G._on_attach_bufnr')
    local expected = child.lua_get('vim.api.nvim_get_current_buf()')
    eq(actual, expected)
end

T['callback']['fires even when maps module is disabled'] = function()
    child.lua([[
        _G._on_attach_fired = false
        require('mkdnflow').setup({
            silent = true,
            modules = { maps = false },
            on_attach = function(bufnr)
                _G._on_attach_fired = true
            end,
        })
        vim.api.nvim_buf_set_name(0, 'test.md')
        vim.bo.filetype = 'markdown'
    ]])
    local fired = child.lua_get('_G._on_attach_fired')
    eq(fired, true)
end

T['callback']['does not fire for non-matching filetypes'] = function()
    child.lua([[
        _G._on_attach_fired = false
        require('mkdnflow').setup({
            silent = true,
            on_attach = function(bufnr)
                _G._on_attach_fired = true
            end,
        })
        vim.api.nvim_buf_set_name(0, 'test.md')
        vim.bo.filetype = 'markdown'
    ]])
    -- Reset the flag after initial activation
    child.lua('_G._on_attach_fired = false')
    -- Open a non-markdown buffer
    child.lua([[
        local buf = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_set_current_buf(buf)
        vim.api.nvim_buf_set_name(buf, 'test.txt')
        vim.bo[buf].filetype = 'text'
    ]])
    local fired = child.lua_get('_G._on_attach_fired')
    eq(fired, false)
end

T['callback']['fires after default mappings are set up'] = function()
    child.lua([[
        vim.cmd('runtime plugin/mkdnflow.lua')
        _G._override_worked = false
        require('mkdnflow').setup({
            silent = true,
            modules = { maps = true },
            on_attach = function(bufnr)
                -- Override the default <Tab> mapping (MkdnNextLink)
                vim.keymap.set('n', '<Tab>', function()
                    _G._override_worked = true
                end, { buffer = bufnr })
            end,
        })
        vim.api.nvim_buf_set_name(0, 'test.md')
        vim.bo.filetype = 'markdown'
    ]])
    -- Trigger BufEnter to ensure mappings are set
    child.cmd('doautocmd BufEnter')
    -- Press Tab and check if our override ran
    child.type_keys('<Tab>')
    local override_worked = child.lua_get('_G._override_worked')
    eq(override_worked, true)
end

-- =============================================================================
-- Default behavior (on_attach = false)
-- =============================================================================
T['default'] = new_set()

T['default']['on_attach = false causes no errors'] = function()
    child.lua([[
        require('mkdnflow').setup({
            silent = true,
            on_attach = false,
        })
        vim.api.nvim_buf_set_name(0, 'test.md')
        vim.bo.filetype = 'markdown'
    ]])
    -- If we got here without error, the test passes
    eq(true, true)
end

T['default']['on_attach defaults to false'] = function()
    child.lua([[
        require('mkdnflow').setup({ silent = true })
    ]])
    local on_attach = child.lua_get('require("mkdnflow").config.on_attach')
    eq(on_attach, false)
end

-- =============================================================================
-- Augroup
-- =============================================================================
T['augroup'] = new_set()

T['augroup']['MkdnflowOnAttach exists when callback is set'] = function()
    child.lua([[
        require('mkdnflow').setup({
            silent = true,
            on_attach = function(bufnr) end,
        })
        vim.api.nvim_buf_set_name(0, 'test.md')
        vim.bo.filetype = 'markdown'
    ]])
    child.lua('_success = pcall(vim.api.nvim_del_augroup_by_name, "MkdnflowOnAttach")')
    local success = child.lua_get('_success')
    eq(success, true)
end

T['augroup']['MkdnflowOnAttach does not exist when on_attach is false'] = function()
    child.lua([[
        require('mkdnflow').setup({
            silent = true,
            on_attach = false,
        })
        vim.api.nvim_buf_set_name(0, 'test.md')
        vim.bo.filetype = 'markdown'
    ]])
    child.lua('_success = pcall(vim.api.nvim_del_augroup_by_name, "MkdnflowOnAttach")')
    local success = child.lua_get('_success')
    eq(success, false)
end

return T
