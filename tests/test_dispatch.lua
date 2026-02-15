-- tests/test_dispatch.lua
-- Tests for the :Mkdnflow subcommand dispatcher

local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local T = new_set()

-- =============================================================================
-- Unit tests: completion and internal helpers (no child Neovim needed)
-- =============================================================================

local dispatch = require('mkdnflow.dispatch')

T['unit'] = new_set()

-- -----------------------------------------------------------------------------
-- parseCmdlineArgs
-- -----------------------------------------------------------------------------
T['unit']['parseCmdlineArgs'] = new_set()

T['unit']['parseCmdlineArgs']['empty command'] = function()
    eq(dispatch._parseCmdlineArgs('Mkdnflow'), {})
end

T['unit']['parseCmdlineArgs']['single group'] = function()
    eq(dispatch._parseCmdlineArgs('Mkdnflow link'), { 'link' })
end

T['unit']['parseCmdlineArgs']['group and action'] = function()
    eq(dispatch._parseCmdlineArgs('Mkdnflow link follow'), { 'link', 'follow' })
end

T['unit']['parseCmdlineArgs']['group action and args'] = function()
    eq(dispatch._parseCmdlineArgs('Mkdnflow link create markdown'), { 'link', 'create', 'markdown' })
end

T['unit']['parseCmdlineArgs']['handles range prefix'] = function()
    eq(dispatch._parseCmdlineArgs("'<,'>Mkdnflow todo toggle"), { 'todo', 'toggle' })
end

T['unit']['parseCmdlineArgs']['handles numeric range prefix'] = function()
    eq(dispatch._parseCmdlineArgs('1,5Mkdnflow todo toggle'), { 'todo', 'toggle' })
end

-- -----------------------------------------------------------------------------
-- resolveAction
-- -----------------------------------------------------------------------------
T['unit']['resolveAction'] = new_set()

T['unit']['resolveAction']['finds exact match'] = function()
    local group = dispatch._groups.link
    local entry = dispatch._resolveAction(group, 'follow')
    eq(entry.cmd, 'MkdnFollowLink')
end

T['unit']['resolveAction']['returns nil for unknown action'] = function()
    local group = dispatch._groups.link
    local entry = dispatch._resolveAction(group, 'nonexistent')
    eq(entry, nil)
end

T['unit']['resolveAction']['returns _default when no action name given'] = function()
    local group = dispatch._groups.start
    local entry = dispatch._resolveAction(group, nil)
    eq(entry.cmd, '_forceStart')
end

T['unit']['resolveAction']['returns nil for multi-action group with no action name'] = function()
    local group = dispatch._groups.link
    local entry = dispatch._resolveAction(group, nil)
    eq(entry, nil)
end

-- -----------------------------------------------------------------------------
-- complete
-- -----------------------------------------------------------------------------
T['unit']['complete'] = new_set()

T['unit']['complete']['empty input returns all groups'] = function()
    local result = dispatch.complete('', 'Mkdnflow ', 10)
    -- Should contain all groups
    local has_link = vim.tbl_contains(result, 'link')
    local has_table = vim.tbl_contains(result, 'table')
    local has_todo = vim.tbl_contains(result, 'todo')
    local has_start = vim.tbl_contains(result, 'start')
    eq(has_link, true)
    eq(has_table, true)
    eq(has_todo, true)
    eq(has_start, true)
end

T['unit']['complete']['partial group filters correctly'] = function()
    local result = dispatch.complete('li', 'Mkdnflow li', 12)
    eq(vim.tbl_contains(result, 'link'), true)
    eq(vim.tbl_contains(result, 'list'), true)
    eq(vim.tbl_contains(result, 'table'), false)
end

T['unit']['complete']['full group returns action names'] = function()
    local result = dispatch.complete('', 'Mkdnflow link ', 15)
    eq(vim.tbl_contains(result, 'follow'), true)
    eq(vim.tbl_contains(result, 'create'), true)
    eq(vim.tbl_contains(result, 'destroy'), true)
end

T['unit']['complete']['partial action filters correctly'] = function()
    local result = dispatch.complete('cr', 'Mkdnflow link cr', 17)
    eq(vim.tbl_contains(result, 'create'), true)
    eq(vim.tbl_contains(result, 'create-from-clipboard'), true)
    eq(vim.tbl_contains(result, 'follow'), false)
end

T['unit']['complete']['action-specific completion for style'] = function()
    local result = dispatch.complete('', 'Mkdnflow link create ', 22)
    eq(vim.tbl_contains(result, 'markdown'), true)
    eq(vim.tbl_contains(result, 'wiki'), true)
end

T['unit']['complete']['action-specific completion for list type'] = function()
    local result = dispatch.complete('', 'Mkdnflow list change-type ', 27)
    eq(vim.tbl_contains(result, 'ul'), true)
    eq(vim.tbl_contains(result, 'ol'), true)
    eq(vim.tbl_contains(result, 'ultd'), true)
    eq(vim.tbl_contains(result, 'oltd'), true)
end

T['unit']['complete']['single-action group returns no actions'] = function()
    local result = dispatch.complete('', 'Mkdnflow start ', 16)
    eq(#result, 0)
end

T['unit']['complete']['unknown group returns empty'] = function()
    local result = dispatch.complete('', 'Mkdnflow nonexistent ', 22)
    eq(#result, 0)
end

T['unit']['complete']['handles range prefix'] = function()
    local result = dispatch.complete('', "'<,'>Mkdnflow ", 15)
    local has_link = vim.tbl_contains(result, 'link')
    eq(has_link, true)
end

-- -----------------------------------------------------------------------------
-- groups table: sanity checks
-- -----------------------------------------------------------------------------
T['unit']['groups'] = new_set()

T['unit']['groups']['all groups have descriptions'] = function()
    for name, _ in pairs(dispatch._groups) do
        -- Check that every group entry has action, cmd, and desc fields
        for _, entry in ipairs(dispatch._groups[name]) do
            eq(type(entry.action), 'string')
            eq(type(entry.cmd), 'string')
            eq(type(entry.desc), 'string')
        end
    end
end

T['unit']['groups']['cmd references are valid command names or sentinels'] = function()
    for _, group in pairs(dispatch._groups) do
        for _, entry in ipairs(group) do
            -- Must start with 'Mkdn' or be the '_forceStart' sentinel
            local valid = entry.cmd:match('^Mkdn') ~= nil or entry.cmd == '_forceStart'
            eq(valid, true)
        end
    end
end

-- =============================================================================
-- Integration tests: dispatch through child Neovim
-- =============================================================================

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

-- Helper to capture vim.notify messages in the child
local function setup_notify_capture()
    child.lua([[
        _G._notifications = {}
        _G._orig_notify = vim.notify
        vim.notify = function(msg, level, opts)
            table.insert(_G._notifications, { msg = msg, level = level })
            _G._orig_notify(msg, level, opts)
        end
    ]])
end

-- Helper to restore vim.notify
local function restore_notify()
    child.lua([[
        if _G._orig_notify then
            vim.notify = _G._orig_notify
        end
    ]])
end

T['integration'] = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                vim.cmd('runtime plugin/mkdnflow.lua')
                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
                require('mkdnflow').setup({})
                vim.cmd('doautocmd BufEnter')
            ]])
        end,
        post_once = child.stop,
    },
})

-- -----------------------------------------------------------------------------
-- Deprecation: bare :Mkdnflow
-- -----------------------------------------------------------------------------
T['integration']['deprecation'] = new_set()

T['integration']['deprecation']['no args shows deprecation warning'] = function()
    setup_notify_capture()
    -- forceStart will error ("already running") after the deprecation warning,
    -- so use pcall to let it finish
    child.lua([[pcall(vim.cmd, 'Mkdnflow')]])
    local notifications = child.lua_get('_G._notifications')
    local found = false
    for _, n in ipairs(notifications) do
        if n.msg:find('deprecated') then
            found = true
        end
    end
    eq(found, true)
    restore_notify()
end

T['integration']['deprecation']['silent arg shows deprecation warning'] = function()
    setup_notify_capture()
    child.lua([[pcall(vim.cmd, 'Mkdnflow silent')]])
    local notifications = child.lua_get('_G._notifications')
    local found = false
    for _, n in ipairs(notifications) do
        if n.msg:find('deprecated') then
            found = true
        end
    end
    eq(found, true)
    restore_notify()
end

T['integration']['deprecation']['unknown group shows deprecation warning'] = function()
    setup_notify_capture()
    child.lua([[pcall(vim.cmd, 'Mkdnflow somethingwrong')]])
    local notifications = child.lua_get('_G._notifications')
    local found = false
    for _, n in ipairs(notifications) do
        if n.msg:find('deprecated') then
            found = true
        end
    end
    eq(found, true)
    restore_notify()
end

-- -----------------------------------------------------------------------------
-- Dispatch: start subcommand
-- -----------------------------------------------------------------------------
T['integration']['start'] = new_set()

T['integration']['start']['Mkdnflow start works'] = function()
    -- Reset loaded state so forceStart has something to do
    child.lua([[
        -- forceStart will say "already running" since setup() was called;
        -- just verify it doesn't error
        _G._notifications = {}
        _G._orig_notify = vim.notify
        vim.notify = function(msg, level, opts)
            table.insert(_G._notifications, { msg = msg, level = level })
        end
        vim.cmd('Mkdnflow start')
    ]])
    -- Should get the "already running" message, not an error
    local notifications = child.lua_get('_G._notifications')
    local found_already = false
    for _, n in ipairs(notifications) do
        if n.msg:find('already running') then
            found_already = true
        end
    end
    eq(found_already, true)
    restore_notify()
end

-- -----------------------------------------------------------------------------
-- Dispatch: todo toggle
-- -----------------------------------------------------------------------------
T['integration']['todo toggle'] = new_set()

T['integration']['todo toggle']['toggles a to-do item'] = function()
    set_lines({ '- [ ] task one' })
    set_cursor(1, 0)
    child.lua([[vim.cmd('Mkdnflow todo toggle')]])
    local line = get_line(1)
    -- Should have toggled to the next status (in-progress or complete)
    eq(line:match('%- %[ %]') == nil, true)
end

-- -----------------------------------------------------------------------------
-- Dispatch: heading increase
-- -----------------------------------------------------------------------------
T['integration']['heading increase'] = new_set()

T['integration']['heading increase']['increases heading level'] = function()
    -- "increase" means increase prominence (fewer #'s): ## → #
    set_lines({ '## Heading' })
    set_cursor(1, 0)
    child.lua([[vim.cmd('Mkdnflow heading increase')]])
    local line = get_line(1)
    eq(line, '# Heading')
end

-- -----------------------------------------------------------------------------
-- Dispatch: unknown action within valid group
-- -----------------------------------------------------------------------------
T['integration']['unknown action'] = new_set()

T['integration']['unknown action']['shows warning for unknown action'] = function()
    setup_notify_capture()
    child.lua([[vim.cmd('Mkdnflow link nonexistent')]])
    local notifications = child.lua_get('_G._notifications')
    local found = false
    for _, n in ipairs(notifications) do
        if n.msg:find('Unknown action') then
            found = true
        end
    end
    eq(found, true)
    restore_notify()
end

-- -----------------------------------------------------------------------------
-- Dispatch: group with no action shows help (not an error)
-- -----------------------------------------------------------------------------
T['integration']['group help'] = new_set()

T['integration']['group help']['group with no action does not error'] = function()
    -- :Mkdnflow link (no action) should show help via nvim_echo, not crash
    -- We verify by checking there's no error thrown
    child.lua([[
        local ok, _ = pcall(vim.cmd, 'Mkdnflow link')
        _G._group_help_ok = ok
    ]])
    local ok = child.lua_get('_G._group_help_ok')
    eq(ok, true)
end

-- -----------------------------------------------------------------------------
-- Dispatch: range passthrough
-- -----------------------------------------------------------------------------
T['integration']['range'] = new_set()

T['integration']['range']['range passed to todo toggle'] = function()
    set_lines({ '- [ ] task one', '- [ ] task two', '- [ ] task three' })
    child.lua([[vim.cmd('1,2Mkdnflow todo toggle')]])
    local line1 = get_line(1)
    local line2 = get_line(2)
    local line3 = get_line(3)
    -- Lines 1 and 2 should be toggled, line 3 unchanged
    eq(line1:match('%- %[ %]') == nil, true)
    eq(line2:match('%- %[ %]') == nil, true)
    eq(line3, '- [ ] task three')
end

return T
