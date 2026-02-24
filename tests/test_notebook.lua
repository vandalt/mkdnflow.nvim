-- tests/test_notebook.lua
-- Tests for notebook primitives (cross-file scanning)

local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

-- =============================================================================
-- Temp directory fixture
-- =============================================================================

--- Set up the shared temp directory structure in the child process.
local function setup_tmpdir()
    child.lua([=[
        _G._tmpdir = vim.fn.resolve(vim.fn.tempname())
        vim.fn.mkdir(_G._tmpdir .. '/subdir', 'p')
        vim.fn.mkdir(_G._tmpdir .. '/deep/nested', 'p')

        vim.fn.writefile({
            '---',
            'title: Note 1',
            '---',
            '# Heading One',
            '',
            'Some text with a [link to note2](note2.md).',
            '',
            '## Sub Heading',
            '',
            'More text and [external](https://example.com).',
            '',
            '```',
            '# Not a heading (in code fence)',
            '```',
            '',
            '### Deep Heading',
        }, _G._tmpdir .. '/note1.md')

        vim.fn.writefile({
            '# Note Two',
            '',
            '[back to note1](note1.md#heading-one)',
            '',
            '![an image](image.png)',
        }, _G._tmpdir .. '/note2.md')

        vim.fn.writefile({
            '# Nested Note',
            '',
            '[[note1|Note One]]',
            '[[note2]]',
        }, _G._tmpdir .. '/subdir/nested.md')

        vim.fn.writefile({
            '# Deep Note',
            '',
            'Very deep content.',
        }, _G._tmpdir .. '/deep/nested/deep.md')

        vim.fn.writefile({
            '# R Markdown',
            '',
            'Analysis content.',
        }, _G._tmpdir .. '/readme.rmd')

        vim.fn.writefile({
            'This is a text file.',
            'It should be ignored.',
        }, _G._tmpdir .. '/ignore.txt')

        vim.fn.writefile({}, _G._tmpdir .. '/empty.md')
    ]=])
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
                        style = 'markdown',
                        transform_on_create = false,
                        transform_on_follow = false,
                    },
                })
            ]])
            setup_tmpdir()
        end,
        post_once = child.stop,
    },
})

-- =============================================================================
-- readFileSync
-- =============================================================================
T['readFileSync'] = new_set()

T['readFileSync']['reads known file content'] = function()
    local lines =
        child.lua_get([[require('mkdnflow.notebook').readFileSync(_G._tmpdir .. '/note2.md')]])
    eq(lines[1], '# Note Two')
    eq(lines[3], '[back to note1](note1.md#heading-one)')
end

T['readFileSync']['returns nil for missing file'] = function()
    local result = child.lua_get(
        [[require('mkdnflow.notebook').readFileSync(_G._tmpdir .. '/nonexistent.md')]]
    )
    eq(result, vim.NIL)
end

T['readFileSync']['handles empty file'] = function()
    local lines =
        child.lua_get([[require('mkdnflow.notebook').readFileSync(_G._tmpdir .. '/empty.md')]])
    eq(type(lines), 'table')
    -- vim.fn.readfile on a file written with writefile({}) returns {}
    eq(#lines, 0)
end

-- =============================================================================
-- scanFilesSync
-- =============================================================================
T['scanFilesSync'] = new_set()

T['scanFilesSync']['finds md and rmd files'] = function()
    local count = child.lua_get([[#require('mkdnflow.notebook').scanFilesSync(_G._tmpdir)]])
    -- note1.md, note2.md, empty.md, subdir/nested.md, deep/nested/deep.md, readme.rmd
    eq(count, 6)
end

T['scanFilesSync']['excludes non-notebook extensions'] = function()
    child.lua([[
        _G._has_txt = false
        for _, f in ipairs(require('mkdnflow.notebook').scanFilesSync(_G._tmpdir)) do
            if f:match('%.txt$') then _G._has_txt = true end
        end
    ]])
    eq(child.lua_get('_G._has_txt'), false)
end

T['scanFilesSync']['respects custom extensions'] = function()
    child.lua([[
        _G._count = #require('mkdnflow.notebook').scanFilesSync(_G._tmpdir, {
            extensions = { txt = true }
        })
    ]])
    eq(child.lua_get('_G._count'), 1)
end

T['scanFilesSync']['respects max_depth'] = function()
    child.lua([[
        _G._count = #require('mkdnflow.notebook').scanFilesSync(_G._tmpdir, { max_depth = 0 })
    ]])
    -- Root only: empty.md, note1.md, note2.md, readme.rmd
    eq(child.lua_get('_G._count'), 4)
end

T['scanFilesSync']['returns empty for nonexistent directory'] = function()
    local files =
        child.lua_get([[require('mkdnflow.notebook').scanFilesSync(_G._tmpdir .. '/nonexistent')]])
    eq(type(files), 'table')
    eq(#files, 0)
end

T['scanFilesSync']['supports predicate filter'] = function()
    child.lua([[
        _G._count = #require('mkdnflow.notebook').scanFilesSync(_G._tmpdir, {
            predicate = function(name) return name:match('^note') ~= nil end
        })
    ]])
    eq(child.lua_get('_G._count'), 2)
end

T['scanFilesSync']['deduplicates symlinked files'] = function()
    child.lua([[
        -- Create a symlink to note1.md
        vim.uv.fs_symlink(_G._tmpdir .. '/note1.md', _G._tmpdir .. '/symlink_note1.md')
        _G._count = #require('mkdnflow.notebook').scanFilesSync(_G._tmpdir)
    ]])
    -- Should still be 6 (symlink resolves to same realpath as note1.md)
    local count = child.lua_get('_G._count')
    eq(count, 6)
end

-- =============================================================================
-- scanHeadings
-- =============================================================================
T['scanHeadings'] = new_set()

T['scanHeadings']['finds headings with correct levels and text'] = function()
    child.lua([[
        local nb = require('mkdnflow.notebook')
        local lines = nb.readFileSync(_G._tmpdir .. '/note1.md')
        _G._headings = nb.scanHeadings(lines)
    ]])
    local headings = child.lua_get('_G._headings')
    -- note1.md has: # Heading One, ## Sub Heading, ### Deep Heading
    eq(#headings, 3)
    eq(headings[1].level, 1)
    eq(headings[1].text, 'Heading One')
    eq(headings[2].level, 2)
    eq(headings[2].text, 'Sub Heading')
    eq(headings[3].level, 3)
    eq(headings[3].text, 'Deep Heading')
end

T['scanHeadings']['computes anchors by default'] = function()
    child.lua([[
        local nb = require('mkdnflow.notebook')
        local lines = nb.readFileSync(_G._tmpdir .. '/note1.md')
        _G._headings = nb.scanHeadings(lines)
    ]])
    local headings = child.lua_get('_G._headings')
    eq(headings[1].anchor, '#heading-one')
    eq(headings[2].anchor, '#sub-heading')
    eq(headings[3].anchor, '#deep-heading')
end

T['scanHeadings']['skips anchors when with_anchor=false'] = function()
    child.lua([[
        local nb = require('mkdnflow.notebook')
        local lines = nb.readFileSync(_G._tmpdir .. '/note1.md')
        _G._headings = nb.scanHeadings(lines, { with_anchor = false })
    ]])
    local headings = child.lua_get('_G._headings')
    -- nil values are absent from tables retrieved via lua_get
    eq(headings[1].anchor, nil)
end

T['scanHeadings']['skips frontmatter'] = function()
    child.lua([[
        local nb = require('mkdnflow.notebook')
        local lines = nb.readFileSync(_G._tmpdir .. '/note1.md')
        _G._texts = {}
        for _, h in ipairs(nb.scanHeadings(lines)) do
            table.insert(_G._texts, h.text)
        end
    ]])
    local texts = child.lua_get('_G._texts')
    for _, text in ipairs(texts) do
        eq(text ~= 'title: Note 1', true)
    end
end

T['scanHeadings']['skips headings in code fences'] = function()
    child.lua([[
        local nb = require('mkdnflow.notebook')
        local lines = nb.readFileSync(_G._tmpdir .. '/note1.md')
        _G._texts = {}
        for _, h in ipairs(nb.scanHeadings(lines)) do
            table.insert(_G._texts, h.text)
        end
    ]])
    local texts = child.lua_get('_G._texts')
    for _, text in ipairs(texts) do
        eq(text ~= 'Not a heading (in code fence)', true)
    end
end

T['scanHeadings']['handles empty input'] = function()
    local headings = child.lua_get([[require('mkdnflow.notebook').scanHeadings({})]])
    eq(type(headings), 'table')
    eq(#headings, 0)
end

T['scanHeadings']['includes correct row numbers'] = function()
    child.lua([[
        local nb = require('mkdnflow.notebook')
        local lines = nb.readFileSync(_G._tmpdir .. '/note1.md')
        _G._headings = nb.scanHeadings(lines)
    ]])
    local headings = child.lua_get('_G._headings')
    -- note1.md: lines 1-3 are frontmatter, line 4 is "# Heading One"
    eq(headings[1].row, 4)
end

-- =============================================================================
-- scanLinks
-- =============================================================================
T['scanLinks'] = new_set()

T['scanLinks']['finds markdown links'] = function()
    child.lua([[
        local nb = require('mkdnflow.notebook')
        local lines = nb.readFileSync(_G._tmpdir .. '/note1.md')
        _G._links = nb.scanLinks(lines)
    ]])
    local links = child.lua_get('_G._links')
    eq(type(links), 'table')
    local md_count = 0
    for _, l in ipairs(links) do
        if l.type == 'md_link' then
            md_count = md_count + 1
        end
    end
    eq(md_count >= 2, true)
end

T['scanLinks']['extracts source and anchor'] = function()
    child.lua([[
        local nb = require('mkdnflow.notebook')
        local lines = nb.readFileSync(_G._tmpdir .. '/note2.md')
        _G._links = nb.scanLinks(lines)
    ]])
    local links = child.lua_get('_G._links')
    -- note2.md line 3: [back to note1](note1.md#heading-one)
    local found = false
    for _, l in ipairs(links) do
        if l.source == 'note1.md' and l.anchor == '#heading-one' then
            found = true
        end
    end
    eq(found, true)
end

T['scanLinks']['finds image links'] = function()
    child.lua([[
        local nb = require('mkdnflow.notebook')
        local lines = nb.readFileSync(_G._tmpdir .. '/note2.md')
        _G._images = {}
        for _, l in ipairs(nb.scanLinks(lines)) do
            if l.type == 'image_link' then
                table.insert(_G._images, l)
            end
        end
    ]])
    local images = child.lua_get('_G._images')
    eq(#images, 1)
    eq(images[1].source, 'image.png')
end

T['scanLinks']['finds wiki links'] = function()
    child.lua([[
        local nb = require('mkdnflow.notebook')
        local lines = nb.readFileSync(_G._tmpdir .. '/subdir/nested.md')
        _G._wikis = {}
        for _, l in ipairs(nb.scanLinks(lines)) do
            if l.type == 'wiki_link' then
                table.insert(_G._wikis, l)
            end
        end
    ]])
    local wikis = child.lua_get('_G._wikis')
    eq(#wikis, 2)
end

T['scanLinks']['supports type filter'] = function()
    child.lua([[
        local nb = require('mkdnflow.notebook')
        local lines = nb.readFileSync(_G._tmpdir .. '/note2.md')
        _G._filtered = nb.scanLinks(lines, { types = { md_link = true } })
    ]])
    local links = child.lua_get('_G._filtered')
    for _, l in ipairs(links) do
        eq(l.type, 'md_link')
    end
end

T['scanLinks']['skips frontmatter and code fences'] = function()
    child.lua([[
        local nb = require('mkdnflow.notebook')
        _G._filtered = nb.scanLinks({
            '---',
            'link: [fm](fm.md)',
            '---',
            '# Heading',
            '[real](real.md)',
            '```',
            '[code](code.md)',
            '```',
            '[also real](also.md)',
        })
    ]])
    local links = child.lua_get('_G._filtered')
    -- Should only find [real](real.md) and [also real](also.md)
    eq(#links, 2)
end

T['scanLinks']['handles empty input'] = function()
    local links = child.lua_get([[require('mkdnflow.notebook').scanLinks({})]])
    eq(type(links), 'table')
    eq(#links, 0)
end

-- =============================================================================
-- readFile (async)
-- =============================================================================
T['readFile'] = new_set()

T['readFile']['returns same content as readFileSync'] = function()
    child.lua([[
        local nb = require('mkdnflow.notebook')
        _G._async_result = 'pending'
        nb.readFile(_G._tmpdir .. '/note2.md', function(lines)
            vim.schedule(function()
                _G._async_result = lines
            end)
        end)
    ]])
    child.lua([[vim.wait(5000, function() return _G._async_result ~= 'pending' end)]])
    local async_lines = child.lua_get('_G._async_result')
    local sync_lines =
        child.lua_get([[require('mkdnflow.notebook').readFileSync(_G._tmpdir .. '/note2.md')]])
    eq(async_lines, sync_lines)
end

T['readFile']['returns nil for missing file'] = function()
    child.lua([[
        local nb = require('mkdnflow.notebook')
        _G._async_result = 'pending'
        nb.readFile(_G._tmpdir .. '/nonexistent.md', function(lines)
            vim.schedule(function()
                _G._async_result = lines or 'nil_value'
            end)
        end)
    ]])
    child.lua([[vim.wait(5000, function() return _G._async_result ~= 'pending' end)]])
    local result = child.lua_get('_G._async_result')
    eq(result, 'nil_value')
end

-- =============================================================================
-- scanFiles (async)
-- =============================================================================
T['scanFiles'] = new_set()

T['scanFiles']['finds same files as scanFilesSync'] = function()
    child.lua([[
        local nb = require('mkdnflow.notebook')
        _G._async_result = 'pending'
        nb.scanFiles(_G._tmpdir, {}, function(files)
            vim.schedule(function()
                table.sort(files)
                _G._async_result = files
            end)
        end)
    ]])
    child.lua([[vim.wait(5000, function() return _G._async_result ~= 'pending' end)]])
    child.lua([[
        local sync = require('mkdnflow.notebook').scanFilesSync(_G._tmpdir)
        table.sort(sync)
        _G._sync_result = sync
    ]])
    local async_files = child.lua_get('_G._async_result')
    local sync_files = child.lua_get('_G._sync_result')
    eq(#async_files, #sync_files)
    for i, f in ipairs(sync_files) do
        eq(async_files[i], f)
    end
end

T['scanFiles']['supports 2-arg form'] = function()
    child.lua([[
        local nb = require('mkdnflow.notebook')
        _G._async_result = 'pending'
        nb.scanFiles(_G._tmpdir, function(files)
            vim.schedule(function()
                _G._async_result = #files
            end)
        end)
    ]])
    child.lua([[vim.wait(5000, function() return _G._async_result ~= 'pending' end)]])
    local count = child.lua_get('_G._async_result')
    eq(count, 6)
end

T['scanFiles']['deduplicates symlinked files'] = function()
    child.lua([[
        vim.uv.fs_symlink(_G._tmpdir .. '/note1.md', _G._tmpdir .. '/async_symlink.md')
        local nb = require('mkdnflow.notebook')
        _G._async_result = 'pending'
        nb.scanFiles(_G._tmpdir, function(files)
            vim.schedule(function()
                _G._async_result = #files
            end)
        end)
    ]])
    child.lua([[vim.wait(5000, function() return _G._async_result ~= 'pending' end)]])
    local count = child.lua_get('_G._async_result')
    -- Should still be 6 (symlink resolves to same realpath as note1.md)
    eq(count, 6)
end

return T
