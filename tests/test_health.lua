-- tests/test_health.lua
-- Tests for health check and MkdnCleanConfig

local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

-- Helper to get all buffer lines as a single string
local function get_buf_text()
    return child.lua_get([[
        table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
    ]])
end

local T = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
            ]])
        end,
        post_once = child.stop,
    },
})

-- =============================================================================
-- State preservation (raw_user_config, default_config)
-- =============================================================================
T['state'] = new_set()

T['state']['stores raw_user_config before compat mutation'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = { name_is_source = true },
            silent = true,
        })
    ]])
    -- raw_user_config should have the deprecated key
    local has_old = child.lua_get(
        "require('mkdnflow').raw_user_config.links.name_is_source"
    )
    eq(has_old, true)
end

T['state']['raw_user_config is independent of compat mutations'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = { name_is_source = true },
            silent = true,
        })
    ]])
    -- compat migrates name_is_source → compact in user_config
    -- but raw_user_config should still have name_is_source
    local raw_has_old = child.lua_get(
        "require('mkdnflow').raw_user_config.links.name_is_source"
    )
    eq(raw_has_old, true)
    -- user_config (post-compat) should have compact, not name_is_source
    local post_has_new = child.lua_get(
        "require('mkdnflow').user_config.links.compact"
    )
    eq(post_has_new, true)
end

T['state']['stores default_config before merge'] = function()
    child.lua([[
        require('mkdnflow').setup({
            silent = true,
            wrap = true,
        })
    ]])
    -- default_config should have the original default for wrap (false)
    local default_wrap = child.lua_get("require('mkdnflow').default_config.wrap")
    eq(default_wrap, false)
    -- merged config should have the user's override
    local config_wrap = child.lua_get("require('mkdnflow').config.wrap")
    eq(config_wrap, true)
end

T['state']['raw_user_config is nil-like for empty setup'] = function()
    child.lua([[
        require('mkdnflow').setup({})
    ]])
    -- raw_user_config should be an empty table (deepcopy of {})
    local is_empty = child.lua_get([[
        next(require('mkdnflow').raw_user_config) == nil
    ]])
    eq(is_empty, true)
end

-- =============================================================================
-- Deprecation registry
-- =============================================================================
T['deprecation_registry'] = new_set()

T['deprecation_registry']['deprecations table is accessible'] = function()
    child.lua([[require('mkdnflow').setup({ silent = true })]])
    local count = child.lua_get("#require('mkdnflow.compat').deprecations")
    -- Should have a reasonable number of deprecation entries
    eq(count > 20, true)
end

T['deprecation_registry']['status_deprecations table is accessible'] = function()
    child.lua([[require('mkdnflow').setup({ silent = true })]])
    local count = child.lua_get("#require('mkdnflow.compat').status_deprecations")
    eq(count, 3)
end

T['deprecation_registry']['extension_to_filetype table is accessible'] = function()
    child.lua([[require('mkdnflow').setup({ silent = true })]])
    local md = child.lua_get("require('mkdnflow.compat').extension_to_filetype.md")
    eq(md, 'markdown')
end

-- =============================================================================
-- Health check (:checkhealth mkdnflow)
-- =============================================================================
T['checkhealth'] = new_set()

T['checkhealth']['reports OK for clean default config'] = function()
    child.lua([[require('mkdnflow').setup({ silent = true })]])
    child.lua([[require('mkdnflow.health').check()]])
    -- No errors should have been raised
end

T['checkhealth']['runs via :checkhealth command'] = function()
    child.lua([[require('mkdnflow').setup({ silent = true })]])
    child.lua([[vim.cmd('checkhealth mkdnflow')]])
    local text = get_buf_text()
    -- Should contain our section headers
    local has_env = text:find('environment') ~= nil
    local has_config = text:find('configuration') ~= nil
    local has_modules = text:find('modules') ~= nil
    eq(has_env, true)
    eq(has_config, true)
    eq(has_modules, true)
end

T['checkhealth']['detects deprecated top-level key'] = function()
    child.lua([[
        require('mkdnflow').setup({
            perspective = { priority = 'current' },
            silent = true,
        })
    ]])
    child.lua([[vim.cmd('checkhealth mkdnflow')]])
    local text = get_buf_text()
    local has_perspective_warn = text:find('perspective.*deprecated') ~= nil
    eq(has_perspective_warn, true)
end

T['checkhealth']['detects deprecated nested key'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = { name_is_source = true },
            silent = true,
        })
    ]])
    child.lua([[vim.cmd('checkhealth mkdnflow')]])
    local text = get_buf_text()
    local has_warn = text:find('name_is_source.*deprecated') ~= nil
    eq(has_warn, true)
end

T['checkhealth']['detects extension-based filetype key'] = function()
    child.lua([[
        require('mkdnflow').setup({
            filetypes = { md = true },
            silent = true,
        })
    ]])
    child.lua([[vim.cmd('checkhealth mkdnflow')]])
    local text = get_buf_text()
    local has_warn = text:find('md.*extension') ~= nil
    eq(has_warn, true)
end

T['checkhealth']['detects status-level deprecated key'] = function()
    child.lua([[
        require('mkdnflow').setup({
            to_do = {
                statuses = {
                    { name = 'not_started', symbol = ' ' },
                }
            },
            silent = true,
        })
    ]])
    child.lua([[vim.cmd('checkhealth mkdnflow')]])
    local text = get_buf_text()
    local has_warn = text:find('symbol.*deprecated') ~= nil
    eq(has_warn, true)
end

T['checkhealth']['detects string mapping values'] = function()
    child.lua([[
        require('mkdnflow').setup({
            mappings = { MkdnGoBack = '<BS>' },
            silent = true,
        })
    ]])
    child.lua([[vim.cmd('checkhealth mkdnflow')]])
    local text = get_buf_text()
    local has_warn = text:find('MkdnGoBack.*string') ~= nil
    eq(has_warn, true)
end

T['checkhealth']['reports redundant defaults'] = function()
    child.lua([[
        require('mkdnflow').setup({
            wrap = false,
            silent = true,
        })
    ]])
    child.lua([[vim.cmd('checkhealth mkdnflow')]])
    local text = get_buf_text()
    -- wrap = false is the default, so it should be flagged
    local has_redundant = text:find('wrap') ~= nil and text:find('default') ~= nil
    eq(has_redundant, true)
end

T['checkhealth']['does not report individual array element fields as redundant'] = function()
    -- to_do.statuses is an array that mergeTables replaces wholesale. Individual
    -- fields inside array elements (like statuses[1].name) must NOT be reported as
    -- redundant, because the user can't remove them independently — they'd need to
    -- remove the entire statuses array or keep all of it.
    child.lua([[
        require('mkdnflow').setup({
            to_do = {
                statuses = {
                    { name = 'not_started', marker = ' ' },
                    { name = 'in_progress', marker = '-' },
                    { name = 'complete', marker = 'x' },
                }
            },
            silent = true,
        })
    ]])
    child.lua([[vim.cmd('checkhealth mkdnflow')]])
    local text = get_buf_text()
    -- Should NOT report individual fields like statuses.1.name
    local has_element_field = text:find('statuses%.%d+%.') ~= nil
    eq(has_element_field, false)
end

T['checkhealth']['reports whole array value as redundant when it matches default'] = function()
    -- Mapping values are simple arrays (e.g. { 'n', '<Tab>' }) that mergeTables
    -- replaces wholesale. If the user provides one identical to the default, the
    -- whole value should be flagged as redundant (not individual elements).
    child.lua([[
        require('mkdnflow').setup({
            mappings = {
                MkdnNextLink = { 'n', '<Tab>' },
            },
            silent = true,
        })
    ]])
    child.lua([[vim.cmd('checkhealth mkdnflow')]])
    local text = get_buf_text()
    -- mappings.MkdnNextLink should be flagged as matching its default
    local has_mapping = text:find('MkdnNextLink') ~= nil
    eq(has_mapping, true)
    -- But not as individual elements like mappings.MkdnNextLink.1
    local has_element = text:find('MkdnNextLink%.%d') ~= nil
    eq(has_element, false)
end

T['checkhealth']['reports no deprecated keys for clean config'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = { compact = true },
            silent = true,
        })
    ]])
    child.lua([[vim.cmd('checkhealth mkdnflow')]])
    local text = get_buf_text()
    local has_no_deprecated = text:find('No deprecated config keys') ~= nil
    eq(has_no_deprecated, true)
end

T['checkhealth']['lists enabled modules'] = function()
    child.lua([[
        require('mkdnflow').setup({ silent = true })
    ]])
    child.lua([[vim.cmd('checkhealth mkdnflow')]])
    local text = get_buf_text()
    local has_enabled = text:find('modules enabled') ~= nil
    eq(has_enabled, true)
end

T['checkhealth']['lists disabled modules'] = function()
    child.lua([[
        require('mkdnflow').setup({
            modules = { bib = false },
            silent = true,
        })
    ]])
    child.lua([[vim.cmd('checkhealth mkdnflow')]])
    local text = get_buf_text()
    local has_disabled = text:find('modules disabled') ~= nil
    eq(has_disabled, true)
    local has_bib = text:find('bib') ~= nil
    eq(has_bib, true)
end

-- =============================================================================
-- MkdnCleanConfig command
-- =============================================================================
T['cleanconfig'] = new_set()

T['cleanconfig']['opens floating window'] = function()
    child.lua([[
        require('mkdnflow').setup({
            wrap = true,
            silent = true,
        })
    ]])
    child.lua([[
        vim.cmd('runtime plugin/mkdnflow.lua')
        vim.cmd('MkdnCleanConfig')
    ]])
    local filetype = child.lua_get('vim.bo.filetype')
    eq(filetype, 'lua')
    -- Current window should be a floating window
    local is_float = child.lua_get([[
        vim.api.nvim_win_get_config(0).relative ~= ''
    ]])
    eq(is_float, true)
end

T['cleanconfig']['removes redundant defaults'] = function()
    child.lua([[
        require('mkdnflow').setup({
            wrap = true,
            silent = false,
        })
    ]])
    child.lua([[
        vim.cmd('runtime plugin/mkdnflow.lua')
        vim.cmd('MkdnCleanConfig')
    ]])
    local text = get_buf_text()
    -- wrap = true is NOT a default (default is false), so it should appear
    local has_wrap = text:find('wrap') ~= nil
    eq(has_wrap, true)
    -- silent = false IS the default, so it should NOT appear
    local has_silent = text:find('silent') ~= nil
    eq(has_silent, false)
end

T['cleanconfig']['keeps non-default values'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = { style = 'wiki', compact = true },
            silent = true,
        })
    ]])
    child.lua([[
        vim.cmd('runtime plugin/mkdnflow.lua')
        vim.cmd('MkdnCleanConfig')
    ]])
    local text = get_buf_text()
    -- style = 'wiki' is not the default ('markdown'), should appear
    local has_style = text:find('wiki') ~= nil
    eq(has_style, true)
    -- compact = true is not the default (false), should appear
    local has_compact = text:find('compact') ~= nil
    eq(has_compact, true)
end

T['cleanconfig']['handles all-default config'] = function()
    child.lua([[
        require('mkdnflow').setup({
            wrap = false,
            silent = false,
        })
    ]])
    child.lua([[
        vim.cmd('runtime plugin/mkdnflow.lua')
        vim.cmd('MkdnCleanConfig')
    ]])
    local text = get_buf_text()
    local has_minimal = text:find('already minimal') ~= nil
    eq(has_minimal, true)
end

T['cleanconfig']['uses current key names for deprecated keys'] = function()
    -- User passes deprecated key; clean config should use the new name
    child.lua([[
        require('mkdnflow').setup({
            links = { name_is_source = true },
            silent = true,
        })
    ]])
    child.lua([[
        vim.cmd('runtime plugin/mkdnflow.lua')
        vim.cmd('MkdnCleanConfig')
    ]])
    local text = get_buf_text()
    -- Should use 'compact' (new name), not 'name_is_source' (old name)
    local has_compact = text:find('compact') ~= nil
    local has_old = text:find('name_is_source') ~= nil
    eq(has_compact, true)
    eq(has_old, false)
end

T['cleanconfig']['marks function values with placeholder'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = {
                transform_on_create = function(text) return text:lower() end,
            },
            silent = true,
        })
    ]])
    child.lua([[
        vim.cmd('runtime plugin/mkdnflow.lua')
        vim.cmd('MkdnCleanConfig')
    ]])
    local text = get_buf_text()
    local has_placeholder = text:find('custom function') ~= nil
    eq(has_placeholder, true)
end

T['cleanconfig']['preserves custom statuses array intact'] = function()
    -- Arrays are replaced wholesale by mergeTables, so MkdnCleanConfig must keep
    -- the entire array even when some element fields happen to match defaults.
    child.lua([[
        require('mkdnflow').setup({
            to_do = {
                statuses = {
                    { name = 'not_started', marker = ' ' },
                    { name = 'in_progress', marker = '-' },
                    { name = 'complete', marker = 'x' },
                }
            },
            silent = true,
        })
    ]])
    child.lua([[
        vim.cmd('runtime plugin/mkdnflow.lua')
        vim.cmd('MkdnCleanConfig')
    ]])
    local text = get_buf_text()
    -- The statuses array should appear in the output (it differs from default
    -- because the default statuses have more fields like highlight, sort, etc.)
    local has_statuses = text:find('statuses') ~= nil
    eq(has_statuses, true)
    -- All three names should be present — none stripped as "redundant"
    local has_not_started = text:find('not_started') ~= nil
    local has_in_progress = text:find('in_progress') ~= nil
    local has_complete = text:find('complete') ~= nil
    eq(has_not_started, true)
    eq(has_in_progress, true)
    eq(has_complete, true)
end

T['cleanconfig']['buffer is not modifiable'] = function()
    child.lua([[
        require('mkdnflow').setup({
            wrap = true,
            silent = true,
        })
    ]])
    child.lua([[
        vim.cmd('runtime plugin/mkdnflow.lua')
        vim.cmd('MkdnCleanConfig')
    ]])
    local modifiable = child.lua_get('vim.bo.modifiable')
    eq(modifiable, false)
end

T['cleanconfig']['contains setup call'] = function()
    child.lua([[
        require('mkdnflow').setup({
            wrap = true,
            silent = true,
        })
    ]])
    child.lua([[
        vim.cmd('runtime plugin/mkdnflow.lua')
        vim.cmd('MkdnCleanConfig')
    ]])
    local text = get_buf_text()
    local has_setup = text:find("require%('mkdnflow'%).setup") ~= nil
    eq(has_setup, true)
end

return T
