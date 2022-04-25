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

local M = {}

--[[
goBack() calls the version of goBack() in the buffers module. This is here so
that anyone calling goBack from the old files module will still have functiona-
lity. (The compat module is called as files in init.lua.)
TODO: Remove this function in June 2022
--]]
M.goBack = function()
    require('mkdnflow.buffers').goBack()
    print("⬇️  Friendly warning: references to files.lua will soon stop working. See :h mkdnflow-changes, commit 511e8e...")
end

--[[
goForward() calls the version of goForward() in the buffers module. This is
here so that anyone calling goForward from the old files module will still have
functionality. (The compat module is called as files in init.lua.)
TODO: Remove this function in June 2022
--]]
M.goForward = function()
    require('mkdnflow.buffers').goForward()
    print("⬇️  Friendly warning: references to files.lua will soon stop working. See :h mkdnflow-changes, commit 511e8e...")
end

--[[
followPath()
--]]
M.followPath = function(path)
    require('mkdnflow.links').followLink(path)
    print('⬇️  Friendly warning: the use of followPath() will soon stop working. See :h mkdnflow-changes, commit c1cf25...')
end

--[[
userConfigCheck() will check a user config for particular settings that have
since been migrated to another setting or another format. It returns an equiva-
lent user config that is upgraded to the new format.
--]]
M.userConfigCheck = function(user_config)
    -- Look for old prefix settings
    if user_config.evaluate_prefix or user_config.new_file_prefix then
        user_config.prefix = {
            evaluate = user_config.evaluate_prefix,
            string = user_config.new_file_prefix
        }
        print('⬇️  The prefix settings are now specified under the "prefix" key, which takes a table value. Please update your config. See :h mkdnflow-changes, commit 1a2195...')
    end
    -- Look for links_relative_to
    if user_config.links_relative_to then
        user_config.perspective = user_config.links_relative_to
        print('⬇️  The links_relative_to key is now called "perspective". Please update your config. See :h mkdnflow-changes, commit e42290...')
    end
    -- Look for wrap preferences
    if user_config.wrap_to_beginning or user_config.wrap_to_end then
        user_config.wrap = true
        print('⬇️  The wrap_to_beginning/end keys have been merged into a single "wrap" key. Please update your config. See :h mkdnflow-changes, commit 9068e1...')
    end
    -- Inspect perspective setting, if specified
    if user_config.perspective then
        if type(user_config.perspective) ~= 'table' then
            print('⬇️  The perspective key (previously "links_relative_to") should now be associated with a table value. Please update your config. See :h mkdnflow-changes, commit 75c8ec...')
            if user_config.perspective == 'current' then
                local table = {
                    target = 'current',
                    fallback = 'first'
                }
                user_config.perspective = table
            elseif user_config.perspective == 'first' then
                local table = {
                    target = 'first',
                    fallback = 'current'
                }
                user_config.perspective = table
            end
        end
    end
    -- Inspect mappings
    if user_config.mappings then
        local string = false
        for _, value in pairs(user_config.mappings) do
            if type(value) == 'string' then
                string = true
            end
        end
        if string then
            print('⬇️  Friendly warning: in the mappings table, commands should now be associated with a table value instead of a string. See :h mkdnflow-changes, commit ...')
            local compatible_mappings = {}
            for key, value in pairs(user_config.mappings) do
                if key == 'MkdnFollowLink' then
                    compatible_mappings[key] = {{'n', 'v'}, value}
                else
                    compatible_mappings[key] = {'n', value}
                end
            end
            user_config.mappings = compatible_mappings
        end
    end
    return(user_config)
end

return M
