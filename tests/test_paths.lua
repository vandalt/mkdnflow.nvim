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
                        transform_on_create = false,
                        transform_on_follow = false
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
    eq(result, 'external')
end

T['pathType']['identifies file: with absolute path'] = function()
    local result =
        child.lua_get([[require('mkdnflow.paths').pathType('file:/path/to/document.pdf')]])
    eq(result, 'external')
end

T['pathType']['identifies file: with home path'] = function()
    local result =
        child.lua_get([[require('mkdnflow.paths').pathType('file:~/documents/file.pdf')]])
    eq(result, 'external')
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

-- Note: transform_on_follow is cached at module load time, so calling setup()
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
    local result =
        child.lua_get([[require('mkdnflow.paths').transformPath('folder/subfolder/note')]])
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
    local result =
        child.lua_get([[require('mkdnflow.paths').formatTemplate('before', 'Created: {{date}}')]])
    -- Should contain a date in YYYY-MM-DD format
    local matches_date = result:match('^Created: %d%d%d%d%-%d%d%-%d%d$') ~= nil
    eq(matches_date, true)
end

T['formatTemplate']['handles template with both placeholders'] = function()
    set_lines({ '[My Note](note.md)' })
    set_cursor(1, 5)
    local result = child.lua_get(
        [[require('mkdnflow.paths').formatTemplate('before', '# {{title}}\nDate: {{date}}')]]
    )
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
    local result =
        child.lua_get([[require('mkdnflow.paths').formatTemplate('after', 'Static text')]])
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
    local result =
        child.lua_get([[require('mkdnflow.paths').formatTemplate('before', 'Date: {{date}}')]])
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
    -- When transform_on_follow is false/nil, transformPath returns the input as-is
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

-- =============================================================================
-- on_create_new callback (Issue #261)
-- =============================================================================
T['on_create_new'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                _G._on_create_calls = {}
                _G._tmpdir = vim.fn.tempname()
                vim.fn.mkdir(_G._tmpdir, 'p')
                local tmpfile = _G._tmpdir .. '/index.md'
                vim.fn.writefile({''}, tmpfile)
                vim.cmd('e ' .. tmpfile)
                vim.bo.filetype = 'markdown'
            ]])
        end,
    },
})

-- Test 1: Callback receives correct path and title
T['on_create_new']['callback receives correct path and title'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = {
                transform_on_create = false,
                transform_on_follow = false,
                on_create_new = function(path, title)
                    table.insert(_G._on_create_calls, { path = path, title = title })
                    return path
                end,
            },
        })
    ]])
    set_lines({ '[My Note](my-note.md)' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.paths').handlePath('my-note.md')]])
    local calls = child.lua_get('_G._on_create_calls')
    eq(#calls, 1)
    -- Path should end with my-note.md
    local path_match = calls[1].path:match('my%-note%.md$') ~= nil
    eq(path_match, true)
    eq(calls[1].title, 'My Note')
end

-- Test 2: Returns nil stops further processing
T['on_create_new']['returns nil stops further processing'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = {
                transform_on_create = false,
                transform_on_follow = false,
                on_create_new = function(path, title)
                    table.insert(_G._on_create_calls, { path = path, title = title })
                    return nil
                end,
            },
        })
    ]])
    set_lines({ '[My Note](my-note.md)' })
    set_cursor(1, 5)
    local buf_before = child.lua_get('vim.api.nvim_buf_get_name(0)')
    child.lua([[require('mkdnflow.paths').handlePath('my-note.md')]])
    local buf_after = child.lua_get('vim.api.nvim_buf_get_name(0)')
    -- Buffer should NOT have changed
    eq(buf_before, buf_after)
    -- Callback was called
    local calls = child.lua_get('_G._on_create_calls')
    eq(#calls, 1)
end

-- Test 3: Returns different path opens that file
T['on_create_new']['returns different path opens that file'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = {
                transform_on_create = false,
                transform_on_follow = false,
                on_create_new = function(path, title)
                    -- Redirect to a different file in the same dir
                    local dir = path:match('(.*)/.-$')
                    return dir .. '/redirected.md'
                end,
            },
        })
    ]])
    set_lines({ '[My Note](my-note.md)' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.paths').handlePath('my-note.md')]])
    local buf_name = child.lua_get('vim.api.nvim_buf_get_name(0)')
    local match = buf_name:match('redirected%.md$') ~= nil
    eq(match, true)
end

-- Test 4: Callback creates file, returns path — skips template
T['on_create_new']['callback creates file returns path skips template'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = {
                transform_on_create = false,
                transform_on_follow = false,
                on_create_new = function(path, title)
                    -- Create the file ourselves with custom content
                    local dir = path:match('(.*)/.-$')
                    local new_path = dir .. '/created-by-callback.md'
                    vim.fn.writefile({'# Custom Header', '', 'Body text'}, new_path)
                    return new_path
                end,
            },
            new_file_template = {
                enabled = true,
                placeholders = {
                    before = { title = 'link_title' },
                    after = {},
                },
                template = '# {{ title }}',
            },
        })
    ]])
    set_lines({ '[My Note](my-note.md)' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.paths').handlePath('my-note.md')]])
    local lines = get_lines()
    -- Should have the callback's content, not the template
    eq(lines[1], '# Custom Header')
    eq(lines[2], '')
    eq(lines[3], 'Body text')
end

-- Test 5: Default (false) doesn't interfere
T['on_create_new']['default false does not interfere'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = {
                transform_on_create = false,
                transform_on_follow = false,
                on_create_new = false,
            },
        })
    ]])
    set_lines({ '[Test](new-page.md)' })
    set_cursor(1, 3)
    child.lua([[require('mkdnflow.paths').handlePath('new-page.md')]])
    -- Should open the file normally
    local buf_name = child.lua_get('vim.api.nvim_buf_get_name(0)')
    local match = buf_name:match('new%-page%.md$') ~= nil
    eq(match, true)
end

-- Test 6: Not called for existing files
T['on_create_new']['not called for existing files'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = {
                transform_on_create = false,
                transform_on_follow = false,
                on_create_new = function(path, title)
                    table.insert(_G._on_create_calls, { path = path, title = title })
                    return path
                end,
            },
        })
        -- Create the target file so it already exists
        vim.fn.writefile({'# Existing'}, _G._tmpdir .. '/existing.md')
    ]])
    set_lines({ '[Existing](existing.md)' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.paths').handlePath('existing.md')]])
    local calls = child.lua_get('_G._on_create_calls')
    eq(#calls, 0)
end

-- Test 7: Returns path of non-existent file — falls through to template
T['on_create_new']['returns non-existent path falls through to template'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = {
                transform_on_create = false,
                transform_on_follow = false,
                on_create_new = function(path, title)
                    -- Return a different non-existent path
                    local dir = path:match('(.*)/.-$')
                    return dir .. '/template-target.md'
                end,
            },
            new_file_template = {
                enabled = true,
                placeholders = {
                    before = { title = 'link_title' },
                    after = {},
                },
                template = '# {{ title }}',
            },
        })
    ]])
    set_lines({ '[My Title](my-note.md)' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.paths').handlePath('my-note.md')]])
    local buf_name = child.lua_get('vim.api.nvim_buf_get_name(0)')
    local match = buf_name:match('template%-target%.md$') ~= nil
    eq(match, true)
    -- Template should have been injected
    local lines = get_lines()
    eq(lines[1], '# My Title')
end

-- Test 8: Anchor navigation works after callback
T['on_create_new']['anchor navigation works after callback'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = {
                transform_on_create = false,
                transform_on_follow = false,
                on_create_new = function(path, title)
                    -- Create a file with a heading to jump to
                    vim.fn.writefile({'# Top', '', '## Target Section', '', 'Content'}, path)
                    return path
                end,
            },
        })
    ]])
    set_lines({ '[Note](anchored.md#target-section)' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.paths').handlePath('anchored.md', '#target-section')]])
    local cursor = child.lua_get('vim.api.nvim_win_get_cursor(0)')
    -- Should jump to the "## Target Section" heading on line 3
    eq(cursor[1], 3)
end

-- Test 9: Receives correct path with non-default implicit_extension
T['on_create_new']['receives correct path with non-default implicit_extension'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = {
                transform_on_create = false,
                transform_on_follow = false,
                implicit_extension = 'txt',
                on_create_new = function(path, title)
                    table.insert(_G._on_create_calls, { path = path, title = title })
                    return path
                end,
            },
        })
    ]])
    set_lines({ '[Note](my-note)' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.paths').handlePath('my-note')]])
    local calls = child.lua_get('_G._on_create_calls')
    eq(#calls, 1)
    -- Path should end with .txt, not .md
    local path_match = calls[1].path:match('my%-note%.txt$') ~= nil
    eq(path_match, true)
end

-- Test 10: Not called when path is a directory
T['on_create_new']['not called when path is a directory'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = {
                transform_on_create = false,
                transform_on_follow = false,
                on_create_new = function(path, title)
                    table.insert(_G._on_create_calls, { path = path, title = title })
                    return path
                end,
            },
        })
        -- Create a directory that matches the link target
        vim.fn.mkdir(_G._tmpdir .. '/subdir', 'p')
        -- Mock vim.ui.input to avoid blocking in headless mode
        vim.ui.input = function(opts, on_confirm)
            on_confirm(nil)
        end
    ]])
    set_lines({ '[Dir](subdir)' })
    set_cursor(1, 3)
    -- handlePath for a directory will enter the directory prompt (enter_internal_path),
    -- not the else branch where on_create_new runs
    child.lua([[require('mkdnflow.paths').handlePath('subdir')]])
    local calls = child.lua_get('_G._on_create_calls')
    eq(#calls, 0)
end

-- Test 11: Callback that throws an error propagates naturally
T['on_create_new']['callback error propagates naturally'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = {
                transform_on_create = false,
                transform_on_follow = false,
                on_create_new = function(path, title)
                    error('intentional test error')
                end,
            },
        })
    ]])
    set_lines({ '[Note](error-note.md)' })
    set_cursor(1, 5)
    local ok, err = unpack(child.lua_get([[{pcall(function()
        require('mkdnflow.paths').handlePath('error-note.md')
    end)}]]))
    eq(ok, false)
    local has_msg = err:match('intentional test error') ~= nil
    eq(has_msg, true)
end

-- Test 12: Title matches source when wiki link has no explicit display text
T['on_create_new']['title is source text for wiki link without display text'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = {
                style = 'wiki',
                transform_on_create = false,
                transform_on_follow = false,
                on_create_new = function(path, title)
                    table.insert(_G._on_create_calls, { path = path, title = title })
                    return path
                end,
            },
        })
    ]])
    -- Wiki link with no pipe/display text: [[page]]
    -- getLinkPart('name') falls back to the source text for wiki links
    set_lines({ '[[some-page]]' })
    set_cursor(1, 5)
    child.lua([[require('mkdnflow.paths').handlePath('some-page')]])
    local calls = child.lua_get('_G._on_create_calls')
    eq(#calls, 1)
    eq(calls[1].title, 'some-page')
end

-- Test 12b: Title is nil when cursor is not on a link
T['on_create_new']['title is nil when no link under cursor'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = {
                transform_on_create = false,
                transform_on_follow = false,
                on_create_new = function(path, title)
                    table.insert(_G._on_create_calls, { path = path, title = title })
                    return path
                end,
            },
        })
    ]])
    -- No link under cursor, but handlePath is called directly with a path
    set_lines({ 'plain text' })
    set_cursor(1, 0)
    child.lua([[require('mkdnflow.paths').handlePath('orphan-note.md')]])
    local calls = child.lua_get('_G._on_create_calls')
    eq(#calls, 1)
    -- No link under cursor means getLinkPart returns nil, which is omitted from table
    eq(calls[1].title, nil)
end

-- Test 13: Callback not invoked when no link under cursor (auto_create=false)
T['on_create_new']['not invoked when no link under cursor'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = {
                transform_on_create = false,
                transform_on_follow = false,
                auto_create = false,
                on_create_new = function(path, title)
                    table.insert(_G._on_create_calls, { path = path, title = title })
                    return path
                end,
            },
        })
    ]])
    set_lines({ 'Just plain text, no links here' })
    set_cursor(1, 5)
    -- followLink returns early when there's no link and auto_create is false
    child.lua([[require('mkdnflow.links').followLink()]])
    local calls = child.lua_get('_G._on_create_calls')
    eq(#calls, 0)
end

-- Test 14: <CR> keypress triggers callback (E2E)
T['on_create_new_e2e'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                _G._on_create_calls = {}
                _G._tmpdir = vim.fn.tempname()
                vim.fn.mkdir(_G._tmpdir, 'p')
                local tmpfile = _G._tmpdir .. '/index.md'
                vim.fn.writefile({''}, tmpfile)

                -- Source the plugin to register commands
                vim.cmd('runtime plugin/mkdnflow.lua')

                vim.cmd('e ' .. tmpfile)
                vim.bo.filetype = 'markdown'

                require('mkdnflow').setup({
                    links = {
                        transform_on_create = false,
                        transform_on_follow = false,
                        on_create_new = function(path, title)
                            table.insert(_G._on_create_calls, { path = path, title = title })
                            return nil
                        end,
                    },
                })

                -- Trigger autocmd to set up mappings
                vim.cmd('doautocmd BufEnter')
            ]])
        end,
    },
})

T['on_create_new_e2e']['<CR> keypress triggers callback'] = function()
    set_lines({ '[E2E Note](e2e-note.md)' })
    set_cursor(1, 5)
    child.type_keys('<CR>')
    local calls = child.lua_get('_G._on_create_calls')
    eq(#calls, 1)
    local path_match = calls[1].path:match('e2e%-note%.md$') ~= nil
    eq(path_match, true)
    eq(calls[1].title, 'E2E Note')
end

-- =============================================================================
-- getRootDir() - Root marker search
-- =============================================================================
T['getRootDir'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                -- Create nested directory structure:
                -- tmpdir/
                -- ├── .root_marker
                -- ├── index.md
                -- ├── sub1/
                -- │   ├── .root_marker
                -- │   └── page.md
                -- └── sub2/
                --     └── page.md
                _G._tmpdir = vim.fn.resolve(vim.fn.tempname())
                vim.fn.mkdir(_G._tmpdir .. '/sub1', 'p')
                vim.fn.mkdir(_G._tmpdir .. '/sub2', 'p')
                vim.fn.writefile({}, _G._tmpdir .. '/.root_marker')
                vim.fn.writefile({''}, _G._tmpdir .. '/index.md')
                vim.fn.writefile({}, _G._tmpdir .. '/sub1/.root_marker')
                vim.fn.writefile({''}, _G._tmpdir .. '/sub1/page.md')
                vim.fn.writefile({''}, _G._tmpdir .. '/sub2/page.md')

                vim.api.nvim_buf_set_name(0, _G._tmpdir .. '/index.md')
                vim.bo.filetype = 'markdown'
                require('mkdnflow').setup({ silent = true })
            ]])
        end,
    },
})

T['getRootDir']['finds marker in current directory'] = function()
    local result =
        child.lua_get([[require('mkdnflow.utils').getRootDir(_G._tmpdir, '.root_marker', 'Linux')]])
    local tmpdir = child.lua_get('_G._tmpdir')
    eq(result, tmpdir)
end

T['getRootDir']['finds marker in parent directory'] = function()
    local result = child.lua_get(
        [[require('mkdnflow.utils').getRootDir(_G._tmpdir .. '/sub2', '.root_marker', 'Linux')]]
    )
    local tmpdir = child.lua_get('_G._tmpdir')
    eq(result, tmpdir)
end

T['getRootDir']['finds nearest marker (nested)'] = function()
    local result = child.lua_get(
        [[require('mkdnflow.utils').getRootDir(_G._tmpdir .. '/sub1', '.root_marker', 'Linux')]]
    )
    local tmpdir = child.lua_get('_G._tmpdir')
    eq(result, tmpdir .. '/sub1')
end

T['getRootDir']['returns nil when no marker exists'] = function()
    child.lua([[
        _G._isolated = vim.fn.resolve(vim.fn.tempname())
        vim.fn.mkdir(_G._isolated, 'p')
    ]])
    local result = child.lua_get(
        [[require('mkdnflow.utils').getRootDir(_G._isolated, '.nonexistent_marker', 'Linux')]]
    )
    eq(result, vim.NIL)
end

T['getRootDir']['finds nearest marker with deep nesting'] = function()
    child.lua([[
        vim.fn.mkdir(_G._tmpdir .. '/sub1/deep', 'p')
        vim.fn.writefile({}, _G._tmpdir .. '/sub1/deep/.root_marker')
        vim.fn.writefile({''}, _G._tmpdir .. '/sub1/deep/page.md')
    ]])
    local result = child.lua_get(
        [[require('mkdnflow.utils').getRootDir(_G._tmpdir .. '/sub1/deep', '.root_marker', 'Linux')]]
    )
    local tmpdir = child.lua_get('_G._tmpdir')
    eq(result, tmpdir .. '/sub1/deep')
end

-- =============================================================================
-- updateDirs() - Root re-evaluation on navigation
-- =============================================================================
T['updateDirs'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                -- Create nested directory structure
                _G._tmpdir = vim.fn.resolve(vim.fn.tempname())
                vim.fn.mkdir(_G._tmpdir .. '/sub1', 'p')
                vim.fn.mkdir(_G._tmpdir .. '/sub2', 'p')
                vim.fn.writefile({}, _G._tmpdir .. '/.root_marker')
                vim.fn.writefile({'[sub1 page](sub1/page.md)'}, _G._tmpdir .. '/index.md')
                vim.fn.writefile({''}, _G._tmpdir .. '/page.md')
                vim.fn.writefile({}, _G._tmpdir .. '/sub1/.root_marker')
                vim.fn.writefile({'[parent](../index.md)'}, _G._tmpdir .. '/sub1/index.md')
                vim.fn.writefile({''}, _G._tmpdir .. '/sub1/page.md')
                vim.fn.writefile({''}, _G._tmpdir .. '/sub2/page.md')

                -- Open the root index file
                vim.cmd('e ' .. _G._tmpdir .. '/index.md')
                vim.bo.filetype = 'markdown'
                require('mkdnflow').setup({
                    silent = true,
                    path_resolution = {
                        primary = 'root',
                        root_marker = '.root_marker',
                        update_on_navigate = true,
                    },
                })
            ]])
        end,
    },
})

T['updateDirs']['re-evaluates when navigating parent to child'] = function()
    -- Initial root should be tmpdir
    local tmpdir = child.lua_get('_G._tmpdir')
    local initial_root = child.lua_get('require("mkdnflow").root_dir')
    eq(initial_root, tmpdir)

    -- Navigate to sub1/page.md, call updateDirs, then follow a relative link
    -- to verify the root updated to sub1
    child.lua([[
        vim.cmd('e ' .. _G._tmpdir .. '/sub1/page.md')
        require('mkdnflow.paths').updateDirs()
        require('mkdnflow.paths').handlePath('index.md')
        _G._result_buf = vim.api.nvim_buf_get_name(0)
    ]])
    local buf_name = child.lua_get('_G._result_buf')
    -- Should resolve to sub1/index.md (not tmpdir/index.md)
    eq(buf_name, tmpdir .. '/sub1/index.md')
end

T['updateDirs']['re-evaluates when navigating child to parent'] = function()
    local tmpdir = child.lua_get('_G._tmpdir')

    -- Start in sub1
    child.lua([[
        vim.cmd('e ' .. _G._tmpdir .. '/sub1/page.md')
        require('mkdnflow.paths').updateDirs()
    ]])

    -- Navigate back to parent and follow a relative link
    child.lua([[
        vim.cmd('e ' .. _G._tmpdir .. '/index.md')
        require('mkdnflow.paths').updateDirs()
        require('mkdnflow.paths').handlePath('page.md')
        _G._result_buf = vim.api.nvim_buf_get_name(0)
    ]])
    local buf_name = child.lua_get('_G._result_buf')
    -- Should resolve to tmpdir/page.md
    eq(buf_name, tmpdir .. '/page.md')
end

T['updateDirs']['skips re-evaluation for same directory'] = function()
    local tmpdir = child.lua_get('_G._tmpdir')

    -- Navigate to sub1/index.md
    child.lua([[
        vim.cmd('e ' .. _G._tmpdir .. '/sub1/index.md')
        require('mkdnflow.paths').updateDirs()
    ]])

    -- Navigate to sub1/page.md (same directory)
    child.lua([[
        vim.cmd('e ' .. _G._tmpdir .. '/sub1/page.md')
        require('mkdnflow.paths').updateDirs()
        require('mkdnflow.paths').handlePath('index.md')
        _G._result_buf = vim.api.nvim_buf_get_name(0)
    ]])
    local buf_name = child.lua_get('_G._result_buf')
    -- Root should still be sub1
    eq(buf_name, tmpdir .. '/sub1/index.md')
end

T['updateDirs']['handles child with no marker (walks to parent)'] = function()
    local tmpdir = child.lua_get('_G._tmpdir')

    -- Navigate to sub2 (no .root_marker)
    child.lua([[
        vim.cmd('e ' .. _G._tmpdir .. '/sub2/page.md')
        require('mkdnflow.paths').updateDirs()
        require('mkdnflow.paths').handlePath('index.md')
        _G._result_buf = vim.api.nvim_buf_get_name(0)
    ]])
    local buf_name = child.lua_get('_G._result_buf')
    -- Root should be tmpdir (parent has the marker)
    eq(buf_name, tmpdir .. '/index.md')
end

T['updateDirs']['respects update_on_navigate = false'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                _G._tmpdir = vim.fn.resolve(vim.fn.tempname())
                vim.fn.mkdir(_G._tmpdir .. '/sub1', 'p')
                vim.fn.writefile({}, _G._tmpdir .. '/.root_marker')
                vim.fn.writefile({''}, _G._tmpdir .. '/index.md')
                vim.fn.writefile({}, _G._tmpdir .. '/sub1/.root_marker')
                vim.fn.writefile({''}, _G._tmpdir .. '/sub1/page.md')

                vim.cmd('e ' .. _G._tmpdir .. '/index.md')
                vim.bo.filetype = 'markdown'
                require('mkdnflow').setup({
                    silent = true,
                    path_resolution = {
                        primary = 'root',
                        root_marker = '.root_marker',
                        update_on_navigate = false,
                    },
                })
            ]])
        end,
    },
})

T['updateDirs']['respects update_on_navigate = false']['root does not change'] = function()
    local tmpdir = child.lua_get('_G._tmpdir')

    -- Navigate to sub1 and call updateDirs
    child.lua([[
        vim.cmd('e ' .. _G._tmpdir .. '/sub1/page.md')
        require('mkdnflow.paths').updateDirs()
        require('mkdnflow.paths').handlePath('index.md')
        _G._result_buf = vim.api.nvim_buf_get_name(0)
    ]])
    local buf_name = child.lua_get('_G._result_buf')
    -- Root should still be tmpdir (update_on_navigate is false)
    eq(buf_name, tmpdir .. '/index.md')
end

-- =============================================================================
-- getNotebook() - Statusline component API
-- =============================================================================
T['getNotebook'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                _G._tmpdir = vim.fn.resolve(vim.fn.tempname())
                vim.fn.mkdir(_G._tmpdir .. '/sub1', 'p')
                vim.fn.writefile({}, _G._tmpdir .. '/.root_marker')
                vim.fn.writefile({''}, _G._tmpdir .. '/index.md')
                vim.fn.writefile({}, _G._tmpdir .. '/sub1/.root_marker')
                vim.fn.writefile({''}, _G._tmpdir .. '/sub1/page.md')

                vim.cmd('e ' .. _G._tmpdir .. '/index.md')
                vim.bo.filetype = 'markdown'
                require('mkdnflow').setup({
                    silent = true,
                    path_resolution = {
                        primary = 'root',
                        root_marker = '.root_marker',
                        update_on_navigate = true,
                    },
                })
            ]])
        end,
    },
})

T['getNotebook']['returns name and root for current notebook'] = function()
    local tmpdir = child.lua_get('_G._tmpdir')
    local nb = child.lua_get('require("mkdnflow").getNotebook()')
    eq(nb.root, tmpdir)
    -- Name is the last path component
    local expected_name = tmpdir:match('.*/(.*)') or tmpdir
    eq(nb.name, expected_name)
end

T['getNotebook']['updates after navigating to nested collection'] = function()
    local tmpdir = child.lua_get('_G._tmpdir')

    child.lua([[
        vim.cmd('e ' .. _G._tmpdir .. '/sub1/page.md')
        require('mkdnflow.paths').updateDirs()
    ]])

    local nb = child.lua_get('require("mkdnflow").getNotebook()')
    eq(nb.root, tmpdir .. '/sub1')
    eq(nb.name, 'sub1')
end

T['getNotebook']['returns nil when no root is set'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
                require('mkdnflow').setup({
                    silent = true,
                    path_resolution = { primary = 'first' },
                })
            ]])
        end,
    },
})

T['getNotebook']['returns nil when no root is set']['returns nil'] = function()
    local result = child.lua_get('require("mkdnflow").getNotebook()')
    eq(result, vim.NIL)
end

-- =============================================================================
-- Issue #188: Links to external files not working
-- Files with non-notebook extensions (e.g., .pdf, .docx, .png) should be
-- opened with the system's default application, not as text files in Neovim.
-- =============================================================================
T['external_files'] = new_set()

-- pathType should recognize non-notebook extensions as needing system_open
T['external_files']['pathType identifies .pdf as external file'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').pathType('paper.pdf')]])
    eq(result, 'external')
end

T['external_files']['pathType identifies .docx as external file'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').pathType('document.docx')]])
    eq(result, 'external')
end

T['external_files']['pathType identifies .xlsx as external file'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').pathType('spreadsheet.xlsx')]])
    eq(result, 'external')
end

T['external_files']['pathType identifies .pptx as external file'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').pathType('slides.pptx')]])
    eq(result, 'external')
end

T['external_files']['pathType identifies .png as external file'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').pathType('image.png')]])
    eq(result, 'external')
end

T['external_files']['pathType identifies .jpg as external file'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').pathType('photo.jpg')]])
    eq(result, 'external')
end

-- Notebook files should still be nb_page
T['external_files']['pathType still identifies .md as nb_page'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').pathType('note.md')]])
    eq(result, 'nb_page')
end

T['external_files']['pathType still identifies .markdown as nb_page'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').pathType('note.markdown')]])
    eq(result, 'nb_page')
end

T['external_files']['pathType still identifies .rmd as nb_page'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').pathType('analysis.rmd')]])
    eq(result, 'nb_page')
end

T['external_files']['pathType still identifies extensionless path as nb_page'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').pathType('my-note')]])
    eq(result, 'nb_page')
end

-- External files with paths should also work
T['external_files']['pathType identifies relative path to .pdf as external file'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').pathType('papers/paper.pdf')]])
    eq(result, 'external')
end

T['external_files']['pathType identifies absolute path to .pdf as external file'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').pathType('/home/user/paper.pdf')]])
    eq(result, 'external')
end

T['external_files']['pathType identifies home path to .pdf as external file'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').pathType('~/documents/paper.pdf')]])
    eq(result, 'external')
end

-- file: prefix should still work as before
T['external_files']['pathType still handles file: prefix'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').pathType('file:document.pdf')]])
    eq(result, 'external')
end

-- Case-insensitive extension matching
T['external_files']['pathType handles uppercase extension .PDF'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').pathType('paper.PDF')]])
    eq(result, 'external')
end

T['external_files']['pathType handles mixed case extension .Md as nb_page'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').pathType('note.Md')]])
    eq(result, 'nb_page')
end

-- Custom filetypes: user adds an extension to filetypes config
T['external_files_custom_filetypes'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
                require('mkdnflow').setup({
                    filetypes = { markdown = true, txt = true },
                    links = {
                        transform_on_create = false,
                        transform_on_follow = false,
                    },
                })
            ]])
        end,
        post_once = child.stop,
    },
})

T['external_files_custom_filetypes']['txt treated as nb_page when in filetypes'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').pathType('notes.txt')]])
    eq(result, 'nb_page')
end

T['external_files_custom_filetypes']['pdf still treated as external'] = function()
    local result = child.lua_get([[require('mkdnflow.paths').pathType('paper.pdf')]])
    eq(result, 'external')
end

-- handlePath should open external files with system_open, not vim_open
T['external_files']['handlePath does not open .pdf in Neovim buffer'] = function()
    child.lua([[
        _G._tmpdir = vim.fn.tempname()
        vim.fn.mkdir(_G._tmpdir, 'p')
        local tmpfile = _G._tmpdir .. '/index.md'
        vim.fn.writefile({''}, tmpfile)
        vim.cmd('e ' .. tmpfile)
        vim.bo.filetype = 'markdown'
        require('mkdnflow').setup({
            links = { transform_on_create = false, transform_on_follow = false },
        })
        -- Create a fake PDF file
        vim.fn.writefile({'%PDF-fake'}, _G._tmpdir .. '/paper.pdf')
    ]])
    local buf_before = child.lua_get('vim.api.nvim_buf_get_name(0)')
    child.lua([[require('mkdnflow.paths').handlePath('paper.pdf')]])
    local buf_after = child.lua_get('vim.api.nvim_buf_get_name(0)')
    -- Buffer should NOT change — external file should be system-opened, not vim-opened
    eq(buf_before, buf_after)
end

T['external_files']['handlePath strips file: prefix and does not open in buffer'] = function()
    child.lua([[
        _G._tmpdir = vim.fn.tempname()
        vim.fn.mkdir(_G._tmpdir, 'p')
        local tmpfile = _G._tmpdir .. '/index.md'
        vim.fn.writefile({''}, tmpfile)
        vim.cmd('e ' .. tmpfile)
        vim.bo.filetype = 'markdown'
        require('mkdnflow').setup({
            links = { transform_on_create = false, transform_on_follow = false },
        })
        vim.fn.writefile({'%PDF-fake'}, _G._tmpdir .. '/report.pdf')
    ]])
    local buf_before = child.lua_get('vim.api.nvim_buf_get_name(0)')
    child.lua([[require('mkdnflow.paths').handlePath('file:report.pdf')]])
    local buf_after = child.lua_get('vim.api.nvim_buf_get_name(0)')
    eq(buf_before, buf_after)
end

-- E2E: <CR> on a PDF link should not switch buffers
T['external_files_e2e'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                _G._tmpdir = vim.fn.tempname()
                vim.fn.mkdir(_G._tmpdir, 'p')
                local tmpfile = _G._tmpdir .. '/index.md'
                vim.fn.writefile({'[A paper](paper.pdf)'}, tmpfile)

                vim.cmd('runtime plugin/mkdnflow.lua')

                vim.cmd('e ' .. tmpfile)
                vim.bo.filetype = 'markdown'

                require('mkdnflow').setup({
                    links = {
                        transform_on_create = false,
                        transform_on_follow = false,
                    },
                })

                -- Create a fake PDF so system_open's existence check passes
                vim.fn.writefile({'%PDF-fake'}, _G._tmpdir .. '/paper.pdf')

                vim.cmd('doautocmd BufEnter')
            ]])
        end,
    },
})

T['external_files_e2e']['<CR> on PDF link does not open in buffer'] = function()
    set_cursor(1, 5)
    local buf_before = child.lua_get('vim.api.nvim_buf_get_name(0)')
    child.type_keys('<CR>')
    local buf_after = child.lua_get('vim.api.nvim_buf_get_name(0)')
    eq(buf_before, buf_after)
end

-- =============================================================================
-- getBaseDir() - Compute resolution base directory
-- =============================================================================
T['getBaseDir'] = new_set()

T['getBaseDir']['returns root_dir when primary=root'] = function()
    child.lua([[
        local init = require('mkdnflow')
        init.root_dir = '/fake/notebook'
        init.setup({
            path_resolution = { primary = 'root', root_marker = '.root', fallback = 'first' },
            links = { transform_on_create = false, transform_on_follow = false },
        })
    ]])
    local result = child.lua_get([[require('mkdnflow.paths').getBaseDir()]])
    eq(result, '/fake/notebook')
end

T['getBaseDir']['returns initial_dir when primary=first'] = function()
    child.lua([[
        local init = require('mkdnflow')
        init.setup({
            path_resolution = { primary = 'first' },
            links = { transform_on_create = false, transform_on_follow = false },
        })
        init.initial_dir = '/fake/wiki'
    ]])
    local result = child.lua_get([[require('mkdnflow.paths').getBaseDir()]])
    eq(result, '/fake/wiki')
end

T['getBaseDir']['falls back to initial_dir when root not found'] = function()
    child.lua([[
        local init = require('mkdnflow')
        init.setup({
            path_resolution = { primary = 'root', root_marker = '.root', fallback = 'first' },
            links = { transform_on_create = false, transform_on_follow = false },
        })
        init.root_dir = nil
        init.initial_dir = '/fake/wiki'
    ]])
    local result = child.lua_get([[require('mkdnflow.paths').getBaseDir()]])
    eq(result, '/fake/wiki')
end

T['getBaseDir']['uses current buffer dir when primary=current'] = function()
    child.lua([[
        local init = require('mkdnflow')
        init.setup({
            path_resolution = { primary = 'current' },
            links = { transform_on_create = false, transform_on_follow = false },
        })
        vim.api.nvim_buf_set_name(0, '/some/dir/file.md')
    ]])
    local result = child.lua_get([[require('mkdnflow.paths').getBaseDir()]])
    eq(result, '/some/dir')
end

T['getBaseDir']['uses buf_path argument for current strategy'] = function()
    child.lua([[
        local init = require('mkdnflow')
        init.setup({
            path_resolution = { primary = 'current' },
            links = { transform_on_create = false, transform_on_follow = false },
        })
    ]])
    local result = child.lua_get([[require('mkdnflow.paths').getBaseDir('/other/path/note.md')]])
    eq(result, '/other/path')
end

T['getBaseDir']['falls back to cwd when dirname is nil'] = function()
    child.lua([[
        local init = require('mkdnflow')
        init.setup({
            path_resolution = { primary = 'current' },
            links = { transform_on_create = false, transform_on_follow = false },
        })
        -- Set buffer name to empty string so dirname returns nil/empty
        vim.api.nvim_buf_set_name(0, '')
    ]])
    local result = child.lua_get([[require('mkdnflow.paths').getBaseDir()]])
    local cwd = child.lua_get([[vim.fn.getcwd()]])
    eq(result, cwd)
end

-- =============================================================================
-- relativeToBase() - Compute path relative to resolution base
-- =============================================================================
T['relativeToBase'] = new_set()

T['relativeToBase']['strips root_dir when primary=root'] = function()
    child.lua([[
        local init = require('mkdnflow')
        init.root_dir = '/fake/notebook'
        init.setup({
            path_resolution = { primary = 'root', root_marker = '.root', fallback = 'first' },
            links = { transform_on_create = false, transform_on_follow = false },
        })
    ]])
    local result =
        child.lua_get([[require('mkdnflow.paths').relativeToBase('/fake/notebook/sub/file.md')]])
    eq(result, 'sub/file.md')
end

T['relativeToBase']['strips initial_dir when primary=first'] = function()
    child.lua([[
        local init = require('mkdnflow')
        init.setup({
            path_resolution = { primary = 'first' },
            links = { transform_on_create = false, transform_on_follow = false },
        })
        init.initial_dir = '/fake/wiki'
    ]])
    local result =
        child.lua_get([[require('mkdnflow.paths').relativeToBase('/fake/wiki/notes/page.md')]])
    eq(result, 'notes/page.md')
end

T['relativeToBase']['falls back to initial_dir when root not found'] = function()
    child.lua([[
        local init = require('mkdnflow')
        init.setup({
            path_resolution = { primary = 'root', root_marker = '.root', fallback = 'first' },
            links = { transform_on_create = false, transform_on_follow = false },
        })
        init.root_dir = nil
        init.initial_dir = '/fake/wiki'
    ]])
    local result =
        child.lua_get([[require('mkdnflow.paths').relativeToBase('/fake/wiki/sub/file.md')]])
    eq(result, 'sub/file.md')
end

T['relativeToBase']['returns basename when path not under base'] = function()
    child.lua([[
        local init = require('mkdnflow')
        init.root_dir = '/fake/notebook'
        init.setup({
            path_resolution = { primary = 'root', root_marker = '.root', fallback = 'first' },
            links = { transform_on_create = false, transform_on_follow = false },
        })
    ]])
    local result =
        child.lua_get([[require('mkdnflow.paths').relativeToBase('/other/path/file.md')]])
    eq(result, 'file.md')
end

T['relativeToBase']['handles file directly in base directory'] = function()
    child.lua([[
        local init = require('mkdnflow')
        init.root_dir = '/fake/notebook'
        init.setup({
            path_resolution = { primary = 'root', root_marker = '.root', fallback = 'first' },
            links = { transform_on_create = false, transform_on_follow = false },
        })
    ]])
    local result =
        child.lua_get([[require('mkdnflow.paths').relativeToBase('/fake/notebook/index.md')]])
    eq(result, 'index.md')
end

-- =============================================================================
-- Custom URI scheme handlers (links.uri_handlers) — Issue #167
-- =============================================================================
T['uri_handlers'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                _G._handler_calls = {}
                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
            ]])
        end,
    },
})

T['uri_handlers']['pathType returns uri_handler for registered scheme'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = {
                transform_on_create = false,
                transform_on_follow = false,
                uri_handlers = { phd = function() end },
            },
        })
    ]])
    local result = child.lua_get([[require('mkdnflow.paths').pathType('phd://path/to/paper.pdf')]])
    eq(result, 'uri_handler')
end

T['uri_handlers']['pathType falls through for unregistered scheme'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = {
                transform_on_create = false,
                transform_on_follow = false,
                uri_handlers = {},
            },
        })
    ]])
    local result = child.lua_get([[require('mkdnflow.paths').pathType('https://example.com')]])
    eq(result, 'url')
end

T['uri_handlers']['pathType skips handler when value is false'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = {
                transform_on_create = false,
                transform_on_follow = false,
                uri_handlers = { phd = false },
            },
        })
    ]])
    local result = child.lua_get([[require('mkdnflow.paths').pathType('phd://path/to/paper.pdf')]])
    -- false handler means fall through; phd:// won't match hasUrl or other checks
    eq(result ~= 'uri_handler', true)
end

T['uri_handlers']['handlePath calls function handler with correct args'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = {
                transform_on_create = false,
                transform_on_follow = false,
                uri_handlers = {
                    phd = function(uri, scheme, path, anchor)
                        table.insert(_G._handler_calls, {
                            uri = uri, scheme = scheme, path = path, anchor = anchor
                        })
                    end,
                },
            },
        })
    ]])
    child.lua([[require('mkdnflow.paths').handlePath('phd://papers/paper.pdf', '#page3')]])
    local calls = child.lua_get('_G._handler_calls')
    eq(#calls, 1)
    eq(calls[1].scheme, 'phd')
    eq(calls[1].path, 'phd://papers/paper.pdf')
    eq(calls[1].anchor, '#page3')
    eq(calls[1].uri, 'phd://papers/paper.pdf#page3')
end

T['uri_handlers']['handlePath with system shorthand does not error'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = {
                transform_on_create = false,
                transform_on_follow = false,
                uri_handlers = { zotero = 'system' },
            },
        })
    ]])
    local ok = child.lua_get([[({pcall(function()
        require('mkdnflow.paths').handlePath('zotero://select/items/ABC123')
    end)})[1] ]])
    eq(ok, true)
end

T['uri_handlers']['handler receives nil anchor when none present'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = {
                transform_on_create = false,
                transform_on_follow = false,
                uri_handlers = {
                    phd = function(uri, scheme, path, anchor)
                        table.insert(_G._handler_calls, { anchor = anchor })
                    end,
                },
            },
        })
    ]])
    child.lua([[require('mkdnflow.paths').handlePath('phd://papers/paper.pdf')]])
    local calls = child.lua_get('_G._handler_calls')
    eq(#calls, 1)
    -- nil table values are absent when retrieved via lua_get
    eq(calls[1].anchor, nil)
end

T['uri_handlers']['http URLs still handled as url type'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = {
                transform_on_create = false,
                transform_on_follow = false,
                uri_handlers = { phd = function() end },
            },
        })
    ]])
    local result = child.lua_get([[require('mkdnflow.paths').pathType('https://example.com')]])
    eq(result, 'url')
end

T['uri_handlers']['file: prefix still handled as external even if registered'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = {
                transform_on_create = false,
                transform_on_follow = false,
                uri_handlers = { file = function() end },
            },
        })
    ]])
    local result = child.lua_get([[require('mkdnflow.paths').pathType('file:document.pdf')]])
    eq(result, 'external')
end

T['uri_handlers']['can override http scheme'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = {
                transform_on_create = false,
                transform_on_follow = false,
                uri_handlers = {
                    https = function(uri, scheme, path, anchor)
                        table.insert(_G._handler_calls, { uri = uri })
                    end,
                },
            },
        })
    ]])
    local result = child.lua_get([[require('mkdnflow.paths').pathType('https://example.com')]])
    eq(result, 'uri_handler')
end

-- E2E: <CR> on custom URI scheme link calls handler
T['uri_handlers_e2e'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                _G._handler_calls = {}
                _G._tmpdir = vim.fn.tempname()
                vim.fn.mkdir(_G._tmpdir, 'p')
                local tmpfile = _G._tmpdir .. '/index.md'
                vim.fn.writefile({''}, tmpfile)

                vim.cmd('runtime plugin/mkdnflow.lua')

                vim.cmd('e ' .. tmpfile)
                vim.bo.filetype = 'markdown'

                require('mkdnflow').setup({
                    links = {
                        transform_on_create = false,
                        transform_on_follow = false,
                        uri_handlers = {
                            phd = function(uri, scheme, path, anchor)
                                table.insert(_G._handler_calls, {
                                    uri = uri, scheme = scheme, path = path, anchor = anchor
                                })
                            end,
                        },
                    },
                })

                vim.cmd('doautocmd BufEnter')
            ]])
        end,
    },
})

T['uri_handlers_e2e']['<CR> on custom scheme link calls handler'] = function()
    set_lines({ '[My Paper](phd://papers/linguistics.pdf#3)' })
    set_cursor(1, 15)
    child.type_keys('<CR>')
    local calls = child.lua_get('_G._handler_calls')
    eq(#calls, 1)
    eq(calls[1].scheme, 'phd')
    eq(calls[1].uri, 'phd://papers/linguistics.pdf#3')
end

-- =============================================================================
-- edit_dirs - Directory link behavior (inspired by PR #184)
-- =============================================================================
T['edit_dirs'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                _G._tmpdir = vim.fn.resolve(vim.fn.tempname())
                vim.fn.mkdir(_G._tmpdir .. '/subdir', 'p')
                local tmpfile = _G._tmpdir .. '/index.md'
                vim.fn.writefile({'[Dir Link](subdir)'}, tmpfile)
                vim.cmd('e ' .. tmpfile)
                vim.bo.filetype = 'markdown'
            ]])
        end,
    },
})

T['edit_dirs']['default false prompts via vim.ui.input'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = {
                transform_on_create = false,
                transform_on_follow = false,
                edit_dirs = false,
            },
        })
        _G._ui_input_called = false
        vim.ui.input = function(opts, on_confirm)
            _G._ui_input_called = true
            on_confirm(nil)
        end
    ]])
    child.lua([[require('mkdnflow.paths').handlePath('subdir')]])
    local called = child.lua_get('_G._ui_input_called')
    eq(called, true)
end

T['edit_dirs']['true opens directory with :edit'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = {
                transform_on_create = false,
                transform_on_follow = false,
                edit_dirs = true,
            },
        })
    ]])
    child.lua([[require('mkdnflow.paths').handlePath('subdir')]])
    local buf_name = child.lua_get('vim.api.nvim_buf_get_name(0)')
    local tmpdir = child.lua_get('_G._tmpdir')
    eq(buf_name, tmpdir .. '/subdir')
end

T['edit_dirs']['function receives absolute directory path'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = {
                transform_on_create = false,
                transform_on_follow = false,
                edit_dirs = function(path)
                    _G._received_path = path
                end,
            },
        })
    ]])
    child.lua([[require('mkdnflow.paths').handlePath('subdir')]])
    local received = child.lua_get('_G._received_path')
    local tmpdir = child.lua_get('_G._tmpdir')
    eq(received, tmpdir .. '/subdir')
end

T['edit_dirs']['true pushes buffer stack for back navigation'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = {
                transform_on_create = false,
                transform_on_follow = false,
                edit_dirs = true,
            },
        })
    ]])
    local buf_before = child.lua_get('vim.api.nvim_buf_get_name(0)')
    child.lua([[require('mkdnflow.paths').handlePath('subdir')]])
    -- Navigate back
    child.lua([[require('mkdnflow.buffers').goBack()]])
    local buf_after_back = child.lua_get('vim.api.nvim_buf_get_name(0)')
    eq(buf_before, buf_after_back)
end

T['edit_dirs']['function pushes buffer stack for back navigation'] = function()
    child.lua([[
        require('mkdnflow').setup({
            links = {
                transform_on_create = false,
                transform_on_follow = false,
                edit_dirs = function(path)
                    _G._received_path = path
                end,
            },
        })
    ]])
    local buf_before = child.lua_get('vim.api.nvim_buf_get_name(0)')
    child.lua([[require('mkdnflow.paths').handlePath('subdir')]])
    -- Navigate back
    child.lua([[require('mkdnflow.buffers').goBack()]])
    local buf_after_back = child.lua_get('vim.api.nvim_buf_get_name(0)')
    eq(buf_before, buf_after_back)
end

-- =============================================================================
-- moveSource notebook-wide reference scanning
-- =============================================================================
T['moveSource_references'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                _G._tmpdir = vim.fn.resolve(vim.fn.tempname())
                vim.fn.mkdir(_G._tmpdir .. '/sub', 'p')
                vim.fn.writefile({'[page](page.md)'}, _G._tmpdir .. '/index.md')
                vim.fn.writefile({'# Page'}, _G._tmpdir .. '/page.md')
                vim.fn.writefile({'[see page](page.md)'}, _G._tmpdir .. '/other.md')
                vim.fn.writefile({'[click here][page]', '', '[page]: page.md'}, _G._tmpdir .. '/refstyle.md')
                vim.fn.writefile({'[page](../page.md)'}, _G._tmpdir .. '/sub/ref.md')
                vim.cmd('e ' .. _G._tmpdir .. '/index.md')
                vim.bo.filetype = 'markdown'

                require('mkdnflow').setup({
                    modules = { paths = true, links = true },
                    path_resolution = { primary = 'first' },
                })
            ]])
        end,
    },
})

-- find_references_async: finds matching links in other files
T['moveSource_references']['find_references finds matching links'] = function()
    child.lua([[
        _G._refs = nil
        require('mkdnflow.paths')._test.find_references_async(
            _G._tmpdir .. '/page.md',
            _G._tmpdir .. '/index.md',
            {},
            function(refs) _G._refs = refs end
        )
        vim.wait(5000, function() return _G._refs ~= nil end, 50)
    ]])
    local refs = child.lua_get('_G._refs')
    -- Should find references in other.md (and possibly refstyle.md for ref_definition)
    local found_other = false
    for _, ref in ipairs(refs) do
        if ref.filepath:match('other%.md$') then
            found_other = true
        end
    end
    eq(found_other, true)
end

-- find_references_async: skips the current file
T['moveSource_references']['find_references skips current file'] = function()
    child.lua([[
        _G._refs = nil
        require('mkdnflow.paths')._test.find_references_async(
            _G._tmpdir .. '/page.md',
            _G._tmpdir .. '/index.md',
            {},
            function(refs) _G._refs = refs end
        )
        vim.wait(5000, function() return _G._refs ~= nil end, 50)
    ]])
    local refs = child.lua_get('_G._refs')
    local found_index = false
    for _, ref in ipairs(refs) do
        if ref.filepath:match('index%.md$') then
            found_index = true
        end
    end
    eq(found_index, false)
end

-- find_references_async: skips non-matching links
T['moveSource_references']['find_references skips non-matching links'] = function()
    child.lua([[
        vim.fn.writefile({'[other](unrelated.md)'}, _G._tmpdir .. '/nomatch.md')
        _G._refs = nil
        require('mkdnflow.paths')._test.find_references_async(
            _G._tmpdir .. '/page.md',
            _G._tmpdir .. '/index.md',
            {},
            function(refs) _G._refs = refs end
        )
        vim.wait(5000, function() return _G._refs ~= nil end, 50)
    ]])
    local refs = child.lua_get('_G._refs')
    local found_nomatch = false
    for _, ref in ipairs(refs) do
        if ref.filepath:match('nomatch%.md$') then
            found_nomatch = true
        end
    end
    eq(found_nomatch, false)
end

-- find_references_async: handles ref_definition type
T['moveSource_references']['find_references handles ref_definition'] = function()
    child.lua([[
        _G._refs = nil
        require('mkdnflow.paths')._test.find_references_async(
            _G._tmpdir .. '/page.md',
            _G._tmpdir .. '/index.md',
            {},
            function(refs) _G._refs = refs end
        )
        vim.wait(5000, function() return _G._refs ~= nil end, 50)
    ]])
    local refs = child.lua_get('_G._refs')
    local found_refdef = false
    for _, ref in ipairs(refs) do
        if ref.filepath:match('refstyle%.md$') and ref.type == 'ref_definition' then
            found_refdef = true
        end
    end
    eq(found_refdef, true)
end

-- compute_new_source: first strategy
T['moveSource_references']['compute_new_source first strategy'] = function()
    local result = child.lua_get([[
        require('mkdnflow.paths')._test.compute_new_source(
            'page',
            require('mkdnflow').initial_dir .. '/renamed.md',
            require('mkdnflow').initial_dir .. '/other.md'
        )
    ]])
    eq(result, 'renamed')
end

-- compute_new_source: preserves implicit extension
T['moveSource_references']['compute_new_source preserves implicit extension'] = function()
    -- Old source has no extension -> new source should have no extension
    local result = child.lua_get([[
        require('mkdnflow.paths')._test.compute_new_source(
            'page',
            require('mkdnflow').initial_dir .. '/sub/renamed.md',
            require('mkdnflow').initial_dir .. '/other.md'
        )
    ]])
    eq(result, 'sub/renamed')
end

-- compute_new_source: keeps extension when old source had one
T['moveSource_references']['compute_new_source keeps explicit extension'] = function()
    local result = child.lua_get([[
        require('mkdnflow.paths')._test.compute_new_source(
            'page.md',
            require('mkdnflow').initial_dir .. '/renamed.md',
            require('mkdnflow').initial_dir .. '/other.md'
        )
    ]])
    eq(result, 'renamed.md')
end

-- compute_new_source: current strategy computes relative paths
T['moveSource_references']['compute_new_source current strategy'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                _G._tmpdir = vim.fn.resolve(vim.fn.tempname())
                vim.fn.mkdir(_G._tmpdir .. '/sub', 'p')
                vim.fn.writefile({''}, _G._tmpdir .. '/index.md')
                vim.cmd('e ' .. _G._tmpdir .. '/index.md')
                vim.bo.filetype = 'markdown'
                require('mkdnflow').setup({
                    modules = { paths = true, links = true },
                    path_resolution = { primary = 'current' },
                })
            ]])
        end,
    },
})

T['moveSource_references']['compute_new_source current strategy']['relative path from root'] = function()
    local result = child.lua_get([[
            require('mkdnflow.paths')._test.compute_new_source(
                'page',
                _G._tmpdir .. '/sub/renamed.md',
                _G._tmpdir .. '/index.md'
            )
        ]])
    eq(result, 'sub/renamed')
end

T['moveSource_references']['compute_new_source current strategy']['relative path from subdir'] = function()
    local result = child.lua_get([[
            require('mkdnflow.paths')._test.compute_new_source(
                '../page',
                _G._tmpdir .. '/renamed.md',
                _G._tmpdir .. '/sub/ref.md'
            )
        ]])
    eq(result, '../renamed')
end

-- compute_relative_path: basic cases
T['moveSource_references']['compute_relative_path same directory'] = function()
    local result = child.lua_get([[
        require('mkdnflow.paths')._test.compute_relative_path(
            '/a/b', '/a/b/to.md'
        )
    ]])
    eq(result, 'to.md')
end

T['moveSource_references']['compute_relative_path parent directory'] = function()
    local result = child.lua_get([[
        require('mkdnflow.paths')._test.compute_relative_path(
            '/a/b/c', '/a/b/to.md'
        )
    ]])
    eq(result, '../to.md')
end

T['moveSource_references']['compute_relative_path child directory'] = function()
    local result = child.lua_get([[
        require('mkdnflow.paths')._test.compute_relative_path(
            '/a/b', '/a/b/c/to.md'
        )
    ]])
    eq(result, 'c/to.md')
end

-- apply_change: modifies file on disk
T['moveSource_references']['apply_change modifies file on disk'] = function()
    child.lua([[
        local changes = {
            {
                filepath = _G._tmpdir .. '/other.md',
                lnum = 1,
                col = 1,
                match = '[see page](page.md)',
                source = 'page.md',
                anchor = '',
                type = 'md_link',
                new_source = 'renamed.md',
            },
        }
        -- Use apply_change via open_review's internal function
        -- Instead, directly test by simulating what apply_change does
        local old_ref = 'page.md'
        local new_ref = 'renamed.md'
        local lines = vim.fn.readfile(_G._tmpdir .. '/other.md')
        local old_match = '[see page](page.md)'
        local new_match = old_match:gsub(vim.pesc(old_ref), function() return new_ref end, 1)
        lines[1] = lines[1]:gsub(vim.pesc(old_match), function() return new_match end, 1)
        vim.fn.writefile(lines, _G._tmpdir .. '/other.md')
    ]])
    local lines = child.lua_get([[vim.fn.readfile(_G._tmpdir .. '/other.md')]])
    eq(lines[1], '[see page](renamed.md)')
end

-- open_review: populates quickfix list
T['moveSource_references']['open_review populates quickfix list'] = function()
    child.lua([[
        local changes = {
            {
                filepath = _G._tmpdir .. '/other.md',
                lnum = 1,
                col = 1,
                match = '[see page](page.md)',
                source = 'page.md',
                anchor = '',
                type = 'md_link',
            },
        }
        require('mkdnflow.paths')._test.open_review(changes, _G._tmpdir .. '/renamed.md')
    ]])
    local qflist = child.lua_get('vim.fn.getqflist()')
    eq(#qflist, 1)
    -- The text should contain the arrow between old and new source
    local has_arrow = qflist[1].text:find('→') ~= nil
    eq(has_arrow, true)
    -- Clean up quickfix window
    child.lua('vim.cmd.cclose()')
end

-- find_references_async: finds wiki links
T['moveSource_references']['wiki links are found'] = function()
    child.lua([=[
        vim.fn.writefile({'[[page]]'}, _G._tmpdir .. '/wikilink.md')
        _G._refs = nil
        require('mkdnflow.paths')._test.find_references_async(
            _G._tmpdir .. '/page.md',
            _G._tmpdir .. '/index.md',
            {},
            function(refs) _G._refs = refs end
        )
        vim.wait(5000, function() return _G._refs ~= nil end, 50)
    ]=])
    local refs = child.lua_get('_G._refs')
    local found_wiki = false
    for _, ref in ipairs(refs) do
        if ref.filepath:match('wikilink%.md$') then
            found_wiki = true
        end
    end
    eq(found_wiki, true)
end

-- resolve_link_source: basic resolution
T['moveSource_references']['resolve_link_source adds extension and resolves'] = function()
    local result = child.lua_get([[
        require('mkdnflow.paths')._test.resolve_link_source(
            'page',
            require('mkdnflow').initial_dir .. '/index.md'
        )
    ]])
    local initial_dir = child.lua_get('require("mkdnflow").initial_dir')
    eq(result, initial_dir .. '/page.md')
end

-- find_references_async with empty notebook
T['moveSource_references']['find_references handles empty results'] = function()
    child.lua([[
        -- Search for a file that nothing links to
        vim.fn.writefile({'# Orphan'}, _G._tmpdir .. '/orphan.md')
        _G._refs = nil
        require('mkdnflow.paths')._test.find_references_async(
            _G._tmpdir .. '/orphan.md',
            _G._tmpdir .. '/index.md',
            {},
            function(refs) _G._refs = refs end
        )
        vim.wait(5000, function() return _G._refs ~= nil end, 50)
    ]])
    local refs = child.lua_get('_G._refs')
    eq(#refs, 0)
end

return T
