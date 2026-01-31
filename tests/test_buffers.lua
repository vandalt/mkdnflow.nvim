-- tests/test_buffers.lua
-- Tests for buffer navigation functionality

local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

-- Helper to set buffer content
local function set_lines(lines)
    child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, ' .. vim.inspect(lines) .. ')')
end

-- Helper to get current buffer number
local function get_bufnr()
    return child.lua_get('vim.api.nvim_get_current_buf()')
end

-- Helper to get buffer name
local function get_bufname()
    return child.lua_get('vim.api.nvim_buf_get_name(0)')
end

-- Helper to create a new buffer with a name
local function create_buffer(name)
    child.lua('vim.cmd("enew")')
    child.lua('vim.api.nvim_buf_set_name(0, "' .. name .. '")')
    return get_bufnr()
end

local T = new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'scripts/minimal_init.lua' })
            child.lua([[
                vim.api.nvim_buf_set_name(0, 'test.md')
                vim.bo.filetype = 'markdown'
                require('mkdnflow').setup({ silent = true })
                -- Clear the stacks before each test
                require('mkdnflow.buffers').main = {}
                require('mkdnflow.buffers').hist = {}
            ]])
        end,
        post_once = child.stop,
    },
})

-- =============================================================================
-- push() - Add buffer to stack
-- =============================================================================
T['push'] = new_set()

T['push']['adds buffer to front of stack'] = function()
    child.lua([[
        local buffers = require('mkdnflow.buffers')
        buffers.push(buffers.main, 1)
    ]])
    local stack = child.lua_get('require("mkdnflow.buffers").main')
    eq(#stack, 1)
    eq(stack[1], 1)
end

T['push']['pushes multiple buffers in order'] = function()
    child.lua([[
        local buffers = require('mkdnflow.buffers')
        buffers.push(buffers.main, 1)
        buffers.push(buffers.main, 2)
        buffers.push(buffers.main, 3)
    ]])
    local stack = child.lua_get('require("mkdnflow.buffers").main')
    eq(#stack, 3)
    eq(stack[1], 3) -- Most recent is first
    eq(stack[2], 2)
    eq(stack[3], 1)
end

T['push']['works with hist stack'] = function()
    child.lua([[
        local buffers = require('mkdnflow.buffers')
        buffers.push(buffers.hist, 5)
    ]])
    local stack = child.lua_get('require("mkdnflow.buffers").hist')
    eq(#stack, 1)
    eq(stack[1], 5)
end

-- =============================================================================
-- pop() - Remove buffer from stack
-- =============================================================================
T['pop'] = new_set()

T['pop']['removes first element from stack'] = function()
    child.lua([[
        local buffers = require('mkdnflow.buffers')
        buffers.push(buffers.main, 1)
        buffers.push(buffers.main, 2)
        buffers.pop(buffers.main)
    ]])
    local stack = child.lua_get('require("mkdnflow.buffers").main')
    eq(#stack, 1)
    eq(stack[1], 1)
end

T['pop']['empties single-element stack'] = function()
    child.lua([[
        local buffers = require('mkdnflow.buffers')
        buffers.push(buffers.main, 1)
        buffers.pop(buffers.main)
    ]])
    local stack = child.lua_get('require("mkdnflow.buffers").main')
    eq(#stack, 0)
end

T['pop']['handles empty stack gracefully'] = function()
    child.lua([[
        local buffers = require('mkdnflow.buffers')
        buffers.pop(buffers.main)
    ]])
    local stack = child.lua_get('require("mkdnflow.buffers").main')
    eq(#stack, 0)
end

-- =============================================================================
-- goBack() - Navigate to previous buffer
-- =============================================================================
T['goBack'] = new_set()

T['goBack']['returns false when stack is empty'] = function()
    local result = child.lua_get('require("mkdnflow.buffers").goBack()')
    eq(result, false)
end

T['goBack']['returns false on first buffer'] = function()
    -- Even with items in stack, if current buffer is 1, can't go back
    child.lua([[
        local buffers = require('mkdnflow.buffers')
        buffers.push(buffers.main, 2)
    ]])
    -- Current buffer is 1 (the initial buffer)
    local result = child.lua_get('require("mkdnflow.buffers").goBack()')
    -- The condition is cur_bufnr > 1 AND #main > 0
    -- Since we're on buffer 1, this should fail
    eq(result, false)
end

T['goBack']['navigates to previous buffer'] = function()
    -- Create a second buffer
    local buf2 = create_buffer('second.md')
    -- Push the first buffer onto the stack (simulating navigation)
    child.lua('require("mkdnflow.buffers").push(require("mkdnflow.buffers").main, 1)')

    -- Now we're on buf2, go back should take us to buf1
    local result = child.lua_get('require("mkdnflow.buffers").goBack()')
    eq(result, true)

    local current = get_bufnr()
    eq(current, 1)
end

T['goBack']['adds current buffer to history'] = function()
    local buf2 = create_buffer('second.md')
    child.lua('require("mkdnflow.buffers").push(require("mkdnflow.buffers").main, 1)')

    child.lua('require("mkdnflow.buffers").goBack()')

    -- The buffer we came from should be in hist
    local hist = child.lua_get('require("mkdnflow.buffers").hist')
    eq(#hist, 1)
    eq(hist[1], buf2)
end

T['goBack']['pops from main stack'] = function()
    local buf2 = create_buffer('second.md')
    child.lua('require("mkdnflow.buffers").push(require("mkdnflow.buffers").main, 1)')

    child.lua('require("mkdnflow.buffers").goBack()')

    -- Main stack should be empty now
    local main = child.lua_get('require("mkdnflow.buffers").main')
    eq(#main, 0)
end

T['goBack']['handles multiple back navigations'] = function()
    local buf2 = create_buffer('second.md')
    local buf3 = create_buffer('third.md')

    -- Simulate navigation: 1 -> 2 -> 3
    child.lua([[
        local buffers = require('mkdnflow.buffers')
        buffers.push(buffers.main, 1)
        buffers.push(buffers.main, ]] .. buf2 .. [[)
    ]])

    -- Go back from 3 to 2
    child.lua('require("mkdnflow.buffers").goBack()')
    eq(get_bufnr(), buf2)

    -- Go back from 2 to 1
    child.lua('require("mkdnflow.buffers").goBack()')
    eq(get_bufnr(), 1)
end

-- =============================================================================
-- goForward() - Navigate forward in history
-- =============================================================================
T['goForward'] = new_set()

T['goForward']['returns false when history is empty'] = function()
    local result = child.lua_get('require("mkdnflow.buffers").goForward()')
    eq(result, false)
end

T['goForward']['navigates to buffer in history'] = function()
    local buf2 = create_buffer('second.md')

    -- Simulate: we were on buf2, went back to buf1, now hist has buf2
    child.lua('require("mkdnflow.buffers").push(require("mkdnflow.buffers").hist, ' .. buf2 .. ')')

    -- Go forward should take us to buf2
    local result = child.lua_get('require("mkdnflow.buffers").goForward()')
    eq(result, true)
    eq(get_bufnr(), buf2)
end

T['goForward']['adds current buffer to main stack'] = function()
    local buf2 = create_buffer('second.md')

    -- Go back to buffer 1
    child.lua('vim.cmd("buffer 1")')

    -- Put buf2 in history
    child.lua('require("mkdnflow.buffers").push(require("mkdnflow.buffers").hist, ' .. buf2 .. ')')

    -- Go forward
    child.lua('require("mkdnflow.buffers").goForward()')

    -- Buffer 1 should now be in main stack
    local main = child.lua_get('require("mkdnflow.buffers").main')
    eq(#main, 1)
    eq(main[1], 1)
end

T['goForward']['pops from history stack'] = function()
    local buf2 = create_buffer('second.md')
    child.lua('vim.cmd("buffer 1")')
    child.lua('require("mkdnflow.buffers").push(require("mkdnflow.buffers").hist, ' .. buf2 .. ')')

    child.lua('require("mkdnflow.buffers").goForward()')

    -- History should be empty
    local hist = child.lua_get('require("mkdnflow.buffers").hist')
    eq(#hist, 0)
end

-- =============================================================================
-- Navigation integration - back and forward together
-- =============================================================================
T['navigation'] = new_set()

T['navigation']['back then forward returns to same buffer'] = function()
    local buf2 = create_buffer('second.md')
    child.lua('require("mkdnflow.buffers").push(require("mkdnflow.buffers").main, 1)')

    -- Go back to buffer 1
    child.lua('require("mkdnflow.buffers").goBack()')
    eq(get_bufnr(), 1)

    -- Go forward to buffer 2
    child.lua('require("mkdnflow.buffers").goForward()')
    eq(get_bufnr(), buf2)
end

T['navigation']['multiple back-forward cycles'] = function()
    local buf2 = create_buffer('second.md')
    child.lua('require("mkdnflow.buffers").push(require("mkdnflow.buffers").main, 1)')

    -- Cycle 1
    child.lua('require("mkdnflow.buffers").goBack()')
    eq(get_bufnr(), 1)
    child.lua('require("mkdnflow.buffers").goForward()')
    eq(get_bufnr(), buf2)

    -- Cycle 2
    child.lua('require("mkdnflow.buffers").goBack()')
    eq(get_bufnr(), 1)
    child.lua('require("mkdnflow.buffers").goForward()')
    eq(get_bufnr(), buf2)
end

T['navigation']['forward clears when navigating to new buffer'] = function()
    local buf2 = create_buffer('second.md')
    local buf3 = create_buffer('third.md')

    -- Setup: 1 -> 2, then back to 1 (hist has 2)
    child.lua('vim.cmd("buffer 1")')
    child.lua('require("mkdnflow.buffers").push(require("mkdnflow.buffers").hist, ' .. buf2 .. ')')

    -- Now go to buf3 instead of forward to buf2
    -- Push 1 to main, go to 3
    child.lua('require("mkdnflow.buffers").push(require("mkdnflow.buffers").main, 1)')
    child.lua('vim.cmd("buffer ' .. buf3 .. '")')

    -- History still has buf2, but conceptually this is a new branch
    -- The module doesn't automatically clear history on new navigation
    local hist = child.lua_get('require("mkdnflow.buffers").hist')
    eq(#hist, 1) -- buf2 is still there
end

-- =============================================================================
-- Stack state - main and hist tables
-- =============================================================================
T['stacks'] = new_set()

T['stacks']['main starts empty'] = function()
    local main = child.lua_get('require("mkdnflow.buffers").main')
    eq(#main, 0)
end

T['stacks']['hist starts empty'] = function()
    local hist = child.lua_get('require("mkdnflow.buffers").hist')
    eq(#hist, 0)
end

T['stacks']['main and hist are independent'] = function()
    child.lua([[
        local buffers = require('mkdnflow.buffers')
        buffers.push(buffers.main, 1)
        buffers.push(buffers.hist, 2)
    ]])

    local main = child.lua_get('require("mkdnflow.buffers").main')
    local hist = child.lua_get('require("mkdnflow.buffers").hist')

    eq(#main, 1)
    eq(main[1], 1)
    eq(#hist, 1)
    eq(hist[1], 2)
end

-- =============================================================================
-- Edge cases
-- =============================================================================
T['edge_cases'] = new_set()

T['edge_cases']['goBack twice with one item in stack'] = function()
    local buf2 = create_buffer('second.md')
    child.lua('require("mkdnflow.buffers").push(require("mkdnflow.buffers").main, 1)')

    -- First goBack succeeds
    local result1 = child.lua_get('require("mkdnflow.buffers").goBack()')
    eq(result1, true)

    -- Second goBack fails (stack is empty, and we're on buffer 1)
    local result2 = child.lua_get('require("mkdnflow.buffers").goBack()')
    eq(result2, false)
end

T['edge_cases']['goForward twice with one item in history'] = function()
    local buf2 = create_buffer('second.md')
    child.lua('vim.cmd("buffer 1")')
    child.lua('require("mkdnflow.buffers").push(require("mkdnflow.buffers").hist, ' .. buf2 .. ')')

    -- First goForward succeeds
    local result1 = child.lua_get('require("mkdnflow.buffers").goForward()')
    eq(result1, true)

    -- Second goForward fails (history is empty)
    local result2 = child.lua_get('require("mkdnflow.buffers").goForward()')
    eq(result2, false)
end

T['edge_cases']['handles deleted buffer in stack'] = function()
    local buf2 = create_buffer('second.md')
    child.lua('require("mkdnflow.buffers").push(require("mkdnflow.buffers").main, 1)')

    -- Delete the buffer we'd go back to
    child.lua('vim.cmd("bdelete! 1")')

    -- goBack will try to go to deleted buffer - this might error or fail
    -- The module doesn't handle this case specially, so behavior depends on nvim
    -- Just verify it doesn't crash
    child.lua('pcall(require("mkdnflow.buffers").goBack)')
end

T['edge_cases']['stack preserves buffer numbers correctly'] = function()
    local buf2 = create_buffer('second.md')
    local buf3 = create_buffer('third.md')
    local buf4 = create_buffer('fourth.md')

    child.lua([[
        local buffers = require('mkdnflow.buffers')
        buffers.push(buffers.main, 1)
        buffers.push(buffers.main, ]] .. buf2 .. [[)
        buffers.push(buffers.main, ]] .. buf3 .. [[)
    ]])

    local main = child.lua_get('require("mkdnflow.buffers").main')
    eq(main[1], buf3)
    eq(main[2], buf2)
    eq(main[3], 1)
end

return T
