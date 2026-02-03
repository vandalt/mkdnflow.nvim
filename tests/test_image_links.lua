-- tests/test_image_links.lua
-- Tests for image link handling
-- Issue #220: Handle bang (`!`) properly in image links

local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

-- Helper to set buffer content
local function set_lines(lines)
    child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, ' .. vim.inspect(lines) .. ')')
end

-- Helper to get buffer content
local function get_lines()
    return child.lua_get('vim.api.nvim_buf_get_lines(0, 0, -1, false)')
end

-- Helper to get a specific line
local function get_line(n)
    return child.lua_get('vim.api.nvim_buf_get_lines(0, ' .. (n - 1) .. ', ' .. n .. ', false)[1]')
end

-- Helper to set cursor position (1-indexed row, 0-indexed col)
local function set_cursor(row, col)
    child.lua('vim.api.nvim_win_set_cursor(0, {' .. row .. ', ' .. col .. '})')
end

-- Helper to get cursor position
local function get_cursor()
    return child.lua_get('vim.api.nvim_win_get_cursor(0)')
end

local T = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
                require('mkdnflow').setup({
                    modules = { links = true },
                    links = { transform_explicit = false },
                    silent = true
                })
            ]])
        end,
        post_once = child.stop,
    },
})

-- =============================================================================
-- Image link detection - getLinkUnderCursor()
-- =============================================================================
T['image_link_detection'] = new_set()

-- Test: cursor on the alt text of image link (inside brackets)
T['image_link_detection']['finds link when cursor on alt text'] = function()
    set_lines({ '![alt text](image.png)' })
    set_cursor(1, 5) -- On 'alt text'
    local result = child.lua_get([[require('mkdnflow.links').getLinkUnderCursor()]])
    -- Currently recognizes this as a link (just the [alt text](image.png) part)
    eq(result ~= vim.NIL, true)
end

-- Test: cursor on the path of image link (inside parentheses)
T['image_link_detection']['finds link when cursor on image path'] = function()
    set_lines({ '![alt text](image.png)' })
    set_cursor(1, 15) -- On 'image.png'
    local result = child.lua_get([[require('mkdnflow.links').getLinkUnderCursor()]])
    eq(result ~= vim.NIL, true)
end

-- Test: cursor on the `!` prefix
T['image_link_detection']['finds link when cursor on bang prefix'] = function()
    set_lines({ '![alt text](image.png)' })
    set_cursor(1, 0) -- On '!'
    local result = child.lua_get([[require('mkdnflow.links').getLinkUnderCursor()]])
    eq(result ~= vim.NIL, true) -- Link should be found
    eq(result.type, 'image_link') -- Should be detected as image_link type
end

-- =============================================================================
-- Image link vs regular link distinction
-- =============================================================================
T['image_vs_regular'] = new_set()

-- Test that we can distinguish image links from regular links
T['image_vs_regular']['regular link is detected'] = function()
    set_lines({ '[regular link](page.md)' })
    set_cursor(1, 5)
    local result = child.lua_get([[require('mkdnflow.links').getLinkUnderCursor()]])
    eq(result ~= vim.NIL, true)
    -- Check it's detected as md_link
    eq(result.type, 'md_link')
end

-- Image links should have their own type
T['image_vs_regular']['image link detected as image_link type'] = function()
    set_lines({ '![image](pic.png)' })
    set_cursor(1, 5) -- On 'image'
    local result = child.lua_get([[require('mkdnflow.links').getLinkUnderCursor()]])
    eq(result ~= vim.NIL, true)
    eq(result.type, 'image_link') -- Should be detected as image_link type
end

-- =============================================================================
-- createLink behavior with image syntax
-- =============================================================================
T['createLink_with_bang'] = new_set()

-- The original issue: pressing Enter on `!` before an image should not create a new link
T['createLink_with_bang']['does not create link when cursor on existing image link'] = function()
    set_lines({ '![existing](image.png)' })
    set_cursor(1, 0) -- On '!'

    -- Try to create a link - should not modify if link already exists
    child.lua([[require('mkdnflow.links').createLink()]])

    local result = get_line(1)
    -- Line should remain unchanged - no new link created
    eq(result, '![existing](image.png)')
end

-- =============================================================================
-- followLink behavior with images
-- =============================================================================
T['followLink'] = new_set()

-- Following an image link should open it (system_open for non-md files)
-- We can't fully test system_open, but we can verify the path is extracted correctly
T['followLink']['extracts correct path from image link'] = function()
    set_lines({ '![screenshot](./images/screenshot.png)' })
    set_cursor(1, 10) -- On 'screenshot' in alt text

    local link = child.lua_get([[require('mkdnflow.links').getLinkUnderCursor()]])
    eq(link ~= vim.NIL, true)

    -- Extract the source part
    local source = child.lua_get([[require('mkdnflow.links').getLinkPart(
        require('mkdnflow.links').getLinkUnderCursor(), 'source')]])
    eq(source, './images/screenshot.png')
end

-- Test that image links get 'image' path type for system_open routing
T['followLink']['image link gets image path type'] = function()
    set_lines({ '![screenshot](./images/screenshot.png)' })
    set_cursor(1, 10)

    -- Get the link and verify it's an image_link type
    local link = child.lua_get([[require('mkdnflow.links').getLinkUnderCursor()]])
    eq(link ~= vim.NIL, true)
    eq(link.type, 'image_link')

    -- Extract source using getLinkPart
    local source = child.lua_get([[require('mkdnflow.links').getLinkPart(
        require('mkdnflow.links').getLinkUnderCursor(), 'source')]])
    eq(source, './images/screenshot.png')

    -- Verify pathType returns 'image' for image_link type
    local path_type = child.lua_get(
        "require('mkdnflow.paths').pathType('./images/screenshot.png', nil, 'image_link')"
    )
    eq(path_type, 'image')
end

T['followLink']['extracts correct alt text from image link'] = function()
    set_lines({ '![My Screenshot](./images/screenshot.png)' })
    set_cursor(1, 10)

    local name = child.lua_get([[require('mkdnflow.links').getLinkPart(
        require('mkdnflow.links').getLinkUnderCursor(), 'name')]])
    eq(name, 'My Screenshot')
end

-- =============================================================================
-- Edge cases
-- =============================================================================
T['edge_cases'] = new_set()

-- Multiple images on one line
T['edge_cases']['handles multiple images on line'] = function()
    set_lines({ '![first](a.png) and ![second](b.png)' })

    -- Cursor on first image
    set_cursor(1, 5)
    local first = child.lua_get([[require('mkdnflow.links').getLinkPart(
        require('mkdnflow.links').getLinkUnderCursor(), 'source')]])
    eq(first, 'a.png')

    -- Cursor on second image
    set_cursor(1, 25)
    local second = child.lua_get([[require('mkdnflow.links').getLinkPart(
        require('mkdnflow.links').getLinkUnderCursor(), 'source')]])
    eq(second, 'b.png')
end

-- Image with empty alt text
T['edge_cases']['handles empty alt text'] = function()
    set_lines({ '![](image.png)' })
    set_cursor(1, 5)
    local source = child.lua_get([[require('mkdnflow.links').getLinkPart(
        require('mkdnflow.links').getLinkUnderCursor(), 'source')]])
    eq(source, 'image.png')
end

-- Image link mixed with regular links
T['edge_cases']['distinguishes image from adjacent regular link'] = function()
    set_lines({ '![img](pic.png) [text](page.md)' })

    -- Cursor on image
    set_cursor(1, 5)
    local img_source = child.lua_get([[require('mkdnflow.links').getLinkPart(
        require('mkdnflow.links').getLinkUnderCursor(), 'source')]])
    eq(img_source, 'pic.png')

    -- Cursor on regular link
    set_cursor(1, 20)
    local link_source = child.lua_get([[require('mkdnflow.links').getLinkPart(
        require('mkdnflow.links').getLinkUnderCursor(), 'source')]])
    eq(link_source, 'page.md')
end

-- Nested brackets in alt text (edge case)
T['edge_cases']['handles special chars in alt text'] = function()
    set_lines({ '![alt with [brackets]](image.png)' })
    set_cursor(1, 10)
    local link = child.lua_get([[require('mkdnflow.links').getLinkUnderCursor()]])
    -- This might not work perfectly due to bracket matching
    -- Document current behavior
    eq(link ~= vim.NIL, true)
end

-- =============================================================================
-- destroyLink behavior with images
-- =============================================================================
T['destroyLink'] = new_set()

T['destroyLink']['removes image link syntax, keeps alt text'] = function()
    set_lines({ '![alt text](image.png)' })
    set_cursor(1, 5) -- On alt text
    child.lua([[require('mkdnflow.links').destroyLink()]])
    local result = get_line(1)
    eq(result, 'alt text')
end

T['destroyLink']['works when cursor on bang prefix'] = function()
    set_lines({ '![screenshot](pic.png)' })
    set_cursor(1, 0) -- On '!'
    child.lua([[require('mkdnflow.links').destroyLink()]])
    local result = get_line(1)
    eq(result, 'screenshot')
end

T['destroyLink']['works when cursor on image path'] = function()
    set_lines({ '![photo](vacation.jpg)' })
    set_cursor(1, 12) -- On path
    child.lua([[require('mkdnflow.links').destroyLink()]])
    local result = get_line(1)
    eq(result, 'photo')
end

T['destroyLink']['preserves surrounding text with image'] = function()
    set_lines({ 'See ![diagram](fig.png) for details' })
    set_cursor(1, 8)
    child.lua([[require('mkdnflow.links').destroyLink()]])
    local result = get_line(1)
    eq(result, 'See diagram for details')
end

-- =============================================================================
-- Regression tests - verify regular links still work
-- =============================================================================
T['regression'] = new_set()

T['regression']['regular link detection still works'] = function()
    set_lines({ '[regular link](page.md)' })
    set_cursor(1, 5)
    local link = child.lua_get([[require('mkdnflow.links').getLinkUnderCursor()]])
    eq(link ~= vim.NIL, true)
    eq(link.type, 'md_link') -- Should still be md_link type, not image_link
end

T['regression']['regular link source extraction works'] = function()
    set_lines({ '[text](target.md)' })
    set_cursor(1, 5)
    local source = child.lua_get([[require('mkdnflow.links').getLinkPart(
        require('mkdnflow.links').getLinkUnderCursor(), 'source')]])
    eq(source, 'target.md')
end

T['regression']['regular link name extraction works'] = function()
    set_lines({ '[Link Name](file.md)' })
    set_cursor(1, 5)
    local name = child.lua_get([[require('mkdnflow.links').getLinkPart(
        require('mkdnflow.links').getLinkUnderCursor(), 'name')]])
    eq(name, 'Link Name')
end

T['regression']['createLink still works on plain text'] = function()
    set_lines({ 'plain word here' })
    set_cursor(1, 6) -- On 'word'
    child.lua([[require('mkdnflow.links').createLink()]])
    local result = get_line(1)
    -- Should create a link around 'word'
    eq(result:match('%[word%]') ~= nil, true)
end

T['regression']['destroyLink still works on regular links'] = function()
    set_lines({ '[link text](path.md)' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.links').destroyLink()]])
    local result = get_line(1)
    eq(result, 'link text')
end

T['regression']['adjacent image and regular links both detected correctly'] = function()
    set_lines({ '![img](a.png) [link](b.md)' })

    -- Check image link type
    set_cursor(1, 3)
    local img_link = child.lua_get([[require('mkdnflow.links').getLinkUnderCursor()]])
    eq(img_link.type, 'image_link')

    -- Check regular link type
    set_cursor(1, 18)
    local reg_link = child.lua_get([[require('mkdnflow.links').getLinkUnderCursor()]])
    eq(reg_link.type, 'md_link')
end

return T
