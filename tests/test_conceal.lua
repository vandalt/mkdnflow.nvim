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
    child.cmd('doautocmd FileType')

    local matches = child.lua_get('vim.fn.getmatches()')
    -- Wiki patterns contain \[\[ (escaped brackets)
    local has_wiki = has_pattern_containing(matches, '\\[\\[')
    eq(has_wiki, true)
end

T['patterns']['markdown patterns are added when no treesitter'] = function()
    -- In headless test environment, treesitter highlighting is not active
    child.lua([[require('mkdnflow').setup({ links = { conceal = true }, silent = true })]])
    child.cmd('doautocmd FileType')

    local matches = child.lua_get('vim.fn.getmatches()')
    -- Markdown inline link patterns contain ([^(] for the URL part
    local has_markdown = has_pattern_containing(matches, '([^(]')
    eq(has_markdown, true)
end

T['patterns']['both wiki and markdown patterns present without treesitter'] = function()
    child.lua([[require('mkdnflow').setup({ links = { conceal = true }, silent = true })]])
    child.cmd('doautocmd FileType')

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
    child.cmd('doautocmd FileType')

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
    child.cmd('doautocmd FileType')

    local conceallevel = child.lua_get('vim.wo.conceallevel')
    eq(conceallevel, 2)
end

T['settings']['sets Conceal highlight to transparent'] = function()
    child.lua([[require('mkdnflow').setup({ links = { conceal = true }, silent = true })]])
    child.cmd('doautocmd FileType')

    local hl = child.lua_get([[vim.api.nvim_get_hl(0, { name = 'Conceal' })]])
    -- Conceal highlight should have no fg/bg (transparent), meaning the
    -- concealed characters are invisible rather than shown in a highlight color
    eq(hl.fg, nil)
    eq(hl.bg, nil)
end

-- =============================================================================
-- Screenshot tests for visual concealing verification
-- =============================================================================
T['screenshot'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            -- Set consistent window size for reproducible screenshots
            child.o.lines = 8
            child.o.columns = 40
            child.lua([[
                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
            ]])
        end,
    },
})

-- Helper to set up concealing and position cursor
local function setup_conceal_test(lines)
    child.lua([[require('mkdnflow').setup({ links = { conceal = true }, silent = true })]])
    child.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    child.cmd('doautocmd FileType')
    -- Move cursor to last line so other lines are concealed
    child.api.nvim_win_set_cursor(0, { #lines, 0 })
end

-- Screenshot options: ignore_attr because highlight groups differ between environments
local screenshot_opts = { ignore_attr = true }

T['screenshot']['wiki_link_simple'] = function()
    -- [[target]] should display as: target
    setup_conceal_test({ '[[wiki target]]', '', 'cursor here' })
    MiniTest.expect.reference_screenshot(child.get_screenshot(), nil, screenshot_opts)
end

T['screenshot']['wiki_link_with_alias'] = function()
    -- [[target|alias]] should display as: alias
    setup_conceal_test({ '[[hidden target|visible alias]]', '', 'cursor here' })
    MiniTest.expect.reference_screenshot(child.get_screenshot(), nil, screenshot_opts)
end

T['screenshot']['markdown_inline_link'] = function()
    -- [text](url) should display as: text
    setup_conceal_test({ '[click here](https://example.com)', '', 'cursor here' })
    MiniTest.expect.reference_screenshot(child.get_screenshot(), nil, screenshot_opts)
end

T['screenshot']['markdown_reference_link'] = function()
    -- [text][ref] should display as: text
    setup_conceal_test({ '[link text][ref1]', '', '[ref1]: https://example.com', '', 'cursor here' })
    MiniTest.expect.reference_screenshot(child.get_screenshot(), nil, screenshot_opts)
end

T['screenshot']['mixed_links'] = function()
    -- All link types together - use larger window to fit all content
    child.o.lines = 12
    setup_conceal_test({
        '[[wiki link]]',
        '[[target|alias]]',
        '[markdown](url)',
        '[ref link][r1]',
        '',
        '[r1]: https://example.com',
        '',
        'cursor here',
    })
    MiniTest.expect.reference_screenshot(child.get_screenshot(), nil, screenshot_opts)
end

-- =============================================================================
-- Treesitter detection
-- =============================================================================
T['treesitter'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
                vim.fn.clearmatches()
            ]])
        end,
    },
})

T['treesitter']['skips markdown patterns when ts active'] = function()
    -- Mock treesitter as active by patching the detection function after setup
    child.lua([[
        -- First, load the conceal module to get the autocmd registered
        require('mkdnflow').setup({ links = { conceal = true }, silent = true })

        -- Clear any matches from the initial load
        vim.fn.clearmatches()

        -- Now mock the treesitter highlighter to appear active
        local hl = require('vim.treesitter.highlighter')
        hl.active[vim.api.nvim_get_current_buf()] = true
    ]])

    -- Trigger the autocmd again with mocked treesitter
    child.cmd('doautocmd FileType')

    local matches = child.lua_get('vim.fn.getmatches()')

    -- Should have wiki patterns (contain \[\[)
    local has_wiki = has_pattern_containing(matches, '\\[\\[')
    -- Should NOT have markdown patterns when treesitter is active
    local has_markdown = has_pattern_containing(matches, '([^(]')

    eq(has_wiki, true)
    eq(has_markdown, false)
end

return T
