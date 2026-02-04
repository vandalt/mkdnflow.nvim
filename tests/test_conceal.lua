-- tests/test_conceal.lua
-- Tests for link concealing functionality

local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

-- Helper to check if any match pattern contains a substring
local function has_pattern_containing(matches, substring)
    for _, m in ipairs(matches) do
        if m.pattern and m.pattern:find(substring, 1, true) then
            return true
        end
    end
    return false
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
-- Module loading
-- =============================================================================
T['module'] = new_set()

T['module']['loads without error'] = function()
    child.lua([[require('mkdnflow').setup({ links = { conceal = true }, silent = true })]])
    -- If we got here, the module loaded successfully
    eq(true, true)
end

T['module']['mkdnflow config has conceal enabled'] = function()
    child.lua([[require('mkdnflow').setup({ links = { conceal = true }, silent = true })]])
    local conceal_enabled = child.lua_get('require("mkdnflow").config.modules.conceal')
    eq(conceal_enabled, true)
end

-- =============================================================================
-- Match patterns
-- =============================================================================
T['patterns'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
                -- Clear any existing matches
                vim.fn.clearmatches()
            ]])
        end,
    },
})

T['patterns']['wiki patterns are always added'] = function()
    child.lua([[require('mkdnflow').setup({ links = { conceal = true }, silent = true })]])
    child.cmd('doautocmd BufEnter test.md')

    local matches = child.lua_get('vim.fn.getmatches()')
    -- Wiki patterns contain \[\[ (escaped brackets)
    local has_wiki = has_pattern_containing(matches, '\\[\\[')
    eq(has_wiki, true)
end

T['patterns']['markdown patterns are added when no treesitter'] = function()
    -- In headless test environment, treesitter highlighting is not active
    child.lua([[require('mkdnflow').setup({ links = { conceal = true }, silent = true })]])
    child.cmd('doautocmd BufEnter test.md')

    local matches = child.lua_get('vim.fn.getmatches()')
    -- Markdown inline link patterns contain ([^(] for the URL part
    local has_markdown = has_pattern_containing(matches, '([^(]')
    eq(has_markdown, true)
end

T['patterns']['both wiki and markdown patterns present without treesitter'] = function()
    child.lua([[require('mkdnflow').setup({ links = { conceal = true }, silent = true })]])
    child.cmd('doautocmd BufEnter test.md')

    local matches = child.lua_get('vim.fn.getmatches()')

    -- Should have wiki patterns (contain \[\[)
    local has_wiki = has_pattern_containing(matches, '\\[\\[')
    -- Should have markdown patterns (contain ([^(] for URL)
    local has_markdown = has_pattern_containing(matches, '([^(]')

    eq(has_wiki, true)
    eq(has_markdown, true)
end

T['patterns']['patterns independent of links.style setting'] = function()
    -- Even with wiki style, both pattern types should be added
    child.lua([[require('mkdnflow').setup({
        links = { conceal = true, style = 'wiki' },
        silent = true
    })]])
    child.cmd('doautocmd BufEnter test.md')

    local matches = child.lua_get('vim.fn.getmatches()')

    local has_wiki = has_pattern_containing(matches, '\\[\\[')
    local has_markdown = has_pattern_containing(matches, '([^(]')

    eq(has_wiki, true)
    eq(has_markdown, true)
end

-- =============================================================================
-- Conceal settings
-- =============================================================================
T['settings'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
            ]])
        end,
    },
})

T['settings']['sets conceallevel to 2'] = function()
    child.lua([[require('mkdnflow').setup({ links = { conceal = true }, silent = true })]])
    child.cmd('doautocmd BufEnter test.md')

    local conceallevel = child.lua_get('vim.wo.conceallevel')
    eq(conceallevel, 2)
end

return T
