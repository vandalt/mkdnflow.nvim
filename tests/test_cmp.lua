-- tests/test_cmp.lua
-- Tests for nvim-cmp completion source functionality

local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

-- Create a temporary directory structure for testing
local test_root = vim.fn.tempname()

--- Helper: set up mock cmp and mkdnflow with given config in the child process.
--- The test_root is passed so the child can set buffer name and initial_dir.
---@param config_overrides string Lua table literal for mkdnflow setup overrides
local function setup_cmp_child(config_overrides)
    child.restart({ '-u', 'scripts/minimal_init.lua' })
    child.lua('_G._test_root = "' .. test_root .. '"')
    child.lua(
        [[
        -- Mock nvim-cmp so cmp.lua can be loaded without the real dependency.
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

        -- Set buffer to a file inside test_root so path resolution works
        vim.api.nvim_buf_set_name(0, _G._test_root .. '/current.md')
        vim.bo.filetype = 'markdown'

        require('mkdnflow').setup(]]
            .. config_overrides
            .. [[)
    ]]
    )
end

--- Helper: call source:complete with '@' trigger and return the items
---@return table[] items
local function complete_items()
    child.lua([[
        local params = { context = { cursor_before_line = '@' } }
        _G._registered_source:complete(params, function(items)
            _G._complete_items = items
        end)
    ]])
    return child.lua_get('_G._complete_items')
end

--- Helper: find a completion item by label
---@param items table[]
---@param label string
---@return table|nil
local function find_item(items, label)
    for _, item in ipairs(items) do
        if item.label == label then
            return item
        end
    end
    return nil
end

local T = new_set({
    hooks = {
        pre_once = function()
            -- Create test directory structure
            vim.fn.mkdir(test_root, 'p')
            vim.fn.mkdir(test_root .. '/subdir', 'p')
            vim.fn.mkdir(test_root .. '/another', 'p')

            -- Create test files with various extensions
            local files = {
                { test_root .. '/note1.md', '# Note 1\n\nFirst note.' },
                { test_root .. '/note2.md', '# Note 2\n\nSecond note.' },
                { test_root .. '/subdir/nested.md', '# Nested\n\nNested note.' },
                { test_root .. '/another/deep.md', '# Deep\n\nDeep note.' },
                { test_root .. '/report.rmd', '# Report\n\nR markdown.' },
                { test_root .. '/not-notebook.txt', 'Plain text file.' },
                { test_root .. '/subdir/script.lua', 'return {}' },
            }
            for _, entry in ipairs(files) do
                local f = io.open(entry[1], 'w')
                f:write(entry[2])
                f:close()
            end
        end,
        post_once = function()
            child.stop()
            vim.fn.delete(test_root, 'rf')
        end,
    },
})

-- =============================================================================
-- get_files_items: relative paths
-- =============================================================================
T['get_files_items'] = new_set()

T['get_files_items']['includes subdirectory in link path'] = function()
    setup_cmp_child([[{
        modules = { cmp = true },
        links = { transform_on_create = false },
        silent = true,
    }]])
    local items = complete_items()
    local nested = find_item(items, 'nested')
    -- insertText should contain the relative path with subdirectory, not just basename
    eq(type(nested), 'table')
    eq(nested.insertText, '[nested](subdir/nested.md)')
end

T['get_files_items']['root-level file has no directory prefix'] = function()
    setup_cmp_child([[{
        modules = { cmp = true },
        links = { transform_on_create = false },
        silent = true,
    }]])
    local items = complete_items()
    local note1 = find_item(items, 'note1')
    eq(type(note1), 'table')
    eq(note1.insertText, '[note1](note1.md)')
end

T['get_files_items']['does not apply transform_on_create to existing files'] = function()
    setup_cmp_child([[{
        modules = { cmp = true },
        links = {
            transform_on_create = function(text)
                return 'TRANSFORMED_' .. text
            end,
        },
        silent = true,
    }]])
    local items = complete_items()
    local note1 = find_item(items, 'note1')
    eq(type(note1), 'table')
    -- The path should be the real filename, NOT 'TRANSFORMED_note1.md'
    eq(note1.insertText, '[note1](note1.md)')
end

T['get_files_items']['finds files in all subdirectories'] = function()
    setup_cmp_child([[{
        modules = { cmp = true },
        links = { transform_on_create = false },
        silent = true,
    }]])
    local items = complete_items()
    -- Should find note1, note2, nested, deep (4 .md files) plus report (.rmd)
    local nested = find_item(items, 'nested')
    local deep = find_item(items, 'deep')
    eq(type(nested), 'table')
    eq(type(deep), 'table')
end

-- =============================================================================
-- get_files_items: notebook extensions
-- =============================================================================
T['notebook_extensions'] = new_set()

T['notebook_extensions']['includes rmd files by default'] = function()
    setup_cmp_child([[{
        modules = { cmp = true },
        links = { transform_on_create = false },
        silent = true,
    }]])
    local items = complete_items()
    local report = find_item(items, 'report')
    eq(type(report), 'table')
    eq(report.insertText, '[report](report.rmd)')
end

T['notebook_extensions']['excludes non-notebook files'] = function()
    setup_cmp_child([[{
        modules = { cmp = true },
        links = { transform_on_create = false },
        silent = true,
    }]])
    local items = complete_items()
    -- .txt and .lua files should not appear
    for _, item in ipairs(items) do
        eq(item.label ~= 'not-notebook', true)
        eq(item.label ~= 'script', true)
    end
end

T['notebook_extensions']['excludes rmd when disabled'] = function()
    setup_cmp_child([[{
        modules = { cmp = true },
        filetypes = { markdown = true, rmd = false },
        links = { transform_on_create = false },
        silent = true,
    }]])
    local items = complete_items()
    local report = find_item(items, 'report')
    eq(report, nil)
end

-- =============================================================================
-- get_files_items: implicit_extension
-- =============================================================================
T['implicit_extension'] = new_set()

T['implicit_extension']['strips extension when implicit_extension is set'] = function()
    setup_cmp_child([[{
        modules = { cmp = true },
        links = { transform_on_create = false, implicit_extension = 'md' },
        silent = true,
    }]])
    local items = complete_items()
    local note1 = find_item(items, 'note1')
    eq(type(note1), 'table')
    -- With implicit_extension, the path should have no extension
    eq(note1.insertText, '[note1](note1)')
end

T['implicit_extension']['strips extension from subdirectory paths'] = function()
    setup_cmp_child([[{
        modules = { cmp = true },
        links = { transform_on_create = false, implicit_extension = 'md' },
        silent = true,
    }]])
    local items = complete_items()
    local nested = find_item(items, 'nested')
    eq(type(nested), 'table')
    eq(nested.insertText, '[nested](subdir/nested)')
end

T['implicit_extension']['keeps extension when implicit_extension is nil'] = function()
    setup_cmp_child([[{
        modules = { cmp = true },
        links = { transform_on_create = false, implicit_extension = nil },
        silent = true,
    }]])
    local items = complete_items()
    local note1 = find_item(items, 'note1')
    eq(type(note1), 'table')
    eq(note1.insertText, '[note1](note1.md)')
end

-- =============================================================================
-- get_files_items: link style
-- =============================================================================
T['link_style'] = new_set()

T['link_style']['uses markdown style by default'] = function()
    setup_cmp_child([[{
        modules = { cmp = true },
        links = { transform_on_create = false },
        silent = true,
    }]])
    local items = complete_items()
    local note1 = find_item(items, 'note1')
    eq(type(note1), 'table')
    eq(note1.insertText, '[note1](note1.md)')
end

T['link_style']['uses wiki style when configured'] = function()
    setup_cmp_child([[{
        modules = { cmp = true },
        links = { style = 'wiki', transform_on_create = false },
        silent = true,
    }]])
    local items = complete_items()
    local note1 = find_item(items, 'note1')
    eq(type(note1), 'table')
    eq(note1.insertText, '[[note1.md|note1]]')
end

T['link_style']['wiki style includes subdirectory path'] = function()
    setup_cmp_child([[{
        modules = { cmp = true },
        links = { style = 'wiki', transform_on_create = false },
        silent = true,
    }]])
    local items = complete_items()
    local nested = find_item(items, 'nested')
    eq(type(nested), 'table')
    eq(nested.insertText, '[[subdir/nested.md|nested]]')
end

T['link_style']['compact wiki style omits path'] = function()
    setup_cmp_child([[{
        modules = { cmp = true },
        links = { style = 'wiki', compact = true, transform_on_create = false },
        silent = true,
    }]])
    local items = complete_items()
    local note1 = find_item(items, 'note1')
    eq(type(note1), 'table')
    eq(note1.insertText, '[[note1]]')
end

-- =============================================================================
-- get_files_items: base directory fallback
-- =============================================================================
T['base_directory'] = new_set()

T['base_directory']['falls back to initial_dir with default config'] = function()
    -- Default path_resolution.primary is 'first', so it should use initial_dir
    setup_cmp_child([[{
        modules = { cmp = true },
        links = { transform_on_create = false },
        silent = true,
    }]])
    local items = complete_items()
    -- Should find files (proves the base directory was resolved correctly)
    local note1 = find_item(items, 'note1')
    eq(type(note1), 'table')
end

T['base_directory']['returns empty when scanning empty directory'] = function()
    local empty_dir = vim.fn.tempname()
    vim.fn.mkdir(empty_dir, 'p')

    child.restart({ '-u', 'scripts/minimal_init.lua' })
    child.lua('_G._empty_dir = "' .. empty_dir .. '"')
    child.lua([[
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
        vim.api.nvim_buf_set_name(0, _G._empty_dir .. '/test.md')
        vim.bo.filetype = 'markdown'
        require('mkdnflow').setup({
            modules = { cmp = true },
            links = { transform_on_create = false },
            silent = true,
        })
    ]])
    local items = complete_items()
    eq(#items, 0)

    vim.fn.delete(empty_dir, 'rf')
end

-- =============================================================================
-- get_files_items: documentation preview
-- =============================================================================
T['documentation'] = new_set()

T['documentation']['includes file preview in documentation'] = function()
    setup_cmp_child([[{
        modules = { cmp = true },
        links = { transform_on_create = false },
        silent = true,
    }]])
    local items = complete_items()
    local note1 = find_item(items, 'note1')
    eq(type(note1), 'table')
    eq(type(note1.documentation), 'table')
    eq(note1.documentation.kind, 'markdown')
    -- Should contain the file's content
    eq(note1.documentation.value:match('# Note 1') ~= nil, true)
end

-- =============================================================================
-- source:complete trigger filtering
-- =============================================================================
T['trigger'] = new_set()

T['trigger']['returns empty without @ trigger'] = function()
    setup_cmp_child([[{
        modules = { cmp = true },
        links = { transform_on_create = false },
        silent = true,
    }]])
    child.lua([[
        local params = { context = { cursor_before_line = 'no trigger here' } }
        _G._registered_source:complete(params, function(items)
            _G._complete_items = items
        end)
    ]])
    local items = child.lua_get('_G._complete_items')
    eq(#items, 0)
end

-- =============================================================================
-- parse_bib (via source:complete) with mock cmp
-- =============================================================================
T['parse_bib'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
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
    child.restart({ '-u', 'scripts/minimal_init.lua' })
    child.lua([[
        _success = pcall(function()
            package.loaded['cmp'] = {
                lsp = {
                    CompletionItemKind = { File = 17, Reference = 18 },
                    MarkupKind = { Markdown = 'markdown' },
                },
                register_source = function() end,
            }
            vim.api.nvim_buf_set_name(0, 'test.md')
            vim.bo.filetype = 'markdown'
            require('mkdnflow').setup({
                modules = { cmp = true },
                silent = true,
            })
        end)
    ]])
    eq(child.lua_get('_success'), true)
end

T['integration']['cmp module disabled by default'] = function()
    child.restart({ '-u', 'scripts/minimal_init.lua' })
    child.lua([[
        vim.api.nvim_buf_set_name(0, 'test.md')
        vim.bo.filetype = 'markdown'
        require('mkdnflow').setup({ silent = true })
    ]])
    local cmp_enabled = child.lua_get('require("mkdnflow").config.modules.cmp')
    eq(cmp_enabled, false)
end

return T
