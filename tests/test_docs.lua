-- tests/test_docs.lua
-- Tests for documentation validation

local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local T = new_set()

-- =============================================================================
-- Vimdoc help tag validation
-- =============================================================================
T['vimdoc'] = new_set()

T['vimdoc']['has no duplicate help tags'] = function()
    -- Read the vimdoc file
    local doc_path = vim.fn.fnamemodify('doc/mkdnflow.txt', ':p')
    local file = io.open(doc_path, 'r')
    if not file then
        error('Could not open doc/mkdnflow.txt')
    end

    local tags = {}
    local duplicates = {}

    -- Process line by line to find help tags
    -- Vimdoc help tags are *tag-name* at end of lines or start of lines
    for line in file:lines() do
        -- Match help tags at end of line: *tag-name* followed by optional whitespace
        local tag = line:match('%*([%w%-%.]+)%*%s*$')
        if tag then
            if tags[tag] then
                table.insert(duplicates, tag)
            else
                tags[tag] = true
            end
        end
        -- Also match tags at start of line (like the title)
        tag = line:match('^%*([%w%-%.]+)%*')
        if tag then
            if tags[tag] then
                table.insert(duplicates, tag)
            else
                tags[tag] = true
            end
        end
    end
    file:close()

    if #duplicates > 0 then
        error('Duplicate help tags found: ' .. table.concat(duplicates, ', '))
    end
end

T['vimdoc']['file exists'] = function()
    local doc_path = vim.fn.fnamemodify('doc/mkdnflow.txt', ':p')
    local file = io.open(doc_path, 'r')
    eq(file ~= nil, true)
    if file then
        file:close()
    end
end

T['vimdoc']['has required standard tags'] = function()
    -- Read the vimdoc file
    local doc_path = vim.fn.fnamemodify('doc/mkdnflow.txt', ':p')
    local file = io.open(doc_path, 'r')
    if not file then
        error('Could not open doc/mkdnflow.txt')
    end
    local content = file:read('*all')
    file:close()

    -- Check for essential tags that should always exist
    local required_tags = {
        'Mkdnflow.nvim', -- Main plugin tag
        'mkdnflow-reference', -- Reference section
        'Mkdnflow-api', -- API section
    }

    for _, tag in ipairs(required_tags) do
        local pattern = '%*' .. tag:gsub('%-', '%%-'):gsub('%.', '%%.') .. '%*'
        if not content:match(pattern) then
            error('Missing required help tag: *' .. tag .. '*')
        end
    end
end

return T
