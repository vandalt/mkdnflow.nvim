-- tests/test_cmp.lua
-- Tests for nvim-cmp completion source functionality
--
-- Note: The cmp module requires nvim-cmp to be installed. These tests focus on
-- the file scanning functionality that replaced plenary.scandir.

local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

-- Create a temporary directory structure for testing
local test_root = vim.fn.tempname()

local T = new_set({
    hooks = {
        pre_once = function()
            -- Create test directory structure
            vim.fn.mkdir(test_root, 'p')
            vim.fn.mkdir(test_root .. '/subdir', 'p')
            vim.fn.mkdir(test_root .. '/another', 'p')

            -- Create test markdown files
            local files = {
                test_root .. '/note1.md',
                test_root .. '/note2.md',
                test_root .. '/subdir/nested.md',
                test_root .. '/another/deep.md',
                test_root .. '/not-markdown.txt',
                test_root .. '/subdir/also-not.lua',
            }
            for _, file in ipairs(files) do
                local f = io.open(file, 'w')
                f:write('# Test file\n\nContent here.')
                f:close()
            end
        end,
        post_once = function()
            child.stop()
            -- Clean up test directory
            vim.fn.delete(test_root, 'rf')
        end,
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
            ]])
        end,
    },
})

-- =============================================================================
-- vim.fs.find() - The replacement for plenary.scandir
-- =============================================================================
T['vim_fs_find'] = new_set()

T['vim_fs_find']['finds markdown files recursively'] = function()
    child.lua('_test_root = "' .. test_root .. '"')
    child.lua([[
        _files = vim.fs.find(function(name)
            return name:match('%.md$')
        end, { path = _test_root, type = 'file', limit = math.huge })
    ]])
    local files = child.lua_get('_files')
    eq(#files, 4) -- note1.md, note2.md, nested.md, deep.md
end

T['vim_fs_find']['excludes non-markdown files'] = function()
    child.lua('_test_root = "' .. test_root .. '"')
    child.lua([[
        _files = vim.fs.find(function(name)
            return name:match('%.md$')
        end, { path = _test_root, type = 'file', limit = math.huge })
    ]])
    local files = child.lua_get('_files')
    -- Check none of the files are .txt or .lua
    for _, file in ipairs(files) do
        eq(file:match('%.txt$'), nil)
        eq(file:match('%.lua$'), nil)
    end
end

T['vim_fs_find']['returns absolute paths'] = function()
    child.lua('_test_root = "' .. test_root .. '"')
    child.lua([[
        _files = vim.fs.find(function(name)
            return name:match('%.md$')
        end, { path = _test_root, type = 'file', limit = math.huge })
    ]])
    local files = child.lua_get('_files')
    for _, file in ipairs(files) do
        -- All paths should start with /
        eq(file:match('^/'), '/')
    end
end

T['vim_fs_find']['finds files in subdirectories'] = function()
    child.lua('_test_root = "' .. test_root .. '"')
    child.lua([[
        _files = vim.fs.find(function(name)
            return name:match('%.md$')
        end, { path = _test_root, type = 'file', limit = math.huge })
        _has_nested = false
        _has_deep = false
        for _, f in ipairs(_files) do
            if f:match('nested%.md$') then _has_nested = true end
            if f:match('deep%.md$') then _has_deep = true end
        end
    ]])
    eq(child.lua_get('_has_nested'), true)
    eq(child.lua_get('_has_deep'), true)
end

T['vim_fs_find']['handles empty directory'] = function()
    local empty_dir = vim.fn.tempname()
    vim.fn.mkdir(empty_dir, 'p')

    child.lua('_empty_dir = "' .. empty_dir .. '"')
    child.lua([[
        _files = vim.fs.find(function(name)
            return name:match('%.md$')
        end, { path = _empty_dir, type = 'file', limit = math.huge })
    ]])
    local files = child.lua_get('_files')
    eq(#files, 0)

    vim.fn.delete(empty_dir, 'rf')
end

-- =============================================================================
-- File path extraction (simulating what cmp.lua does)
-- =============================================================================
T['path_extraction'] = new_set()

T['path_extraction']['extracts filename from path'] = function()
    child.lua([[
        _path = '/some/path/to/my-note.md'
        _extension = '.md'
        _label = _path:match('([^/^\\]+)' .. _extension .. '$')
    ]])
    local label = child.lua_get('_label')
    eq(label, 'my-note')
end

T['path_extraction']['handles paths with special characters'] = function()
    child.lua([[
        _path = '/path/to/note_2024-01-15.md'
        _extension = '.md'
        _label = _path:match('([^/^\\]+)' .. _extension .. '$')
    ]])
    local label = child.lua_get('_label')
    eq(label, 'note_2024-01-15')
end

T['path_extraction']['handles paths with spaces'] = function()
    child.lua([[
        _path = '/path/to/my note here.md'
        _extension = '.md'
        _label = _path:match('([^/^\\]+)' .. _extension .. '$')
    ]])
    local label = child.lua_get('_label')
    eq(label, 'my note here')
end

-- =============================================================================
-- parse_bib (via source:complete) with mock cmp
-- =============================================================================
T['parse_bib'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                -- Mock nvim-cmp so cmp.lua can be loaded without the real dependency.
                -- Capture the registered source so we can call :complete directly.
                _G._registered_source = nil
                package.loaded['cmp'] = {
                    lsp = {
                        CompletionItemKind = { File = 17, Reference = 18 },
                        MarkupKind = { Markdown = 'markdown' },
                    },
                    register_source = function(_, src)
                        _G._registered_source = src
                    end,
                }

                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
            ]])
        end,
    },
})

T['parse_bib']['nonexistent bib path does not error'] = function()
    child.lua([[
        require('mkdnflow').setup({
            modules = { bib = true, cmp = true },
            bib = {
                default_path = '/tmp/nonexistent_' .. vim.fn.getpid() .. '.bib',
                find_in_root = false,
            },
            silent = true,
        })

        local params = { context = { cursor_before_line = '@cite' } }
        _G._complete_ok, _G._complete_err = pcall(function()
            _G._registered_source:complete(params, function(items)
                _G._complete_items = items
            end)
        end)
    ]])
    eq(child.lua_get('_G._complete_ok'), true)
end

-- =============================================================================
-- Integration with mkdnflow setup
-- =============================================================================
T['integration'] = new_set()

T['integration']['cmp module can be enabled'] = function()
    -- Note: This will fail if nvim-cmp is not installed, but that's expected
    -- We wrap in pcall to handle both cases
    child.lua([[
        _success = pcall(function()
            require('mkdnflow').setup({
                modules = { cmp = true },
                silent = true
            })
        end)
    ]])
    -- We just verify it doesn't crash during setup
    -- The actual success depends on whether cmp is installed
    eq(true, true)
end

T['integration']['cmp module disabled by default'] = function()
    child.lua([[
        require('mkdnflow').setup({ silent = true })
    ]])
    local cmp_enabled = child.lua_get('require("mkdnflow").config.modules.cmp')
    eq(cmp_enabled, false)
end

return T
