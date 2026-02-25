-- tests/test_validate.lua
-- Tests for config validation (unknown keys, type checking, enum, mappings, conflicts)

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

-- Helper: run validation directly and return diagnostics
-- Helper: run validation directly and return diagnostics
local function validate(user_config_str)
    child.lua(string.format(
        [[
        local validate = require('mkdnflow.validate')
        local defaults = require('mkdnflow').default_config
        local user_config = %s
        _G._test_diags = validate.validate(user_config, vim.deepcopy(defaults))
    ]],
        user_config_str
    ))
    return child.lua_get('_G._test_diags')
end

-- =============================================================================
-- Unknown key detection
-- =============================================================================
T['unknown_key'] = new_set()

T['unknown_key']['detects top-level unknown key'] = function()
    child.lua([[ require('mkdnflow').setup({ silent = true }) ]])
    local diags = validate("{ bogus = true }")
    eq(#diags, 1)
    eq(diags[1].path, 'bogus')
    eq(diags[1].message:find('Unknown') ~= nil, true)
end

T['unknown_key']['detects nested unknown key'] = function()
    child.lua([[ require('mkdnflow').setup({ silent = true }) ]])
    local diags = validate("{ links = { bogus = true } }")
    eq(#diags, 1)
    eq(diags[1].path, 'links.bogus')
end

T['unknown_key']['skips dynamic container children (filetypes)'] = function()
    child.lua([[ require('mkdnflow').setup({ silent = true }) ]])
    local diags = validate("{ filetypes = { wiki = true } }")
    eq(#diags, 0)
end

T['unknown_key']['skips dynamic container children (placeholders)'] = function()
    child.lua([[ require('mkdnflow').setup({ silent = true }) ]])
    local diags = validate("{ new_file_template = { placeholders = { author = 'Jake' } } }")
    eq(#diags, 0)
end

T['unknown_key']['skips dynamic container children (mappings)'] = function()
    child.lua([[ require('mkdnflow').setup({ silent = true }) ]])
    -- Valid command name should not be flagged by unknown-key walker
    -- (mappings is dynamic; dedicated validateMappings handles command names)
    local diags = validate("{ mappings = { MkdnGoBack = { 'n', '<BS>' } } }")
    -- Should have 0 diagnostics from the general walker (mappings is dynamic)
    -- The dedicated mappings validator runs separately via M.validate()
    eq(#diags, 0)
end

T['unknown_key']['valid keys produce no diagnostics'] = function()
    child.lua([[ require('mkdnflow').setup({ silent = true }) ]])
    local diags = validate("{ silent = true, wrap = true, links = { style = 'wiki' } }")
    eq(#diags, 0)
end

T['unknown_key']['detects typo in modules'] = function()
    child.lua([[ require('mkdnflow').setup({ silent = true }) ]])
    local diags = validate("{ modules = { bibs = true } }")
    eq(#diags, 1)
    eq(diags[1].path, 'modules.bibs')
end

-- =============================================================================
-- Type checking
-- =============================================================================
T['type_check'] = new_set()

T['type_check']['detects wrong type for boolean key'] = function()
    child.lua([[ require('mkdnflow').setup({ silent = true }) ]])
    local diags = validate("{ silent = 'yes' }")
    eq(#diags, 1)
    eq(diags[1].path, 'silent')
    eq(diags[1].message:find('Expected boolean') ~= nil, true)
end

T['type_check']['detects wrong type for nested key'] = function()
    child.lua([[ require('mkdnflow').setup({ silent = true }) ]])
    local diags = validate("{ links = { search_range = 'all' } }")
    eq(#diags, 1)
    eq(diags[1].path, 'links.search_range')
    eq(diags[1].message:find('Expected number') ~= nil, true)
end

T['type_check']['accepts multi-type key: root_marker as string'] = function()
    child.lua([[ require('mkdnflow').setup({ silent = true }) ]])
    local diags = validate("{ path_resolution = { root_marker = '.root' } }")
    eq(#diags, 0)
end

T['type_check']['accepts multi-type key: root_marker as table'] = function()
    child.lua([[ require('mkdnflow').setup({ silent = true }) ]])
    local diags = validate("{ path_resolution = { root_marker = { '.root', 'index.md' } } }")
    eq(#diags, 0)
end

T['type_check']['accepts multi-type key: root_marker as false'] = function()
    child.lua([[ require('mkdnflow').setup({ silent = true }) ]])
    local diags = validate("{ path_resolution = { root_marker = false } }")
    eq(#diags, 0)
end

T['type_check']['false accepted for any key (disable pattern)'] = function()
    child.lua([[ require('mkdnflow').setup({ silent = true }) ]])
    -- wrap default is boolean, but false should always be accepted
    local diags = validate("{ wrap = false }")
    eq(#diags, 0)
end

T['type_check']['accepts function for transform_on_follow'] = function()
    child.lua([[ require('mkdnflow').setup({ silent = true }) ]])
    local diags = validate("{ links = { transform_on_follow = function(s) return s end } }")
    eq(#diags, 0)
end

T['type_check']['rejects string for transform_on_follow'] = function()
    child.lua([[ require('mkdnflow').setup({ silent = true }) ]])
    local diags = validate("{ links = { transform_on_follow = 'lower' } }")
    eq(#diags, 1)
    eq(diags[1].path, 'links.transform_on_follow')
end

T['type_check']['accepts function for transform_on_create'] = function()
    child.lua([[ require('mkdnflow').setup({ silent = true }) ]])
    local diags = validate("{ links = { transform_on_create = function(s) return s end } }")
    eq(#diags, 0)
end

T['type_check']['accepts function for on_create_new'] = function()
    child.lua([[ require('mkdnflow').setup({ silent = true }) ]])
    local diags = validate("{ links = { on_create_new = function() end } }")
    eq(#diags, 0)
end

T['type_check']['accepts boolean for on_create_new'] = function()
    child.lua([[ require('mkdnflow').setup({ silent = true }) ]])
    local diags = validate("{ links = { on_create_new = true } }")
    eq(#diags, 0)
end

-- =============================================================================
-- Enum validation
-- =============================================================================
T['enum'] = new_set()

T['enum']['detects invalid links.style value'] = function()
    child.lua([[ require('mkdnflow').setup({ silent = true }) ]])
    local diags = validate("{ links = { style = 'wikilink' } }")
    eq(#diags, 1)
    eq(diags[1].path, 'links.style')
    eq(diags[1].message:find('Invalid value') ~= nil, true)
    eq(diags[1].message:find('markdown') ~= nil, true)
    eq(diags[1].message:find('wiki') ~= nil, true)
end

T['enum']['accepts valid links.style value'] = function()
    child.lua([[ require('mkdnflow').setup({ silent = true }) ]])
    local diags = validate("{ links = { style = 'wiki' } }")
    eq(#diags, 0)
end

T['enum']['detects invalid path_resolution.primary value'] = function()
    child.lua([[ require('mkdnflow').setup({ silent = true }) ]])
    local diags = validate("{ path_resolution = { primary = 'bogus' } }")
    eq(#diags, 1)
    eq(diags[1].path, 'path_resolution.primary')
end

T['enum']['accepts valid path_resolution.primary values'] = function()
    child.lua([[ require('mkdnflow').setup({ silent = true }) ]])
    for _, val in ipairs({ 'first', 'current', 'root' }) do
        local diags = validate("{ path_resolution = { primary = '" .. val .. "' } }")
        eq(#diags, 0)
    end
end

T['enum']['detects invalid foldtext.object_count_icon_set value'] = function()
    child.lua([[ require('mkdnflow').setup({ silent = true }) ]])
    local diags = validate("{ foldtext = { object_count_icon_set = 'unicode' } }")
    eq(#diags, 1)
    eq(diags[1].path, 'foldtext.object_count_icon_set')
    eq(diags[1].message:find('emoji') ~= nil, true)
end

T['enum']['accepts valid foldtext.object_count_icon_set value'] = function()
    child.lua([[ require('mkdnflow').setup({ silent = true }) ]])
    local diags = validate("{ foldtext = { object_count_icon_set = 'nerdfont' } }")
    eq(#diags, 0)
end

-- =============================================================================
-- Mappings validation
-- =============================================================================
T['mappings'] = new_set()

T['mappings']['detects unknown command name'] = function()
    child.lua([[ require('mkdnflow').setup({ silent = true }) ]])
    local diags = validate("{ mappings = { MkdnBogusCommand = { 'n', '<CR>' } } }")
    local mapping_diags = {}
    for _, d in ipairs(diags) do
        if d.message:find('Unknown command') then
            table.insert(mapping_diags, d)
        end
    end
    eq(#mapping_diags, 1)
    eq(mapping_diags[1].path, 'mappings.MkdnBogusCommand')
end

T['mappings']['detects invalid mapping structure (1-element table)'] = function()
    child.lua([[ require('mkdnflow').setup({ silent = true }) ]])
    local diags = validate("{ mappings = { MkdnGoBack = { 'n' } } }")
    local struct_diags = {}
    for _, d in ipairs(diags) do
        if d.message:find('2 elements') then
            table.insert(struct_diags, d)
        end
    end
    eq(#struct_diags, 1)
end

T['mappings']['detects non-string key binding'] = function()
    child.lua([[ require('mkdnflow').setup({ silent = true }) ]])
    local diags = validate("{ mappings = { MkdnGoBack = { 'n', 123 } } }")
    local binding_diags = {}
    for _, d in ipairs(diags) do
        if d.message:find('Key binding must be a string') then
            table.insert(binding_diags, d)
        end
    end
    eq(#binding_diags, 1)
end

T['mappings']['accepts valid mapping'] = function()
    child.lua([[ require('mkdnflow').setup({ silent = true }) ]])
    local diags = validate("{ mappings = { MkdnGoBack = { 'n', '<BS>' } } }")
    eq(#diags, 0)
end

T['mappings']['accepts false (disabled)'] = function()
    child.lua([[ require('mkdnflow').setup({ silent = true }) ]])
    local diags = validate("{ mappings = { MkdnGoBack = false } }")
    eq(#diags, 0)
end

T['mappings']['accepts multi-mode mapping'] = function()
    child.lua([[ require('mkdnflow').setup({ silent = true }) ]])
    local diags = validate("{ mappings = { MkdnEnter = { { 'n', 'v' }, '<CR>' } } }")
    eq(#diags, 0)
end

T['mappings']['accepts table override for default-false mapping'] = function()
    child.lua([[ require('mkdnflow').setup({ silent = true }) ]])
    -- MkdnTab defaults to false; overriding with a table is valid
    local diags = validate("{ mappings = { MkdnTab = { 'n', '<Tab>' } } }")
    eq(#diags, 0)
end

-- =============================================================================
-- Conflict detection
-- =============================================================================
T['conflicts'] = new_set()

T['conflicts']['detects both deprecated and replacement keys'] = function()
    child.lua([[ require('mkdnflow').setup({ silent = true }) ]])
    child.lua([[
        local validate = require('mkdnflow.validate')
        _G._test_diags = validate.checkConflicts({
            links = { name_is_source = true, compact = false },
        })
    ]])
    local diags = child.lua_get('_G._test_diags')
    eq(#diags, 1)
    eq(diags[1].message:find('deprecated') ~= nil, true)
    eq(diags[1].message:find('replacement') ~= nil, true)
end

T['conflicts']['no conflict when only deprecated key is present'] = function()
    child.lua([[ require('mkdnflow').setup({ silent = true }) ]])
    child.lua([[
        local validate = require('mkdnflow.validate')
        _G._test_diags = validate.checkConflicts({
            links = { name_is_source = true },
        })
    ]])
    local diags = child.lua_get('_G._test_diags')
    eq(#diags, 0)
end

T['conflicts']['no conflict when only replacement key is present'] = function()
    child.lua([[ require('mkdnflow').setup({ silent = true }) ]])
    child.lua([[
        local validate = require('mkdnflow.validate')
        _G._test_diags = validate.checkConflicts({
            links = { compact = false },
        })
    ]])
    local diags = child.lua_get('_G._test_diags')
    eq(#diags, 0)
end

-- =============================================================================
-- Integration: setup() emits warnings
-- =============================================================================
T['integration'] = new_set()

T['integration']['setup emits warning for unknown key'] = function()
    child.lua([[
        _G._notifications = {}
        local orig_notify = vim.notify
        vim.notify = function(msg, level, opts)
            table.insert(_G._notifications, { msg = msg, level = level })
            orig_notify(msg, level, opts)
        end
        require('mkdnflow').setup({
            bogus_key = true,
        })
    ]])
    local has_warning = child.lua_get([[
        (function()
            for _, n in ipairs(_G._notifications) do
                if n.msg:find('bogus_key') and n.msg:find('Unknown') then
                    return true
                end
            end
            return false
        end)()
    ]])
    eq(has_warning, true)
end

T['integration']['setup respects silent for validation warnings'] = function()
    child.lua([[
        _G._notifications = {}
        local orig_notify = vim.notify
        vim.notify = function(msg, level, opts)
            table.insert(_G._notifications, { msg = msg, level = level })
            orig_notify(msg, level, opts)
        end
        require('mkdnflow').setup({
            silent = true,
            bogus_key = true,
        })
    ]])
    local has_validation_warning = child.lua_get([[
        (function()
            for _, n in ipairs(_G._notifications) do
                if n.msg:find('bogus_key') then
                    return true
                end
            end
            return false
        end)()
    ]])
    eq(has_validation_warning, false)
end

T['integration']['validation diagnostics stored on init'] = function()
    child.lua([[
        require('mkdnflow').setup({
            silent = true,
            bogus_key = true,
        })
    ]])
    local count = child.lua_get([[
        #require('mkdnflow').validation_diagnostics
    ]])
    eq(count > 0, true)
end

T['integration']['checkhealth shows validation section'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = { style = 'invalid_style' },
            silent = true,
        })
        vim.cmd('checkhealth mkdnflow')
    ]])
    local text = get_buf_text()
    eq(text:find('config validation') ~= nil, true)
    eq(text:find('invalid_style') ~= nil, true)
end

T['integration']['checkhealth shows OK for valid config'] = function()
    child.lua([[
        require('mkdnflow').setup({
            silent = true,
        })
        vim.cmd('checkhealth mkdnflow')
    ]])
    local text = get_buf_text()
    eq(text:find('config validation') ~= nil, true)
    eq(text:find('No config validation issues found') ~= nil, true)
end

return T
