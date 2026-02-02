-- tests/test_maps.lua
-- Tests for keybinding setup functionality
--
-- Note: The maps module sets up buffer-local keymaps via autocmds.
-- Testing keymaps in a headless environment is limited, so we focus on
-- verifying module loading and configuration access.

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
                    modules = { maps = true },
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
    eq(true, true)
end

T['module']['mkdnflow config has maps enabled'] = function()
    local maps_enabled = child.lua_get('require("mkdnflow").config.modules.maps')
    eq(maps_enabled, true)
end

-- =============================================================================
-- Default mappings configuration
-- =============================================================================
T['mappings'] = new_set()

T['mappings']['has mappings table in config'] = function()
    local has_mappings = child.lua_get('require("mkdnflow").config.mappings ~= nil')
    eq(has_mappings, true)
end

T['mappings']['MkdnEnter mapping exists'] = function()
    local mapping = child.lua_get('require("mkdnflow").config.mappings.MkdnEnter')
    eq(mapping ~= nil, true)
end

T['mappings']['MkdnNextLink mapping exists'] = function()
    local mapping = child.lua_get('require("mkdnflow").config.mappings.MkdnNextLink')
    eq(mapping ~= nil, true)
end

T['mappings']['MkdnPrevLink mapping exists'] = function()
    local mapping = child.lua_get('require("mkdnflow").config.mappings.MkdnPrevLink')
    eq(mapping ~= nil, true)
end

T['mappings']['MkdnGoBack mapping exists'] = function()
    local mapping = child.lua_get('require("mkdnflow").config.mappings.MkdnGoBack')
    eq(mapping ~= nil, true)
end

T['mappings']['MkdnGoForward mapping exists'] = function()
    local mapping = child.lua_get('require("mkdnflow").config.mappings.MkdnGoForward')
    eq(mapping ~= nil, true)
end

-- =============================================================================
-- Mapping disabling
-- =============================================================================
T['disable'] = new_set()

T['disable']['can disable specific mapping'] = function()
    child.lua([[
        require('mkdnflow').setup({
            modules = { maps = true },
            mappings = {
                MkdnEnter = false
            },
            silent = true
        })
    ]])
    local mapping = child.lua_get('require("mkdnflow").config.mappings.MkdnEnter')
    eq(mapping, false)
end

T['disable']['can customize mapping'] = function()
    child.lua([[
        require('mkdnflow').setup({
            modules = { maps = true },
            mappings = {
                MkdnEnter = { 'n', '<Leader>m' }
            },
            silent = true
        })
    ]])
    local mapping = child.lua_get('require("mkdnflow").config.mappings.MkdnEnter')
    eq(mapping[1], 'n')
    eq(mapping[2], '<Leader>m')
end

-- =============================================================================
-- Keymap descriptions (for which-key compatibility)
-- =============================================================================
T['descriptions'] = new_set()

T['descriptions']['are set on keymaps'] = function()
    -- Trigger the autocmd that sets up keymaps
    child.cmd('doautocmd BufEnter')
    -- Check that the Tab keymap has a description containing 'next link'
    child.lua(
        '_test_found = false; for _, km in ipairs(vim.api.nvim_buf_get_keymap(0, "n")) do if km.lhs == "<Tab>" and km.desc and km.desc:match("next link") then _test_found = true; break end end'
    )
    local found = child.lua_get('_test_found')
    eq(found, true)
end

T['descriptions']['MkdnEnter has description'] = function()
    -- Trigger the autocmd that sets up keymaps
    child.cmd('doautocmd BufEnter')
    child.lua(
        '_test_found = false; for _, km in ipairs(vim.api.nvim_buf_get_keymap(0, "n")) do if km.lhs == "<CR>" and km.desc and km.desc:match("Follow link") then _test_found = true; break end end'
    )
    local found = child.lua_get('_test_found')
    eq(found, true)
end

T['descriptions']['MkdnToggleToDo has description'] = function()
    -- Trigger the autocmd that sets up keymaps
    child.cmd('doautocmd BufEnter')
    child.lua(
        '_test_found = false; for _, km in ipairs(vim.api.nvim_buf_get_keymap(0, "n")) do if km.lhs == "<C-Space>" and km.desc and km.desc:match("to%-do") then _test_found = true; break end end'
    )
    local found = child.lua_get('_test_found')
    eq(found, true)
end

-- =============================================================================
-- Autogroup
-- =============================================================================
T['autogroup'] = new_set()

T['autogroup']['MkdnflowMappings exists'] = function()
    -- Try to get autocmds for the group
    child.lua('_success = pcall(vim.api.nvim_del_augroup_by_name, "MkdnflowMappings")')
    local success = child.lua_get('_success')
    eq(success, true)
end

return T
