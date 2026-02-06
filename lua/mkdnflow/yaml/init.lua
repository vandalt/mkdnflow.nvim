-- mkdnflow.nvim (Tools for personal markdown notebook navigation and management)
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

local core = require('mkdnflow.yaml.core')
local bib = require('mkdnflow').bib
local filetype_patterns = require('mkdnflow').config.resolved_filetypes

local M = {}

-- Export class for advanced use
M.YAMLFrontmatter = core.YAMLFrontmatter

-- Register autocmd to extract bibliography paths from YAML frontmatter
vim.api.nvim_create_autocmd('FileType', {
    pattern = filetype_patterns,
    callback = function()
        bib.bib_paths.yaml = {}
        local start, finish = M.hasYaml()
        if start then
            local yaml = M.ingestYamlBlock(start, finish)
            if yaml and yaml.bib then
                bib.bib_paths.yaml = yaml.bib
            end
        end
    end,
})

--- Detect YAML frontmatter in the current buffer
--- @return integer|nil start 0-indexed start line (always 0 if found)
--- @return integer|nil finish 0-indexed finish line (the closing ---)
M.hasYaml = function()
    return core.detect_yaml_block(0)
end

--- Parse a YAML frontmatter block from the current buffer
--- @param start integer 0-indexed start line
--- @param finish integer 0-indexed finish line
--- @return table|nil data Parsed key-value pairs (values are arrays), or nil if params are nil
M.ingestYamlBlock = function(start, finish)
    if start and finish then
        return core.parse_yaml_block(0, start, finish)
    end
    return nil
end

return M
