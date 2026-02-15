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

--- Config validation for mkdnflow.nvim
--- Validates user config against defaults and a sparse schema overlay.
--- Called at setup time (vim.notify warnings) and by :checkhealth.
local M = {}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

--- Check if a table is array-like (consecutive integer keys starting at 1)
---@param t any
---@return boolean
local function isArray(t)
    if type(t) ~= 'table' then
        return false
    end
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    if count == 0 then
        return false
    end
    for i = 1, count do
        if t[i] == nil then
            return false
        end
    end
    return true
end

--- Navigate a nested table using a key path array
---@param tbl table
---@param path string[]
---@return any
local function getPath(tbl, path)
    local current = tbl
    for _, key in ipairs(path) do
        if type(current) ~= 'table' then
            return nil
        end
        current = current[key]
    end
    return current
end

--- Format a key path array as a dotted string
---@param path string[]
---@return string
local function pathStr(path)
    return table.concat(path, '.')
end

--- Build a display path string from a prefix and key
---@param prefix string
---@param key string|number
---@return string
local function buildPath(prefix, key)
    if prefix == '' then
        return tostring(key)
    end
    return prefix .. '.' .. tostring(key)
end

--- Add a diagnostic entry
---@param diagnostics table[]
---@param path string
---@param message string
local function addDiagnostic(diagnostics, path, message)
    table.insert(diagnostics, { path = path, message = message })
end

-- ---------------------------------------------------------------------------
-- Schema overlay
--
-- Sparse table mirroring the config structure. Only keys that need annotation
-- beyond what can be inferred from the default config get an entry.
--
-- Annotation fields:
--   types    = {'type1', ...}  -- accepted type() strings
--   enum     = {'val1', ...}   -- valid string values
--   dynamic  = true            -- child keys are user-defined (skip unknown-key check)
-- ---------------------------------------------------------------------------

M.schema = {
    path_resolution = {
        primary = { enum = { 'first', 'root' } },
        fallback = { enum = { 'current', 'first' } },
        root_marker = { types = { 'boolean', 'string', 'table' } },
    },
    filetypes = { dynamic = true },
    foldtext = {
        object_count_icon_set = { enum = { 'emoji', 'nerdfont', 'plain' } },
        object_count_opts = { types = { 'function' } },
        title_transformer = { types = { 'function' } },
    },
    bib = {
        default_path = { types = { 'nil', 'string' } },
    },
    cursor = {
        jump_patterns = { types = { 'nil', 'table' } },
    },
    links = {
        style = { enum = { 'markdown', 'wiki' } },
        implicit_extension = { types = { 'nil', 'string' } },
        transform_on_follow = { types = { 'boolean', 'function' } },
        transform_on_create = { types = { 'function' } },
        transform_scope = { enum = { 'path', 'filename' } },
        on_create_new = { types = { 'boolean', 'function' } },
        uri_handlers = { dynamic = true },
    },
    footnotes = {
        heading = { types = { 'boolean', 'string', 'table' } },
    },
    new_file_template = {
        placeholders = { dynamic = true },
    },
    on_attach = { types = { 'boolean', 'function' } },
    mappings = { dynamic = true },
}

-- ---------------------------------------------------------------------------
-- Recursive walker
-- ---------------------------------------------------------------------------

--- Determine the accepted types for a config key
---@param schema_node table|nil Schema annotation for this key
---@param default_value any The default value for this key
---@return string[] accepted type() strings
local function inferTypes(schema_node, default_value)
    if schema_node and schema_node.types then
        return schema_node.types
    end
    if default_value == nil then
        -- Key exists in defaults as nil; accept any type
        return {}
    end
    return { type(default_value) }
end

--- Check if a type string is in a list of accepted types
---@param actual_type string
---@param accepted string[]
---@return boolean
local function typeMatches(actual_type, accepted)
    if #accepted == 0 then
        return true
    end
    for _, t in ipairs(accepted) do
        if t == actual_type then
            return true
        end
    end
    return false
end

--- Walk user config recursively and collect diagnostics
---@param user table User-provided config subtree
---@param defaults table|nil Default config subtree
---@param schema_node table|nil Schema annotation subtree
---@param prefix string Dotted path prefix for diagnostic messages
---@param diagnostics table[] Accumulator for diagnostic entries
---@param is_dynamic boolean Whether the parent is a dynamic container
local function walk(user, defaults, schema_node, prefix, diagnostics, is_dynamic)
    for key, user_value in pairs(user) do
        local key_path = buildPath(prefix, key)
        local default_value = defaults and defaults[key]
        local key_schema = schema_node and schema_node[key]

        -- Skip integer keys (array indices)
        if type(key) == 'number' then
            goto continue
        end

        -- 1. Unknown key detection
        if not is_dynamic and default_value == nil and key_schema == nil then
            addDiagnostic(
                diagnostics,
                key_path,
                'Unknown config key. Check spelling or see :h mkdnflow-configuration.'
            )
            goto continue
        end

        -- 2. Type checking
        -- Skip in dynamic containers (dedicated validators handle their own types)
        -- false is always accepted (Neovim convention for "disable")
        if not is_dynamic and user_value ~= false then
            local accepted = inferTypes(key_schema, default_value)
            local actual_type = type(user_value)
            if not typeMatches(actual_type, accepted) then
                addDiagnostic(
                    diagnostics,
                    key_path,
                    string.format(
                        'Expected %s, got %s.',
                        table.concat(accepted, ' or '),
                        actual_type
                    )
                )
                goto continue
            end
        end

        -- 3. Enum validation
        if key_schema and key_schema.enum and type(user_value) == 'string' then
            local valid = false
            for _, v in ipairs(key_schema.enum) do
                if v == user_value then
                    valid = true
                    break
                end
            end
            if not valid then
                addDiagnostic(
                    diagnostics,
                    key_path,
                    string.format(
                        "Invalid value '%s'. Valid values: %s.",
                        user_value,
                        "'" .. table.concat(key_schema.enum, "', '") .. "'"
                    )
                )
            end
        end

        -- 4. Recurse into dict-like sub-tables
        if type(user_value) == 'table' and not isArray(user_value) then
            local child_dynamic = (key_schema and key_schema.dynamic) or false
            walk(
                user_value,
                (type(default_value) == 'table') and default_value or {},
                key_schema or {},
                key_path,
                diagnostics,
                child_dynamic
            )
        end

        ::continue::
    end
end

-- ---------------------------------------------------------------------------
-- Mappings validation
-- ---------------------------------------------------------------------------

--- Validate mappings config: check command names and value structure
---@param mappings_config table The user's mappings table
---@param diagnostics table[] Accumulator for diagnostic entries
local function validateMappings(mappings_config, diagnostics)
    local mkdnflow = require('mkdnflow')
    local command_deps = mkdnflow.command_deps
    if not command_deps then
        return
    end

    for cmd, value in pairs(mappings_config) do
        local key_path = 'mappings.' .. cmd

        -- Check if the command name is known
        if command_deps[cmd] == nil then
            addDiagnostic(
                diagnostics,
                key_path,
                'Unknown command name. See :h mkdnflow-commands for valid names.'
            )
        end

        -- Check value structure (false = disabled, which is fine)
        if value ~= false then
            if type(value) ~= 'table' then
                addDiagnostic(
                    diagnostics,
                    key_path,
                    "Expected false or { mode(s), 'keystring' } table."
                )
            elseif #value ~= 2 then
                addDiagnostic(
                    diagnostics,
                    key_path,
                    "Mapping table should have exactly 2 elements: { mode(s), 'keystring' }."
                )
            else
                local modes, binding = value[1], value[2]
                if type(modes) ~= 'string' and type(modes) ~= 'table' then
                    addDiagnostic(
                        diagnostics,
                        key_path .. '[1]',
                        "Mode must be a string (e.g. 'n') or array of strings."
                    )
                end
                if type(binding) ~= 'string' then
                    addDiagnostic(diagnostics, key_path .. '[2]', 'Key binding must be a string.')
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Validate user config against defaults and schema
---@param user_config table Post-compat user configuration
---@param default_config table Default configuration
---@return table[] diagnostics List of { path = '...', message = '...' }
M.validate = function(user_config, default_config)
    local diagnostics = {}
    walk(user_config, default_config, M.schema, '', diagnostics, false)

    -- Mappings get dedicated validation
    if user_config.mappings then
        validateMappings(user_config.mappings, diagnostics)
    end

    return diagnostics
end

--- Check for conflicts between deprecated and replacement config keys
---@param raw_user_config table Raw user config (before compat migration)
---@param diagnostics table[]|nil Existing diagnostics list to append to (or nil to create new)
---@return table[] diagnostics
M.checkConflicts = function(raw_user_config, diagnostics)
    diagnostics = diagnostics or {}
    local ok, compat = pcall(require, 'mkdnflow.compat')
    if not ok or not compat.deprecations then
        return diagnostics
    end

    for _, dep in ipairs(compat.deprecations) do
        local old_val = getPath(raw_user_config, dep.path)
        local new_val = getPath(raw_user_config, dep.new_path)
        if old_val ~= nil and new_val ~= nil then
            addDiagnostic(
                diagnostics,
                pathStr(dep.path),
                string.format(
                    "Both deprecated '%s' and its replacement '%s' are set. "
                        .. 'The replacement takes precedence; remove the deprecated key.',
                    pathStr(dep.path),
                    pathStr(dep.new_path)
                )
            )
        end
    end

    return diagnostics
end

return M
