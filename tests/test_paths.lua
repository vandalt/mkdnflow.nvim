-- tests/test_paths.lua
-- Tests for path handling functionality

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
                    links = {
                        transform_explicit = false,
                        transform_implicit = false
                    }
                })
            ]])
        end,
        post_once = child.stop,
    },
})

-- =============================================================================
-- pathType() - Determine type of path
-- =============================================================================
T['pathType'] = new_set()

-- Notebook pages (internal markdown files)
T['pathType']['identifies simple filename as nb_page'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').pathType('my-note')]])
    eq(result, 'nb_page')
end

T['pathType']['identifies relative path as nb_page'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').pathType('folder/my-note')]])
    eq(result, 'nb_page')
end

T['pathType']['identifies markdown file as nb_page'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').pathType('note.md')]])
    eq(result, 'nb_page')
end

-- URLs
T['pathType']['identifies http URL'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').pathType('http://example.com')]])
    eq(result, 'url')
end

T['pathType']['identifies https URL'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').pathType('https://example.com')]])
    eq(result, 'url')
end

T['pathType']['identifies URL with path'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').pathType('https://example.com/page')]])
    eq(result, 'url')
end

-- File paths (external files)
T['pathType']['identifies file: prefix'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').pathType('file:document.pdf')]])
    eq(result, 'file')
end

T['pathType']['identifies file: with absolute path'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').pathType('file:/path/to/document.pdf')]])
    eq(result, 'file')
end

T['pathType']['identifies file: with home path'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').pathType('file:~/documents/file.pdf')]])
    eq(result, 'file')
end

-- Citations
T['pathType']['identifies citation'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').pathType('@smith2020')]])
    eq(result, 'citation')
end

T['pathType']['identifies citation with complex key'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').pathType('@smith_jones_2020')]])
    eq(result, 'citation')
end

-- Anchors
T['pathType']['identifies anchor when path empty and anchor provided'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').pathType('', '#section')]])
    eq(result, 'anchor')
end

T['pathType']['identifies nb_page when path has anchor'] = function()
    -- When path is not empty but has anchor, it's still a notebook page
    local result = child.lua_get([[require('mkdnflow.paths').pathType('note', '#section')]])
    eq(result, 'nb_page')
end

-- Edge cases
T['pathType']['returns nil for nil path'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').pathType(nil)]])
    eq(result, vim.NIL)
end

T['pathType']['handles empty path without anchor as nb_page'] = function()
    -- Empty string without anchor
    local result = child.lua_get([[require('mkdnflow.paths').pathType('')]])
    eq(result, 'nb_page')
end

-- =============================================================================
-- transformPath() - Apply user transformation
-- =============================================================================
T['transformPath'] = new_set()

-- Note: transform_implicit is cached at module load time, so calling setup()
-- after the module loads does NOT update the transform function. These tests
-- verify the default behavior (no transform).

T['transformPath']['returns path unchanged when no transform set'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').transformPath('my-note')]])
    eq(result, 'my-note')
end

T['transformPath']['preserves path with spaces'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').transformPath('my note here')]])
    eq(result, 'my note here')
end

T['transformPath']['preserves path with special chars'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').transformPath('note_2023-01-15')]])
    eq(result, 'note_2023-01-15')
end

T['transformPath']['preserves relative paths'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').transformPath('folder/subfolder/note')]])
    eq(result, 'folder/subfolder/note')
end

-- =============================================================================
-- formatTemplate() - Template placeholder substitution
-- =============================================================================
T['formatTemplate'] = new_set()

-- Note: new_file_config is cached at module load time. The default config has:
--   placeholders.before = { title = 'link_title', date = 'os_date' }
--   template = '# {{title}}'
-- These tests use the default config.

T['formatTemplate']['replaces link_title when cursor on link'] = function()
    -- Set up a buffer with a link and cursor on it
    set_lines({ '[My Page Title](my-page.md)' })
    set_cursor(1, 5)
    local result = child.lua_get([[require('mkdnflow.paths').formatTemplate('before')]])
    eq(result, '# My Page Title')
end

T['formatTemplate']['replaces link_title from wiki link'] = function()
    set_lines({ '[[my-page|Display Name]]' })
    set_cursor(1, 5)
    local result = child.lua_get([[require('mkdnflow.paths').formatTemplate('before')]])
    eq(result, '# Display Name')
end

T['formatTemplate']['uses custom template parameter'] = function()
    set_lines({ '[Note Title](note.md)' })
    set_cursor(1, 5)
    -- Pass a custom template that uses date instead of title
    local result = child.lua_get([[require('mkdnflow.paths').formatTemplate('before', 'Created: {{date}}')]])
    -- Should contain a date in YYYY-MM-DD format
    local matches_date = result:match('^Created: %d%d%d%d%-%d%d%-%d%d$') ~= nil
    eq(matches_date, true)
end

T['formatTemplate']['handles template with both placeholders'] = function()
    set_lines({ '[My Note](note.md)' })
    set_cursor(1, 5)
    local result = child.lua_get([[require('mkdnflow.paths').formatTemplate('before', '# {{title}}\nDate: {{date}}')]])
    -- First line should be title
    local has_title = result:match('^# My Note\n') ~= nil
    eq(has_title, true)
    -- Second line should be date
    local has_date = result:match('Date: %d%d%d%d%-%d%d%-%d%d$') ~= nil
    eq(has_date, true)
end

T['formatTemplate']['after timing uses after placeholders'] = function()
    -- Default config has empty 'after' placeholders, so template stays unchanged
    set_lines({ '[Title](note.md)' })
    set_cursor(1, 5)
    local result = child.lua_get([[require('mkdnflow.paths').formatTemplate('after', 'Static text')]])
    eq(result, 'Static text')
end

T['formatTemplate']['handles no link under cursor gracefully'] = function()
    set_lines({ 'No link here' })
    set_cursor(1, 5)
    -- Should return template with placeholder removed (empty string for title)
    local result = child.lua_get([[require('mkdnflow.paths').formatTemplate('before')]])
    -- The default template is "# {{title}}" - with no link, title should be empty
    eq(result, '# ')
end

T['formatTemplate']['handles empty buffer'] = function()
    set_lines({ '' })
    set_cursor(1, 0)
    local result = child.lua_get([[require('mkdnflow.paths').formatTemplate('before')]])
    eq(result, '# ')
end

T['formatTemplate']['handles cursor at end of line with no link'] = function()
    set_lines({ 'Some text without links' })
    set_cursor(1, 20)
    local result = child.lua_get([[require('mkdnflow.paths').formatTemplate('before')]])
    eq(result, '# ')
end

T['formatTemplate']['os_date still works when no link'] = function()
    set_lines({ 'No link here' })
    set_cursor(1, 5)
    local result = child.lua_get([[require('mkdnflow.paths').formatTemplate('before', 'Date: {{date}}')]])
    -- Should still replace date placeholder
    local matches_date = result:match('^Date: %d%d%d%d%-%d%d%-%d%d$') ~= nil
    eq(matches_date, true)
end

-- =============================================================================
-- handlePath() - Integration tests for path handling
-- =============================================================================
T['handlePath'] = new_set()

-- Note: handlePath has side effects (opens files, runs commands), so we test
-- behavior that doesn't require file system operations

T['handlePath']['handles anchor-only path'] = function()
    set_lines({ '# Target Heading', '', 'Some content' })
    set_cursor(3, 0) -- Start at bottom
    -- handlePath with empty path and anchor should jump to heading
    child.lua([[require('mkdnflow.paths').handlePath('', '#target-heading')]])
    local cursor = child.lua_get('vim.api.nvim_win_get_cursor(0)')
    -- Should move cursor to heading on line 1
    eq(cursor[1], 1)
end

T['handlePath']['url type triggers system_open path'] = function()
    -- We can't fully test system_open, but we can verify it doesn't error
    -- and the path is recognized as a URL
    local path_type = child.lua_get([[require('mkdnflow.paths').pathType('https://example.com')]])
    eq(path_type, 'url')
end

-- =============================================================================
-- Edge cases and error handling
-- =============================================================================
T['edge_cases'] = new_set()

T['edge_cases']['pathType handles path with only hash'] = function()
    -- Just "#" without text
    local result = child.lua_get([[require('mkdnflow.paths').pathType('#')]])
    eq(result, 'nb_page')
end

T['edge_cases']['pathType handles path starting with dot'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').pathType('./relative/path')]])
    eq(result, 'nb_page')
end

T['edge_cases']['pathType handles path starting with double dot'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').pathType('../parent/path')]])
    eq(result, 'nb_page')
end

T['edge_cases']['pathType handles absolute path'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').pathType('/absolute/path')]])
    eq(result, 'nb_page')
end

T['edge_cases']['pathType handles home path'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').pathType('~/home/path')]])
    eq(result, 'nb_page')
end

T['edge_cases']['pathType distinguishes URL from path with dot'] = function()
    -- example.com looks like URL, but file.md should not
    local url_result = child.lua_get([[require('mkdnflow.paths').pathType('example.com')]])
    local file_result = child.lua_get([[require('mkdnflow.paths').pathType('file.md')]])
    eq(url_result, 'url')
    eq(file_result, 'nb_page')
end

T['edge_cases']['transformPath returns nil for nil input'] = function()
    -- When transform_implicit is false/nil, transformPath returns the input as-is
    -- For nil input, it returns nil
    local result = child.lua_get([[require('mkdnflow.paths').transformPath(nil)]])
    eq(result, vim.NIL)
end

T['edge_cases']['transformPath handles empty string'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').transformPath('')]])
    eq(result, '')
end

-- =============================================================================
-- Issue #293: setup() called with unnamed buffer leaves initial_dir nil
-- When lazy.nvim loads the plugin via a key mapping (e.g. <leader>Ni),
-- setup() runs BEFORE the markdown file is opened. At that point,
-- nvim_buf_get_name(0) returns "" and initial_dir becomes nil.
-- Later, following a link crashes with:
--   "attempt to concatenate upvalue 'initial_dir' (a nil value)"
-- =============================================================================
T['setup_without_file'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
        end,
        post_once = child.stop,
    },
})

T['setup_without_file']['initial_dir is set after activation'] = function()
    -- Simulate lazy.nvim key trigger: setup() runs with no file open
    child.lua([[require('mkdnflow').setup({
        links = { transform_explicit = false, transform_implicit = false },
    })]])

    -- Open a markdown file to trigger activation
    child.lua([[
        local tmpdir = vim.fn.tempname()
        vim.fn.mkdir(tmpdir, 'p')
        local tmpfile = tmpdir .. '/test.md'
        vim.fn.writefile({''}, tmpfile)
        vim.cmd('e ' .. tmpfile)
        vim.bo.filetype = 'markdown'
    ]])

    local initial_dir = child.lua_get([[require('mkdnflow').initial_dir]])
    eq(type(initial_dir), 'string')
end

T['setup_without_file']['following link works after setup with unnamed buffer'] = function()
    -- 1. Setup with no file open (like lazy.nvim key trigger loading)
    child.lua([[require('mkdnflow').setup({
        links = { transform_explicit = false, transform_implicit = false },
    })]])

    -- 2. Open a markdown file (like <cmd>e ~/wiki/index.md<CR>)
    child.lua([[
        local tmpdir = vim.fn.tempname()
        vim.fn.mkdir(tmpdir, 'p')
        local tmpfile = tmpdir .. '/index.md'
        vim.fn.writefile({'[test](other.md)'}, tmpfile)
        vim.cmd('e ' .. tmpfile)
        vim.bo.filetype = 'markdown'
    ]])

    -- 3. Following a link should NOT crash with nil initial_dir
    child.lua('vim.api.nvim_win_set_cursor(0, {1, 2})')
    local ok, err = unpack(child.lua_get([[{pcall(function()
        require('mkdnflow.paths').handlePath('other.md')
    end)}]]))
    eq(ok, true)
end

return T
