-- mkdnflow.nvim (Tools for fluent markdown notebook navigation and management)
-- Copyright (C) 2022 Jake W. Vincent <https://github.com/jakewvincent>
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.
--
-- This module: Template formatting and injection for new files

local function mkdn()
    return require('mkdnflow')
end
local function cfg()
    return mkdn().config
end

local M = {}

--- Fill in placeholders in the new-file template string
---@param timing? string 'before' or 'after' buffer creation (defaults to 'before')
---@param template? string The template string to fill (defaults to config template)
---@return string template The template with placeholders replaced
M.formatTemplate = function(timing, template)
    timing = timing or 'before'
    local new_file_config = cfg().new_file_template
    local links = mkdn().links
    template = template or new_file_config.template
    -- Build context table with all resolved built-in values
    local link_under_cursor = links.getLinkUnderCursor()
    local ctx = {
        link_title = links.getLinkPart(link_under_cursor, 'name') or '',
        os_date = os.date('%Y-%m-%d'),
    }
    for placeholder_name, value in pairs(new_file_config.placeholders[timing]) do
        local replacement
        if type(value) == 'function' then
            replacement = value(ctx)
        elseif ctx[value] ~= nil then
            -- Magic string shorthand: 'link_title', 'os_date'
            replacement = ctx[value]
        else
            -- Plain string literal (e.g., author = 'Jake')
            replacement = value
        end
        replacement = replacement ~= nil and tostring(replacement) or ''
        template = string.gsub(template, '{{%s?' .. placeholder_name .. '%s?}}', replacement)
    end
    return template
end

--- Inject a formatted template into the current (newly created) buffer.
--- Performs the 'after' timing substitutions and writes the result to the top of the buffer.
---@param template string The pre-formatted template string (output of formatTemplate('before'))
M.apply = function(template)
    template = M.formatTemplate('after', template)
    local lines = vim.split(template, '\n', { plain = true })
    vim.api.nvim_buf_set_lines(0, 0, #template, false, lines)
end

return M
