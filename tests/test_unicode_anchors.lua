-- tests/test_unicode_anchors.lua
-- Tests for Unicode/Chinese character support in anchor links
-- Issue #221: Support anchor links with Chinese and other special chars

local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

-- Helper to set buffer content
local function set_lines(lines)
    child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, ' .. vim.inspect(lines) .. ')')
end

-- Helper to get cursor position
local function get_cursor()
    return child.lua_get('vim.api.nvim_win_get_cursor(0)')
end

-- Helper to set cursor position (1-indexed row, 0-indexed col)
local function set_cursor(row, col)
    child.lua('vim.api.nvim_win_set_cursor(0, {' .. row .. ', ' .. col .. '})')
end

local T = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
                require('mkdnflow').setup({
                    modules = { links = true, cursor = true },
                    silent = true
                })
            ]])
        end,
        post_once = child.stop,
    },
})

-- =============================================================================
-- formatLink anchor generation with Unicode
-- =============================================================================
T['formatLink_unicode'] = new_set()

-- Test how formatLink converts headings to anchors
T['formatLink_unicode']['ASCII heading converts to lowercase anchor'] = function()
    -- Basic ASCII test to establish baseline
    local result = child.lua_get([[require('mkdnflow.links').formatLink('## Hello World', nil, 2)]])
    eq(result, '#hello-world')
end

T['formatLink_unicode']['Chinese heading anchor generation'] = function()
    -- This is the core issue - Chinese characters should be preserved
    local result =
        child.lua_get([[require('mkdnflow.links').formatLink('## 中文字符集', nil, 2)]])
    -- Current behavior: Chinese chars are stripped, leaving just '#-' or '#'
    -- Expected behavior: Should preserve Chinese chars, e.g., '#中文字符集'
    print('Chinese heading result: ' .. tostring(result))
    -- Document current behavior - this test will show what actually happens
    local has_chinese = result:match('中') ~= nil
    eq(has_chinese, true) -- EXPECTED: should contain Chinese chars
end

T['formatLink_unicode']['mixed ASCII and Chinese heading'] = function()
    local result =
        child.lua_get([[require('mkdnflow.links').formatLink('## Hello 世界', nil, 2)]])
    print('Mixed heading result: ' .. tostring(result))
    -- Should preserve both ASCII and Chinese
    local has_hello = result:match('hello') ~= nil
    local has_chinese = result:match('世界') ~= nil
    eq(has_hello, true)
    eq(has_chinese, true) -- EXPECTED: should contain Chinese chars
end

T['formatLink_unicode']['Japanese heading'] = function()
    local result =
        child.lua_get([[require('mkdnflow.links').formatLink('## こんにちは', nil, 2)]])
    print('Japanese heading result: ' .. tostring(result))
    local has_japanese = result:match('こんにちは') ~= nil
    eq(has_japanese, true) -- EXPECTED: should contain Japanese chars
end

T['formatLink_unicode']['Korean heading'] = function()
    local result =
        child.lua_get([[require('mkdnflow.links').formatLink('## 안녕하세요', nil, 2)]])
    print('Korean heading result: ' .. tostring(result))
    local has_korean = result:match('안녕') ~= nil
    eq(has_korean, true) -- EXPECTED: should contain Korean chars
end

T['formatLink_unicode']['Cyrillic heading'] = function()
    local result =
        child.lua_get([[require('mkdnflow.links').formatLink('## Привет мир', nil, 2)]])
    print('Cyrillic heading result: ' .. tostring(result))
    local has_cyrillic = result:match('привет') ~= nil or result:match('Привет') ~= nil
    eq(has_cyrillic, true) -- EXPECTED: should contain Cyrillic chars
end

-- =============================================================================
-- Anchor link following with Unicode
-- =============================================================================
T['anchor_following'] = new_set()

T['anchor_following']['follows Chinese anchor link'] = function()
    set_lines({
        '## 中文字符集',
        '',
        '[锚点链接](#中文字符集)',
    })
    set_cursor(3, 5) -- On the link

    -- Try to follow the link
    child.lua([[require('mkdnflow.links').followLink()]])

    local cursor = get_cursor()
    -- Should jump to line 1 (the heading)
    eq(cursor[1], 1) -- EXPECTED: cursor should be on line 1
end

T['anchor_following']['follows Japanese anchor link'] = function()
    set_lines({
        '## こんにちは',
        '',
        '[リンク](#こんにちは)',
    })
    set_cursor(3, 5)

    child.lua([[require('mkdnflow.links').followLink()]])

    local cursor = get_cursor()
    eq(cursor[1], 1) -- EXPECTED: cursor should be on line 1
end

T['anchor_following']['follows mixed language anchor link'] = function()
    set_lines({
        '## Hello 世界',
        '',
        '[link](#hello-世界)',
    })
    set_cursor(3, 5)

    child.lua([[require('mkdnflow.links').followLink()]])

    local cursor = get_cursor()
    eq(cursor[1], 1) -- EXPECTED: cursor should be on line 1
end

-- =============================================================================
-- Edge cases
-- =============================================================================
T['edge_cases'] = new_set()

T['edge_cases']['emoji in heading'] = function()
    local result = child.lua_get([[require('mkdnflow.links').formatLink('## 🚀 Rocket', nil, 2)]])
    print('Emoji heading result: ' .. tostring(result))
    -- Emoji might be stripped, but 'rocket' should remain
    local has_rocket = result:match('rocket') ~= nil
    eq(has_rocket, true)
end

T['edge_cases']['special chars in heading'] = function()
    local result = child.lua_get([[require('mkdnflow.links').formatLink("## What's New?", nil, 2)]])
    print('Special chars result: ' .. tostring(result))
    -- Apostrophe and question mark should be stripped
    local has_whats = result:match('whats') ~= nil or result:match("what's") ~= nil
    eq(has_whats, true)
end

T['edge_cases']['numbers in heading preserved'] = function()
    local result = child.lua_get([[require('mkdnflow.links').formatLink('## Chapter 1', nil, 2)]])
    eq(result, '#chapter-1')
end

T['edge_cases']['underscores preserved'] = function()
    local result =
        child.lua_get([[require('mkdnflow.links').formatLink('## my_heading_here', nil, 2)]])
    eq(result, '#my_heading_here')
end

-- =============================================================================
-- Backwards compatibility - legacy anchor links should still work
-- =============================================================================
T['backwards_compat'] = new_set()

-- Emoji headings with legacy (stripped) anchors
T['backwards_compat']['follows legacy anchor for emoji heading'] = function()
    set_lines({
        '## 🚀 Getting Started',
        '',
        '[link](#-getting-started)', -- Legacy: emoji stripped
    })
    set_cursor(3, 5)
    child.lua([[require('mkdnflow.links').followLink()]])
    local cursor = get_cursor()
    eq(cursor[1], 1) -- Should find the heading via legacy fallback
end

-- Emoji headings with new (preserved) anchors
T['backwards_compat']['follows new anchor for emoji heading'] = function()
    set_lines({
        '## 🚀 Getting Started',
        '',
        '[link](#🚀-getting-started)', -- New: emoji preserved
    })
    set_cursor(3, 5)
    child.lua([[require('mkdnflow.links').followLink()]])
    local cursor = get_cursor()
    eq(cursor[1], 1) -- Should find the heading via new method
end

-- Accented characters with legacy (stripped) anchors
T['backwards_compat']['follows legacy anchor for accented heading'] = function()
    set_lines({
        '## Café Culture',
        '',
        '[link](#caf-culture)', -- Legacy: é stripped
    })
    set_cursor(3, 5)
    child.lua([[require('mkdnflow.links').followLink()]])
    local cursor = get_cursor()
    eq(cursor[1], 1) -- Should find the heading via legacy fallback
end

-- Accented characters with new (preserved) anchors
T['backwards_compat']['follows new anchor for accented heading'] = function()
    set_lines({
        '## Café Culture',
        '',
        '[link](#café-culture)', -- New: é preserved
    })
    set_cursor(3, 5)
    child.lua([[require('mkdnflow.links').followLink()]])
    local cursor = get_cursor()
    eq(cursor[1], 1) -- Should find the heading via new method
end

-- Mixed document with both old and new style links
T['backwards_compat']['both old and new links work in same document'] = function()
    set_lines({
        '## 🎉 Celebration',
        '',
        '## Naïve Approach',
        '',
        '[old emoji link](#-celebration)', -- Legacy
        '[new emoji link](#🎉-celebration)', -- New
        '[old accented link](#nave-approach)', -- Legacy
        '[new accented link](#naïve-approach)', -- New
    })

    -- Test old emoji link
    set_cursor(5, 5)
    child.lua([[require('mkdnflow.links').followLink()]])
    eq(get_cursor()[1], 1)

    -- Test new emoji link
    set_cursor(6, 5)
    child.lua([[require('mkdnflow.links').followLink()]])
    eq(get_cursor()[1], 1)

    -- Test old accented link
    set_cursor(7, 5)
    child.lua([[require('mkdnflow.links').followLink()]])
    eq(get_cursor()[1], 3)

    -- Test new accented link
    set_cursor(8, 5)
    child.lua([[require('mkdnflow.links').followLink()]])
    eq(get_cursor()[1], 3)
end

-- Pure CJK - only new style works (no legacy equivalent)
T['backwards_compat']['CJK headings work with new anchors'] = function()
    set_lines({
        '## 日本語タイトル',
        '',
        '[link](#日本語タイトル)',
    })
    set_cursor(3, 5)
    child.lua([[require('mkdnflow.links').followLink()]])
    local cursor = get_cursor()
    eq(cursor[1], 1)
end

-- Edge case: heading with only emoji (legacy anchor would be empty/just hyphen)
T['backwards_compat']['emoji-only heading with legacy anchor'] = function()
    set_lines({
        '## 🎯',
        '',
        '[link](#)', -- Legacy: would be empty or just #
    })
    set_cursor(3, 5)
    child.lua([[require('mkdnflow.links').followLink()]])
    local cursor = get_cursor()
    eq(cursor[1], 1) -- Should still find it via legacy fallback
end

return T
